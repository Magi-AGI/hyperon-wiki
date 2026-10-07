#!/usr/bin/env python3
"""Export Otter.ai conversations over Otter's remote MCP server.

Otter's bulk export is Business-tier only and the private password-login API
is a dead end, so this exporter talks to the sanctioned remote MCP server at
https://mcp.otter.ai/mcp using the OAuth 2.1 credentials established by
scripts/otter_oauth.py. Run that once first:

    python scripts/otter_oauth.py authorize --open

Then:

    python scripts/export_otter_mcp.py --plan
    python scripts/export_otter_mcp.py --list --from-date 2026-01-01
    python scripts/export_otter_mcp.py --output DIR
    python scripts/export_otter_mcp.py --id <CONVERSATION_ID>

TRANSPORT
JSON-RPC 2.0 over MCP's streamable-HTTP transport: every call is a POST to
/mcp with `Accept: application/json, text/event-stream`, so a response may
come back either as a single JSON object or as an SSE stream carrying the
JSON-RPC envelope in a `data:` line. Both are handled. The session id the
server returns on `initialize` is echoed on every later request as
`Mcp-Session-Id`, and the negotiated protocol version as
`MCP-Protocol-Version`.

WHY SWEEPS INSTEAD OF A LISTING CALL
The server exposes only `search` and `fetch` (plus `get_user_info`). There is
no list-everything endpoint and no pagination cursor: `search` answers a query
with the matched set and nothing tells you what it left out. A single broad
query therefore cannot enumerate an archive. This exporter instead issues many
NARROW sweeps — one per calendar month, with an empty query, plus any extra
`--query` terms — and merges them, de-duplicating by conversation id. Month
windows are mutually exclusive by construction, so coverage comes from the
calendar rather than from trusting one result set to be complete.

`search` returns metadata only; the transcript text requires a `fetch` per
conversation id. Both tools double-wrap their payload: the outer MCP content
envelope's text is itself a content envelope whose text holds the real JSON.

DEFAULT OUTPUT IS OUTSIDE THE REPOSITORY. Transcripts are private meeting
content; writing them into the work tree invites an accidental commit.
"""

import os
import re
import sys
import json
import time
import uuid
import argparse
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts import otter_oauth
from scripts.pipeline.transcript_sources import (
    TranscriptRecord,
    save_transcripts_json,
)

OTTER_MCP_URL = otter_oauth.OTTER_MCP_URL

# The revision this client implements. The server may answer `initialize` with
# a different one; whatever it returns is echoed back on later requests.
MCP_PROTOCOL_VERSION = "2025-06-18"

CLIENT_INFO = {"name": "magi-transcripts-otter", "version": "1.0"}

SOURCE_SERVICE = "otter.ai"

# Otter was founded in 2016; nothing in an account predates it.
ARCHIVE_EPOCH = "2016-01-01"

# Private meeting content stays out of the git work tree by default.
DEFAULT_ARTIFACT_ROOT = Path(
    os.environ.get("MAGI_TRANSCRIPT_ARTIFACTS")
    or Path(__file__).resolve().parents[2] / "_transcript_artifacts"
)


def default_output_dir() -> Path:
    stamp = datetime.now(tz=timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return DEFAULT_ARTIFACT_ROOT / f"otter_{stamp}"


def _assert_outside_repo(path: Path) -> None:
    """Refuse to write private transcripts inside the git work tree."""
    repo_root = Path(__file__).resolve().parents[1]
    try:
        path.resolve().relative_to(repo_root)
    except ValueError:
        return
    raise SystemExit(
        f"ERROR: refusing to write transcripts inside the repository "
        f"({path}). Private meeting content committed by accident cannot be "
        f"un-published. Choose a path outside {repo_root}, or set "
        f"MAGI_TRANSCRIPT_ARTIFACTS."
    )


# ---------------------------------------------------------------------------
# JSON-RPC / streamable-HTTP plumbing
# ---------------------------------------------------------------------------

class McpError(RuntimeError):
    """A JSON-RPC error, an HTTP failure, or a malformed MCP envelope."""


def build_rpc_request(method: str, params: dict = None,
                      request_id=None) -> dict:
    """Build a JSON-RPC 2.0 request envelope.

    A request carries an id; a notification must NOT (passing id=None as a
    key would make the server treat it as a request expecting a reply).
    """
    payload = {"jsonrpc": "2.0", "method": method}
    if request_id is not None:
        payload["id"] = request_id
    if params is not None:
        payload["params"] = params
    return payload


def build_rpc_notification(method: str, params: dict = None) -> dict:
    return build_rpc_request(method, params, request_id=None)


def parse_sse_events(body: str) -> list:
    """Pull JSON payloads out of an SSE body.

    The streamable-HTTP transport may answer a POST with text/event-stream.
    Each event's data may span multiple `data:` lines, which are joined with
    newlines per the SSE spec before being parsed.
    """
    events = []
    data_lines = []

    def flush():
        if not data_lines:
            return
        raw = "\n".join(data_lines).strip()
        data_lines.clear()
        if not raw or raw == "[DONE]":
            return
        try:
            events.append(json.loads(raw))
        except ValueError:
            pass

    for line in (body or "").splitlines():
        if line.startswith("data:"):
            data_lines.append(line[5:].lstrip())
        elif not line.strip():
            flush()
    flush()
    return events


def parse_rpc_response(body: str, content_type: str, request_id) -> dict:
    """Extract the JSON-RPC result for `request_id` from a response body."""
    body = body or ""
    candidates = []

    if "text/event-stream" in (content_type or "").lower():
        candidates = parse_sse_events(body)
    else:
        try:
            parsed = json.loads(body) if body.strip() else {}
        except ValueError:
            # A server that mislabels an SSE stream as JSON is still readable.
            candidates = parse_sse_events(body)
            if not candidates:
                raise McpError(
                    f"non-JSON response from the MCP server: {body[:200]!r}")
        else:
            candidates = parsed if isinstance(parsed, list) else [parsed]

    for envelope in candidates:
        if not isinstance(envelope, dict):
            continue
        if envelope.get("id") != request_id:
            # Server-initiated requests and unrelated ids are ignored.
            continue
        if envelope.get("error"):
            err = envelope["error"]
            raise McpError(
                f"JSON-RPC error {err.get('code')}: {err.get('message')}")
        return envelope.get("result") or {}

    raise McpError(
        f"no JSON-RPC response with id={request_id!r} in the reply "
        f"({len(candidates)} envelope(s) seen)")


def unwrap_tool_payload(result: dict, max_layers: int = 4):
    """Unwrap an MCP tool result down to the real JSON payload.

    Otter's `search` and `fetch` double-wrap: the outer result's
    content[0].text is itself a serialised MCP content envelope whose own text
    holds the JSON we want. Rather than hardcoding "exactly two layers", this
    peels content envelopes until the payload stops looking like one.

    Returns a dict/list for JSON payloads, or a str when the innermost
    content is prose (which is what `get_user_info` returns).
    """
    if not isinstance(result, dict):
        raise McpError(f"tool result is not an object: {type(result).__name__}")
    if result.get("isError"):
        raise McpError(f"tool reported an error: {_first_text(result)!r}")

    current = result
    for _ in range(max_layers):
        text = _first_text(current)
        if text is None:
            structured = current.get("structuredContent")
            if structured is not None:
                return structured
            raise McpError("tool result carried no text content")
        try:
            parsed = json.loads(text)
        except ValueError:
            return text
        if _looks_like_content_envelope(parsed):
            current = parsed
            continue
        return parsed

    raise McpError(f"tool result nested deeper than {max_layers} envelopes")


def _looks_like_content_envelope(value) -> bool:
    return (
        isinstance(value, dict)
        and isinstance(value.get("content"), list)
        and any(isinstance(b, dict) and "text" in b for b in value["content"])
    )


def _first_text(envelope: dict):
    for block in envelope.get("content") or []:
        if isinstance(block, dict) and isinstance(block.get("text"), str):
            return block["text"]
    return None


class OtterMcpClient:
    """Minimal MCP client for Otter's streamable-HTTP endpoint.

    `transport` is injectable for tests: it is called as
    transport(url, body_bytes, headers) and must return
    (status, response_headers, body_text).
    """

    def __init__(self, token_provider, url: str = OTTER_MCP_URL,
                 transport=None, timeout: int = 120):
        self._token_provider = token_provider
        self.url = url
        self._transport = transport or _urllib_transport
        self.timeout = timeout
        self.session_id = None
        self.protocol_version = MCP_PROTOCOL_VERSION
        self.server_info = {}
        self.tools = []
        self._counter = 0
        self.call_count = 0

    # -- plumbing ---------------------------------------------------------

    def _next_id(self) -> str:
        self._counter += 1
        return f"magi-{self._counter}"

    def request_headers(self) -> dict:
        headers = {
            "Content-Type": "application/json",
            # Streamable HTTP: the server picks between a JSON reply and an
            # SSE stream, so both must be advertised.
            "Accept": "application/json, text/event-stream",
            "User-Agent": otter_oauth.USER_AGENT,
            "Authorization": f"Bearer {self._token_provider()}",
        }
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
        if self.protocol_version:
            headers["MCP-Protocol-Version"] = self.protocol_version
        return headers

    def _send(self, payload: dict, expect_reply: bool = True):
        body = json.dumps(payload).encode("utf-8")
        status, headers, text = self._transport(
            self.url, body, self.request_headers())
        self.call_count += 1

        session = _header(headers, "mcp-session-id")
        if session:
            self.session_id = session

        if status == 401:
            raise McpError("401 unauthorized from the MCP server")
        if status >= 400:
            raise McpError(f"HTTP {status} from the MCP server: {text[:200]!r}")
        if not expect_reply:
            return None
        return parse_rpc_response(text, _header(headers, "content-type"),
                                  payload.get("id"))

    # -- protocol ---------------------------------------------------------

    def initialize(self) -> dict:
        payload = build_rpc_request("initialize", {
            "protocolVersion": MCP_PROTOCOL_VERSION,
            "capabilities": {},
            "clientInfo": CLIENT_INFO,
        }, request_id=self._next_id())
        result = self._send(payload)
        self.protocol_version = (result.get("protocolVersion")
                                 or MCP_PROTOCOL_VERSION)
        self.server_info = result.get("serverInfo") or {}
        # The spec requires this notification before any other request.
        self._send(build_rpc_notification("notifications/initialized"),
                   expect_reply=False)
        return result

    def list_tools(self) -> list:
        result = self._send(build_rpc_request(
            "tools/list", {}, request_id=self._next_id()))
        self.tools = result.get("tools") or []
        return self.tools

    def call_tool(self, name: str, arguments: dict = None):
        result = self._send(build_rpc_request(
            "tools/call", {"name": name, "arguments": arguments or {}},
            request_id=self._next_id()))
        return unwrap_tool_payload(result)

    # -- Otter tools ------------------------------------------------------

    def get_user_info(self):
        return self.call_tool("get_user_info", {})

    def search(self, query: str = "", **filters) -> list:
        args = {"query": query or ""}
        for key, value in filters.items():
            if value not in (None, "", []):
                args[key] = value
        payload = self.call_tool("search", args)
        if isinstance(payload, dict):
            results = payload.get("results")
            if isinstance(results, list):
                return results
            return []
        if isinstance(payload, list):
            return payload
        return []

    def fetch(self, conversation_id: str) -> dict:
        # The tool rejects URLs outright, so normalise first.
        payload = self.call_tool(
            "fetch", {"id": normalise_conversation_id(conversation_id)})
        if not isinstance(payload, dict):
            raise McpError(
                f"fetch returned {type(payload).__name__}, expected an object")
        return payload


def _urllib_transport(url: str, body: bytes, headers: dict):
    request = urllib.request.Request(url, data=body, headers=headers,
                                     method="POST")
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return (response.status, dict(response.headers),
                    response.read().decode("utf-8", errors="replace"))
    except urllib.error.HTTPError as exc:
        return (exc.code, dict(exc.headers or {}),
                exc.read().decode("utf-8", errors="replace"))
    except (urllib.error.URLError, TimeoutError) as exc:
        raise McpError(f"network failure contacting {url}: {exc}")


def _header(headers, name: str) -> str:
    """Case-insensitive header lookup over a plain dict."""
    if not headers:
        return ""
    lowered = name.lower()
    for key, value in dict(headers).items():
        if str(key).lower() == lowered:
            return value
    return ""


# ---------------------------------------------------------------------------
# Sweep planning
# ---------------------------------------------------------------------------

def _parse_iso_date(value: str) -> date:
    return datetime.strptime(value, "%Y-%m-%d").date()


def to_otter_date(value) -> str:
    """Otter's search filters take YYYY/MM/DD, not ISO-8601."""
    if isinstance(value, date):
        return value.strftime("%Y/%m/%d")
    return _parse_iso_date(str(value)).strftime("%Y/%m/%d")


def month_windows(from_date: str, to_date: str) -> list:
    """Split a date range into inclusive per-calendar-month windows.

    Mutually exclusive and gap-free by construction, so merging their results
    covers the range without relying on any single query being complete.
    """
    start = _parse_iso_date(from_date)
    end = _parse_iso_date(to_date)
    if end < start:
        raise SystemExit(
            f"ERROR: --to-date {to_date} precedes --from-date {from_date}")

    windows = []
    cursor = start.replace(day=1)
    while cursor <= end:
        if cursor.month == 12:
            next_month = cursor.replace(year=cursor.year + 1, month=1)
        else:
            next_month = cursor.replace(month=cursor.month + 1)
        last_day = next_month - timedelta(days=1)
        windows.append((max(cursor, start), min(last_day, end)))
        cursor = next_month
    return windows


def build_sweep_plan(from_date: str, to_date: str, queries=(),
                     split_months: bool = True) -> list:
    """Build the list of narrow `search` calls that make up one export.

    Month windows with an empty query are the backbone: they enumerate by
    calendar rather than by relevance. Extra --query terms are then swept over
    the whole range to catch anything the date-only browse mode missed (for
    example conversations whose creation date sits outside the window but
    whose content matches).
    """
    plan = []
    if split_months:
        for start, end in month_windows(from_date, to_date):
            plan.append({
                "label": f"month:{start.strftime('%Y-%m')}",
                "query": "",
                "created_after": to_otter_date(start),
                "created_before": to_otter_date(end),
            })
    else:
        plan.append({
            "label": f"range:{from_date}..{to_date}",
            "query": "",
            "created_after": to_otter_date(from_date),
            "created_before": to_otter_date(to_date),
        })

    for term in queries or ():
        term = (term or "").strip()
        if not term:
            continue
        plan.append({
            "label": f"query:{term}",
            "query": term,
            "created_after": to_otter_date(from_date),
            "created_before": to_otter_date(to_date),
        })
    return plan


def merge_sweep_results(batches) -> tuple:
    """Merge sweep result lists, de-duplicating by conversation id.

    `batches` is an iterable of (label, results). The first sighting of an id
    wins; later sightings only record provenance. Returns
    (ordered {id: meeting}, stats dict).
    """
    merged = {}
    stats = {"sweeps": 0, "rows_seen": 0, "unique": 0, "duplicates": 0,
             "skipped_no_id": 0, "per_sweep": {}}

    for label, results in batches:
        stats["sweeps"] += 1
        results = results or []
        new_here = 0
        for row in results:
            if not isinstance(row, dict):
                stats["skipped_no_id"] += 1
                continue
            stats["rows_seen"] += 1
            cid = normalise_conversation_id(row.get("id") or row.get("url"))
            if not cid:
                stats["skipped_no_id"] += 1
                continue
            if cid in merged:
                stats["duplicates"] += 1
                merged[cid].setdefault("_sweeps", []).append(label)
                continue
            row = dict(row)
            row["id"] = cid
            row["_sweeps"] = [label]
            merged[cid] = row
            new_here += 1
        stats["per_sweep"][label] = {"returned": len(results), "new": new_here}

    stats["unique"] = len(merged)
    return merged, stats


_ID_FROM_URL = re.compile(r"otter\.ai/u/([A-Za-z0-9_\-]+)")


def normalise_conversation_id(value: str) -> str:
    """Reduce an id or an otter.ai/u/<id> URL to the bare id.

    Otter's `fetch` tool rejects URLs, and `search` rows are keyed by the bare
    slug — so normalising here keeps dedupe from treating the URL form and the
    id form of one conversation as two conversations.
    """
    text = (value or "").strip()
    if not text:
        return ""
    match = _ID_FROM_URL.search(text)
    if match:
        return match.group(1)
    if "://" in text or "/" in text:
        tail = text.rstrip("/").rsplit("/", 1)[-1]
        text = tail
    # Drop any query string or fragment left over from a pasted URL.
    text = text.split("?", 1)[0].split("#", 1)[0]
    return text


# ---------------------------------------------------------------------------
# Normalisation into the shared transcript record
# ---------------------------------------------------------------------------

_DURATION_RE = re.compile(
    r"(?:(?P<h>\d+)\s*h)?\s*(?:(?P<m>\d+)\s*m)?\s*(?:(?P<s>\d+)\s*s)?",
    re.IGNORECASE)

_TURN_RE = re.compile(
    r"^\[(?P<ts>\d{1,2}:\d{2}(?::\d{2})?)\]\s*"
    r"(?P<speaker>[^:]{1,80}?):\s*(?P<text>.*)$")


def parse_duration_minutes(value) -> int:
    """Convert Otter's pre-humanised duration ("3h 51m") to whole minutes."""
    if isinstance(value, (int, float)):
        return int(round(value))
    text = (value or "").strip()
    if not text:
        return 0

    # A clock form (H:MM:SS or MM:SS) shows up in some payloads.
    if re.fullmatch(r"\d{1,3}(?::\d{2}){1,2}", text):
        parts = [int(p) for p in text.split(":")]
        while len(parts) < 3:
            parts.insert(0, 0)
        hours, minutes, seconds = parts[-3:]
        return hours * 60 + minutes + (1 if seconds >= 30 else 0)

    match = _DURATION_RE.fullmatch(text)
    if not match or not any(match.groupdict().values()):
        return 0
    hours = int(match.group("h") or 0)
    minutes = int(match.group("m") or 0)
    seconds = int(match.group("s") or 0)
    return hours * 60 + minutes + (1 if seconds >= 30 else 0)


def parse_start_date(value) -> str:
    """Normalise Otter's start_time to a YYYY-MM-DD date string."""
    text = str(value or "").strip()
    if not text:
        return ""
    if isinstance(value, (int, float)) or re.fullmatch(r"\d{10,13}", text):
        ts = float(text)
        if ts > 1e11:  # milliseconds
            ts /= 1000
        return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%d")
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S",
                "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%fZ",
                "%Y/%m/%d %H:%M:%S", "%Y-%m-%d", "%Y/%m/%d"):
        try:
            return datetime.strptime(text, fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    match = re.match(r"(\d{4})[-/](\d{2})[-/](\d{2})", text)
    if match:
        return "-".join(match.groups())
    return ""


def parse_transcript_text(text: str) -> list:
    """Split Otter's "[H:MM:SS] Speaker N: ..." transcript into turns.

    Continuation lines (a wrapped paragraph with no timestamp) are appended to
    the previous turn rather than dropped, so no words are lost.
    """
    turns = []
    for line in (text or "").splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        match = _TURN_RE.match(stripped)
        if match:
            turns.append({
                "speaker_name": match.group("speaker").strip(),
                "text": match.group("text").strip(),
                "start_time": match.group("ts"),
            })
        elif turns:
            turns[-1]["text"] = (turns[-1]["text"] + " " + stripped).strip()
        else:
            turns.append({"speaker_name": "Unknown", "text": stripped,
                          "start_time": ""})
    return turns


def _as_str_list(value) -> list:
    if value in (None, ""):
        return []
    if isinstance(value, str):
        return [line.strip() for line in value.split("\n") if line.strip()]
    if isinstance(value, dict):
        value = list(value.values())
    out = []
    for item in value:
        if isinstance(item, dict):
            text = (item.get("text") or item.get("title")
                    or item.get("item") or json.dumps(item, sort_keys=True))
            out.append(str(text).strip())
        elif str(item).strip():
            out.append(str(item).strip())
    return out


def otter_to_record(fetched: dict, search_row: dict = None
                    ) -> TranscriptRecord:
    """Convert a `fetch` payload (+ its `search` row) to a TranscriptRecord."""
    fetched = fetched or {}
    search_row = search_row or {}
    metadata = fetched.get("metadata") or {}

    def pick(key, *fallbacks):
        for source in (fetched, metadata, search_row):
            value = source.get(key)
            if value not in (None, "", [], {}):
                return value
        for value in fallbacks:
            if value not in (None, "", [], {}):
                return value
        return ""

    cid = normalise_conversation_id(
        fetched.get("id") or search_row.get("id") or search_row.get("url"))
    title = str(pick("title") or "Untitled Otter conversation").strip()
    full_text = fetched.get("text") or ""
    sentences = parse_transcript_text(full_text)
    speakers = []
    for turn in sentences:
        name = turn.get("speaker_name") or ""
        if name and name not in speakers and name != "Unknown":
            speakers.append(name)

    record = TranscriptRecord(
        meeting_name=title,
        date=parse_start_date(pick("start_time")),
        source_service=SOURCE_SERVICE,
        summary=str(pick("short_summary") or "").strip(),
        action_items=_as_str_list(metadata.get("action_items")
                                  or search_row.get("action_items")),
        full_text=full_text,
        duration_minutes=parse_duration_minutes(pick("duration")),
        participants=speakers,
        keywords=[],
        transcript_id=cid,
        transcript_url=str(pick("url")
                           or (f"https://otter.ai/u/{cid}" if cid else "")),
        sentences=sentences,
        # MCP only exposes finished conversations; there is no live flag.
        is_live=False,
    )
    return record


# ---------------------------------------------------------------------------
# Export driver
# ---------------------------------------------------------------------------

def _token_provider():
    """Callable minting a valid access token, refreshing as needed.

    Called once per HTTP request on purpose: an archive sweep can outlive a
    single access token, and otter_oauth serialises refresh behind a lock.
    """
    return otter_oauth.get_access_token


def run_sweeps(client: OtterMcpClient, plan: list, verbose: bool = True,
               pause: float = 0.0) -> tuple:
    """Execute a sweep plan and merge the results by conversation id."""
    batches = []
    failures = []
    for index, sweep in enumerate(plan, start=1):
        try:
            results = client.search(
                query=sweep.get("query", ""),
                created_after=sweep.get("created_after"),
                created_before=sweep.get("created_before"),
            )
        except McpError as exc:
            # One bad window must not abandon the rest of the archive.
            failures.append({"sweep": sweep["label"], "error": str(exc)})
            if verbose:
                print(f"  [{index}/{len(plan)}] {sweep['label']}: "
                      f"FAILED ({exc})")
            continue
        batches.append((sweep["label"], results))
        if verbose:
            print(f"  [{index}/{len(plan)}] {sweep['label']}: "
                  f"{len(results)} row(s)")
        if pause:
            time.sleep(pause)

    merged, stats = merge_sweep_results(batches)
    stats["sweep_failures"] = failures
    return merged, stats


def cmd_plan(from_date: str, to_date: str, queries, split_months: bool) -> int:
    plan = build_sweep_plan(from_date, to_date, queries, split_months)
    print(f"Sweep plan: {len(plan)} search call(s) over "
          f"{from_date} .. {to_date}")
    for sweep in plan:
        print(f"  {sweep['label']:<22} query={sweep['query']!r} "
              f"{sweep['created_after']} .. {sweep['created_before']}")
    print("\nNo network contact was made (plan only).")
    return 0


def _connect() -> OtterMcpClient:
    client = OtterMcpClient(_token_provider())
    client.initialize()
    names = [t.get("name") for t in client.list_tools()]
    print(f"Connected to Otter MCP ({client.server_info.get('name', 'server')})"
          f"; tools: {', '.join(n for n in names if n)}")
    for required in ("search", "fetch"):
        if required not in names:
            raise SystemExit(
                f"ERROR: the MCP server does not expose a {required!r} tool; "
                f"available: {names}")
    return client


def cmd_list(from_date: str, to_date: str, queries, split_months: bool) -> int:
    client = _connect()
    plan = build_sweep_plan(from_date, to_date, queries, split_months)
    merged, stats = run_sweeps(client, plan)
    print(f"\nUnique conversations: {stats['unique']} "
          f"(rows seen {stats['rows_seen']}, duplicates "
          f"{stats['duplicates']})")
    dates = sorted(parse_start_date(m.get("start_time"))
                   for m in merged.values() if m.get("start_time"))
    dates = [d for d in dates if d]
    if dates:
        print(f"Date range: {dates[0]} .. {dates[-1]}")
    if stats["sweep_failures"]:
        print(f"Sweep failures: {len(stats['sweep_failures'])}")
    print("No transcripts were fetched (--list is metadata only).")
    return 0


def cmd_export(output_dir: Path, from_date: str, to_date: str, queries,
               split_months: bool, conversation_id: str = None,
               limit: int = 0) -> int:
    _assert_outside_repo(output_dir)
    client = _connect()

    if conversation_id:
        cid = normalise_conversation_id(conversation_id)
        merged = {cid: {"id": cid, "_sweeps": ["explicit:--id"]}}
        stats = {"sweeps": 0, "rows_seen": 1, "unique": 1, "duplicates": 0,
                 "skipped_no_id": 0, "per_sweep": {}, "sweep_failures": []}
        plan = []
    else:
        plan = build_sweep_plan(from_date, to_date, queries, split_months)
        print(f"Sweeping {len(plan)} window(s)/term(s)...")
        merged, stats = run_sweeps(client, plan)

    ids = list(merged)
    if limit:
        ids = ids[:limit]
        print(f"Limited to the first {len(ids)} conversation(s)")

    records = []
    fetch_failures = []
    empty_text = []

    for index, cid in enumerate(ids, start=1):
        try:
            fetched = client.fetch(cid)
        except McpError as exc:
            fetch_failures.append({"id": cid, "error": str(exc)})
            print(f"  [{index}/{len(ids)}] FAILED {cid}: {exc}")
            continue
        record = otter_to_record(fetched, merged.get(cid))
        if not record.full_text.strip():
            empty_text.append(cid)
        records.append(record)
        print(f"  [{index}/{len(ids)}] {record.date or '????-??-??'} "
              f"turns={len(record.sentences)} chars={len(record.full_text)}")

    if not records:
        print("No exportable conversations found.")

    # save_transcripts_json writes the per-transcript JSON files and the
    # export_summary.json artifact shared with the Read AI/Fireflies exports.
    save_transcripts_json(records, output_dir)

    manifest = {
        "exported_at": datetime.now(tz=timezone.utc).isoformat(),
        "source_service": SOURCE_SERVICE,
        "transport": "mcp-streamable-http",
        "endpoint": client.url,
        "auth": "oauth2.1-dcr-pkce-loopback",
        "protocol_version": client.protocol_version,
        "sweeps_planned": len(plan),
        "sweep_stats": {k: v for k, v in stats.items()
                        if k != "sweep_failures"},
        "sweep_failures": stats.get("sweep_failures", []),
        "conversations_unique": stats["unique"],
        "records_written": len(records),
        "conversations_without_text": len(empty_text),
        "fetch_failures": fetch_failures,
        "mcp_calls": client.call_count,
    }
    (output_dir / "otter_export_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"\nWrote {len(records)} transcript records to {output_dir}")
    print(f"  unique conversations: {stats['unique']}  "
          f"duplicates skipped: {stats['duplicates']}")
    print(f"  without text: {len(empty_text)}  "
          f"fetch failures: {len(fetch_failures)}")
    print(f"\nNext: python scripts/acceptance_otter_export.py {output_dir}")
    return 0 if not fetch_failures else 1


def main():
    parser = argparse.ArgumentParser(
        description="Export Otter.ai conversations over the Otter MCP server")
    parser.add_argument("--output", default=None,
                        help="Output directory (default: timestamped dir "
                             "outside the repo)")
    parser.add_argument("--plan", action="store_true", dest="do_plan",
                        help="Print the sweep plan and exit (no network)")
    parser.add_argument("--list", action="store_true", dest="do_list",
                        help="Sweep metadata only; fetch no transcripts")
    parser.add_argument("--id", default=None,
                        help="Export a single conversation by id or "
                             "otter.ai/u/<id> URL")
    parser.add_argument("--from-date", default=ARCHIVE_EPOCH,
                        help=f"Sweep from YYYY-MM-DD (default {ARCHIVE_EPOCH})")
    parser.add_argument("--to-date", default=None,
                        help="Sweep to YYYY-MM-DD (default: today, UTC)")
    parser.add_argument("--query", action="append", default=[],
                        dest="queries",
                        help="Extra search term swept over the whole range; "
                             "repeatable")
    parser.add_argument("--no-month-windows", action="store_true",
                        help="One wide range sweep instead of per-month "
                             "windows (faster, but relies on a single result "
                             "set being complete)")
    parser.add_argument("--limit", type=int, default=0,
                        help="Fetch at most N conversations (0 = all)")
    args = parser.parse_args()

    to_date = args.to_date or datetime.now(tz=timezone.utc).strftime("%Y-%m-%d")
    split_months = not args.no_month_windows

    if args.do_plan:
        return cmd_plan(args.from_date, to_date, args.queries, split_months)
    if args.do_list:
        return cmd_list(args.from_date, to_date, args.queries, split_months)

    output_dir = Path(args.output) if args.output else default_output_dir()
    return cmd_export(output_dir, args.from_date, to_date, args.queries,
                      split_months, conversation_id=args.id,
                      limit=args.limit)


if __name__ == "__main__":
    sys.exit(main())
