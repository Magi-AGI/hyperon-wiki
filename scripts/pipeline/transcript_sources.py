"""Transcript source connectors for the raw data pipeline.

Primary: Fireflies.ai GraphQL API — provides full transcripts with speaker
labels, timestamps, summaries, and action items.

Secondary: Otter.ai email summaries via Gmail (summaries only, not full
transcripts — full Otter API requires Business plan).

Environment variables:
    FIREFLIES_API_KEY  — API key from https://app.fireflies.ai/integrations/custom/fireflies
    OTTER_API_KEY      — (future) Otter.ai API key if Business plan available
"""

import json
import re
import html
import subprocess
import tempfile
from dataclasses import dataclass, field, asdict
from datetime import datetime
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

# Query to list all transcripts (metadata only, for discovery)
FIREFLIES_LIST_QUERY = """
query ListTranscripts {
  transcripts {
    id
    title
    date
    duration
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
    duration
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

    Uses curl to avoid Python dependency on requests/httpx.
    """
    payload = {"query": query}
    if variables:
        payload["variables"] = variables

    with tempfile.NamedTemporaryFile(
        mode='w', suffix='.json', delete=False, encoding='utf-8'
    ) as f:
        json.dump(payload, f, ensure_ascii=False)
        tmpfile = f.name

    try:
        result = subprocess.run(
            [
                "curl", "-s", "-X", "POST",
                FIREFLIES_API_URL,
                "-H", "Content-Type: application/json",
                "-H", f"Authorization: Bearer {api_key}",
                "-d", f"@{tmpfile}",
            ],
            capture_output=True, timeout=60,
            encoding='utf-8', errors='replace',
        )
        if result.returncode == 0 and result.stdout and result.stdout.strip():
            return json.loads(result.stdout)
    except (subprocess.TimeoutExpired, json.JSONDecodeError) as e:
        print(f"  Fireflies API error: {e}")
    finally:
        Path(tmpfile).unlink(missing_ok=True)

    return {}


def fireflies_list_transcripts(api_key: str) -> list[dict]:
    """List all transcripts from Fireflies.ai.

    Returns list of transcript metadata dicts.
    """
    resp = _fireflies_request(FIREFLIES_LIST_QUERY, api_key=api_key)
    data = resp.get("data", {})
    if "transcripts" in data:
        return data["transcripts"]

    if "errors" in resp:
        for err in resp["errors"]:
            print(f"  Fireflies API error: {err.get('message', err)}")
    return []


def fireflies_get_transcript(transcript_id: str, api_key: str) -> dict:
    """Get a single transcript with full text from Fireflies.ai."""
    resp = _fireflies_request(
        FIREFLIES_DETAIL_QUERY,
        variables={"id": transcript_id},
        api_key=api_key,
    )
    data = resp.get("data", {})
    if "transcript" in data:
        return data["transcript"]

    if "errors" in resp:
        for err in resp["errors"]:
            print(f"  Fireflies API error: {err.get('message', err)}")
    return {}


def fireflies_to_record(transcript: dict) -> TranscriptRecord:
    """Convert a Fireflies API transcript dict to a TranscriptRecord."""
    summary_data = transcript.get("summary") or {}

    # Parse date — Fireflies returns epoch milliseconds or ISO string
    date_raw = transcript.get("date", "")
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

    for record in transcripts:
        safe_name = re.sub(r'[^\w\-]', '_', record.meeting_name)
        filename = f"{record.date}_{safe_name}.json"
        filepath = output_dir / filename

        export_data = record.to_dict()
        # Keep full_text in the export (it's the whole point)
        # but drop sentences to avoid duplication
        export_data.pop('sentences', None)

        filepath.write_text(
            json.dumps(export_data, indent=2, ensure_ascii=False),
            encoding='utf-8',
        )

    summary = {
        "exported_at": datetime.utcnow().isoformat() + "Z",
        "total_transcripts": len(transcripts),
        "services": list(set(t.source_service for t in transcripts)),
        "date_range": {
            "earliest": min(t.date for t in transcripts) if transcripts else "",
            "latest": max(t.date for t in transcripts) if transcripts else "",
        },
    }
    (output_dir / "export_summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False),
        encoding='utf-8',
    )

    return output_dir
