#!/usr/bin/env python3
"""Read AI OAuth 2.1 client: dynamic client registration + PKCE + token refresh.

Read AI's REST API and MCP server do not issue static API keys (Read AI lists
those as a GA-only plan). Access requires OAuth 2.1 with RFC 7591 dynamic
client registration and RFC 7636 PKCE. This script implements that flow and
stores credentials OUTSIDE the repository.

Endpoints are discovered at runtime from the two well-known documents rather
than hardcoded, because Read AI's registration endpoint lives on api.read.ai
while authorize/token live on authn.read.ai, and the API is in open beta:

    https://api.read.ai/.well-known/oauth-protected-resource/mcp
        -> authorization_servers: ["https://authn.read.ai/"]
    https://authn.read.ai/.well-known/oauth-authorization-server
        -> authorization_endpoint, token_endpoint, registration_endpoint

Credential store (never the repo):
    %LOCALAPPDATA%/magi-transcripts/readai/credentials.json   (Windows)
    ~/.config/magi-transcripts/readai/credentials.json        (POSIX, mode 600)

Usage:
    # 1. Register a client and print the URL to open in a browser
    python scripts/readai_oauth.py register
    python scripts/readai_oauth.py authorize --open

    # 2. Approve in the browser, then paste the FULL post-approval URL
    python scripts/readai_oauth.py exchange --redirect-url "<URL>"

    # 3. Thereafter: print a valid access token, refreshing if needed
    python scripts/readai_oauth.py token
    python scripts/readai_oauth.py status

"SESSION DATA NOT FOUND" IS EXPECTED, NOT A FAILURE
The registered redirect target, https://api.read.ai/oauth/ui, is Read AI's
browser-side OAuth playground. Its own "Start OAuth Flow" button mints a PKCE
code_verifier in JavaScript and keeps it in sessionStorage; its callback
handler then refuses to render the code unless it finds that same
sessionStorage entry. Because this script starts the flow itself (and holds
the only copy of the verifier on disk), sessionStorage is empty and the page
renders "Session Data Not Found" after you click "Allow Access". The
authorization code is still present in the page's address bar as ?code=...,
so pass that whole URL to 'exchange --redirect-url'. Never click that page's
"Try Again" link: it restarts the flow with a browser-generated verifier this
script cannot reproduce, and discards the code you already earned.

A loopback redirect (http://127.0.0.1:PORT/...) would avoid the dance, but
Read AI's documentation instructs that redirect_uris be left unmodified, so
it is not assumed to be accepted.

TOKEN LIFECYCLE WARNING
Read AI access tokens expire in ~10 minutes and refresh tokens are SINGLE USE:
each refresh returns a new refresh token and invalidates the old one after a
short grace period. If a process crashes between receiving and persisting the
rotated token, the chain breaks and a human must redo the browser consent.
This module therefore writes the new refresh token to disk atomically
(tmp file + os.replace) BEFORE returning the access token, and serialises
refreshes behind a lock file so two processes cannot race the rotation.
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
import argparse
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path

# Canonical resource identifier for the Read AI MCP server. The protected
# resource metadata document is published at the RFC 9728 path-suffixed
# location derived from this URI.
READAI_MCP_RESOURCE = "https://api.read.ai/mcp"
READAI_REST_RESOURCE = "https://api.read.ai/v1/meetings"

# RFC 9728 section 3: insert /.well-known/oauth-protected-resource between the
# host and the path of the resource identifier.
PROTECTED_RESOURCE_METADATA_URL = (
    "https://api.read.ai/.well-known/oauth-protected-resource/mcp"
)

# Read AI's documented redirect URI: a hosted helper page that displays the
# authorization code for the user to copy. Read AI's docs instruct leaving
# this unmodified, so a loopback redirect is not assumed to work.
DEFAULT_REDIRECT_URI = "https://api.read.ai/oauth/ui"

DEFAULT_SCOPE = "openid email offline_access profile meeting:read mcp:execute"

# Refresh this many seconds before nominal expiry to absorb clock skew and
# the round trip; access tokens only live ~600 seconds.
EXPIRY_SKEW_SECONDS = 60

USER_AGENT = "magi-transcripts-readai/1.0"


# ---------------------------------------------------------------------------
# Credential storage (outside the repository)
# ---------------------------------------------------------------------------

def credential_dir() -> Path:
    """Resolve the on-disk credential directory, outside any git work tree."""
    override = os.environ.get("READAI_CREDENTIAL_DIR")
    if override:
        return Path(override).expanduser()

    if os.name == "nt":
        base = os.environ.get("LOCALAPPDATA") or (Path.home() / "AppData" / "Local")
        return Path(base) / "magi-transcripts" / "readai"

    base = os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")
    return Path(base) / "magi-transcripts" / "readai"


def credential_path() -> Path:
    return credential_dir() / "credentials.json"


def _assert_outside_repo(path: Path) -> None:
    """Refuse to write credentials anywhere inside a git work tree."""
    resolved = path.resolve()
    for parent in [resolved, *resolved.parents]:
        if (parent / ".git").exists():
            raise SystemExit(
                f"REFUSING to write credentials inside a git repository: "
                f"{resolved}\nSet READAI_CREDENTIAL_DIR to a path outside the repo."
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
    # file or the new one, never a truncated token.
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
            parsed = {"error": f"HTTP {exc.code}", "error_description": raw[:500]}
        parsed.setdefault("__status", exc.code)
        return parsed
    except (urllib.error.URLError, TimeoutError) as exc:
        raise SystemExit(f"ERROR: network failure contacting {url}: {exc}")


# ---------------------------------------------------------------------------
# Discovery (RFC 9728 + RFC 8414)
# ---------------------------------------------------------------------------

def discover() -> dict:
    """Discover the authorization server metadata for the Read AI MCP server.

    Follows the spec chain rather than trusting hardcoded URLs:
    protected resource metadata -> authorization_servers -> AS metadata.
    """
    prm = _http_json(PROTECTED_RESOURCE_METADATA_URL)
    if "authorization_servers" not in prm:
        raise SystemExit(
            f"ERROR: no authorization_servers in protected resource metadata "
            f"at {PROTECTED_RESOURCE_METADATA_URL}: "
            f"{prm.get('error_description') or prm}"
        )

    issuer = prm["authorization_servers"][0]
    # RFC 8414 section 3: insert the well-known segment between host and path.
    parts = urllib.parse.urlsplit(issuer)
    issuer_path = parts.path.rstrip("/")
    as_url = urllib.parse.urlunsplit((
        parts.scheme, parts.netloc,
        f"/.well-known/oauth-authorization-server{issuer_path}",
        "", "",
    ))

    meta = _http_json(as_url)
    for required in ("authorization_endpoint", "token_endpoint"):
        if required not in meta:
            raise SystemExit(
                f"ERROR: authorization server metadata at {as_url} is missing "
                f"{required}"
            )

    return {
        "issuer": meta.get("issuer", issuer),
        "authorization_endpoint": meta["authorization_endpoint"],
        "token_endpoint": meta["token_endpoint"],
        "registration_endpoint": meta.get("registration_endpoint"),
        "scopes_supported": meta.get("scopes_supported", []),
        "code_challenge_methods_supported": meta.get(
            "code_challenge_methods_supported", []
        ),
        "resource_scopes": prm.get("scopes_supported", []),
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
# Flow steps
# ---------------------------------------------------------------------------

def register_client(client_name: str, redirect_uri: str,
                    scope: str) -> dict:
    """RFC 7591 dynamic client registration."""
    meta = discover()
    endpoint = meta.get("registration_endpoint")
    if not endpoint:
        raise SystemExit(
            "ERROR: the authorization server advertises no "
            "registration_endpoint; dynamic client registration is "
            "unavailable and a client must be provisioned manually."
        )

    payload = {
        "client_name": client_name,
        "redirect_uris": [redirect_uri],
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "scope": scope,
        "token_endpoint_auth_method": "client_secret_basic",
    }

    resp = _http_json(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    if "client_id" not in resp:
        raise SystemExit(
            f"ERROR: registration failed: "
            f"{resp.get('error_description') or resp.get('error') or resp}"
        )

    creds = load_credentials()
    creds.update({
        "client_id": resp["client_id"],
        "client_secret": resp.get("client_secret", ""),
        "registration_access_token": resp.get("registration_access_token", ""),
        "registration_client_uri": resp.get("registration_client_uri", ""),
        "redirect_uri": redirect_uri,
        "scope": resp.get("scope", scope),
        "audience": resp.get("audience", []),
        "issuer": meta["issuer"],
        "authorization_endpoint": meta["authorization_endpoint"],
        "token_endpoint": meta["token_endpoint"],
        "registered_at": int(time.time()),
    })
    path = save_credentials(creds)

    print("Client registered.")
    print(f"  client_id stored in: {path}")
    print(f"  client_secret issued: {'yes' if resp.get('client_secret') else 'no'}")
    print(f"  granted scope: {resp.get('scope', scope)}")
    print("\nNext: python scripts/readai_oauth.py authorize")
    return resp


def build_authorize_url(creds: dict, verifier: str,
                        state: str, resource: str = None) -> str:
    """Construct the OAuth 2.1 + PKCE authorization URL."""
    params = {
        "response_type": "code",
        "client_id": creds["client_id"],
        "redirect_uri": creds["redirect_uri"],
        "scope": creds.get("scope", DEFAULT_SCOPE),
        "state": state,
        "code_challenge": code_challenge_for(verifier),
        # RFC 7636 section 4.3: this parameter defaults to "plain" when
        # omitted, so S256 must be sent explicitly.
        "code_challenge_method": "S256",
    }
    if resource:
        # RFC 8707 resource indicator; the MCP spec requires it on both the
        # authorize and token requests.
        params["resource"] = resource

    return (
        creds["authorization_endpoint"]
        + "?"
        + urllib.parse.urlencode(params, quote_via=urllib.parse.quote)
    )


def _preflight_authorize_url(url: str) -> str:
    """GET the authorize URL without following redirects to catch a dead client.

    A healthy request 302s toward Read AI's hosted login page. A client_id the
    authorization server has never seen comes back as invalid_client, which in
    a browser renders as "The requested OAuth 2.0 Client does not exist" —
    catching it here saves the user a confusing round trip.
    """
    class _NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            return None

    opener = urllib.request.build_opener(_NoRedirect)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with opener.open(request, timeout=30) as response:
            status = response.status
            location = response.headers.get("Location", "")
    except urllib.error.HTTPError as exc:
        status = exc.code
        location = exc.headers.get("Location", "")
    except (urllib.error.URLError, TimeoutError) as exc:
        return f"skipped (network: {exc})"

    if status in (301, 302, 303, 307, 308):
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(location).query)
        error = (query.get("error") or [""])[0]
        if error:
            return f"FAILED ({error}) — re-run 'register'"
        return "ok (server accepted the client and is redirecting to login)"
    if status == 200:
        return "ok (server rendered a page directly)"
    return f"unexpected HTTP {status}"


def cmd_authorize(resource: str = None, open_browser: bool = False) -> None:
    creds = load_credentials()
    if not creds.get("client_id"):
        raise SystemExit(
            "ERROR: no registered client. Run "
            "'python scripts/readai_oauth.py register' first."
        )

    if creds.get("pending_verifier"):
        print("NOTE: a previous 'authorize' is still pending. Generating a new "
              "URL invalidates the old one — do not use any URL you copied "
              "earlier.\n")

    verifier = generate_code_verifier()
    state = secrets.token_urlsafe(24)

    creds["pending_verifier"] = verifier
    creds["pending_state"] = state
    creds["pending_resource"] = resource or ""
    creds["pending_started_at"] = int(time.time())
    save_credentials(creds)

    url = build_authorize_url(creds, verifier, state, resource)
    _emit_authorize_url(url, open_browser)


def cmd_url(open_browser: bool = False) -> None:
    """Re-print the CURRENT pending authorization URL without rotating PKCE.

    Use this when the URL was lost or mangled in copy/paste; re-running
    'authorize' would invalidate the verifier that matches an already-issued
    code.
    """
    creds = load_credentials()
    if not creds.get("client_id"):
        raise SystemExit(
            "ERROR: no registered client. Run "
            "'python scripts/readai_oauth.py register' first."
        )
    verifier = creds.get("pending_verifier")
    if not verifier:
        raise SystemExit(
            "ERROR: no pending authorization. Run "
            "'python scripts/readai_oauth.py authorize' first."
        )
    url = build_authorize_url(creds, verifier, creds["pending_state"],
                              creds.get("pending_resource") or None)
    _emit_authorize_url(url, open_browser)


def _emit_authorize_url(url: str, open_browser: bool) -> None:
    """Print the consent URL, write it to a file, and optionally open it.

    The URL is ~360 characters and wraps in a terminal; copying a wrapped line
    truncates the client_id and the server then reports invalid_client. Writing
    it to a file and offering --open removes that failure mode.
    """
    url_file = credential_dir() / "authorize_url.txt"
    url_file.parent.mkdir(parents=True, exist_ok=True)
    url_file.write_text(url + "\n", encoding="utf-8")

    print(f"Client preflight: {_preflight_authorize_url(url)}")
    print()

    print("=" * 72)
    print("ACTION REQUIRED — open this URL in a browser and sign in to Read AI")
    print("=" * 72)
    print()
    print(url)
    print()
    print(f"Saved to: {url_file}")
    print("(Copy from that file, or re-run with --open, rather than copying "
          "a wrapped terminal line — a truncated client_id surfaces as "
          "'invalid_client'.)")
    print()
    if open_browser:
        print("Opening the default browser...")
        webbrowser.open(url)
        print()
    print("-" * 72)
    print("EXPECTED: after you click 'Allow Access', https://api.read.ai/oauth/ui")
    print("will render:  \"Session Data Not Found\"")
    print()
    print("That error is HARMLESS here and is not a failure of this flow.")
    print("That page is Read AI's standalone browser playground: its own")
    print("'Start OAuth Flow' button generates a PKCE verifier in the browser and")
    print("stashes it in sessionStorage, then its callback handler refuses to")
    print("render unless it finds that sessionStorage entry. We start the flow")
    print("from this script instead, so sessionStorage is legitimately empty --")
    print("but the authorization code is still delivered, in the page URL.")
    print()
    print("Do NOT click 'Try Again' (it restarts with a browser-side verifier")
    print("that this script does not hold, and your code is discarded).")
    print("-" * 72)
    print()
    print("Instead, copy the FULL address-bar URL of that error page and run:")
    print()
    print("  python scripts/readai_oauth.py exchange --redirect-url \"<PASTED_URL>\"")
    print()
    print("(--redirect-url pulls out code and state and verifies state for you.")
    print(" If you prefer, 'exchange --code <AUTH_CODE>' still works.)")
    print()
    print("The PKCE verifier and state are saved locally; do not run "
          "'authorize' again until you have exchanged this code.")


def _token_request(creds: dict, form: dict) -> dict:
    """POST to the token endpoint with client_secret_basic auth."""
    body = urllib.parse.urlencode(form).encode("utf-8")
    headers = {"Content-Type": "application/x-www-form-urlencoded"}

    secret = creds.get("client_secret")
    if secret:
        raw = f"{creds['client_id']}:{secret}".encode("utf-8")
        headers["Authorization"] = "Basic " + base64.b64encode(raw).decode()
    else:
        # Public client: no secret to present, so identify via the form.
        form = dict(form, client_id=creds["client_id"])
        body = urllib.parse.urlencode(form).encode("utf-8")

    return _http_json(creds["token_endpoint"], data=body, headers=headers,
                      method="POST")


def _store_token_response(creds: dict, resp: dict) -> dict:
    """Persist a token response atomically before the caller uses it."""
    creds["access_token"] = resp.get("access_token", "")
    creds["token_type"] = resp.get("token_type", "bearer")
    creds["granted_scope"] = resp.get("scope", "")
    expires_in = int(resp.get("expires_in") or 0)
    creds["expires_at"] = int(time.time()) + expires_in if expires_in else 0

    # Single-use rotation: only overwrite when the server issued a new one,
    # never blank out a still-valid refresh token.
    if resp.get("refresh_token"):
        creds["refresh_token"] = resp["refresh_token"]
        creds["refresh_rotated_at"] = int(time.time())

    save_credentials(creds)
    return creds


def _parse_redirect_url(redirect_url: str) -> tuple:
    """Extract (code, state) from a pasted post-approval address-bar URL.

    Read AI's hosted redirect target (https://api.read.ai/oauth/ui) is a
    browser-side playground that only renders the code when it finds a
    code_verifier it generated itself in sessionStorage. When the flow is
    started from this script that entry is absent, so the page shows
    "Session Data Not Found" — but the authorization server still appended
    ?code=...&state=... to the URL, so the code is recoverable from the
    address bar. Accepts a bare query string or fragment form too.
    """
    text = (redirect_url or "").strip().strip('"').strip("'")
    if not text:
        raise SystemExit("ERROR: --redirect-url was empty.")

    parts = urllib.parse.urlsplit(text)
    query = dict(urllib.parse.parse_qsl(parts.query, keep_blank_values=True))
    # Some providers return parameters in the fragment; merge it as a fallback.
    if parts.fragment:
        for key, value in urllib.parse.parse_qsl(parts.fragment,
                                                 keep_blank_values=True):
            query.setdefault(key, value)
    if not query and "=" in text:
        # The user pasted only the query string, e.g. "code=...&state=...".
        query = dict(urllib.parse.parse_qsl(text.lstrip("?#"),
                                            keep_blank_values=True))

    if query.get("error"):
        raise SystemExit(
            f"ERROR: the authorization server returned an error instead of a "
            f"code: {query['error']}"
            + (f" — {query['error_description']}"
               if query.get("error_description") else "")
            + "\nRe-run 'authorize --open' to start a fresh consent."
        )

    code = query.get("code")
    if not code:
        raise SystemExit(
            "ERROR: no 'code' parameter found in the URL you pasted.\n"
            "Paste the FULL address-bar URL of the page you landed on after "
            "clicking 'Allow Access' — it must contain '?code='.\n"
            "If the URL has no code, the consent did not complete; re-run "
            "'authorize --open'."
        )
    return code, query.get("state")


def cmd_exchange(code: str = None, state: str = None,
                 redirect_url: str = None) -> None:
    if redirect_url:
        parsed_code, parsed_state = _parse_redirect_url(redirect_url)
        if code and code != parsed_code:
            raise SystemExit(
                "ERROR: --code and the code inside --redirect-url disagree; "
                "pass only one of them."
            )
        code = parsed_code
        # A state parsed out of the real redirect is trustworthy, so prefer it
        # over nothing and let the comparison below actually run.
        state = state or parsed_state
    if not code:
        raise SystemExit(
            "ERROR: provide either --code <AUTH_CODE> or "
            "--redirect-url \"<FULL_URL_AFTER_APPROVAL>\"."
        )

    creds = load_credentials()
    verifier = creds.get("pending_verifier")
    if not verifier:
        raise SystemExit(
            "ERROR: no pending PKCE verifier. Run 'authorize' first."
        )

    expected_state = creds.get("pending_state")
    if state and expected_state and not secrets.compare_digest(
        state, expected_state
    ):
        raise SystemExit(
            "ERROR: state mismatch — this code belongs to a different "
            "authorization attempt (for example one started from Read AI's "
            "own 'Start OAuth Flow' button, whose PKCE verifier lives only in "
            "the browser). Run 'authorize --open' and approve again."
        )

    form = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": creds["redirect_uri"],
        "code_verifier": verifier,
    }
    if creds.get("pending_resource"):
        form["resource"] = creds["pending_resource"]

    resp = _token_request(creds, form)
    if "access_token" not in resp:
        raise SystemExit(
            f"ERROR: code exchange failed: "
            f"{resp.get('error_description') or resp.get('error') or resp}"
        )

    for key in ("pending_verifier", "pending_state", "pending_resource",
                "pending_started_at"):
        creds.pop(key, None)
    creds = _store_token_response(creds, resp)

    print("Token exchange succeeded.")
    print(f"  granted scope: {creds.get('granted_scope')}")
    print(f"  access token expires in: "
          f"{max(0, creds['expires_at'] - int(time.time()))}s")
    print(f"  refresh token stored: "
          f"{'yes' if creds.get('refresh_token') else 'NO (no offline access)'}")
    print(f"  credential file: {credential_path()}")


def refresh_access_token(creds: dict = None) -> dict:
    """Exchange the refresh token, persisting the rotated one atomically."""
    creds = creds or load_credentials()
    refresh = creds.get("refresh_token")
    if not refresh:
        raise SystemExit(
            "ERROR: no refresh token stored. Re-run the browser flow: "
            "'authorize' then 'exchange'."
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
            f"ERROR: could not acquire {lock}; another refresh is in flight. "
            f"Concurrent refreshes break Read AI's single-use token chain."
        )

    try:
        # Re-read under the lock: another process may have just rotated.
        creds = load_credentials()
        form = {
            "grant_type": "refresh_token",
            "refresh_token": creds["refresh_token"],
        }
        resp = _token_request(creds, form)
        if "access_token" not in resp:
            raise SystemExit(
                f"ERROR: refresh failed: "
                f"{resp.get('error_description') or resp.get('error') or resp}\n"
                f"Read AI refresh tokens are single-use; if the chain is "
                f"broken you must redo the browser consent via 'authorize'."
            )
        return _store_token_response(creds, resp)
    finally:
        lock.unlink(missing_ok=True)


def get_access_token() -> str:
    """Return a usable access token, refreshing when it is near expiry."""
    creds = load_credentials()
    if not creds.get("access_token"):
        if creds.get("refresh_token"):
            creds = refresh_access_token(creds)
        else:
            raise SystemExit(
                "ERROR: no token stored. Run 'register', 'authorize', "
                "then 'exchange'."
            )

    expires_at = creds.get("expires_at") or 0
    if expires_at and time.time() >= expires_at - EXPIRY_SKEW_SECONDS:
        creds = refresh_access_token(creds)

    return creds["access_token"]


def cmd_status() -> None:
    creds = load_credentials()
    path = credential_path()
    if not creds:
        print(f"No credentials at {path}")
        print("Run: python scripts/readai_oauth.py register")
        return

    remaining = (creds.get("expires_at") or 0) - int(time.time())
    print(f"Credential file:  {path}")
    print(f"Client registered: {'yes' if creds.get('client_id') else 'no'}")
    print(f"Client secret:     {'present' if creds.get('client_secret') else 'none'}")
    print(f"Access token:      {'present' if creds.get('access_token') else 'none'}")
    print(f"Access expires in: {remaining if remaining > 0 else 'EXPIRED'}"
          + ("s" if remaining > 0 else ""))
    print(f"Refresh token:     {'present' if creds.get('refresh_token') else 'none'}")
    print(f"Granted scope:     {creds.get('granted_scope') or creds.get('scope') or '-'}")
    print(f"Pending auth:      "
          f"{'yes — run exchange --code' if creds.get('pending_verifier') else 'no'}")
    # Deliberately prints no token material.


def cmd_discover() -> None:
    meta = discover()
    print(json.dumps(meta, indent=2))


def main():
    parser = argparse.ArgumentParser(
        description="Read AI OAuth 2.1 client (DCR + PKCE)"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("discover", help="Print discovered OAuth endpoints")

    p_reg = sub.add_parser("register", help="Dynamically register a client")
    p_reg.add_argument("--client-name", default="Magi Transcript Pipeline")
    p_reg.add_argument("--redirect-uri", default=DEFAULT_REDIRECT_URI)
    p_reg.add_argument("--scope", default=DEFAULT_SCOPE)

    p_auth = sub.add_parser("authorize", help="Print the browser consent URL")
    p_auth.add_argument("--resource", default=None,
                        help=f"RFC 8707 resource indicator, e.g. "
                             f"{READAI_MCP_RESOURCE}")
    p_auth.add_argument("--open", action="store_true", dest="open_browser",
                        help="Launch the default browser on the consent URL")

    p_url = sub.add_parser(
        "url", help="Re-print the pending consent URL (does not rotate PKCE)"
    )
    p_url.add_argument("--open", action="store_true", dest="open_browser",
                       help="Launch the default browser on the consent URL")

    p_ex = sub.add_parser("exchange", help="Exchange an authorization code")
    p_ex.add_argument("--code", default=None,
                      help="The authorization code by itself")
    p_ex.add_argument("--redirect-url", default=None, dest="redirect_url",
                      help="The FULL address-bar URL you landed on after "
                           "clicking 'Allow Access' (works even when the page "
                           "shows 'Session Data Not Found'); code and state "
                           "are parsed out of it")
    p_ex.add_argument("--state", default=None)

    sub.add_parser("token", help="Print a valid access token (refreshes)")
    sub.add_parser("refresh", help="Force a refresh now")
    sub.add_parser("status", help="Show credential state (no secrets)")

    args = parser.parse_args()

    if args.command == "discover":
        cmd_discover()
    elif args.command == "register":
        register_client(args.client_name, args.redirect_uri, args.scope)
    elif args.command == "authorize":
        cmd_authorize(args.resource, args.open_browser)
    elif args.command == "url":
        cmd_url(args.open_browser)
    elif args.command == "exchange":
        cmd_exchange(args.code, args.state, args.redirect_url)
    elif args.command == "token":
        print(get_access_token())
    elif args.command == "refresh":
        refresh_access_token()
        cmd_status()
    elif args.command == "status":
        cmd_status()


if __name__ == "__main__":
    main()
