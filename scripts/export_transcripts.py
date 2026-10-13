#!/usr/bin/env python3
"""Export meeting transcripts from Fireflies.ai for the Hyperon Wiki pipeline.

Pulls full transcripts via the Fireflies GraphQL API and saves as JSON
for server-side ingestion by ingest_transcripts.rb.

Usage:
    export FIREFLIES_API_KEY="your-api-key"
    python scripts/export_transcripts.py [--output DIR] [--list] [--id TRANSCRIPT_ID]

Credentials, in order of preference:
    1. FIREFLIES_API_KEY_FILE=/path/to/key.txt   (file, mode 600 — safest)
    2. FIREFLIES_API_KEY=...                     (env var)
    3. --key-file /path/to/key.txt               (file)

`--key` on the command line is deliberately NOT supported: an argv secret is
visible to every other process on the box via `ps` and lands in shell history.

By default only finished meetings are exported. Fireflies lists in-progress
captures alongside completed ones, and a live transcript is still having
sentences appended — exporting it stores a truncated conversation that the
pipeline never revisits. Pass --include-live to override.

Get your API key from:
    https://app.fireflies.ai/integrations/custom/fireflies
"""

import os
import sys
import json
import stat
import argparse
from pathlib import Path
from datetime import datetime

# Add parent to path so we can import pipeline modules
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.pipeline.transcript_sources import (
    fireflies_list_transcripts,
    fireflies_get_transcript,
    fireflies_to_record,
    save_transcripts_json,
    _parse_fireflies_date,
)


def load_api_key(key_file: str = None) -> str:
    """Resolve the Fireflies API key without ever exposing it in argv.

    Returns an empty string when no credential is configured; the caller is
    responsible for the user-facing error.
    """
    candidate = key_file or os.environ.get("FIREFLIES_API_KEY_FILE")
    if candidate:
        path = Path(candidate).expanduser()
        if not path.is_file():
            raise SystemExit(f"ERROR: key file not found: {path}")
        if os.name == "posix":
            mode = path.stat().st_mode
            if mode & (stat.S_IRGRP | stat.S_IROTH):
                print(
                    f"WARNING: {path} is readable by other users. "
                    f"Run: chmod 600 {path}",
                    file=sys.stderr,
                )
        return path.read_text(encoding="utf-8").strip()

    return (os.environ.get("FIREFLIES_API_KEY") or "").strip()


def _iso_bound(value: str, end_of_day: bool = False) -> str:
    """Normalise a YYYY-MM-DD or full ISO string into a Fireflies DateTime."""
    if not value:
        return None
    if "T" in value:
        return value
    suffix = "T23:59:59.999Z" if end_of_day else "T00:00:00.000Z"
    return f"{value}{suffix}"


def cmd_list(api_key: str, include_live: bool, from_date: str, to_date: str):
    """List available transcripts from Fireflies."""
    print("Fetching transcript list from Fireflies.ai...")
    transcripts = fireflies_list_transcripts(
        api_key,
        include_live=include_live,
        from_date=from_date,
        to_date=to_date,
    )

    if not transcripts:
        print("No transcripts found (or API error).")
        return

    print(f"\nFound {len(transcripts)} transcripts:\n")
    print(f"{'ID':<28} {'Date':<12} {'Duration':<10} {'Live':<6} {'Title'}")
    print("-" * 100)

    for t in sorted(transcripts, key=lambda x: x.get("dateString") or ""):
        tid = t.get("id", "?")
        title = t.get("title", "?")
        dur = t.get("duration", 0) or 0
        dur_min = f"{round(dur / 60)}m" if dur else "?"
        live = "LIVE" if t.get("is_live") else "-"
        date_str = _parse_fireflies_date(
            t.get("dateString") or t.get("date", "")
        )
        print(f"{tid:<28} {date_str:<12} {dur_min:<10} {live:<6} {title}")


def cmd_export_all(api_key: str, output_dir: Path, meeting_filter: str = None,
                   include_live: bool = False, from_date: str = None,
                   to_date: str = None, limit: int = None):
    """Export all transcripts (or a filtered subset) with full text."""
    print("Fetching transcript list from Fireflies.ai...")
    transcripts = fireflies_list_transcripts(
        api_key,
        include_live=include_live,
        from_date=from_date,
        to_date=to_date,
    )

    if not transcripts:
        print("No transcripts found (or API error).")
        return

    if meeting_filter:
        filter_lower = meeting_filter.lower()
        transcripts = [
            t for t in transcripts
            if filter_lower in (t.get("title", "")).lower()
        ]
        print(f"Filtered to {len(transcripts)} transcripts matching "
              f"'{meeting_filter}'")

    # Oldest first so an interrupted run leaves a contiguous backfill.
    transcripts.sort(key=lambda t: t.get("dateString") or "")

    if limit:
        transcripts = transcripts[:limit]
        print(f"Limited to first {len(transcripts)} transcripts")

    print(f"Exporting {len(transcripts)} transcripts with full text...")
    print(f"Output: {output_dir.absolute()}\n")

    records = []
    failed = []
    for i, t in enumerate(transcripts, 1):
        tid = t.get("id", "")
        title = t.get("title", "?")
        print(f"  [{i}/{len(transcripts)}] {title}...", end=" ", flush=True)

        full = fireflies_get_transcript(tid, api_key,
                                        include_live=include_live)
        if not full:
            print("FAILED")
            failed.append({"id": tid, "title": title})
            continue

        record = fireflies_to_record(full)
        records.append(record)

        word_count = len(record.full_text.split()) if record.full_text else 0
        print(f"OK ({word_count} words)")

    if records:
        save_transcripts_json(records, output_dir)
        print(f"\nExported {len(records)} transcripts to "
              f"{output_dir.absolute()}")
    else:
        print("\nNo transcripts exported.")

    if failed:
        print(f"WARNING: {len(failed)} transcript(s) could not be fetched:")
        for item in failed:
            print(f"  - {item['title']} ({item['id']})")
        # Non-zero exit so a wrapper script notices a partial export.
        sys.exit(2)


def cmd_export_one(api_key: str, transcript_id: str, output_dir: Path,
                   include_live: bool = False):
    """Export a single transcript by ID."""
    print(f"Fetching transcript {transcript_id}...")
    full = fireflies_get_transcript(transcript_id, api_key,
                                    include_live=include_live)
    if not full:
        print("Failed to fetch transcript.")
        sys.exit(2)

    record = fireflies_to_record(full)
    save_transcripts_json([record], output_dir)

    word_count = len(record.full_text.split()) if record.full_text else 0
    print(f"Exported: {record.meeting_name} ({record.date}, "
          f"{word_count} words)")
    print(f"Output: {output_dir.absolute()}")


def main():
    parser = argparse.ArgumentParser(
        description="Export Fireflies.ai transcripts for Hyperon Wiki"
    )
    parser.add_argument("--key-file",
                        help="Path to a file containing the Fireflies API key "
                             "(or set FIREFLIES_API_KEY_FILE / "
                             "FIREFLIES_API_KEY)")
    parser.add_argument("--output", help="Output directory")
    parser.add_argument("--list", action="store_true",
                        help="List available transcripts (no export)")
    parser.add_argument("--id", dest="transcript_id",
                        help="Export a single transcript by ID")
    parser.add_argument("--filter", dest="meeting_filter",
                        help="Filter transcripts by meeting name "
                             "(substring match)")
    parser.add_argument("--include-live", action="store_true",
                        help="Include in-progress/partial captures "
                             "(default: skip them)")
    parser.add_argument("--from-date",
                        help="Backfill window start (YYYY-MM-DD or ISO-8601)")
    parser.add_argument("--to-date",
                        help="Backfill window end (YYYY-MM-DD or ISO-8601)")
    parser.add_argument("--limit", type=int,
                        help="Export at most N transcripts (oldest first)")
    args = parser.parse_args()

    api_key = load_api_key(args.key_file)
    if not api_key:
        print("ERROR: Fireflies API key required.")
        print("Set FIREFLIES_API_KEY_FILE (preferred), FIREFLIES_API_KEY, "
              "or pass --key-file")
        print("\nGet your key from:")
        print("  https://app.fireflies.ai/integrations/custom/fireflies")
        sys.exit(1)

    from_date = _iso_bound(args.from_date)
    to_date = _iso_bound(args.to_date, end_of_day=True)

    if args.list:
        cmd_list(api_key, args.include_live, from_date, to_date)
        return

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = Path(args.output) if args.output else Path(
        f"transcript_exports/fireflies_{timestamp}"
    )

    if args.transcript_id:
        cmd_export_one(api_key, args.transcript_id, output_dir,
                       args.include_live)
    else:
        cmd_export_all(api_key, output_dir, args.meeting_filter,
                       args.include_live, from_date, to_date, args.limit)


if __name__ == "__main__":
    main()
