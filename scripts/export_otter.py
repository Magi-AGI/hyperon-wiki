#!/usr/bin/env python3
"""Export meeting transcripts from Otter.ai for the Hyperon Wiki pipeline.

Uses the unofficial otterai-api library (https://github.com/gmchad/otterai-api)
to pull full transcripts via Otter.ai's internal API.

Prerequisites:
    pip install requests requests-toolbelt
    pip install git+https://github.com/gmchad/otterai-api.git

Usage:
    python scripts/export_otter.py --email USER --password PASS --list
    python scripts/export_otter.py --email USER --password PASS [--filter "MeTTa"] [--output DIR]

Environment variables:
    OTTER_EMAIL    — Otter.ai account email
    OTTER_PASSWORD — Otter.ai account password
"""

import os
import sys
import json
import re
import argparse
from pathlib import Path
from datetime import datetime

try:
    from otterai import OtterAI
except ImportError:
    # Try local copy in scripts/otterai/
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        from otterai import OtterAI
    except ImportError:
        print("ERROR: otterai-api not installed.")
        print("Install with: pip install git+https://github.com/gmchad/otterai-api.git")
        print("Or the library should be at scripts/otterai/")
        sys.exit(1)


def connect(email: str, password: str) -> OtterAI:
    """Authenticate with Otter.ai and return client."""
    otter = OtterAI()
    result = otter.login(email, password)
    if result.get("status") != 200:
        print(f"ERROR: Login failed (status {result.get('status')})")
        print("Check your email/password.")
        sys.exit(1)
    print(f"Logged in as {email}")
    return otter


def list_speeches(otter: OtterAI):
    """List all available speeches/transcripts."""
    # Fetch owned speeches
    result = otter.get_speeches(page_size=200, source="owned")
    speeches = result.get("data", {}).get("speeches", [])

    # Also fetch shared speeches
    shared_result = otter.get_speeches(page_size=200, source="shared")
    shared = shared_result.get("data", {}).get("speeches", [])

    all_speeches = speeches + shared

    if not all_speeches:
        print("No speeches found.")
        return []

    return all_speeches


def speech_to_record(otter: OtterAI, speech_summary: dict) -> dict:
    """Fetch full speech data and convert to our transcript record format."""
    speech_id = speech_summary.get("otid", "")
    title = speech_summary.get("title", "Unknown")

    # Fetch full speech with transcript
    full = otter.get_speech(speech_id)
    speech_data = full.get("data", {}).get("speech", {})
    if not speech_data:
        return None

    # Parse transcript segments and build speaker map
    transcripts = speech_data.get("transcripts", [])
    speakers_list = speech_data.get("speakers", [])
    speaker_map = {s["id"]: s.get("speaker_name", f"Speaker {s['id']}") for s in speakers_list}

    # Each transcript item has: transcript (text), speaker_id, start_offset, end_offset
    sentences = []
    for t in transcripts:
        text = (t.get("transcript") or "").strip()
        if not text:
            continue
        speaker_id = t.get("speaker_id")
        speaker = speaker_map.get(speaker_id, f"Speaker {speaker_id}" if speaker_id else "Unknown")
        sentences.append({
            "speaker_name": speaker,
            "text": text,
            "start_time": t.get("start_offset", 0),
            "end_time": t.get("end_offset", 0),
        })

    # Build full text
    full_text_lines = []
    current_speaker = None
    current_lines = []

    for s in sentences:
        if s["speaker_name"] != current_speaker:
            if current_speaker and current_lines:
                full_text_lines.append(
                    f"{current_speaker}: {' '.join(current_lines)}"
                )
            current_speaker = s["speaker_name"]
            current_lines = [s["text"]]
        else:
            current_lines.append(s["text"])

    if current_speaker and current_lines:
        full_text_lines.append(
            f"{current_speaker}: {' '.join(current_lines)}"
        )

    full_text = '\n'.join(full_text_lines)

    # Parse date
    created_at = speech_data.get("created_at", 0)
    if created_at:
        dt = datetime.utcfromtimestamp(created_at)
        date_str = dt.strftime('%Y-%m-%d')
    else:
        date_str = ""

    # Duration
    duration_sec = speech_data.get("duration", 0) or 0
    duration_min = round(duration_sec / 60) if duration_sec else 0

    # Summary (Otter AI-generated)
    summary = speech_data.get("summary", "") or ""
    if isinstance(summary, dict):
        summary = summary.get("text", "") or ""

    # Participants
    participants = list(dict.fromkeys(
        s["speaker_name"] for s in sentences
        if s["speaker_name"] not in ("Unknown", "")
    ))

    return {
        "meeting_name": title,
        "date": date_str,
        "source_service": "otter.ai",
        "summary": summary,
        "action_items": [],
        "full_text": full_text,
        "duration_minutes": duration_min,
        "participants": participants,
        "keywords": [],
        "transcript_id": speech_id,
        "transcript_url": f"https://otter.ai/u/{speech_id}",
        "sentences": [],  # Omit raw sentences to save space
    }


def cmd_list(otter: OtterAI):
    """List all available speeches."""
    speeches = list_speeches(otter)
    if not speeches:
        return

    print(f"\nFound {len(speeches)} speeches:\n")
    print(f"{'ID':<30} {'Date':<12} {'Dur':<8} {'Title'}")
    print("-" * 90)

    for s in speeches:
        sid = s.get("otid", "?")
        title = s.get("title", "?")
        created = s.get("created_at", 0)
        dur = s.get("duration", 0) or 0
        dur_str = f"{round(dur/60)}m" if dur else "?"

        date_str = ""
        if created:
            dt = datetime.utcfromtimestamp(created)
            date_str = dt.strftime('%Y-%m-%d')

        print(f"{sid:<30} {date_str:<12} {dur_str:<8} {title}")


def cmd_export(otter: OtterAI, output_dir: Path, meeting_filter: str = None):
    """Export all speeches (or filtered subset) with full text."""
    speeches = list_speeches(otter)
    if not speeches:
        return

    if meeting_filter:
        filter_lower = meeting_filter.lower()
        speeches = [
            s for s in speeches
            if filter_lower in (s.get("title") or "").lower()
        ]
        print(f"Filtered to {len(speeches)} matching '{meeting_filter}'")

    print(f"Exporting {len(speeches)} transcripts...\n")
    output_dir.mkdir(parents=True, exist_ok=True)

    exported = 0
    for i, speech in enumerate(speeches, 1):
        title = speech.get("title", "?")
        print(f"  [{i}/{len(speeches)}] {title}...", end=" ", flush=True)

        try:
            record = speech_to_record(otter, speech)
            if not record:
                print("FAILED (no data)")
                continue

            word_count = len(record["full_text"].split()) if record.get("full_text") else 0
            if word_count == 0:
                print("EMPTY")
                continue

            # Save JSON
            safe_name = re.sub(r'[^\w\-]', '_', record["meeting_name"])
            date_prefix = record["date"] or "undated"
            filename = f"{date_prefix}_{safe_name}.json"
            filepath = output_dir / filename

            export_data = dict(record)
            filepath.write_text(
                json.dumps(export_data, indent=2, ensure_ascii=False),
                encoding='utf-8',
            )

            exported += 1
            print(f"OK ({word_count} words, {len(record['participants'])} speakers)")

        except Exception as e:
            print(f"ERROR: {e}")

    # Write summary
    summary = {
        "exported_at": datetime.utcnow().isoformat() + "Z",
        "source": "otter.ai API",
        "total_transcripts": exported,
    }
    (output_dir / "export_summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False),
        encoding='utf-8',
    )

    print(f"\nExported {exported} transcripts to {output_dir.absolute()}")


def main():
    parser = argparse.ArgumentParser(
        description="Export Otter.ai transcripts for Hyperon Wiki"
    )
    parser.add_argument("--email", help="Otter.ai email (or set OTTER_EMAIL)")
    parser.add_argument("--password", help="Otter.ai password (or set OTTER_PASSWORD)")
    parser.add_argument("--list", action="store_true",
                        help="List available speeches (no export)")
    parser.add_argument("--filter", dest="meeting_filter",
                        help="Filter by meeting name (substring)")
    parser.add_argument("--output", help="Output directory")
    args = parser.parse_args()

    email = args.email or os.environ.get("OTTER_EMAIL")
    password = args.password or os.environ.get("OTTER_PASSWORD")

    if not email or not password:
        print("ERROR: Otter.ai credentials required.")
        print("Set OTTER_EMAIL + OTTER_PASSWORD env vars, or use --email/--password")
        sys.exit(1)

    otter = connect(email, password)

    if args.list:
        cmd_list(otter)
        return

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = Path(args.output) if args.output else Path(
        f"transcript_exports/otter_{timestamp}"
    )

    cmd_export(otter, output_dir, args.meeting_filter)


if __name__ == "__main__":
    main()
