"""Transcript source connectors for the raw data pipeline.

Primary: Fireflies.ai GraphQL API — provides full transcripts with speaker
labels, timestamps, summaries, and action items.

Also primary: Read AI REST API — full transcripts with speaker turns,
summaries, chapters, action items, topics and key questions. Read AI issues no
static API keys; access is OAuth 2.1 (see scripts/readai_oauth.py), so these
helpers take a `token_provider` callable instead of a key string.

Secondary: Otter.ai email summaries via Gmail (summaries only, not full
transcripts — full Otter API requires Business plan).

Environment variables:
    FIREFLIES_API_KEY  — API key from https://app.fireflies.ai/integrations/custom/fireflies
    OTTER_API_KEY      — (future) Otter.ai API key if Business plan available
    (Read AI uses the OAuth credential store, not an environment variable.)
"""

import json
import re
import html
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class TranscriptRecord:
    """A meeting transcript from any supported service."""
    meeting_name: str
    date: str                    # ISO date: 2026-01-16
    source_service: str          # "fireflies.ai", "otter.ai", etc.
    summary: str                 # AI-generated overview
    action_items: list[str]      # Extracted action items
    full_text: str = ""          # Complete transcript text (speaker-labeled)
    duration_minutes: int = 0
    participants: list[str] = field(default_factory=list)
    keywords: list[str] = field(default_factory=list)
    transcript_id: str = ""      # Service-specific ID for dedup
    transcript_url: str = ""     # Link to view on source platform
    sentences: list[dict] = field(default_factory=list)  # [{speaker, text, start, end}]
    is_live: bool = False        # True if captured while still in progress

    def to_dict(self) -> dict:
        return asdict(self)

    def to_html(self) -> str:
        """Render as HTML for a RawData card."""
        lines = [
            f'<p><strong>Source:</strong> {_esc(self.source_service)} — '
            f'{_esc(self.meeting_name)}</p>',
            f'<p><strong>Date:</strong> {_esc(self.date)}</p>',
        ]
        if self.duration_minutes:
            lines.append(
                f'<p><strong>Duration:</strong> {self.duration_minutes} min</p>')
        if self.participants:
            lines.append(
                f'<p><strong>Participants:</strong> '
                f'{_esc(", ".join(self.participants))}</p>')
        if self.keywords:
            lines.append(
                f'<p><strong>Keywords:</strong> '
                f'{_esc(", ".join(self.keywords))}</p>')
        if self.transcript_url:
            lines.append(
                f'<p><strong>Full transcript:</strong> '
                f'<a href="{_esc(self.transcript_url)}">'
                f'View on {_esc(self.source_service)}</a></p>')

        lines.append('<hr>')

        if self.summary:
            lines.append('<h3>Summary</h3>')
            lines.append(f'<p>{_esc(self.summary)}</p>')

        if self.action_items:
            lines.append('<h3>Action Items</h3>')
            lines.append('<ul>')
            for item in self.action_items:
                lines.append(f'  <li>{_esc(item)}</li>')
            lines.append('</ul>')

        if self.full_text:
            lines.append('<h3>Full Transcript</h3>')
            lines.append(f'<pre>{_esc(self.full_text)}</pre>')
        elif self.sentences:
            lines.append('<h3>Full Transcript</h3>')
            lines.append('<pre>')
            for s in self.sentences:
                speaker = s.get('speaker_name', 'Unknown')
                text = s.get('text', '')
                lines.append(f'{_esc(speaker)}: {_esc(text)}')
            lines.append('</pre>')

        return '\n'.join(lines)

    def card_name(self) -> str:
        """Generate the RawData card name for this transcript."""
        safe_name = self.meeting_name.replace('+', '-').replace('/', '-')
        return f"Raw Data+transcripts+{safe_name}+{self.date}"

    def build_full_text(self) -> str:
        """Build full_text from sentences if not already set."""
        if self.full_text:
            return self.full_text
        if not self.sentences:
            return ""
        lines = []
        for s in self.sentences:
            speaker = s.get('speaker_name', 'Unknown')
            text = s.get('text', '')
            lines.append(f"{speaker}: {text}")
        self.full_text = '\n'.join(lines)
        return self.full_text


def _esc(text: str) -> str:
    return html.escape(str(text))


# ---------------------------------------------------------------------------
# Fireflies.ai GraphQL API
# ---------------------------------------------------------------------------

FIREFLIES_API_URL = "https://api.fireflies.ai/graphql"

# The API rejects limit > 50 with "Invalid argument(s) were provided", so every
# listing has to be walked with skip/limit rather than fetched in one shot.
FIREFLIES_MAX_PAGE_SIZE = 50

# Query to list transcripts (metadata only, for discovery).
# `is_live` distinguishes in-progress/partial captures from finished meetings;
# a live transcript's sentences are still being appended, so ingesting one
# writes a truncated record that never gets corrected.
FIREFLIES_LIST_QUERY = """
query ListTranscripts($limit: Int, $skip: Int, $fromDate: DateTime, $toDate: DateTime) {
  transcripts(limit: $limit, skip: $skip, fromDate: $fromDate, toDate: $toDate) {
    id
    title
    date
    dateString
    duration
    is_live
    organizer_email
    participants
    transcript_url
    summary {
      overview
      shorthand_bullet
      action_items
      keywords
    }
  }
}
"""

# Query to get a single transcript with full text
FIREFLIES_DETAIL_QUERY = """
query GetTranscript($id: String!) {
  transcript(id: $id) {
    id
    title
    date
    dateString
    duration
    is_live
    organizer_email
    participants
    transcript_url
    sentences {
      speaker_name
      text
      raw_text
      start_time
      end_time
    }
    summary {
      overview
      shorthand_bullet
      action_items
      keywords
    }
  }
}
"""


def _fireflies_request(query: str, variables: dict = None,
                        api_key: str = "") -> dict:
    """Make a GraphQL request to the Fireflies API.

    Uses urllib from the stdlib rather than shelling out to curl: the API key
    is a request header built in-process, so it never appears in a command
    line, in `ps` output, or in a shell history file.
    """
    if not api_key:
        raise ValueError("Fireflies API key is required")

    payload = {"query": query}
    if variables:
        payload["variables"] = {
            k: v for k, v in variables.items() if v is not None
        }

    request = urllib.request.Request(
        FIREFLIES_API_URL,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        # GraphQL errors (bad auth, bad args) arrive as a JSON body on a 4xx.
        try:
            return json.loads(exc.read().decode("utf-8"))
        except (ValueError, OSError):
            return {"errors": [{"message": f"HTTP {exc.code}"}]}
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        return {"errors": [{"message": f"{type(exc).__name__}: {exc}"}]}


def _report_errors(resp: dict, context: str = "") -> None:
    """Print GraphQL errors without ever echoing credentials."""
    for err in resp.get("errors") or []:
        message = err.get("message", err) if isinstance(err, dict) else err
        suffix = f" ({context})" if context else ""
        print(f"  Fireflies API error{suffix}: {message}")


def is_usable_transcript(transcript: dict) -> bool:
    """True when a transcript is finished and safe to ingest.

    Fireflies exposes in-progress meetings through the same listing as
    finished ones. A live transcript is still having sentences appended, so
    exporting it captures a partial conversation and the record is never
    revisited. Treat only an explicit ``is_live is False`` as finished; a
    missing field means the API did not tell us, which is not a green light.
    """
    return transcript.get("is_live") is False


def fireflies_list_transcripts(
    api_key: str,
    include_live: bool = False,
    from_date: str = None,
    to_date: str = None,
    page_size: int = FIREFLIES_MAX_PAGE_SIZE,
    max_pages: int = 200,
) -> list[dict]:
    """List transcripts from Fireflies.ai, walking every page.

    The API caps ``limit`` at 50 and has no cursor, so pages are walked with
    ``skip`` until a short page arrives. Results are de-duplicated by id
    because skip-based paging can repeat rows if the underlying set shifts
    between requests.

    Args:
        include_live: keep in-progress/partial captures. Off by default.
        from_date / to_date: ISO-8601 window (e.g. "2026-01-01T00:00:00.000Z")
            for backfilling a bounded slice of history.
    """
    page_size = max(1, min(page_size, FIREFLIES_MAX_PAGE_SIZE))

    collected: dict[str, dict] = {}
    skipped_live = 0
    skip = 0

    for _ in range(max_pages):
        resp = _fireflies_request(
            FIREFLIES_LIST_QUERY,
            variables={
                "limit": page_size,
                "skip": skip,
                "fromDate": from_date,
                "toDate": to_date,
            },
            api_key=api_key,
        )

        batch = (resp.get("data") or {}).get("transcripts")
        if batch is None:
            _report_errors(resp, context=f"skip={skip}")
            break

        new_in_page = 0
        for transcript in batch:
            tid = transcript.get("id")
            if not tid or tid in collected:
                continue
            if not include_live and not is_usable_transcript(transcript):
                skipped_live += 1
                continue
            collected[tid] = transcript
            new_in_page += 1

        if len(batch) < page_size:
            break

        # Guard against a server that ignores skip and keeps returning page 1.
        if new_in_page == 0 and not skipped_live:
            break

        skip += page_size

    if skipped_live:
        print(f"  Skipped {skipped_live} live/unfinished transcript(s)")

    return list(collected.values())


def fireflies_get_transcript(transcript_id: str, api_key: str,
                             include_live: bool = False) -> dict:
    """Get a single transcript with full text from Fireflies.ai.

    Re-checks ``is_live`` on the detail response: a meeting can start between
    the listing call and this one, and the detail payload is the authoritative
    read of whether the sentence list is complete.
    """
    resp = _fireflies_request(
        FIREFLIES_DETAIL_QUERY,
        variables={"id": transcript_id},
        api_key=api_key,
    )
    data = resp.get("data") or {}
    transcript = data.get("transcript")
    if transcript:
        if not include_live and not is_usable_transcript(transcript):
            print("  Skipping live/unfinished transcript")
            return {}
        return transcript

    _report_errors(resp, context=f"id={transcript_id}")
    return {}


def fireflies_to_record(transcript: dict) -> TranscriptRecord:
    """Convert a Fireflies API transcript dict to a TranscriptRecord."""
    summary_data = transcript.get("summary") or {}

    # Parse date — prefer dateString (ISO-8601) and fall back to the epoch
    # milliseconds in `date`, which is timezone-naive and easy to misread.
    date_raw = transcript.get("dateString") or transcript.get("date", "")
    meeting_date = _parse_fireflies_date(date_raw)

    # Parse duration (seconds to minutes)
    duration_sec = transcript.get("duration", 0) or 0
    duration_min = round(duration_sec / 60) if duration_sec else 0

    # Build overview from summary fields
    overview = summary_data.get("overview", "") or ""
    bullets = summary_data.get("shorthand_bullet", []) or []
    if not overview and bullets:
        overview = " ".join(bullets) if isinstance(bullets, list) else str(bullets)

    # Action items
    action_items_raw = summary_data.get("action_items", []) or []
    if isinstance(action_items_raw, str):
        action_items = [a.strip() for a in action_items_raw.split('\n') if a.strip()]
    else:
        action_items = [str(a) for a in action_items_raw]

    # Keywords
    keywords_raw = summary_data.get("keywords", []) or []
    if isinstance(keywords_raw, str):
        keywords = [k.strip() for k in keywords_raw.split(',') if k.strip()]
    else:
        keywords = [str(k) for k in keywords_raw]

    # Sentences (full transcript)
    sentences = transcript.get("sentences", []) or []

    # Participants
    participants = transcript.get("participants", []) or []

    record = TranscriptRecord(
        meeting_name=transcript.get("title", "Unknown Meeting"),
        date=meeting_date,
        source_service="fireflies.ai",
        summary=overview,
        action_items=action_items,
        duration_minutes=duration_min,
        participants=participants,
        keywords=keywords,
        transcript_id=transcript.get("id", ""),
        transcript_url=transcript.get("transcript_url", ""),
        sentences=sentences,
        is_live=bool(transcript.get("is_live")),
    )
    record.build_full_text()
    return record


def _parse_fireflies_date(date_raw) -> str:
    """Parse Fireflies date field (epoch ms or ISO string) to YYYY-MM-DD."""
    if isinstance(date_raw, (int, float)):
        # Epoch milliseconds
        dt = datetime.utcfromtimestamp(date_raw / 1000)
        return dt.strftime('%Y-%m-%d')
    if isinstance(date_raw, str):
        # Try ISO format
        for fmt in ['%Y-%m-%dT%H:%M:%S.%fZ', '%Y-%m-%dT%H:%M:%SZ', '%Y-%m-%d']:
            try:
                dt = datetime.strptime(date_raw, fmt)
                return dt.strftime('%Y-%m-%d')
            except ValueError:
                continue
        # Try epoch as string
        try:
            ts = float(date_raw)
            if ts > 1e12:  # milliseconds
                ts /= 1000
            dt = datetime.utcfromtimestamp(ts)
            return dt.strftime('%Y-%m-%d')
        except (ValueError, OSError):
            pass
    return str(date_raw)


# ---------------------------------------------------------------------------
# Read AI REST API (OAuth 2.1 — see scripts/readai_oauth.py)
# ---------------------------------------------------------------------------

READAI_API_BASE = "https://api.read.ai/v1"

# Read AI caps a listing page at 10 rows and ignores larger values rather than
# erroring, so a bigger limit silently yields 10 and an unwary caller concludes
# it has reached the end of the account.
READAI_MAX_PAGE_SIZE = 10

# Read AI's listing returns metadata only. Rich content is opt-in per section
# via repeated `expand[]` query parameters. NOTE: the bracketed form is
# required — `?expand=transcript` is accepted with HTTP 200 and silently
# returns the unexpanded record, which looks like "this account has no
# transcripts" instead of "you asked the wrong way".
READAI_EXPAND_SECTIONS = (
    "summary",
    "chapter_summaries",
    "action_items",
    "key_questions",
    "topics",
    "transcript",
    "metrics",
)

# `recording_download` is deliberately NOT requested by default: it mints a
# short-lived signed media URL, which is credential-like material we do not
# want persisted into a JSON artifact that outlives its own expiry.


def readai_expand_query(sections=READAI_EXPAND_SECTIONS) -> str:
    """Build the repeated expand[] query string Read AI actually honours."""
    return "&".join(
        f"expand[]={urllib.parse.quote(str(s))}" for s in sections
    )


def readai_list_meetings(
    token_provider,
    limit: int = READAI_MAX_PAGE_SIZE,
    start_datetime_gte: str = None,
    start_datetime_lte: str = None,
    max_pages: int = 500,
    api_request=None,
) -> list[dict]:
    """List every Read AI meeting, walking the cursor to the end.

    Read AI paginates with an opaque `cursor` parameter rather than
    page/offset. The other candidates (page, offset, per_page, page_size,
    starting_after, after) are all accepted with HTTP 200 and ignored, each
    returning page one forever — so a page/offset loop either spins until
    max_pages or re-exports the same 10 meetings. The cursor is the id of the
    last row of the previous page.

    `token_provider` is a zero-argument callable returning a bearer token. It
    is called once per request rather than once per export because Read AI
    access tokens live ~10 minutes and a full transcript walk takes longer.
    """
    collected: list[dict] = []
    seen_ids: set[str] = set()
    cursor = None
    request = api_request or _readai_request

    for _ in range(max_pages):
        params = [f"limit={int(min(limit, READAI_MAX_PAGE_SIZE))}"]
        if start_datetime_gte:
            params.append(
                "start_datetime_gte=" + urllib.parse.quote(start_datetime_gte))
        if start_datetime_lte:
            params.append(
                "start_datetime_lte=" + urllib.parse.quote(start_datetime_lte))
        if cursor:
            params.append("cursor=" + urllib.parse.quote(str(cursor)))

        payload = request(
            f"{READAI_API_BASE}/meetings?" + "&".join(params), token_provider)
        rows = payload.get("data") or []

        fresh = [r for r in rows if r.get("id") not in seen_ids]
        if rows and not fresh:
            # The cursor stopped advancing. Returning here beats looping
            # max_pages times and appending the same meetings repeatedly.
            break
        for row in fresh:
            seen_ids.add(row.get("id"))
        collected.extend(fresh)

        if not payload.get("has_more") or not rows:
            break
        cursor = rows[-1].get("id")
        if not cursor:
            break

    return collected


def readai_get_meeting(meeting_id: str, token_provider,
                       sections=READAI_EXPAND_SECTIONS,
                       api_request=None) -> dict:
    """Fetch one meeting with rich sections expanded."""
    request = api_request or _readai_request
    url = (f"{READAI_API_BASE}/meetings/{urllib.parse.quote(str(meeting_id))}"
           f"?{readai_expand_query(sections)}")
    return request(url, token_provider)


def _readai_request(url: str, token_provider) -> dict:
    """GET a Read AI endpoint with a freshly resolved bearer token."""
    token = token_provider()
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {token}",
            "User-Agent": "magi-transcripts-readai/1.0",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            body = response.read().decode("utf-8")
            return json.loads(body) if body.strip() else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:400]
        # Report the URL but never the Authorization header.
        raise RuntimeError(
            f"Read AI API error HTTP {exc.code} for "
            f"{urllib.parse.urlsplit(url).path}: {detail}"
        ) from None
    except (urllib.error.URLError, TimeoutError) as exc:
        raise RuntimeError(
            f"Read AI network failure for "
            f"{urllib.parse.urlsplit(url).path}: {exc}"
        ) from None


def readai_to_record(meeting: dict) -> TranscriptRecord:
    """Convert a Read AI meeting (expanded) to a TranscriptRecord."""
    transcript = meeting.get("transcript") or {}
    turns = transcript.get("turns") or []

    # Read AI returns turns in an unspecified order; the first turn of the
    # sample export was the speaker saying goodbye. Sort by start time so the
    # rendered transcript reads in the order the meeting actually happened.
    sentences = [
        {
            "speaker_name": ((t.get("speaker") or {}).get("name")
                             or "Unknown"),
            "text": t.get("text", "") or "",
            "start_time": t.get("start_time_ms"),
            "end_time": t.get("end_time_ms"),
        }
        for t in sorted(turns, key=lambda t: (t.get("start_time_ms") or 0))
    ]

    start_ms = meeting.get("start_time_ms") or meeting.get(
        "scheduled_start_time_ms")
    end_ms = meeting.get("end_time_ms") or meeting.get(
        "scheduled_end_time_ms")

    duration_min = 0
    if start_ms and end_ms and end_ms > start_ms:
        duration_min = round((end_ms - start_ms) / 60000)

    participants = [
        p.get("name") for p in (meeting.get("participants") or [])
        if p.get("name")
    ]

    action_items = [str(a) for a in (meeting.get("action_items") or []) if a]
    topics = [str(t) for t in (meeting.get("topics") or []) if t]

    summary = meeting.get("summary") or ""
    chapters = meeting.get("chapter_summaries") or []
    if chapters:
        rendered = "\n".join(
            f"- {c.get('title', '').strip()}: {c.get('description', '').strip()}"
            for c in chapters
            if isinstance(c, dict) and (c.get("title") or c.get("description"))
        )
        if rendered:
            summary = (summary + "\n\nChapters:\n" + rendered).strip()

    questions = [str(q) for q in (meeting.get("key_questions") or []) if q]
    if questions:
        summary = (summary + "\n\nKey questions:\n"
                   + "\n".join(f"- {q}" for q in questions)).strip()

    record = TranscriptRecord(
        meeting_name=meeting.get("title") or "Untitled Read AI Meeting",
        date=_readai_date(start_ms),
        source_service="read.ai",
        summary=summary,
        action_items=action_items,
        duration_minutes=duration_min,
        participants=participants,
        keywords=topics,
        transcript_id=meeting.get("id", "") or "",
        transcript_url=meeting.get("report_url", "") or "",
        sentences=sentences,
        # Read AI's `live_enabled` advertises that live features were on for the
        # meeting, not that this record is a partial in-progress capture, so it
        # must not be mapped onto is_live — doing so would make every
        # live-enabled meeting look unfinished and get skipped by the exporter.
        is_live=False,
    )
    if transcript.get("text") and not sentences:
        # Fall back to the flat transcript blob when turns are absent.
        record.full_text = transcript["text"]
    record.build_full_text()
    return record


def _readai_date(start_ms) -> str:
    """Convert Read AI epoch milliseconds to an ISO date (UTC)."""
    if not start_ms:
        return ""
    try:
        return datetime.fromtimestamp(
            float(start_ms) / 1000, tz=timezone.utc).strftime("%Y-%m-%d")
    except (ValueError, OSError, OverflowError):
        return ""


def readai_has_transcript(meeting: dict) -> bool:
    """True when an expanded meeting actually carries transcript content.

    Read AI returns HTTP 200 with `transcript: null` for meetings whose owner
    has not enabled downloads, so emptiness is a normal per-meeting state
    rather than an error worth aborting a 51-meeting walk over.
    """
    transcript = meeting.get("transcript") or {}
    return bool(transcript.get("turns") or transcript.get("text"))


# ---------------------------------------------------------------------------
# Otter.ai email parser (secondary — summaries only)
# ---------------------------------------------------------------------------

def parse_otter_email(email_body: str, headers: dict) -> Optional[TranscriptRecord]:
    """Parse an Otter.ai meeting summary email into a TranscriptRecord.

    Note: This only extracts the email summary, not the full transcript.
    Full Otter.ai transcripts require API access (Business plan).
    """
    subject = headers.get("Subject", "")
    email_date = headers.get("Date", "")

    match = re.search(r'Meeting Summary for (.+)', subject)
    if not match:
        return None
    meeting_name = match.group(1).strip()

    clean_body = _clean_otter_body(email_body)

    date_match = re.search(
        r'(\w{3}\s+\d{1,2},?\s*\d{0,4}),?\s+(\d{1,2}:\d{2}\s*[ap]m),?\s+(\d+\s*min)',
        clean_body
    )

    meeting_date = ""
    duration_min = 0
    if date_match:
        date_str = date_match.group(1).strip()
        dur_str = date_match.group(3).strip()
        meeting_date = _parse_meeting_date(date_str, email_date)
        dur_match = re.search(r'(\d+)', dur_str)
        if dur_match:
            duration_min = int(dur_match.group(1))
    elif email_date:
        meeting_date = _parse_email_date(email_date)

    summary = _extract_otter_summary(clean_body, meeting_name)
    action_items = _extract_otter_action_items(clean_body)

    return TranscriptRecord(
        meeting_name=meeting_name,
        date=meeting_date,
        source_service="otter.ai",
        summary=summary,
        action_items=action_items,
        duration_minutes=duration_min,
        transcript_id=headers.get("messageId", ""),
        transcript_url=_extract_otter_url(email_body),
    )


def _clean_otter_body(body: str) -> str:
    text = html.unescape(body)
    text = re.sub(r'\(\s*https://email\.otter\.ai/ls/click\?[^\)]+\)', '', text)
    text = re.sub(r'https://email\.otter\.ai/ls/click\?[^\s\)]+', '', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = re.sub(r'[ \t]{2,}', ' ', text)
    return text.strip()


def _extract_otter_summary(clean_body: str, meeting_name: str) -> str:
    lines = clean_body.split('\n')
    summary_lines = []
    in_summary = False

    for line in lines:
        stripped = line.strip()
        if not stripped:
            if in_summary and summary_lines:
                break
            continue
        if stripped.startswith('*') and stripped.endswith('*'):
            if meeting_name.lower() in stripped.lower():
                in_summary = True
                continue
        if in_summary:
            if any(m in stripped.lower() for m in [
                'action item', 'see full summary', 'see all insights',
                'view in otter', 'otter.ai logo', 'email settings', 'unsubscribe',
            ]):
                break
            if re.match(r'^(\w{3}\s+\d{1,2})', stripped) and 'min' in stripped:
                continue
            summary_lines.append(stripped)

    if summary_lines:
        return ' '.join(summary_lines)

    for line in lines:
        stripped = line.strip()
        if len(stripped) > 100 and '. ' in stripped:
            return stripped
    return ""


def _extract_otter_action_items(clean_body: str) -> list[str]:
    items = []
    lines = clean_body.split('\n')
    in_actions = False
    for line in lines:
        stripped = line.strip()
        if 'action item' in stripped.lower():
            in_actions = True
            continue
        if in_actions:
            if any(m in stripped.lower() for m in [
                'see all insights', 'otter.ai logo', 'email settings', 'unsubscribe',
            ]):
                break
            if not stripped:
                continue
            if '–' in stripped or '—' in stripped:
                items.append(stripped)
    return items


def _extract_otter_url(raw_body: str) -> str:
    match = re.search(r'https://otter\.ai/[^\s\)"\']+', raw_body)
    return match.group(0) if match else ""


def _parse_meeting_date(date_str: str, email_date: str) -> str:
    year_match = re.search(r'(\d{4})', email_date)
    year = int(year_match.group(1)) if year_match else datetime.now().year
    try:
        dt = datetime.strptime(date_str.rstrip(','), '%b %d')
        dt = dt.replace(year=year)
        return dt.strftime('%Y-%m-%d')
    except ValueError:
        pass
    for fmt in ['%b %d, %Y', '%b %d %Y']:
        try:
            dt = datetime.strptime(date_str.strip(), fmt)
            return dt.strftime('%Y-%m-%d')
        except ValueError:
            continue
    return date_str


def _parse_email_date(email_date: str) -> str:
    match = re.search(r'(\d{1,2})\s+(\w{3})\s+(\d{4})', email_date)
    if match:
        day, month, year = match.groups()
        try:
            dt = datetime.strptime(f"{day} {month} {year}", "%d %b %Y")
            return dt.strftime('%Y-%m-%d')
        except ValueError:
            pass
    return ""


# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

def parse_transcript_email(email_body: str, headers: dict) -> Optional[TranscriptRecord]:
    """Parse a transcript email from any supported service."""
    from_addr = headers.get("From", "").lower()
    if "otter.ai" in from_addr:
        return parse_otter_email(email_body, headers)
    return None


# ---------------------------------------------------------------------------
# Batch export
# ---------------------------------------------------------------------------

def save_transcripts_json(
    transcripts: list[TranscriptRecord],
    output_dir: Path,
) -> Path:
    """Save transcript records as JSON for server-side ingestion."""
    output_dir.mkdir(parents=True, exist_ok=True)

    used_names: set[str] = set()
    for record in transcripts:
        safe_name = re.sub(r'[^\w\-]', '_', record.meeting_name)
        # A recurring meeting can produce two records with the same title on
        # the same day; without the id suffix the second silently overwrites
        # the first and the export quietly loses data.
        suffix = re.sub(r'[^\w\-]', '', record.transcript_id)[-8:]
        filename = f"{record.date}_{safe_name}"
        if suffix:
            filename = f"{filename}_{suffix}"
        filename = f"{filename}.json"

        if filename in used_names:
            print(f"  WARNING: duplicate export filename {filename}, skipping")
            continue
        used_names.add(filename)

        filepath = output_dir / filename

        export_data = record.to_dict()
        # Keep full_text in the export (it's the whole point)
        # but drop sentences to avoid duplication
        export_data.pop('sentences', None)

        filepath.write_text(
            json.dumps(export_data, indent=2, ensure_ascii=False),
            encoding='utf-8',
        )

    dates = sorted(t.date for t in transcripts if t.date)
    summary = {
        "exported_at": datetime.utcnow().isoformat() + "Z",
        "total_transcripts": len(transcripts),
        "files_written": len(used_names),
        "live_transcripts": sum(1 for t in transcripts if t.is_live),
        "services": sorted(set(t.source_service for t in transcripts)),
        "date_range": {
            "earliest": dates[0] if dates else "",
            "latest": dates[-1] if dates else "",
        },
    }
    (output_dir / "export_summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False),
        encoding='utf-8',
    )

    return output_dir
