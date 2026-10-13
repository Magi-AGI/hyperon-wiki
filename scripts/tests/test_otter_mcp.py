#!/usr/bin/env python3
"""Offline tests for the Otter.ai MCP OAuth client and transcript exporter.

No network calls and no credentials: OAuth discovery/registration/token
endpoints are stubbed with plain callables, and the MCP transport is a fake
that records requests and replays canned JSON-RPC envelopes.

Run:
    python scripts/tests/test_otter_mcp.py
"""

import io
import os
import sys
import json
import time
import base64
import hashlib
import tempfile
import contextlib
import unittest
import urllib.parse
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts import otter_oauth as oo
from scripts import export_otter_mcp as ex
from scripts.pipeline.transcript_sources import save_transcripts_json


# ---------------------------------------------------------------------------
# Canned metadata (the real values, captured from public documentation)
# ---------------------------------------------------------------------------

PRM = {
    "resource": "https://mcp.otter.ai/",
    "authorization_servers": ["https://otter.ai/"],
    "scopes_supported": ["profile:read", "conversations:read"],
    "bearer_methods_supported": ["header"],
}

ASM = {
    "issuer": "https://otter.ai",
    "authorization_endpoint": "https://otter.ai/oauth2/authorize",
    "token_endpoint": "https://otter.ai/oauth/token",
    "registration_endpoint": "https://otter.ai/oauth/register",
    "revocation_endpoint": "https://otter.ai/oauth/revoke_token",
    "response_types_supported": ["code"],
    "code_challenge_methods_supported": ["plain", "S256"],
    "token_endpoint_auth_methods_supported": [
        "none", "client_secret_post", "client_secret_basic"],
    "grant_types_supported": ["authorization_code", "refresh_token"],
}


def fake_fetch_json(url):
    if url == oo.PROTECTED_RESOURCE_METADATA_URL:
        return dict(PRM)
    if url == "https://otter.ai/.well-known/oauth-authorization-server":
        return dict(ASM)
    raise AssertionError(f"unexpected discovery URL: {url}")


class CredStoreCase(unittest.TestCase):
    """Base class pointing the credential store at a temp dir."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self._prev = os.environ.get("OTTER_CREDENTIAL_DIR")
        os.environ["OTTER_CREDENTIAL_DIR"] = self.tmp.name

    def tearDown(self):
        if self._prev is None:
            os.environ.pop("OTTER_CREDENTIAL_DIR", None)
        else:
            os.environ["OTTER_CREDENTIAL_DIR"] = self._prev
        self.tmp.cleanup()


# ---------------------------------------------------------------------------
# PKCE
# ---------------------------------------------------------------------------

class OtterPKCETests(unittest.TestCase):
    def test_verifier_shape_is_rfc7636_compliant(self):
        for length in (43, 64, 128):
            v = oo.generate_code_verifier(length)
            self.assertEqual(len(v), length)
            self.assertRegex(v, r"^[A-Za-z0-9\-._~]+$")

    def test_verifier_length_bounds_enforced(self):
        for bad in (42, 129, 0):
            with self.assertRaises(ValueError):
                oo.generate_code_verifier(bad)

    def test_verifiers_are_unique(self):
        self.assertEqual(
            len({oo.generate_code_verifier() for _ in range(50)}), 50)

    def test_challenge_matches_s256_definition(self):
        v = oo.generate_code_verifier()
        expected = base64.urlsafe_b64encode(
            hashlib.sha256(v.encode("ascii")).digest()
        ).decode().rstrip("=")
        self.assertEqual(oo.code_challenge_for(v), expected)

    def test_challenge_is_unpadded(self):
        self.assertNotIn("=", oo.code_challenge_for(
            oo.generate_code_verifier()))

    def test_known_rfc7636_appendix_b_vector(self):
        # RFC 7636 Appendix B worked example — pins the exact byte sequence.
        self.assertEqual(
            oo.code_challenge_for("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
        )

    def test_challenge_rejects_malformed_verifier(self):
        for bad in ("short", "has spaces in it " * 4, "!" * 50, ""):
            with self.assertRaises(ValueError):
                oo.code_challenge_for(bad)

    def test_challenge_differs_from_verifier(self):
        v = oo.generate_code_verifier()
        self.assertNotEqual(v, oo.code_challenge_for(v))


# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

class OtterDiscoveryTests(unittest.TestCase):
    def test_rfc8414_url_inserts_well_known_between_host_and_path(self):
        self.assertEqual(
            oo.authorization_server_metadata_url("https://otter.ai/"),
            "https://otter.ai/.well-known/oauth-authorization-server")
        self.assertEqual(
            oo.authorization_server_metadata_url("https://ex.com/tenant/1"),
            "https://ex.com/.well-known/oauth-authorization-server/tenant/1")

    def test_discovery_follows_the_spec_chain(self):
        meta = oo.discover(fetch_json=fake_fetch_json)
        self.assertEqual(meta["authorization_endpoint"],
                         "https://otter.ai/oauth2/authorize")
        self.assertEqual(meta["token_endpoint"], "https://otter.ai/oauth/token")
        self.assertEqual(meta["registration_endpoint"],
                         "https://otter.ai/oauth/register")
        self.assertEqual(meta["resource"], "https://mcp.otter.ai/")
        self.assertEqual(meta["resource_scopes"],
                         ["profile:read", "conversations:read"])

    def test_discovery_requires_an_authorization_server(self):
        with self.assertRaises(SystemExit):
            oo.discover(fetch_json=lambda url: {"resource": "x"})

    def test_discovery_requires_a_token_endpoint(self):
        def partial(url):
            if url == oo.PROTECTED_RESOURCE_METADATA_URL:
                return dict(PRM)
            return {"authorization_endpoint": "https://otter.ai/oauth2/authorize"}
        with self.assertRaises(SystemExit):
            oo.discover(fetch_json=partial)

    def test_protected_resource_metadata_url_is_root_well_known(self):
        self.assertEqual(
            oo.PROTECTED_RESOURCE_METADATA_URL,
            "https://mcp.otter.ai/.well-known/oauth-protected-resource")

    def test_default_scope_is_read_only(self):
        self.assertEqual(oo.DEFAULT_SCOPE, "profile:read conversations:read")
        for word in ("write", "delete", "admin"):
            self.assertNotIn(word, oo.DEFAULT_SCOPE)


# ---------------------------------------------------------------------------
# Dynamic client registration (RFC 7591)
# ---------------------------------------------------------------------------

class OtterRegistrationTests(CredStoreCase):
    def test_payload_is_a_public_client_with_every_loopback_uri(self):
        payload = oo.build_registration_payload(
            "test-client", oo.all_redirect_uris(), oo.DEFAULT_SCOPE)
        self.assertEqual(payload["token_endpoint_auth_method"], "none")
        self.assertEqual(payload["response_types"], ["code"])
        self.assertIn("refresh_token", payload["grant_types"])
        self.assertIn("authorization_code", payload["grant_types"])
        self.assertEqual(len(payload["redirect_uris"]),
                         len(oo.LOOPBACK_PORTS))
        for uri in payload["redirect_uris"]:
            self.assertTrue(uri.startswith("http://127.0.0.1:"))
            self.assertTrue(uri.endswith("/callback"))

    def test_loopback_uris_use_the_literal_ip_not_localhost(self):
        # RFC 8252 section 7.3: "localhost" may resolve to ::1 or be hijacked.
        for uri in oo.all_redirect_uris():
            self.assertNotIn("localhost", uri)

    def test_registration_response_parsing_keeps_only_what_we_store(self):
        parsed = oo.parse_registration_response({
            "client_id": "cid-123",
            "token_endpoint_auth_method": "none",
            "scope": "profile:read conversations:read",
            "redirect_uris": ["http://127.0.0.1:41789/callback"],
            "client_id_issued_at": 1750000000,
        })
        self.assertEqual(parsed["client_id"], "cid-123")
        self.assertEqual(parsed["client_secret"], "")
        self.assertEqual(parsed["token_endpoint_auth_method"], "none")

    def test_registration_failure_raises(self):
        for bad in ({"error": "invalid_client_metadata"}, {}, None, "nope"):
            with self.assertRaises(SystemExit):
                oo.parse_registration_response(bad)

    def test_register_client_posts_to_the_discovered_endpoint(self):
        seen = {}

        def post_json(url, body):
            seen["url"] = url
            seen["body"] = body
            return {"client_id": "cid-xyz",
                    "token_endpoint_auth_method": "none"}

        meta = oo.discover(fetch_json=fake_fetch_json)
        oo.register_client(meta=meta, post_json=post_json)
        self.assertEqual(seen["url"], "https://otter.ai/oauth/register")
        self.assertEqual(seen["body"]["scope"], oo.DEFAULT_SCOPE)

        stored = oo.load_credentials()
        self.assertEqual(stored["client_id"], "cid-xyz")
        self.assertEqual(stored["resource"], "https://mcp.otter.ai/")
        self.assertEqual(stored["token_endpoint"],
                         "https://otter.ai/oauth/token")
        self.assertEqual(len(stored["redirect_uris"]), len(oo.LOOPBACK_PORTS))

    def test_register_client_without_registration_endpoint_fails_loudly(self):
        meta = dict(oo.discover(fetch_json=fake_fetch_json))
        meta["registration_endpoint"] = None
        with self.assertRaises(SystemExit):
            oo.register_client(meta=meta, post_json=lambda u, b: {})


# ---------------------------------------------------------------------------
# Authorization URL
# ---------------------------------------------------------------------------

class OtterAuthorizeURLTests(unittest.TestCase):
    def creds(self):
        return {
            "client_id": "cid-abc",
            "scope": oo.DEFAULT_SCOPE,
            "resource": "https://mcp.otter.ai/",
            "authorization_endpoint": "https://otter.ai/oauth2/authorize",
        }

    def parse(self, url):
        parts = urllib.parse.urlsplit(url)
        return parts, dict(urllib.parse.parse_qsl(parts.query))

    def test_contains_all_required_oauth21_params(self):
        v = oo.generate_code_verifier()
        url = oo.build_authorize_url(self.creds(), v, "state-xyz",
                                     oo.redirect_uri_for(41789))
        parts, q = self.parse(url)
        self.assertEqual(parts.netloc, "otter.ai")
        self.assertEqual(parts.path, "/oauth2/authorize")
        self.assertEqual(q["response_type"], "code")
        self.assertEqual(q["client_id"], "cid-abc")
        self.assertEqual(q["state"], "state-xyz")
        self.assertEqual(q["redirect_uri"], "http://127.0.0.1:41789/callback")
        self.assertEqual(q["code_challenge"], oo.code_challenge_for(v))
        self.assertEqual(q["scope"], oo.DEFAULT_SCOPE)

    def test_code_challenge_method_always_explicit_s256(self):
        # Otter advertises "plain" too; omitting the method would downgrade.
        url = oo.build_authorize_url(self.creds(),
                                     oo.generate_code_verifier(), "s",
                                     oo.redirect_uri_for(41789))
        _, q = self.parse(url)
        self.assertEqual(q["code_challenge_method"], "S256")

    def test_verifier_never_appears_in_the_url(self):
        v = oo.generate_code_verifier()
        url = oo.build_authorize_url(self.creds(), v, "s",
                                     oo.redirect_uri_for(41789))
        self.assertNotIn(v, url)

    def test_resource_indicator_defaults_to_the_discovered_resource(self):
        url = oo.build_authorize_url(self.creds(),
                                     oo.generate_code_verifier(), "s",
                                     oo.redirect_uri_for(41790))
        _, q = self.parse(url)
        self.assertEqual(q["resource"], "https://mcp.otter.ai/")

    def test_resource_indicator_can_be_overridden(self):
        url = oo.build_authorize_url(self.creds(),
                                     oo.generate_code_verifier(), "s",
                                     oo.redirect_uri_for(41790),
                                     resource="https://other.example/")
        _, q = self.parse(url)
        self.assertEqual(q["resource"], "https://other.example/")


# ---------------------------------------------------------------------------
# Loopback callback
# ---------------------------------------------------------------------------

class OtterLoopbackTests(unittest.TestCase):
    def test_callback_query_parsing(self):
        params = oo.parse_callback_query("/callback?code=abc&state=xyz")
        self.assertEqual(params, {"code": "abc", "state": "xyz"})

    def test_callback_error_parsing(self):
        params = oo.parse_callback_query(
            "/callback?error=access_denied&error_description=User+said+no")
        self.assertEqual(params["error"], "access_denied")
        self.assertEqual(params["error_description"], "User said no")

    def test_port_picker_returns_the_first_free_registered_port(self):
        free = {41789: False, 41790: False, 41791: True, 41792: True}
        self.assertEqual(oo.pick_loopback_port(probe=free.get), 41791)

    def test_port_picker_fails_when_every_port_is_taken(self):
        with self.assertRaises(SystemExit):
            oo.pick_loopback_port(probe=lambda p: False)

    def test_failure_html_escapes_the_message(self):
        html = oo._failure_html("<script>alert(1)</script>")
        self.assertNotIn("<script>", html)
        self.assertIn("&lt;script&gt;", html)


# ---------------------------------------------------------------------------
# Token persistence and refresh
# ---------------------------------------------------------------------------

class OtterTokenStoreTests(CredStoreCase):
    def test_roundtrip(self):
        oo.save_credentials({"client_id": "abc"})
        self.assertEqual(oo.load_credentials()["client_id"], "abc")

    def test_missing_file_returns_empty(self):
        self.assertEqual(oo.load_credentials(), {})

    def test_refuses_to_write_inside_a_git_repo(self):
        repo = Path(self.tmp.name) / "repo"
        (repo / ".git").mkdir(parents=True)
        os.environ["OTTER_CREDENTIAL_DIR"] = str(repo / "creds")
        with self.assertRaises(SystemExit):
            oo.save_credentials({"client_id": "abc"})

    def test_default_dir_is_outside_the_repo(self):
        os.environ.pop("OTTER_CREDENTIAL_DIR", None)
        d = str(oo.credential_dir()).replace("\\", "/").lower()
        self.assertNotIn("magi-agi", d)
        self.assertNotIn("hyperon-wiki", d)
        self.assertTrue(d.endswith("magi-transcripts/otter"))

    def test_posix_permission_intent_is_owner_only(self):
        # On POSIX the file must be 0600; on Windows the ACL inherits from
        # LOCALAPPDATA, so assert the intent is encoded for POSIX runs.
        oo.save_credentials({"client_id": "abc", "access_token": "at"})
        path = oo.credential_path()
        self.assertTrue(path.is_file())
        if os.name == "posix":
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        else:
            import inspect
            src = inspect.getsource(oo.save_credentials)
            self.assertIn("S_IRUSR", src)
            self.assertIn("S_IWUSR", src)

    def test_no_temp_file_is_left_behind(self):
        oo.save_credentials({"client_id": "abc"})
        leftovers = list(Path(self.tmp.name).glob("*.tmp"))
        self.assertEqual(leftovers, [])

    def test_token_response_is_persisted(self):
        oo.save_credentials({"client_id": "c"})
        oo.store_token_response(oo.load_credentials(), {
            "access_token": "at-1",
            "refresh_token": "rt-1",
            "token_type": "Bearer",
            "expires_in": 3600,
            "scope": oo.DEFAULT_SCOPE,
        })
        stored = oo.load_credentials()
        self.assertEqual(stored["access_token"], "at-1")
        self.assertEqual(stored["refresh_token"], "rt-1")
        self.assertEqual(stored["granted_scope"], oo.DEFAULT_SCOPE)
        self.assertGreater(stored["expires_at"], time.time())

    def test_rotated_refresh_token_replaces_the_old_one(self):
        oo.save_credentials({"client_id": "c", "refresh_token": "old"})
        oo.store_token_response(oo.load_credentials(),
                                {"access_token": "at", "refresh_token": "new",
                                 "expires_in": 3600})
        self.assertEqual(oo.load_credentials()["refresh_token"], "new")

    def test_absent_refresh_token_does_not_clear_the_existing_one(self):
        oo.save_credentials({"client_id": "c", "refresh_token": "keepme"})
        oo.store_token_response(oo.load_credentials(),
                                {"access_token": "at", "expires_in": 3600})
        self.assertEqual(oo.load_credentials()["refresh_token"], "keepme")

    def test_token_freshness_uses_the_skew_margin(self):
        now = 1_000_000.0
        self.assertGreater(oo.EXPIRY_SKEW_SECONDS, 0)
        creds = {"access_token": "at", "expires_at": now + 3600}
        self.assertTrue(oo.token_is_fresh(creds, now=now))
        # Inside the skew window the token is treated as already stale.
        creds["expires_at"] = now + oo.EXPIRY_SKEW_SECONDS - 1
        self.assertFalse(oo.token_is_fresh(creds, now=now))
        self.assertFalse(oo.token_is_fresh({"expires_at": now + 3600},
                                           now=now))
        # No advertised expiry: usable, and let a 401 drive the refresh.
        self.assertTrue(oo.token_is_fresh({"access_token": "at",
                                           "expires_at": 0}, now=now))

    def test_public_client_sends_client_id_in_the_form_and_no_secret(self):
        form = oo.build_token_form({"client_id": "cid"},
                                   {"grant_type": "refresh_token"})
        self.assertEqual(form["client_id"], "cid")
        self.assertNotIn("client_secret", form)

    def test_confidential_client_sends_the_secret_when_one_was_issued(self):
        form = oo.build_token_form({"client_id": "cid",
                                    "client_secret": "shh"},
                                   {"grant_type": "refresh_token"})
        self.assertEqual(form["client_secret"], "shh")

    def test_code_exchange_sends_pkce_verifier_and_resource(self):
        oo.save_credentials({
            "client_id": "cid",
            "token_endpoint": "https://otter.ai/oauth/token",
            "resource": "https://mcp.otter.ai/",
        })
        seen = {}

        def post_form(url, data):
            seen["url"] = url
            seen["data"] = data
            return {"access_token": "at-2", "refresh_token": "rt-2",
                    "expires_in": 3600, "scope": oo.DEFAULT_SCOPE}

        oo.exchange_code(oo.load_credentials(), "the-code", "v" * 64,
                         oo.redirect_uri_for(41789), post_form=post_form)
        self.assertEqual(seen["url"], "https://otter.ai/oauth/token")
        self.assertEqual(seen["data"]["grant_type"], "authorization_code")
        self.assertEqual(seen["data"]["code"], "the-code")
        self.assertEqual(seen["data"]["code_verifier"], "v" * 64)
        self.assertEqual(seen["data"]["redirect_uri"],
                         "http://127.0.0.1:41789/callback")
        self.assertEqual(seen["data"]["resource"], "https://mcp.otter.ai/")
        self.assertEqual(oo.load_credentials()["access_token"], "at-2")

    def test_code_exchange_failure_raises_with_guidance(self):
        oo.save_credentials({"client_id": "cid",
                             "token_endpoint": "https://otter.ai/oauth/token"})
        with self.assertRaises(SystemExit) as ctx:
            oo.exchange_code(oo.load_credentials(), "c", "v" * 64,
                             oo.redirect_uri_for(41789),
                             post_form=lambda u, d: {"error": "invalid_grant"})
        self.assertIn("invalid_grant", str(ctx.exception))

    def test_refresh_flow_rotates_and_persists(self):
        oo.save_credentials({
            "client_id": "cid",
            "token_endpoint": "https://otter.ai/oauth/token",
            "refresh_token": "rt-old",
            "scope": oo.DEFAULT_SCOPE,
            "resource": "https://mcp.otter.ai/",
            "access_token": "at-old",
            "expires_at": 1,
        })
        seen = {}

        def post_form(url, data):
            seen.update(data)
            return {"access_token": "at-new", "refresh_token": "rt-new",
                    "expires_in": 3600}

        oo.refresh_access_token(post_form=post_form)
        self.assertEqual(seen["grant_type"], "refresh_token")
        self.assertEqual(seen["refresh_token"], "rt-old")
        self.assertEqual(seen["client_id"], "cid")
        stored = oo.load_credentials()
        self.assertEqual(stored["access_token"], "at-new")
        self.assertEqual(stored["refresh_token"], "rt-new")
        self.assertGreater(stored["expires_at"], time.time())

    def test_refresh_releases_its_lock_file(self):
        oo.save_credentials({"client_id": "cid", "refresh_token": "rt",
                             "token_endpoint": "https://otter.ai/oauth/token"})
        oo.refresh_access_token(
            post_form=lambda u, d: {"access_token": "at", "expires_in": 60})
        self.assertFalse((oo.credential_dir() / "refresh.lock").exists())

    def test_refresh_without_a_stored_token_fails_loudly(self):
        oo.save_credentials({"client_id": "cid"})
        with self.assertRaises(SystemExit):
            oo.refresh_access_token(post_form=lambda u, d: {})

    def test_refresh_failure_releases_the_lock(self):
        oo.save_credentials({"client_id": "cid", "refresh_token": "rt",
                             "token_endpoint": "https://otter.ai/oauth/token"})
        with self.assertRaises(SystemExit):
            oo.refresh_access_token(
                post_form=lambda u, d: {"error": "invalid_grant"})
        self.assertFalse((oo.credential_dir() / "refresh.lock").exists())

    def test_get_access_token_refreshes_a_stale_token(self):
        oo.save_credentials({
            "client_id": "cid",
            "token_endpoint": "https://otter.ai/oauth/token",
            "access_token": "at-stale", "refresh_token": "rt",
            "expires_at": int(time.time()) - 10,
        })
        calls = []
        real = oo._token_request
        oo._token_request = lambda creds, form, post_form=None: (
            calls.append(form) or {"access_token": "at-fresh",
                                   "expires_in": 3600})
        try:
            self.assertEqual(oo.get_access_token(), "at-fresh")
        finally:
            oo._token_request = real
        self.assertEqual(len(calls), 1)

    def test_get_access_token_reuses_a_fresh_token(self):
        oo.save_credentials({
            "client_id": "cid",
            "token_endpoint": "https://otter.ai/oauth/token",
            "access_token": "at-good", "refresh_token": "rt",
            "expires_at": int(time.time()) + 3600,
        })
        real = oo._token_request
        oo._token_request = lambda *a, **k: self.fail("should not refresh")
        try:
            self.assertEqual(oo.get_access_token(), "at-good")
        finally:
            oo._token_request = real

    def test_get_access_token_without_credentials_fails_loudly(self):
        with self.assertRaises(SystemExit):
            oo.get_access_token()

    def test_status_prints_no_token_material(self):
        oo.save_credentials({
            "client_id": "cid", "client_secret": "SECRET-CS",
            "access_token": "SECRET-AT", "refresh_token": "SECRET-RT",
            "registration_access_token": "SECRET-RAT",
            "expires_at": int(time.time()) + 300,
            "granted_scope": oo.DEFAULT_SCOPE,
        })
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            oo.cmd_status()
        out = buf.getvalue()
        for secret in ("SECRET-CS", "SECRET-AT", "SECRET-RT", "SECRET-RAT"):
            self.assertNotIn(secret, out)
        self.assertIn("present", out)

    def test_module_exposes_no_token_printing_subcommand(self):
        # A `token` subcommand would make echoing a bearer token a one-liner.
        import inspect
        src = inspect.getsource(oo.main)
        self.assertNotIn('"token"', src)

    def test_logout_clears_tokens_but_keeps_the_registration(self):
        oo.save_credentials({"client_id": "cid", "access_token": "at",
                             "refresh_token": "rt", "expires_at": 1,
                             "revocation_endpoint": ""})
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            oo.cmd_logout()
        stored = oo.load_credentials()
        self.assertEqual(stored["client_id"], "cid")
        self.assertNotIn("access_token", stored)
        self.assertNotIn("refresh_token", stored)


# ---------------------------------------------------------------------------
# MCP JSON-RPC envelopes
# ---------------------------------------------------------------------------

class McpEnvelopeTests(unittest.TestCase):
    def test_request_envelope_shape(self):
        env = ex.build_rpc_request("tools/list", {}, request_id="magi-1")
        self.assertEqual(env["jsonrpc"], "2.0")
        self.assertEqual(env["method"], "tools/list")
        self.assertEqual(env["id"], "magi-1")
        self.assertEqual(env["params"], {})

    def test_notification_carries_no_id(self):
        # A notification with an id would make the server wait for a reply.
        env = ex.build_rpc_notification("notifications/initialized")
        self.assertNotIn("id", env)
        self.assertEqual(env["jsonrpc"], "2.0")

    def test_params_omitted_when_none(self):
        self.assertNotIn("params", ex.build_rpc_request("ping",
                                                        request_id="x"))

    def test_parse_plain_json_response(self):
        body = json.dumps({"jsonrpc": "2.0", "id": "magi-1",
                           "result": {"tools": []}})
        self.assertEqual(
            ex.parse_rpc_response(body, "application/json", "magi-1"),
            {"tools": []})

    def test_parse_sse_response(self):
        body = ("event: message\n"
                'data: {"jsonrpc":"2.0","id":"magi-2","result":{"ok":true}}\n'
                "\n")
        self.assertEqual(
            ex.parse_rpc_response(body, "text/event-stream", "magi-2"),
            {"ok": True})

    def test_parse_sse_joins_multiline_data(self):
        body = 'data: {"jsonrpc":"2.0","id":"i",\ndata: "result":{"a":1}}\n\n'
        self.assertEqual(ex.parse_rpc_response(body, "text/event-stream", "i"),
                         {"a": 1})

    def test_parse_sse_skips_unrelated_ids(self):
        body = ('data: {"jsonrpc":"2.0","id":"other","result":{"no":1}}\n\n'
                'data: {"jsonrpc":"2.0","id":"mine","result":{"yes":1}}\n\n')
        self.assertEqual(
            ex.parse_rpc_response(body, "text/event-stream", "mine"),
            {"yes": 1})

    def test_jsonrpc_error_becomes_an_mcp_error(self):
        body = json.dumps({"jsonrpc": "2.0", "id": "i",
                           "error": {"code": -32602,
                                     "message": "Invalid params"}})
        with self.assertRaises(ex.McpError) as ctx:
            ex.parse_rpc_response(body, "application/json", "i")
        self.assertIn("Invalid params", str(ctx.exception))

    def test_missing_response_id_raises(self):
        body = json.dumps({"jsonrpc": "2.0", "id": "other", "result": {}})
        with self.assertRaises(ex.McpError):
            ex.parse_rpc_response(body, "application/json", "mine")

    def test_mislabelled_sse_still_parses(self):
        body = 'data: {"jsonrpc":"2.0","id":"i","result":{"ok":1}}\n\n'
        self.assertEqual(ex.parse_rpc_response(body, "application/json", "i"),
                         {"ok": 1})

    def test_garbage_body_raises(self):
        with self.assertRaises(ex.McpError):
            ex.parse_rpc_response("<html>502</html>", "text/html", "i")


# ---------------------------------------------------------------------------
# tools/call result unwrapping
# ---------------------------------------------------------------------------

def wrap_once(payload) -> dict:
    text = payload if isinstance(payload, str) else json.dumps(payload)
    return {"content": [{"type": "text", "text": text}]}


def wrap_twice(payload) -> dict:
    """Mimic Otter's double-wrapped search/fetch results."""
    return wrap_once(json.dumps(wrap_once(payload)))


class ToolResultUnwrapTests(unittest.TestCase):
    def test_double_wrapped_search_payload(self):
        payload = {"results": [{"id": "abc", "title": "Weekly"}]}
        self.assertEqual(ex.unwrap_tool_payload(wrap_twice(payload)), payload)

    def test_single_wrapped_json_payload(self):
        payload = {"id": "abc", "text": "hello"}
        self.assertEqual(ex.unwrap_tool_payload(wrap_once(payload)), payload)

    def test_prose_payload_returned_as_text(self):
        prose = "User Information:\nName: Jane Doe\nEmail: jane@example.com"
        self.assertEqual(ex.unwrap_tool_payload(wrap_once(prose)), prose)

    def test_structured_content_fallback(self):
        result = {"content": [], "structuredContent": {"results": []}}
        self.assertEqual(ex.unwrap_tool_payload(result), {"results": []})

    def test_is_error_flag_raises(self):
        result = wrap_once("conversation not found")
        result["isError"] = True
        with self.assertRaises(ex.McpError):
            ex.unwrap_tool_payload(result)

    def test_empty_result_raises(self):
        with self.assertRaises(ex.McpError):
            ex.unwrap_tool_payload({"content": []})

    def test_non_object_result_raises(self):
        with self.assertRaises(ex.McpError):
            ex.unwrap_tool_payload("nope")


# ---------------------------------------------------------------------------
# Fake MCP transport
# ---------------------------------------------------------------------------

class FakeTransport:
    """Records POSTs and replays canned results keyed by JSON-RPC method/tool.

    Signature matches the real transport: (url, body, headers) ->
    (status, headers, text).

    tools/list advertises the LIVE server's prefixed names
    (`otter_search`/`otter_fetch`/`otter_get_user_info`) by default, so every
    test exercises the alias resolution the real server needs. Canned results
    and calls_for() are keyed by the logical name, matched against the tail of
    whatever the tool is actually called.
    """

    LIVE_TOOL_NAMES = ("otter_search", "otter_fetch", "otter_get_user_info")

    def __init__(self, tool_results=None, session_id="sess-1",
                 sse=False, status=200, tool_names=None):
        self.tool_results = tool_results or {}
        self.session_id = session_id
        self.sse = sse
        self.status = status
        self.tool_names = (list(self.LIVE_TOOL_NAMES) if tool_names is None
                           else list(tool_names))
        self.requests = []
        self.headers_seen = []

    @staticmethod
    def _logical(name):
        for logical in ("get_user_info", "search", "fetch"):
            if name == logical or name.endswith("_" + logical):
                return logical
        return name

    def __call__(self, url, body, headers):
        payload = json.loads(body.decode("utf-8"))
        self.requests.append(payload)
        self.headers_seen.append(dict(headers))

        method = payload.get("method")
        if "id" not in payload:
            # A notification gets an accepted-with-no-body reply.
            return 202, {"Mcp-Session-Id": self.session_id}, ""

        if method == "initialize":
            result = {"protocolVersion": "2025-06-18",
                      "serverInfo": {"name": "otter-mcp", "version": "1.0"},
                      "capabilities": {"tools": {}}}
        elif method == "tools/list":
            result = {"tools": [{"name": n} for n in self.tool_names]}
        elif method == "tools/call":
            name = payload["params"]["name"]
            args = payload["params"].get("arguments") or {}
            entry = self.tool_results.get(name)
            if entry is None:
                entry = self.tool_results.get(self._logical(name))
            if callable(entry):
                result = entry(args)
            elif entry is None:
                raise AssertionError(f"no canned result for tool {name!r}")
            else:
                result = entry
        else:
            raise AssertionError(f"unexpected method {method!r}")

        envelope = {"jsonrpc": "2.0", "id": payload["id"], "result": result}
        resp_headers = {"Mcp-Session-Id": self.session_id}
        if self.sse:
            resp_headers["Content-Type"] = "text/event-stream"
            text = f"event: message\ndata: {json.dumps(envelope)}\n\n"
        else:
            resp_headers["Content-Type"] = "application/json"
            text = json.dumps(envelope)
        return self.status, resp_headers, text

    def calls_for(self, tool):
        wanted = self._logical(tool)
        return [r["params"].get("arguments") or {}
                for r in self.requests
                if r.get("method") == "tools/call"
                and self._logical(r["params"]["name"]) == wanted]

    def tool_calls_by_name(self, tool):
        """Exact server-side names used for calls to a logical tool."""
        wanted = self._logical(tool)
        return [r["params"]["name"] for r in self.requests
                if r.get("method") == "tools/call"
                and self._logical(r["params"]["name"]) == wanted]


def make_meeting(i, start="2026-03-04 10:00:00", title=None):
    cid = f"conv{i:03d}AbCdEfGhIjKlMnOpQrS"
    return {
        "id": cid,
        "title": title or f"Weekly roadmap review {i}",
        "url": f"https://otter.ai/u/{cid}",
        "start_time": start,
        "duration": "31m",
        "short_summary": "Reviewed milestones and reprioritized the backlog.",
        "action_items": ["Send recap to the team"],
    }


def make_transcript(meeting):
    return {
        "id": meeting["id"],
        "title": meeting["title"],
        "url": meeting["url"],
        "text": ("[0:00:00] Speaker 1: Thanks everyone for joining.\n"
                 "[0:00:12] Speaker 2: Happy to be here.\n"
                 "and glad to help out today.\n"
                 "[0:01:40] Speaker 1: Let us start with the roadmap."),
        "metadata": {
            "action_items": meeting["action_items"],
            "duration": meeting["duration"],
            "short_summary": meeting["short_summary"],
            "start_time": meeting["start_time"],
        },
    }


class McpClientTests(unittest.TestCase):
    def client(self, transport):
        return ex.OtterMcpClient(lambda: "test-token", transport=transport)

    def test_initialize_handshake_sends_notification_and_keeps_session(self):
        t = FakeTransport()
        client = self.client(t)
        client.initialize()
        methods = [r.get("method") for r in t.requests]
        self.assertEqual(methods, ["initialize", "notifications/initialized"])
        self.assertEqual(client.session_id, "sess-1")
        self.assertEqual(client.protocol_version, "2025-06-18")
        self.assertEqual(client.server_info["name"], "otter-mcp")
        init_params = t.requests[0]["params"]
        self.assertIn("protocolVersion", init_params)
        self.assertIn("clientInfo", init_params)

    def test_headers_carry_bearer_accept_and_session(self):
        t = FakeTransport()
        client = self.client(t)
        client.initialize()
        client.list_tools()
        first, last = t.headers_seen[0], t.headers_seen[-1]
        self.assertEqual(first["Authorization"], "Bearer test-token")
        self.assertIn("application/json", first["Accept"])
        self.assertIn("text/event-stream", first["Accept"])
        # The session id only exists after initialize replies.
        self.assertNotIn("Mcp-Session-Id", first)
        self.assertEqual(last["Mcp-Session-Id"], "sess-1")
        self.assertEqual(last["MCP-Protocol-Version"], "2025-06-18")

    def test_tools_list_returns_the_otter_tool_surface(self):
        t = FakeTransport()
        client = self.client(t)
        client.initialize()
        names = [tool["name"] for tool in client.list_tools()]
        # The live server prefixes every tool with `otter_`.
        self.assertEqual(names, ["otter_search", "otter_fetch",
                                 "otter_get_user_info"])
        self.assertEqual(client.tool_names, {
            "search": "otter_search",
            "fetch": "otter_fetch",
            "get_user_info": "otter_get_user_info",
        })

    def test_calls_use_the_servers_actual_tool_names(self):
        t = FakeTransport({"search": wrap_twice({"results": []}),
                           "fetch": wrap_twice({"id": "a", "text": ""})})
        client = self.client(t)
        client.initialize()
        client.list_tools()
        client.search("x")
        client.fetch("a")
        self.assertEqual(t.tool_calls_by_name("search"), ["otter_search"])
        self.assertEqual(t.tool_calls_by_name("fetch"), ["otter_fetch"])

    def test_bare_tool_names_still_work(self):
        # An older/self-hosted deployment without the `otter_` prefix.
        t = FakeTransport({"search": wrap_twice({"results": []})},
                          tool_names=["search", "fetch", "get_user_info"])
        client = self.client(t)
        client.initialize()
        client.list_tools()
        client.search("x")
        self.assertEqual(t.tool_calls_by_name("search"), ["search"])

    def test_calls_fall_back_to_logical_names_without_discovery(self):
        # No list_tools() call: the client must still be usable.
        t = FakeTransport({"search": wrap_twice({"results": []})},
                          tool_names=["search", "fetch"])
        client = self.client(t)
        client.initialize()
        client.search("x")
        self.assertEqual(t.tool_calls_by_name("search"), ["search"])

    def test_search_unwraps_double_wrapped_results(self):
        meetings = [make_meeting(1), make_meeting(2)]
        t = FakeTransport({"search": wrap_twice({"results": meetings})})
        client = self.client(t)
        client.initialize()
        rows = client.search("roadmap", created_after="2026/03/01")
        self.assertEqual([r["id"] for r in rows],
                         [m["id"] for m in meetings])
        args = t.calls_for("search")[0]
        self.assertEqual(args["query"], "roadmap")
        self.assertEqual(args["created_after"], "2026/03/01")
        # Empty filters are dropped rather than sent as nulls.
        self.assertNotIn("created_before", args)

    def test_search_sends_an_empty_query_for_date_only_browse(self):
        t = FakeTransport({"search": wrap_twice({"results": []})})
        client = self.client(t)
        client.initialize()
        client.search("", created_after="2026/01/01",
                      created_before="2026/01/31")
        args = t.calls_for("search")[0]
        self.assertEqual(args["query"], "")
        self.assertEqual(args["created_before"], "2026/01/31")

    def test_search_tolerates_a_payload_without_results(self):
        t = FakeTransport({"search": wrap_twice({"message": "none"})})
        client = self.client(t)
        client.initialize()
        self.assertEqual(client.search("x"), [])

    def test_fetch_normalises_a_url_to_a_bare_id(self):
        meeting = make_meeting(1)
        t = FakeTransport({"fetch": wrap_twice(make_transcript(meeting))})
        client = self.client(t)
        client.initialize()
        client.fetch(f"https://otter.ai/u/{meeting['id']}?tab=chat")
        # The tool rejects URLs outright.
        self.assertEqual(t.calls_for("fetch")[0], {"id": meeting["id"]})

    def test_get_user_info_returns_prose(self):
        prose = "User Information:\nName: Jane Doe\nEmail: j@example.com"
        t = FakeTransport({"get_user_info": wrap_once(prose)})
        client = self.client(t)
        client.initialize()
        self.assertEqual(client.get_user_info(), prose)

    def test_sse_transport_is_handled(self):
        t = FakeTransport({"search": wrap_twice({"results": [make_meeting(1)]})},
                          sse=True)
        client = self.client(t)
        client.initialize()
        self.assertEqual(len(client.search("x")), 1)

    def test_401_becomes_an_mcp_error(self):
        class Unauthorized:
            def __call__(self, url, body, headers):
                return 401, {}, '{"error":"invalid_token"}'
        client = self.client(Unauthorized())
        with self.assertRaises(ex.McpError) as ctx:
            client.initialize()
        self.assertIn("401", str(ctx.exception))

    def test_token_is_requested_per_call_not_cached(self):
        minted = []

        def provider():
            minted.append(1)
            return f"tok-{len(minted)}"

        t = FakeTransport({"search": wrap_twice({"results": []})})
        client = ex.OtterMcpClient(provider, transport=t)
        client.initialize()
        client.search("a")
        client.search("b")
        self.assertGreaterEqual(len(minted), 4)
        self.assertNotEqual(t.headers_seen[0]["Authorization"],
                            t.headers_seen[-1]["Authorization"])


# ---------------------------------------------------------------------------
# Sweep planning and dedupe
# ---------------------------------------------------------------------------

class MonthWindowTests(unittest.TestCase):
    def test_single_month_is_clipped_to_the_requested_bounds(self):
        self.assertEqual(ex.month_windows("2026-03-10", "2026-03-20"),
                         [(date(2026, 3, 10), date(2026, 3, 20))])

    def test_windows_span_month_boundaries_without_gaps_or_overlaps(self):
        windows = ex.month_windows("2026-01-15", "2026-04-02")
        self.assertEqual(windows, [
            (date(2026, 1, 15), date(2026, 1, 31)),
            (date(2026, 2, 1), date(2026, 2, 28)),
            (date(2026, 3, 1), date(2026, 3, 31)),
            (date(2026, 4, 1), date(2026, 4, 2)),
        ])
        for earlier, later in zip(windows, windows[1:]):
            self.assertEqual((later[0] - earlier[1]).days, 1)

    def test_leap_february_is_handled(self):
        windows = ex.month_windows("2024-02-01", "2024-02-29")
        self.assertEqual(windows, [(date(2024, 2, 1), date(2024, 2, 29))])

    def test_year_boundary_is_handled(self):
        windows = ex.month_windows("2025-12-01", "2026-01-31")
        self.assertEqual(windows, [
            (date(2025, 12, 1), date(2025, 12, 31)),
            (date(2026, 1, 1), date(2026, 1, 31)),
        ])

    def test_full_archive_range_produces_one_window_per_month(self):
        windows = ex.month_windows("2016-01-01", "2026-12-31")
        self.assertEqual(len(windows), 11 * 12)

    def test_inverted_range_is_rejected(self):
        with self.assertRaises(SystemExit):
            ex.month_windows("2026-05-01", "2026-04-01")

    def test_otter_date_format_is_slash_separated(self):
        self.assertEqual(ex.to_otter_date("2026-03-04"), "2026/03/04")
        self.assertEqual(ex.to_otter_date(date(2026, 3, 4)), "2026/03/04")


class ToolNameResolutionTests(unittest.TestCase):
    def test_live_prefixed_names_resolve(self):
        resolved = ex.resolve_tool_names(
            [{"name": "otter_search"}, {"name": "otter_fetch"},
             {"name": "otter_get_user_info"}])
        self.assertEqual(resolved, {"search": "otter_search",
                                    "fetch": "otter_fetch",
                                    "get_user_info": "otter_get_user_info"})
        self.assertEqual(ex.missing_required_tools(resolved), [])

    def test_bare_names_resolve(self):
        resolved = ex.resolve_tool_names(["search", "fetch", "get_user_info"])
        self.assertEqual(resolved, {"search": "search", "fetch": "fetch",
                                    "get_user_info": "get_user_info"})

    def test_plain_string_list_is_accepted(self):
        self.assertEqual(
            ex.resolve_tool_names(["otter_search", "otter_fetch"]),
            {"search": "otter_search", "fetch": "otter_fetch"})

    def test_unanticipated_prefix_resolves_by_suffix(self):
        resolved = ex.resolve_tool_names(["otterai_v2_search", "acme_fetch"])
        self.assertEqual(resolved["search"], "otterai_v2_search")
        self.assertEqual(resolved["fetch"], "acme_fetch")

    def test_substring_without_a_segment_boundary_is_not_a_match(self):
        # "research" ends with "search" textually but is a different tool.
        resolved = ex.resolve_tool_names(["research", "prefetch"])
        self.assertNotIn("search", resolved)
        self.assertNotIn("fetch", resolved)
        self.assertEqual(ex.missing_required_tools(resolved),
                         ["search", "fetch"])

    def test_exact_alias_beats_a_suffix_match(self):
        resolved = ex.resolve_tool_names(["weird_legacy_search", "search",
                                          "fetch"])
        self.assertEqual(resolved["search"], "search")

    def test_prefixed_alias_is_preferred_over_bare(self):
        # Both spellings present: the documented live name wins.
        resolved = ex.resolve_tool_names(["search", "otter_search", "fetch"])
        self.assertEqual(resolved["search"], "otter_search")

    def test_missing_tools_are_reported(self):
        resolved = ex.resolve_tool_names(["otter_search"])
        self.assertEqual(ex.missing_required_tools(resolved), ["fetch"])

    def test_empty_and_malformed_input_is_safe(self):
        for bad in (None, [], [{}], [None], [{"name": ""}], [123]):
            self.assertEqual(
                ex.missing_required_tools(ex.resolve_tool_names(bad)),
                ["search", "fetch"], msg=f"for {bad!r}")

    def test_get_user_info_is_optional(self):
        resolved = ex.resolve_tool_names(["otter_search", "otter_fetch"])
        self.assertEqual(ex.missing_required_tools(resolved), [])
        self.assertNotIn("get_user_info", resolved)


class SearchPaginationTests(unittest.TestCase):
    """`search` must drain next_cursor or every month window is truncated."""

    def client(self, transport):
        client = ex.OtterMcpClient(lambda: "tok", transport=transport)
        client.initialize()
        client.list_tools()
        return client

    def test_cursor_is_followed_until_exhausted(self):
        pages = [
            {"results": [make_meeting(1), make_meeting(2)],
             "next_cursor": "c1"},
            {"results": [make_meeting(3)], "next_cursor": "c2"},
            {"results": [make_meeting(4)]},
        ]

        def search(args):
            if not args.get("cursor"):
                return wrap_twice(pages[0])
            return wrap_twice(pages[{"c1": 1, "c2": 2}[args["cursor"]]])

        t = FakeTransport({"search": search})
        rows = self.client(t).search("", created_after="2026/01/01")
        self.assertEqual([r["id"] for r in rows],
                         [make_meeting(i)["id"] for i in (1, 2, 3, 4)])
        self.assertEqual(len(t.calls_for("search")), 3)

    def test_pagination_calls_send_only_the_cursor(self):
        def search(args):
            if not args.get("cursor"):
                return wrap_twice({"results": [make_meeting(1)],
                                   "next_cursor": "c1"})
            return wrap_twice({"results": [make_meeting(2)]})

        t = FakeTransport({"search": search})
        self.client(t).search("topic", created_after="2026/01/01",
                              created_before="2026/01/31")
        first, second = t.calls_for("search")
        self.assertEqual(first["query"], "topic")
        self.assertEqual(first["created_after"], "2026/01/01")
        self.assertNotIn("cursor", first)
        # The server preserves the original query/filters for a cursor call;
        # re-sending them is not supported.
        self.assertEqual(second["cursor"], "c1")
        self.assertNotIn("query", second)
        self.assertNotIn("created_after", second)

    def test_page_size_is_requested_within_the_server_cap(self):
        t = FakeTransport({"search": wrap_twice({"results": []})})
        self.client(t).search("x")
        self.assertEqual(t.calls_for("search")[0]["page_size"],
                         ex.SEARCH_PAGE_SIZE)
        self.assertLessEqual(ex.SEARCH_PAGE_SIZE, 25)

    def test_a_server_ignoring_the_cursor_does_not_loop_forever(self):
        # Same page and a fresh cursor every time: the no-new-ids guard must
        # break the loop instead of spinning to max_pages.
        counter = {"n": 0}

        def search(args):
            counter["n"] += 1
            return wrap_twice({"results": [make_meeting(1)],
                               "next_cursor": f"c{counter['n']}"})

        t = FakeTransport({"search": search})
        rows = self.client(t).search("x")
        self.assertEqual(len(rows), 1)
        self.assertEqual(len(t.calls_for("search")), 2)

    def test_repeated_cursor_value_stops_the_loop(self):
        def search(args):
            idx = 2 if args.get("cursor") else 1
            return wrap_twice({"results": [make_meeting(idx)],
                               "next_cursor": "same"})

        t = FakeTransport({"search": search})
        rows = self.client(t).search("x")
        self.assertEqual(len(rows), 2)
        self.assertEqual(len(t.calls_for("search")), 2)

    def test_max_pages_bounds_the_walk(self):
        def search(args):
            # Always new ids and a new cursor: only max_pages can stop this.
            n = len(t.calls_for("search")) + 1
            return wrap_twice({"results": [make_meeting(n)],
                               "next_cursor": f"c{n}"})

        t = FakeTransport({"search": search})
        rows = self.client(t).search("x", max_pages=3)
        self.assertEqual(len(rows), 3)
        self.assertEqual(len(t.calls_for("search")), 3)

    def test_duplicate_rows_across_pages_are_collapsed(self):
        def search(args):
            if not args.get("cursor"):
                return wrap_twice({"results": [make_meeting(1),
                                               make_meeting(2)],
                                   "next_cursor": "c1"})
            return wrap_twice({"results": [make_meeting(2), make_meeting(3)]})

        t = FakeTransport({"search": search})
        rows = self.client(t).search("x")
        self.assertEqual([r["id"] for r in rows],
                         [make_meeting(i)["id"] for i in (1, 2, 3)])

    def test_empty_first_page_returns_nothing(self):
        t = FakeTransport({"search": wrap_twice({"results": []})})
        self.assertEqual(self.client(t).search("x"), [])
        self.assertEqual(len(t.calls_for("search")), 1)

    def test_payload_nested_under_result_is_handled(self):
        t = FakeTransport({"search": wrap_twice(
            {"result": {"results": [make_meeting(1)]}})})
        self.assertEqual(len(self.client(t).search("x")), 1)


class SweepPlanTests(unittest.TestCase):
    def test_plan_is_one_sweep_per_month_plus_one_per_query(self):
        plan = ex.build_sweep_plan("2026-01-01", "2026-03-31",
                                   queries=["roadmap", "hiring"])
        self.assertEqual(len(plan), 5)
        labels = [s["label"] for s in plan]
        self.assertEqual(labels[:3], ["month:2026-01", "month:2026-02",
                                      "month:2026-03"])
        self.assertEqual(labels[3:], ["query:roadmap", "query:hiring"])

    def test_month_sweeps_use_an_empty_query_for_browse_mode(self):
        plan = ex.build_sweep_plan("2026-01-01", "2026-01-31")
        self.assertEqual(plan[0]["query"], "")
        self.assertEqual(plan[0]["created_after"], "2026/01/01")
        self.assertEqual(plan[0]["created_before"], "2026/01/31")

    def test_query_sweeps_cover_the_whole_range(self):
        plan = ex.build_sweep_plan("2026-01-01", "2026-03-31",
                                   queries=["roadmap"])
        term = plan[-1]
        self.assertEqual(term["created_after"], "2026/01/01")
        self.assertEqual(term["created_before"], "2026/03/31")

    def test_blank_query_terms_are_dropped(self):
        plan = ex.build_sweep_plan("2026-01-01", "2026-01-31",
                                   queries=["", "  ", None, "real"])
        self.assertEqual([s["label"] for s in plan],
                         ["month:2026-01", "query:real"])

    def test_no_month_windows_collapses_to_one_range_sweep(self):
        plan = ex.build_sweep_plan("2026-01-01", "2026-06-30",
                                   split_months=False)
        self.assertEqual(len(plan), 1)
        self.assertEqual(plan[0]["label"], "range:2026-01-01..2026-06-30")


class ConversationIdTests(unittest.TestCase):
    def test_bare_id_passes_through(self):
        self.assertEqual(ex.normalise_conversation_id("aBcDeF123"), "aBcDeF123")

    def test_url_is_reduced_to_the_id(self):
        for url in ("https://otter.ai/u/aBcDeF123",
                    "http://otter.ai/u/aBcDeF123",
                    "https://otter.ai/u/aBcDeF123?tab=chat&view=summary",
                    "otter.ai/u/aBcDeF123"):
            self.assertEqual(ex.normalise_conversation_id(url), "aBcDeF123")

    def test_empty_input_yields_empty_string(self):
        for bad in ("", None, "   "):
            self.assertEqual(ex.normalise_conversation_id(bad), "")

    def test_url_and_id_forms_collapse_to_one_identity(self):
        # Otherwise one conversation would be exported twice.
        self.assertEqual(
            ex.normalise_conversation_id("https://otter.ai/u/X9"),
            ex.normalise_conversation_id("X9"))


class DedupeTests(unittest.TestCase):
    def test_duplicates_across_sweeps_collapse_to_one_record(self):
        m1, m2, m3 = make_meeting(1), make_meeting(2), make_meeting(3)
        merged, stats = ex.merge_sweep_results([
            ("month:2026-01", [m1, m2]),
            ("month:2026-02", [m3]),
            ("query:roadmap", [m1, m3]),
        ])
        self.assertEqual(len(merged), 3)
        self.assertEqual(stats["unique"], 3)
        self.assertEqual(stats["rows_seen"], 5)
        self.assertEqual(stats["duplicates"], 2)

    def test_first_sighting_wins_and_provenance_accumulates(self):
        m1 = make_meeting(1)
        later = dict(m1, title="Renamed later")
        merged, _ = ex.merge_sweep_results([
            ("month:2026-01", [m1]),
            ("query:x", [later]),
        ])
        row = merged[m1["id"]]
        self.assertEqual(row["title"], m1["title"])
        self.assertEqual(row["_sweeps"], ["month:2026-01", "query:x"])

    def test_url_keyed_rows_dedupe_against_id_keyed_rows(self):
        m1 = make_meeting(1)
        url_only = {"url": m1["url"], "title": m1["title"]}
        merged, stats = ex.merge_sweep_results([
            ("a", [m1]),
            ("b", [url_only]),
        ])
        self.assertEqual(len(merged), 1)
        self.assertEqual(stats["duplicates"], 1)

    def test_rows_without_an_id_are_counted_and_skipped(self):
        merged, stats = ex.merge_sweep_results([
            ("a", [{"title": "no id"}, make_meeting(1), "garbage"]),
        ])
        self.assertEqual(len(merged), 1)
        self.assertEqual(stats["skipped_no_id"], 2)

    def test_per_sweep_stats_report_new_versus_returned(self):
        m1, m2 = make_meeting(1), make_meeting(2)
        _, stats = ex.merge_sweep_results([
            ("a", [m1, m2]),
            ("b", [m1]),
        ])
        self.assertEqual(stats["per_sweep"]["a"], {"returned": 2, "new": 2})
        self.assertEqual(stats["per_sweep"]["b"], {"returned": 1, "new": 0})

    def test_empty_and_none_batches_are_safe(self):
        merged, stats = ex.merge_sweep_results([("a", []), ("b", None)])
        self.assertEqual(merged, {})
        self.assertEqual(stats["sweeps"], 2)
        self.assertEqual(stats["unique"], 0)


class RunSweepsTests(unittest.TestCase):
    def test_sweeps_are_executed_and_merged(self):
        pages = {
            "2026/01/01": [make_meeting(1), make_meeting(2)],
            "2026/02/01": [make_meeting(2), make_meeting(3)],
        }

        def search(args):
            return wrap_twice(
                {"results": pages.get(args.get("created_after"), [])})

        t = FakeTransport({"search": search})
        client = ex.OtterMcpClient(lambda: "tok", transport=t)
        client.initialize()
        plan = ex.build_sweep_plan("2026-01-01", "2026-02-28")
        merged, stats = ex.run_sweeps(client, plan, verbose=False)
        self.assertEqual(len(merged), 3)
        self.assertEqual(stats["duplicates"], 1)
        self.assertEqual(stats["sweep_failures"], [])
        self.assertEqual(len(t.calls_for("search")), 2)

    def test_one_failing_window_does_not_abandon_the_rest(self):
        def search(args):
            if args.get("created_after") == "2026/02/01":
                return {"content": [{"type": "text", "text": "boom"}],
                        "isError": True}
            return wrap_twice({"results": [make_meeting(1)]})

        t = FakeTransport({"search": search})
        client = ex.OtterMcpClient(lambda: "tok", transport=t)
        client.initialize()
        plan = ex.build_sweep_plan("2026-01-01", "2026-03-31")
        merged, stats = ex.run_sweeps(client, plan, verbose=False)
        self.assertEqual(len(merged), 1)
        self.assertEqual(len(stats["sweep_failures"]), 1)
        self.assertEqual(stats["sweep_failures"][0]["sweep"], "month:2026-02")

    def test_a_full_export_sweeps_every_window(self):
        t = FakeTransport({"search": wrap_twice({"results": []})})
        client = ex.OtterMcpClient(lambda: "tok", transport=t)
        client.initialize()
        plan = ex.build_sweep_plan("2026-01-01", "2026-06-30")
        merged, stats = ex.run_sweeps(client, plan, verbose=False)
        self.assertEqual(len(t.calls_for("search")), 6)
        self.assertFalse(stats["stopped_early"])

    def test_stop_after_halts_once_enough_ids_are_known(self):
        def search(args):
            return wrap_twice({"results": [make_meeting(1), make_meeting(2),
                                           make_meeting(3)]})

        t = FakeTransport({"search": search})
        client = ex.OtterMcpClient(lambda: "tok", transport=t)
        client.initialize()
        plan = ex.build_sweep_plan("2016-01-01", "2026-06-30")
        self.assertGreater(len(plan), 100)
        merged, stats = ex.run_sweeps(client, plan, verbose=False,
                                      stop_after=3)
        # One window already satisfies the limit, so the other ~125 months of
        # live API traffic must not happen.
        self.assertEqual(len(t.calls_for("search")), 1)
        self.assertTrue(stats["stopped_early"])
        self.assertGreaterEqual(len(merged), 3)

    def test_stop_after_sweeps_newest_months_first(self):
        seen = []

        def search(args):
            seen.append(args.get("created_after"))
            return wrap_twice({"results": [make_meeting(len(seen))]})

        t = FakeTransport({"search": search})
        client = ex.OtterMcpClient(lambda: "tok", transport=t)
        client.initialize()
        plan = ex.build_sweep_plan("2026-01-01", "2026-06-30")
        ex.run_sweeps(client, plan, verbose=False, stop_after=1)
        # Newest window first, not January 2016 onwards.
        self.assertEqual(seen, ["2026/06/01"])

    def test_stop_after_keeps_going_until_the_limit_is_reachable(self):
        def search(args):
            # Only the oldest window in the plan holds anything.
            if args.get("created_after") == "2026/01/01":
                return wrap_twice({"results": [make_meeting(1)]})
            return wrap_twice({"results": []})

        t = FakeTransport({"search": search})
        client = ex.OtterMcpClient(lambda: "tok", transport=t)
        client.initialize()
        plan = ex.build_sweep_plan("2026-01-01", "2026-04-30")
        merged, stats = ex.run_sweeps(client, plan, verbose=False,
                                      stop_after=5)
        # The limit is never reached, so every window still runs.
        self.assertEqual(len(t.calls_for("search")), 4)
        self.assertFalse(stats["stopped_early"])
        self.assertEqual(len(merged), 1)


# ---------------------------------------------------------------------------
# Normalisation
# ---------------------------------------------------------------------------

class DurationParsingTests(unittest.TestCase):
    def test_humanised_forms(self):
        cases = {"31m": 31, "3h 51m": 231, "1h": 60, "2h 0m": 120,
                 "45s": 1, "1m 30s": 2, "": 0, None: 0}
        for raw, expected in cases.items():
            self.assertEqual(ex.parse_duration_minutes(raw), expected,
                             msg=f"for {raw!r}")

    def test_clock_forms(self):
        self.assertEqual(ex.parse_duration_minutes("1:30:00"), 90)
        self.assertEqual(ex.parse_duration_minutes("0:31:00"), 31)
        # A two-part clock is MM:SS, so this is 31 seconds -> 1 minute, NOT
        # 31 minutes. Reading it the other way inflates every short call 60x.
        self.assertEqual(ex.parse_duration_minutes("00:31"), 1)
        self.assertEqual(ex.parse_duration_minutes("31:00"), 31)

    def test_numeric_input_is_treated_as_minutes(self):
        self.assertEqual(ex.parse_duration_minutes(42), 42)

    def test_unparseable_duration_is_zero_not_a_crash(self):
        self.assertEqual(ex.parse_duration_minutes("a while"), 0)


class StartDateParsingTests(unittest.TestCase):
    def test_otter_space_separated_timestamp(self):
        self.assertEqual(ex.parse_start_date("2026-05-04 10:00:00"),
                         "2026-05-04")

    def test_iso_forms(self):
        for raw in ("2026-05-04T10:00:00", "2026-05-04T10:00:00Z",
                    "2026-05-04T10:00:00.123Z", "2026-05-04"):
            self.assertEqual(ex.parse_start_date(raw), "2026-05-04")

    def test_slash_form(self):
        self.assertEqual(ex.parse_start_date("2026/05/04 10:00:00"),
                         "2026-05-04")

    def test_epoch_milliseconds_are_not_read_as_seconds(self):
        # 1746352800000 ms == 2025-05-04; read as seconds it would be year 57k.
        self.assertEqual(ex.parse_start_date(1746352800000)[:4], "2025")

    def test_unparseable_date_is_empty_not_garbage(self):
        self.assertEqual(ex.parse_start_date("sometime last spring"), "")
        self.assertEqual(ex.parse_start_date(None), "")

    # --- the 1-day date-shift regression -----------------------------------
    # The legacy exporter (scripts/export_otter.py) derived the meeting date
    # with datetime.utcfromtimestamp(created_at), i.e. a naive UTC date. For a
    # series that met in the late local evening that instant falls on the NEXT
    # calendar day, so every occurrence was filed one day late -- which is how
    # the deck ended up with 59 duplicate "date_shifted" transcript cards.
    #
    # Otter's MCP start_time is already a LOCAL wall-clock string, so the fix
    # is to read it as written and never convert it. These tests pin exactly
    # that, because the failure is silent: a shifted date still looks valid.
    def test_a_late_evening_start_keeps_its_own_calendar_date(self):
        self.assertEqual(ex.parse_start_date("2026-01-22 21:30:00"),
                         "2026-01-22")

    def test_midnight_and_last_second_stay_on_their_own_day(self):
        self.assertEqual(ex.parse_start_date("2026-01-22 00:00:00"),
                         "2026-01-22")
        self.assertEqual(ex.parse_start_date("2026-01-22 23:59:59"),
                         "2026-01-22")

    def test_a_wall_clock_date_is_independent_of_the_exporting_machine_tz(self):
        # Same input, extreme opposite process timezones: a wall-clock date
        # must not depend on where the exporter happens to run.
        original = os.environ.get("TZ")
        try:
            for tz in ("Pacific/Kiritimati", "Pacific/Niue", "UTC"):
                os.environ["TZ"] = tz
                if hasattr(time, "tzset"):
                    time.tzset()
                self.assertEqual(ex.parse_start_date("2026-01-22 21:30:00"),
                                 "2026-01-22", tz)
        finally:
            if original is None:
                os.environ.pop("TZ", None)
            else:
                os.environ["TZ"] = original
            if hasattr(time, "tzset"):
                time.tzset()

    def test_the_record_date_comes_from_start_time_not_created_at(self):
        # created_at is the epoch field the legacy exporter used; start_time is
        # the local wall clock. If a record ever reverts to created_at, an
        # evening meeting silently shifts a day again.
        record = ex.otter_to_record({
            "id": "otter-1",
            "title": "Meeting @ Elowyn AI",
            "metadata": {"start_time": "2026-01-22 21:30:00",
                         "created_at": 1769146200},
            "transcript": "[0:00:00] Speaker 1: good evening\n",
        })
        self.assertEqual(record.date, "2026-01-22")


class TranscriptTextParsingTests(unittest.TestCase):
    def test_timestamped_turns_are_split(self):
        turns = ex.parse_transcript_text(
            "[0:00:00] Speaker 1: Hello there.\n"
            "[0:00:12] Speaker 2: Hi back.")
        self.assertEqual(len(turns), 2)
        self.assertEqual(turns[0]["speaker_name"], "Speaker 1")
        self.assertEqual(turns[0]["text"], "Hello there.")
        self.assertEqual(turns[0]["start_time"], "0:00:00")

    def test_continuation_lines_append_rather_than_drop(self):
        turns = ex.parse_transcript_text(
            "[0:00:00] Speaker 1: First part\nsecond part.")
        self.assertEqual(len(turns), 1)
        self.assertEqual(turns[0]["text"], "First part second part.")

    def test_untimestamped_leading_text_is_kept(self):
        turns = ex.parse_transcript_text("no timestamps here")
        self.assertEqual(turns[0]["speaker_name"], "Unknown")
        self.assertEqual(turns[0]["text"], "no timestamps here")

    def test_empty_text_yields_no_turns(self):
        self.assertEqual(ex.parse_transcript_text(""), [])
        self.assertEqual(ex.parse_transcript_text(None), [])


class RecordMappingTests(unittest.TestCase):
    def test_fetch_payload_becomes_a_transcript_record(self):
        meeting = make_meeting(1, start="2026-03-04 10:00:00")
        record = ex.otter_to_record(make_transcript(meeting), meeting)
        self.assertEqual(record.source_service, "otter.ai")
        self.assertEqual(record.date, "2026-03-04")
        self.assertEqual(record.meeting_name, meeting["title"])
        self.assertEqual(record.transcript_id, meeting["id"])
        self.assertEqual(record.transcript_url, meeting["url"])
        self.assertEqual(record.duration_minutes, 31)
        self.assertEqual(record.action_items, ["Send recap to the team"])
        self.assertEqual(record.participants, ["Speaker 1", "Speaker 2"])
        self.assertEqual(len(record.sentences), 3)
        self.assertFalse(record.is_live)
        self.assertIn("Thanks everyone", record.full_text)

    def test_search_row_fills_gaps_left_by_fetch(self):
        meeting = make_meeting(2)
        thin = {"id": meeting["id"], "text": "[0:00:00] A: hi"}
        record = ex.otter_to_record(thin, meeting)
        self.assertEqual(record.meeting_name, meeting["title"])
        self.assertEqual(record.date, "2026-03-04")
        self.assertEqual(record.summary, meeting["short_summary"])

    def test_missing_title_falls_back_without_crashing(self):
        record = ex.otter_to_record({"id": "X1", "text": ""}, {})
        self.assertEqual(record.meeting_name, "Untitled Otter conversation")
        self.assertEqual(record.transcript_url, "https://otter.ai/u/X1")
        self.assertEqual(record.date, "")

    def test_calendar_participants_are_preferred_over_speaker_labels(self):
        # Otter's diarised labels are usually "Speaker 1"; the invite list
        # carries the real names, so both end up on the record.
        meeting = make_meeting(7)
        fetched = make_transcript(meeting)
        fetched["metadata"]["calendar_participants"] = ["Ada L", "Grace H"]
        record = ex.otter_to_record(fetched, meeting)
        self.assertEqual(record.participants[:2], ["Ada L", "Grace H"])
        self.assertIn("Speaker 1", record.participants)

    def test_calendar_participants_are_not_duplicated(self):
        meeting = make_meeting(8)
        fetched = make_transcript(meeting)
        fetched["metadata"]["calendar_participants"] = ["Speaker 1"]
        record = ex.otter_to_record(fetched, meeting)
        self.assertEqual(record.participants.count("Speaker 1"), 1)

    def test_action_items_of_mixed_shapes_normalise_to_strings(self):
        record = ex.otter_to_record(
            {"id": "X", "text": "", "metadata": {
                "action_items": [{"text": "Do a thing"}, "Do another", 7]}},
            {})
        self.assertEqual(record.action_items,
                         ["Do a thing", "Do another", "7"])
        self.assertTrue(all(isinstance(a, str) for a in record.action_items))

    def test_record_card_name_matches_the_pipeline_convention(self):
        meeting = make_meeting(1)
        record = ex.otter_to_record(make_transcript(meeting), meeting)
        self.assertTrue(
            record.card_name().startswith("Raw Data+transcripts+"))
        self.assertTrue(record.card_name().endswith("+2026-03-04"))


# ---------------------------------------------------------------------------
# Artifacts
# ---------------------------------------------------------------------------

class ExportArtifactTests(unittest.TestCase):
    def records(self, n=3):
        out = []
        for i in range(1, n + 1):
            meeting = make_meeting(i, start=f"2026-03-0{i} 10:00:00")
            out.append(ex.otter_to_record(make_transcript(meeting), meeting))
        return out

    def test_export_refuses_to_write_inside_the_repository(self):
        repo_root = Path(ex.__file__).resolve().parents[1]
        with self.assertRaises(SystemExit):
            ex._assert_outside_repo(repo_root / "scripts" / "out")

    def test_default_output_dir_is_outside_the_repository(self):
        repo_root = Path(ex.__file__).resolve().parents[1]
        out = ex.default_output_dir()
        with self.assertRaises(ValueError):
            out.resolve().relative_to(repo_root)
        self.assertTrue(out.name.startswith("otter_"))

    def test_summary_matches_the_shared_artifact_format(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            save_transcripts_json(self.records(), out)
            summary = json.loads(
                (out / "export_summary.json").read_text(encoding="utf-8"))
        for field in ("exported_at", "total_transcripts", "files_written",
                      "live_transcripts", "services", "date_range"):
            self.assertIn(field, summary)
        self.assertEqual(summary["total_transcripts"], 3)
        self.assertEqual(summary["files_written"], 3)
        self.assertEqual(summary["live_transcripts"], 0)
        self.assertEqual(summary["services"], ["otter.ai"])
        self.assertEqual(summary["date_range"]["earliest"], "2026-03-01")
        self.assertEqual(summary["date_range"]["latest"], "2026-03-03")

    def test_saved_records_contain_no_credential_material(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            save_transcripts_json(self.records(1), out)
            blob = "\n".join(p.read_text(encoding="utf-8")
                             for p in out.glob("*.json"))
        for marker in ("access_token", "refresh_token", "Bearer",
                       "client_secret", "code_verifier", "Mcp-Session-Id"):
            self.assertNotIn(marker, blob)
        self.assertIn("otter.ai", blob)

    def test_acceptance_checker_passes_a_clean_export(self):
        from scripts import acceptance_otter_export as acc
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            save_transcripts_json(self.records(), out)
            (out / "otter_export_manifest.json").write_text(json.dumps({
                "source_service": "otter.ai", "records_written": 3,
                "sweeps_planned": 3, "mcp_calls": 9,
                "fetch_failures": [], "sweep_failures": [],
            }), encoding="utf-8")
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = acc.main(["acceptance_otter_export.py", str(out)])
        self.assertEqual(rc, 0, msg=buf.getvalue())
        self.assertIn("PASS", buf.getvalue())

    def test_acceptance_checker_fails_a_duplicated_conversation(self):
        from scripts import acceptance_otter_export as acc
        meeting = make_meeting(1)
        record = ex.otter_to_record(make_transcript(meeting), meeting)
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            save_transcripts_json([record], out)
            # Same conversation id under a second filename: exactly what the
            # cross-sweep dedupe exists to prevent.
            payload = json.loads(next(
                p for p in out.glob("*.json")
                if p.name != "export_summary.json"
            ).read_text(encoding="utf-8"))
            (out / "2026-03-04_duplicate.json").write_text(
                json.dumps(payload), encoding="utf-8")
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = acc.main(["acceptance_otter_export.py", str(out)])
        self.assertEqual(rc, 1)
        self.assertIn("duplicate conversation id", buf.getvalue())

    def test_acceptance_checker_fails_on_a_leaked_token(self):
        from scripts import acceptance_otter_export as acc
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            save_transcripts_json(self.records(1), out)
            (out / "2026-03-01_leak.json").write_text(json.dumps({
                "meeting_name": "Leaky", "date": "2026-03-01",
                "source_service": "otter.ai", "summary": "",
                "action_items": [], "full_text": "x",
                "duration_minutes": 1, "participants": [], "keywords": [],
                "transcript_id": "LEAK1", "transcript_url": "",
                "is_live": False,
                "note": "Authorization: Bearer abc123",
            }), encoding="utf-8")
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = acc.main(["acceptance_otter_export.py", str(out)])
        self.assertEqual(rc, 1)
        self.assertIn("secret marker", buf.getvalue())

    def test_acceptance_checker_rejects_a_missing_directory(self):
        from scripts import acceptance_otter_export as acc
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = acc.main(["acceptance_otter_export.py", "no/such/dir"])
        self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
