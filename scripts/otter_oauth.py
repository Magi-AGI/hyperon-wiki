#!/usr/bin/env python3
"""Otter.ai MCP OAuth 2.1 client: dynamic registration + PKCE + loopback.

Otter sells static API keys only on Enterprise workspaces, and the old
password-login private API (scripts/otterai/) is a dead end. The supported
no-cost path for an Otter Pro account is Otter's own remote MCP server at
https://mcp.otter.ai/mcp, which is OAuth-protected and self-onboarding: the
client registers itself via RFC 7591 dynamic client registration, so there is
no developer portal, no client_id to provision and no client secret.

Endpoints are discovered at runtime from the two well-known documents rather
than hardcoded, because the resource server and the authorization server live
on different hosts:

    https://mcp.otter.ai/.well-known/oauth-protected-resource
        -> resource: "https://mcp.otter.ai/"
        -> authorization_servers: ["https://otter.ai/"]
        -> scopes_supported: ["profile:read", "conversations:read"]
    https://otter.ai/.well-known/oauth-authorization-server
        -> authorization_endpoint: https://otter.ai/oauth2/authorize
        -> token_endpoint:         https://otter.ai/oauth/token
        -> registration_endpoint:  https://otter.ai/oauth/register
        -> revocation_endpoint:    https://otter.ai/oauth/revoke_token
        -> code_challenge_methods_supported: ["plain", "S256"]  (we send S256)
        -> token_endpoint_auth_methods_supported includes "none"

The granted scopes are read-only: `profile:read conversations:read`. There is
no write capability upstream, so this client cannot modify anything in Otter.

Credential store (never the repo):
    %LOCALAPPDATA%/magi-transcripts/otter/credentials.json   (Windows)
    ~/.config/magi-transcripts/otter/credentials.json         (POSIX, mode 600)

Usage — ONE command, ONE browser click:

    python scripts/otter_oauth.py authorize --open

That single subcommand discovers metadata, registers a client if needed,
binds a loopback listener on 127.0.0.1, prints (and optionally opens) the
consent URL, waits for Otter to redirect back, exchanges the code and writes
the tokens. Afterwards everything is headless:

    python scripts/otter_oauth.py status
    python scripts/otter_oauth.py refresh

WHY A LOOPBACK REDIRECT, NOT A HOSTED PASTE PAGE
Otter's authorization codes are short-lived: a long gap between minting the
authorize URL and approving it yields `invalid_grant` at the token step. A
loopback redirect closes that gap to milliseconds because the code never
passes through a human's clipboard. Several candidate ports are registered as
redirect_uris up front so a busy port does not force a re-registration.

NO TOKEN IS EVER PRINTED
Unlike the Read AI client this module deliberately exposes no `token`
subcommand. Access tokens, refresh tokens and registration access tokens are
written to the credential file and reported only as present/absent. Callers
inside this repo use get_access_token() in-process.
"""

import os
import re
import sys
import json
import time
import stat
import base64
import hashlib
import secrets
import socket
import argparse
import threading
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

# The MCP endpoint itself. Used as the RFC 8707 resource indicator's source;
# the canonical resource identifier is read from the metadata document.
OTTER_MCP_URL = "https://mcp.otter.ai/mcp"

# RFC 9728: the protected resource metadata for mcp.otter.ai is published at
# the root well-known path (the server advertises exactly this URL in the
# WWW-Authenticate challenge of an unauthenticated /mcp call).
PROTECTED_RESOURCE_METADATA_URL = (
    "https://mcp.otter.ai/.well-known/oauth-protected-resource"
)

# Fallbacks used only when a metadata document is reachable but incomplete.
FALLBACK_RESOURCE = "https://mcp.otter.ai/"
FALLBACK_AUTH_SERVER = "https://otter.ai/"

# Read-only scopes; these are the only two the server grants.
DEFAULT_SCOPE = "profile:read conversations:read"

# Every candidate port is registered as a redirect_uri so any one of them may
# be bound later without re-registering the client.
LOOPBACK_PORTS = (41789, 41790, 41791, 41792)
LOOPBACK_PATH = "/callback"

# Refresh this many seconds before nominal expiry to absorb clock skew and the
# round trip.
EXPIRY_SKEW_SECONDS = 60

# How long to wait for the human to finish the browser consent.
DEFAULT_CALLBACK_TIMEOUT = 300

USER_AGENT = "magi-transcripts-otter/1.0"

CLIENT_NAME = "Magi Transcript Pipeline"


# ---------------------------------------------------------------------------
# Credential storage (outside the repository)
# ---------------------------------------------------------------------------

def credential_dir() -> Path:
    """Resolve the on-disk credential directory, outside any git work tree."""
    override = os.environ.get("OTTER_CREDENTIAL_DIR")
    if override:
        return Path(override).expanduser()

    if os.name == "nt":
        base = os.environ.get("LOCALAPPDATA") or (Path.home() / "AppData" / "Local")
        return Path(base) / "magi-transcripts" / "otter"

    base = os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")
    return Path(base) / "magi-transcripts" / "otter"


def credential_path() -> Path:
    return credential_dir() / "credentials.json"


def _assert_outside_repo(path: Path) -> None:
    """Refuse to write credentials anywhere inside a git work tree."""
    resolved = path.resolve()
    for parent in [resolved, *resolved.parents]:
        if (parent / ".git").exists():
            raise SystemExit(
                f"REFUSING to write credentials inside a git repository: "
                f"{resolved}\nSet OTTER_CREDENTIAL_DIR to a path outside the repo."
            )


def load_credentials() -> dict:
    path = credential_path()
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError) as exc:
        raise SystemExit(f"ERROR: cannot read {path}: {exc}")


def save_credentials(data: dict) -> Path:
    """Write credentials atomically with owner-only permissions."""
    path = credential_path()
    _assert_outside_repo(path)
    path.parent.mkdir(parents=True, exist_ok=True)

    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2), encoding="utf-8")
    if os.name == "posix":
        os.chmod(tmp, stat.S_IRUSR | stat.S_IWUSR)
    # os.replace is atomic on POSIX and Windows: a crash leaves either the old
    # file or the new one, never a half-written token.
    os.replace(tmp, path)
    if os.name == "posix":
        os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
    return path


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def _http_json(url: str, data: bytes = None, headers: dict = None,
               method: str = None) -> dict:
    hdrs = {"Accept": "application/json", "User-Agent": USER_AGENT}
    hdrs.update(headers or {})
    request = urllib.request.Request(url, data=data, headers=hdrs,
                                     method=method)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            body = response.read().decode("utf-8")
            return json.loads(body) if body.strip() else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw)
        except ValueError:
            parsed = {"error": f"HTTP {exc.code}",
                      "error_description": raw[:500]}
        if not isinstance(parsed, dict):
            parsed = {"error": f"HTTP {exc.code}"}
        parsed.setdefault("__status", exc.code)
        return parsed
    except (urllib.error.URLError, TimeoutError) as exc:
        raise SystemExit(f"ERROR: network failure contacting {url}: {exc}")


# ---------------------------------------------------------------------------
# Discovery (RFC 9728 + RFC 8414)
# ---------------------------------------------------------------------------

def authorization_server_metadata_url(issuer: str) -> str:
    """Build the RFC 8414 metadata URL for an issuer.

    RFC 8414 section 3 inserts the well-known segment between the host and any
    issuer path component, so an issuer of "https://otter.ai/" resolves to
    https://otter.ai/.well-known/oauth-authorization-server and NOT to
    https://otter.ai/oauth-authorization-server.
    """
    parts = urllib.parse.urlsplit(issuer)
    issuer_path = parts.path.rstrip("/")
    return urllib.parse.urlunsplit((
        parts.scheme, parts.netloc,
        f"/.well-known/oauth-authorization-server{issuer_path}",
        "", "",
    ))


def discover(fetch_json=None) -> dict:
    """Discover the authorization server metadata for Otter's MCP server.

    Follows the spec chain rather than trusting hardcoded URLs:
    protected resource metadata -> authorization_servers -> AS metadata.
    `fetch_json` is injectable so tests can exercise the chain offline.
    """
    fetch = fetch_json or _http_json

    prm = fetch(PROTECTED_RESOURCE_METADATA_URL)
    servers = prm.get("authorization_servers") or []
    if not servers:
        raise SystemExit(
            f"ERROR: no authorization_servers in protected resource metadata "
            f"at {PROTECTED_RESOURCE_METADATA_URL}: "
            f"{prm.get('error_description') or prm}"
        )

    issuer = servers[0]
    as_url = authorization_server_metadata_url(issuer)
    meta = fetch(as_url)

    for required in ("authorization_endpoint", "token_endpoint"):
        if required not in meta:
            raise SystemExit(
                f"ERROR: authorization server metadata at {as_url} is missing "
                f"{required}"
            )

    return {
        "issuer": meta.get("issuer", issuer.rstrip("/")),
        "resource": prm.get("resource") or FALLBACK_RESOURCE,
        "authorization_endpoint": meta["authorization_endpoint"],
        "token_endpoint": meta["token_endpoint"],
        "registration_endpoint": meta.get("registration_endpoint"),
        "revocation_endpoint": meta.get("revocation_endpoint", ""),
        "scopes_supported": meta.get("scopes_supported", []),
        "resource_scopes": prm.get("scopes_supported", []),
        "code_challenge_methods_supported": meta.get(
            "code_challenge_methods_supported", []
        ),
        "token_endpoint_auth_methods_supported": meta.get(
            "token_endpoint_auth_methods_supported", []
        ),
    }


# ---------------------------------------------------------------------------
# PKCE (RFC 7636)
# ---------------------------------------------------------------------------

_VERIFIER_RE = re.compile(r"^[A-Za-z0-9\-._~]{43,128}$")


def generate_code_verifier(length: int = 64) -> str:
    """Generate a PKCE code_verifier.

    RFC 7636 section 4.1: 43-128 characters from the unreserved set
    [A-Za-z0-9-._~]. token_urlsafe emits '-' and '_' which are both allowed.
    """
    if not 43 <= length <= 128:
        raise ValueError("code_verifier length must be 43-128 characters")
    verifier = secrets.token_urlsafe(96)[:length]
    if not _VERIFIER_RE.match(verifier):
        raise ValueError("generated code_verifier is not RFC 7636 compliant")
    return verifier


def code_challenge_for(verifier: str) -> str:
    """S256 challenge: BASE64URL(SHA256(ASCII(verifier))), no padding."""
    if not _VERIFIER_RE.match(verifier):
        raise ValueError("code_verifier is not RFC 7636 compliant")
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    return base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")


# ---------------------------------------------------------------------------
# Loopback redirect
# ---------------------------------------------------------------------------

def redirect_uri_for(port: int) -> str:
    """Loopback redirect URI for a port.

    OAuth 2.1 / RFC 8252 section 7.3: use the literal 127.0.0.1 rather than
    "localhost", which may resolve to ::1 or be hijacked by a hosts entry.
    """
    return f"http://127.0.0.1:{port}{LOOPBACK_PATH}"


def all_redirect_uris(ports=LOOPBACK_PORTS) -> list:
    return [redirect_uri_for(p) for p in ports]


def pick_loopback_port(ports=LOOPBACK_PORTS, probe=None) -> int:
    """Return the first candidate port that can be bound on 127.0.0.1.

    Only ports registered as redirect_uris are considered: an ephemeral port
    would be rejected by the authorization server as an unregistered redirect.
    """
    check = probe or _port_is_free
    for port in ports:
        if check(port):
            return port
    raise SystemExit(
        f"ERROR: none of the registered loopback ports {list(ports)} is free. "
        f"Close whatever is listening and retry."
    )


def _port_is_free(port: int) -> bool:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.bind(("127.0.0.1", port))
        return True
    except OSError:
        return False
    finally:
        sock.close()


def parse_callback_query(path: str) -> dict:
    """Extract the OAuth parameters from a callback request path."""
    query = urllib.parse.urlsplit(path).query
    return dict(urllib.parse.parse_qsl(query, keep_blank_values=True))


_SUCCESS_HTML = (
    "<!doctype html><title>Otter connected</title>"
    "<body style='font-family:system-ui;max-width:34rem;margin:4rem auto'>"
    "<h1>Otter is connected.</h1>"
    "<p>The Magi transcript pipeline now holds a read-only token for "
    "<code>profile:read conversations:read</code>.</p>"
    "<p>You can close this tab and return to the terminal.</p></body>"
)


def _failure_html(message: str) -> str:
    safe = (message or "").replace("<", "&lt;").replace(">", "&gt;")
    return (
        "<!doctype html><title>Otter connection failed</title>"
        "<body style='font-family:system-ui;max-width:34rem;margin:4rem auto'>"
        "<h1>Connection failed.</h1>"
        f"<p><code>{safe}</code></p>"
        "<p>Re-run <code>python scripts/otter_oauth.py authorize --open</code>"
        "</p></body>"
    )


def serve_one_callback(port: int, handle, timeout: int) -> dict:
    """Serve exactly one loopback callback and let `handle` finish the flow.

    `handle(params)` runs BEFORE the HTTP response is written, so the browser
    tab stays open until the token exchange has been persisted. It returns
    (ok: bool, message: str). The returned dict reports the outcome.
    """
    outcome = {"received": False, "ok": False, "message": "timeout",
               "params": {}}

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.0"

        def do_GET(self):  # noqa: N802 - BaseHTTPRequestHandler API
            params = parse_callback_query(self.path)
            if urllib.parse.urlsplit(self.path).path != LOOPBACK_PATH:
                self.send_response(404)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return

            outcome["received"] = True
            outcome["params"] = {
                k: v for k, v in params.items() if k != "code"
            }
            try:
                ok, message = handle(params)
            except SystemExit as exc:
                ok, message = False, str(exc)
            except Exception as exc:  # pragma: no cover - defensive
                ok, message = False, f"{type(exc).__name__}: {exc}"
            outcome["ok"] = bool(ok)
            outcome["message"] = message

            body = (_SUCCESS_HTML if ok else _failure_html(message))
            raw = body.encode("utf-8")
            self.send_response(200 if ok else 400)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def log_message(self, *args):
            # The request path carries the authorization code; never log it.
            return

    server = HTTPServer(("127.0.0.1", port), Handler)
    server.timeout = timeout
    thread = threading.Thread(target=server.handle_request, daemon=True)
    thread.start()
    thread.join(timeout + 5)
    server.server_close()
    return outcome


# ---------------------------------------------------------------------------
# Dynamic client registration (RFC 7591)
# ---------------------------------------------------------------------------

def build_registration_payload(client_name: str, redirect_uris: list,
                               scope: str) -> dict:
    """Body for an RFC 7591 public-client registration.

    token_endpoint_auth_method is "none": Otter advertises it, and a public
    client with PKCE has no secret to protect on a developer workstation.
    """
    return {
        "client_name": client_name,
        "redirect_uris": list(redirect_uris),
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "scope": scope,
        "token_endpoint_auth_method": "none",
        "application_type": "native",
    }


def parse_registration_response(resp: dict) -> dict:
    """Validate a DCR response and reduce it to the fields we persist."""
    if not isinstance(resp, dict) or "client_id" not in resp:
        detail = ""
        if isinstance(resp, dict):
            detail = (resp.get("error_description") or resp.get("error")
                      or json.dumps(resp)[:300])
        raise SystemExit(
            f"ERROR: dynamic client registration failed: {detail or resp}"
        )
    return {
        "client_id": resp["client_id"],
        "client_secret": resp.get("client_secret", ""),
        "registration_access_token": resp.get("registration_access_token", ""),
        "registration_client_uri": resp.get("registration_client_uri", ""),
        "token_endpoint_auth_method": resp.get(
            "token_endpoint_auth_method", "none"),
        "granted_registration_scope": resp.get("scope", ""),
    }


def register_client(client_name: str = CLIENT_NAME, scope: str = DEFAULT_SCOPE,
                    ports=LOOPBACK_PORTS, meta: dict = None,
                    post_json=None) -> dict:
    """Register a public client and persist the client_id."""
    meta = meta or discover()
    endpoint = meta.get("registration_endpoint")
    if not endpoint:
        raise SystemExit(
            "ERROR: Otter's authorization server advertises no "
            "registration_endpoint; dynamic client registration is "
            "unavailable and a client must be provisioned manually."
        )

    payload = build_registration_payload(client_name, all_redirect_uris(ports),
                                         scope)
    poster = post_json or (lambda url, body: _http_json(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    ))
    parsed = parse_registration_response(poster(endpoint, payload))

    creds = load_credentials()
    creds.update(parsed)
    creds.update({
        "redirect_uris": all_redirect_uris(ports),
        "scope": scope,
        "issuer": meta["issuer"],
        "resource": meta["resource"],
        "authorization_endpoint": meta["authorization_endpoint"],
        "token_endpoint": meta["token_endpoint"],
        "revocation_endpoint": meta.get("revocation_endpoint", ""),
        "registered_at": int(time.time()),
    })
    save_credentials(creds)
    return parsed


# ---------------------------------------------------------------------------
# Authorization request
# ---------------------------------------------------------------------------

def build_authorize_url(creds: dict, verifier: str, state: str,
                        redirect_uri: str, resource: str = None) -> str:
    """Construct the OAuth 2.1 + PKCE authorization URL."""
    params = {
        "response_type": "code",
        "client_id": creds["client_id"],
        "redirect_uri": redirect_uri,
        "scope": creds.get("scope", DEFAULT_SCOPE),
        "state": state,
        "code_challenge": code_challenge_for(verifier),
        # RFC 7636 section 4.3: this parameter defaults to "plain" when
        # omitted, and Otter advertises "plain" as supported — so S256 must be
        # sent explicitly or PKCE is silently downgraded.
        "code_challenge_method": "S256",
    }
    resource = resource or creds.get("resource")
    if resource:
        # RFC 8707 resource indicator; the MCP authorization spec requires it
        # on both the authorize and the token request.
        params["resource"] = resource

    return (
        creds["authorization_endpoint"]
        + "?"
        + urllib.parse.urlencode(params, quote_via=urllib.parse.quote)
    )


# ---------------------------------------------------------------------------
# Token endpoint
# ---------------------------------------------------------------------------

def build_token_form(creds: dict, form: dict) -> dict:
    """Add client authentication to a token request body.

    Otter registers us as a public client (token_endpoint_auth_method
    "none"), so client_id travels in the form and there is no secret. The
    client_secret_post branch exists only so a future non-public registration
    does not silently authenticate as nobody.
    """
    body = dict(form)
    body["client_id"] = creds["client_id"]
    if creds.get("client_secret"):
        body["client_secret"] = creds["client_secret"]
    return body


def _token_request(creds: dict, form: dict, post_form=None) -> dict:
    body = build_token_form(creds, form)
    poster = post_form or (lambda url, data: _http_json(
        url,
        data=urllib.parse.urlencode(data).encode("utf-8"),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    ))
    return poster(creds["token_endpoint"], body)


def store_token_response(creds: dict, resp: dict) -> dict:
    """Persist a token response atomically before the caller uses it."""
    creds["access_token"] = resp.get("access_token", "")
    creds["token_type"] = resp.get("token_type", "bearer")
    creds["granted_scope"] = resp.get("scope", creds.get("granted_scope", ""))
    expires_in = int(resp.get("expires_in") or 0)
    creds["expires_at"] = int(time.time()) + expires_in if expires_in else 0

    # Only overwrite when the server issued a new one: if Otter rotates the
    # refresh token we must keep the new one, and if it does not send one we
    # must not blank out the still-valid old one.
    if resp.get("refresh_token"):
        creds["refresh_token"] = resp["refresh_token"]
        creds["refresh_rotated_at"] = int(time.time())

    save_credentials(creds)
    return creds


def exchange_code(creds: dict, code: str, verifier: str, redirect_uri: str,
                  resource: str = None, post_form=None) -> dict:
    """Exchange an authorization code for tokens and persist them."""
    form = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirect_uri,
        "code_verifier": verifier,
    }
    resource = resource or creds.get("resource")
    if resource:
        form["resource"] = resource

    resp = _token_request(creds, form, post_form=post_form)
    if "access_token" not in resp:
        raise SystemExit(
            f"ERROR: code exchange failed: "
            f"{resp.get('error_description') or resp.get('error') or resp}\n"
            f"Otter authorization codes are short-lived; if this says "
            f"invalid_grant, just re-run 'authorize --open' and approve "
            f"promptly."
        )
    return store_token_response(creds, resp)


def refresh_access_token(creds: dict = None, post_form=None) -> dict:
    """Exchange the refresh token, persisting any rotated one atomically."""
    creds = creds or load_credentials()
    if not creds.get("refresh_token"):
        raise SystemExit(
            "ERROR: no refresh token stored. Re-run the browser flow: "
            "python scripts/otter_oauth.py authorize --open"
        )

    lock = credential_dir() / "refresh.lock"
    lock.parent.mkdir(parents=True, exist_ok=True)
    acquired = False
    for _ in range(60):
        try:
            fd = os.open(str(lock), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.close(fd)
            acquired = True
            break
        except FileExistsError:
            # Reap a lock orphaned by a crashed process.
            try:
                if time.time() - lock.stat().st_mtime > 120:
                    lock.unlink(missing_ok=True)
                    continue
            except OSError:
                pass
            time.sleep(0.5)

    if not acquired:
        raise SystemExit(
            f"ERROR: could not acquire {lock}; another refresh is in flight."
        )

    try:
        # Re-read under the lock: another process may have just rotated.
        creds = load_credentials()
        form = {
            "grant_type": "refresh_token",
            "refresh_token": creds["refresh_token"],
        }
        if creds.get("scope"):
            form["scope"] = creds["scope"]
        if creds.get("resource"):
            form["resource"] = creds["resource"]

        resp = _token_request(creds, form, post_form=post_form)
        if "access_token" not in resp:
            raise SystemExit(
                f"ERROR: refresh failed: "
                f"{resp.get('error_description') or resp.get('error') or resp}"
                f"\nRe-run the browser consent: "
                f"python scripts/otter_oauth.py authorize --open"
            )
        return store_token_response(creds, resp)
    finally:
        lock.unlink(missing_ok=True)


def token_is_fresh(creds: dict, now: float = None) -> bool:
    """True when the stored access token is usable without a refresh."""
    if not creds.get("access_token"):
        return False
    expires_at = creds.get("expires_at") or 0
    if not expires_at:
        # No expiry advertised: treat as usable and let a 401 drive a refresh.
        return True
    now = time.time() if now is None else now
    return now < expires_at - EXPIRY_SKEW_SECONDS


def get_access_token() -> str:
    """Return a usable access token, refreshing when it is near expiry.

    In-process use only — the value is never printed by this module.
    """
    creds = load_credentials()
    if not creds.get("access_token") and not creds.get("refresh_token"):
        raise SystemExit(
            "ERROR: no Otter token stored. Run:\n"
            "  python scripts/otter_oauth.py authorize --open"
        )
    if not token_is_fresh(creds):
        creds = refresh_access_token(creds)
    return creds["access_token"]


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_discover() -> int:
    print(json.dumps(discover(), indent=2))
    return 0


def cmd_register(client_name: str, scope: str) -> int:
    parsed = register_client(client_name=client_name, scope=scope)
    print("Client registered with Otter (RFC 7591 dynamic registration).")
    print(f"  credential file : {credential_path()}")
    print(f"  client_secret   : "
          f"{'issued' if parsed['client_secret'] else 'none (public client)'}")
    print(f"  auth method     : {parsed['token_endpoint_auth_method']}")
    print(f"  requested scope : {scope}")
    print("\nNext: python scripts/otter_oauth.py authorize --open")
    return 0


def cmd_authorize(open_browser: bool, timeout: int, port: int = None,
                  scope: str = DEFAULT_SCOPE) -> int:
    """Register if needed, then run the whole consent in one invocation.

    Deliberately end-to-end: Otter's authorization codes expire quickly, so
    splitting "print a URL" from "exchange a code" across two commands is how
    people end up staring at invalid_grant.
    """
    creds = load_credentials()
    if not creds.get("client_id"):
        print("No client registered yet; registering one first...")
        register_client(scope=scope)
        creds = load_credentials()

    chosen = port or pick_loopback_port()
    redirect_uri = redirect_uri_for(chosen)
    if redirect_uri not in (creds.get("redirect_uris") or []):
        raise SystemExit(
            f"ERROR: {redirect_uri} is not one of the registered redirect "
            f"URIs {creds.get('redirect_uris')}. Re-run 'register'."
        )

    verifier = generate_code_verifier()
    state = secrets.token_urlsafe(24)
    url = build_authorize_url(creds, verifier, state, redirect_uri)

    url_file = credential_dir() / "authorize_url.txt"
    url_file.parent.mkdir(parents=True, exist_ok=True)
    url_file.write_text(url + "\n", encoding="utf-8")

    print("=" * 72)
    print("ACTION REQUIRED — approve Otter access in a browser (one click)")
    print("=" * 72)
    print()
    print(url)
    print()
    print(f"Saved to: {url_file}")
    print("(Copy from that file rather than a wrapped terminal line — a "
          "truncated client_id surfaces as 'invalid_client'.)")
    print()
    print(f"Listening on {redirect_uri} for up to {timeout}s.")
    print("Sign in to Otter as the account that owns the conversations, then "
          "click 'Authorize access'.")
    print("Requested scopes are READ-ONLY: " +
          (creds.get("scope") or DEFAULT_SCOPE))
    print()
    if open_browser:
        print("Opening the default browser...")
        webbrowser.open(url)
        print()

    def handle(params):
        if params.get("error"):
            return False, (params["error"] + ": " +
                           params.get("error_description", ""))
        if not params.get("code"):
            return False, "no authorization code in the callback"
        returned_state = params.get("state") or ""
        if not secrets.compare_digest(returned_state, state):
            return False, "state mismatch — callback belongs to another flow"
        exchange_code(load_credentials(), params["code"], verifier,
                      redirect_uri)
        return True, "tokens stored"

    outcome = serve_one_callback(chosen, handle, timeout)

    if not outcome["received"]:
        print("TIMED OUT: no callback arrived. Nothing was stored.")
        print("Re-run: python scripts/otter_oauth.py authorize --open")
        return 1
    if not outcome["ok"]:
        print(f"FAILED: {outcome['message']}")
        return 1

    print("Authorization complete.")
    cmd_status()
    return 0


def cmd_refresh() -> int:
    refresh_access_token()
    print("Refreshed.")
    cmd_status()
    return 0


def cmd_status() -> int:
    creds = load_credentials()
    path = credential_path()
    if not creds:
        print(f"No credentials at {path}")
        print("Run: python scripts/otter_oauth.py authorize --open")
        return 0

    remaining = (creds.get("expires_at") or 0) - int(time.time())
    print(f"Credential file:   {path}")
    print(f"Client registered: {'yes' if creds.get('client_id') else 'no'}")
    print(f"Client secret:     "
          f"{'present' if creds.get('client_secret') else 'none (public)'}")
    print(f"Access token:      "
          f"{'present' if creds.get('access_token') else 'none'}")
    if creds.get("expires_at"):
        print(f"Access expires in: "
              f"{str(remaining) + 's' if remaining > 0 else 'EXPIRED'}")
    else:
        print("Access expires in: unknown (no expires_in advertised)")
    print(f"Refresh token:     "
          f"{'present' if creds.get('refresh_token') else 'none'}")
    print(f"Granted scope:     "
          f"{creds.get('granted_scope') or creds.get('scope') or '-'}")
    print(f"Resource:          {creds.get('resource') or '-'}")
    print(f"Token usable now:  "
          f"{'yes' if token_is_fresh(creds) else 'no — will refresh'}")
    # Deliberately prints no token material.
    return 0


def cmd_logout() -> int:
    """Revoke the stored tokens upstream, then delete them locally."""
    creds = load_credentials()
    endpoint = creds.get("revocation_endpoint")
    revoked = []
    if endpoint:
        for kind in ("refresh_token", "access_token"):
            if not creds.get(kind):
                continue
            form = {"token": creds[kind], "token_type_hint": kind,
                    "client_id": creds.get("client_id", "")}
            _http_json(
                endpoint,
                data=urllib.parse.urlencode(form).encode("utf-8"),
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                method="POST",
            )
            revoked.append(kind)

    for key in ("access_token", "refresh_token", "granted_scope",
                "expires_at", "token_type", "refresh_rotated_at"):
        creds.pop(key, None)
    if creds:
        save_credentials(creds)

    print(f"Revoked upstream: {', '.join(revoked) if revoked else 'nothing'}")
    print("Local tokens cleared (client registration kept).")
    return 0


def main():
    parser = argparse.ArgumentParser(
        description="Otter.ai MCP OAuth 2.1 client (DCR + PKCE + loopback)"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("discover", help="Print discovered OAuth endpoints")

    p_reg = sub.add_parser("register",
                           help="Dynamically register a public client")
    p_reg.add_argument("--client-name", default=CLIENT_NAME)
    p_reg.add_argument("--scope", default=DEFAULT_SCOPE)

    p_auth = sub.add_parser(
        "authorize",
        help="Run the whole browser consent in one command (one click)")
    p_auth.add_argument("--open", action="store_true", dest="open_browser",
                        help="Launch the default browser on the consent URL")
    p_auth.add_argument("--timeout", type=int,
                        default=DEFAULT_CALLBACK_TIMEOUT,
                        help="Seconds to wait for the browser callback")
    p_auth.add_argument("--port", type=int, default=None,
                        help="Force one of the registered loopback ports")
    p_auth.add_argument("--scope", default=DEFAULT_SCOPE)

    sub.add_parser("refresh", help="Force a token refresh now")
    sub.add_parser("status", help="Show credential state (no secrets)")
    sub.add_parser("logout", help="Revoke and clear the stored tokens")

    args = parser.parse_args()

    if args.command == "discover":
        return cmd_discover()
    if args.command == "register":
        return cmd_register(args.client_name, args.scope)
    if args.command == "authorize":
        return cmd_authorize(args.open_browser, args.timeout, args.port,
                             args.scope)
    if args.command == "refresh":
        return cmd_refresh()
    if args.command == "status":
        return cmd_status()
    if args.command == "logout":
        return cmd_logout()
    return 2


if __name__ == "__main__":
    sys.exit(main())
