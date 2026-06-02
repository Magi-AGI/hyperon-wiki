#!/usr/bin/env python3
"""Export meeting transcripts from Fireflies.ai for the Hyperon Wiki pipeline.

Pulls full transcripts via the Fireflies GraphQL API and saves as JSON
for server-side ingestion by ingest_transcripts.rb.

Usage:
    export FIREFLIES_API_KEY="your-api-key"
    python scripts/export_transcripts.py [--output DIR] [--list] [--id TRANSCRIPT_ID]

Or pass key directly:
    python scripts/export_transcripts.py --key YOUR_API_KEY

Get your API key from:
    https://app.fireflies.ai/integrations/custom/fireflies
"""

import os
import sys
import json
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
)


def cmd_list(api_key: str):
    """List all available transcripts from Fireflies."""
    print("Fetching transcript list from Fireflies.ai...")
    transcripts = fireflies_list_transcripts(api_key)

    if not transcripts:
        print("No transcripts found (or API error).")
        return

    print(f"\nFound {len(transcripts)} transcripts:\n")
    print(f"{'ID':<28} {'Date':<12} {'Duration':<10} {'Title'}")
    print("-" * 90)

    for t in transcripts:
        tid = t.get("id", "?")
        title = t.get("title", "?")
        date_raw = t.get("date", "")
        dur = t.get("duration", 0) or 0
        dur_min = f"{round(dur / 60)}m" if dur else "?"

        # Parse date
        from scripts.pipeline.transcript_sources import _parse_fireflies_date
        date_str = _parse_fireflies_date(date_raw)

        print(f"{tid:<28} {date_str:<12} {dur_min:<10} {title}")


def cmd_export_all(api_key: str, output_dir: Path, meeting_filter: str = None):
    """Export all transcripts (or filtered subset) with full text."""
    print("Fetching transcript list from Fireflies.ai...")
    transcripts = fireflies_list_transcripts(api_key)

    if not transcripts:
        print("No transcripts found (or API error).")
        return

    if meeting_filter:
        filter_lower = meeting_filter.lower()
        transcripts = [
            t for t in transcripts
            if filter_lower in (t.get("title", "")).lower()
        ]
        print(f"Filtered to {len(transcripts)} transcripts matching '{meeting_filter}'")

    print(f"Exporting {len(transcripts)} transcripts with full text...")
    print(f"Output: {output_dir.absolute()}\n")

    records = []
    for i, t in enumerate(transcripts, 1):
        tid = t.get("id", "")
        title = t.get("title", "?")
        print(f"  [{i}/{len(transcripts)}] {title}...", end=" ", flush=True)

        # Fetch full transcript with sentences
        full = fireflies_get_transcript(tid, api_key)
        if not full:
            print("FAILED")
            continue

        record = fireflies_to_record(full)
        records.append(record)

        word_count = len(record.full_text.split()) if record.full_text else 0
        print(f"OK ({word_count} words)")

    if records:
        save_transcripts_json(records, output_dir)
        print(f"\nExported {len(records)} transcripts to {output_dir.absolute()}")
    else:
        print("\nNo transcripts exported.")


def cmd_export_one(api_key: str, transcript_id: str, output_dir: Path):
    """Export a single transcript by ID."""
    print(f"Fetching transcript {transcript_id}...")
    full = fireflies_get_transcript(transcript_id, api_key)
    if not full:
        print("Failed to fetch transcript.")
        return

    record = fireflies_to_record(full)
    save_transcripts_json([record], output_dir)

    word_count = len(record.full_text.split()) if record.full_text else 0
    print(f"Exported: {record.meeting_name} ({record.date}, {word_count} words)")
    print(f"Output: {output_dir.absolute()}")


def main():
    parser = argparse.ArgumentParser(
        description="Export Fireflies.ai transcripts for Hyperon Wiki"
    )
    parser.add_argument("--key", help="Fireflies API key (or set FIREFLIES_API_KEY)")
    parser.add_argument("--output", help="Output directory")
    parser.add_argument("--list", action="store_true",
                        help="List available transcripts (no export)")
    parser.add_argument("--id", dest="transcript_id",
                        help="Export a single transcript by ID")
    parser.add_argument("--filter", dest="meeting_filter",
                        help="Filter transcripts by meeting name (substring match)")
    args = parser.parse_args()

    api_key = args.key or os.environ.get("FIREFLIES_API_KEY")
    if not api_key:
        print("ERROR: Fireflies API key required.")
        print("Set FIREFLIES_API_KEY env var or use --key")
        print("\nGet your key from:")
        print("  https://app.fireflies.ai/integrations/custom/fireflies")
        sys.exit(1)

    if args.list:
        cmd_list(api_key)
        return

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = Path(args.output) if args.output else Path(
        f"transcript_exports/fireflies_{timestamp}"
    )

    if args.transcript_id:
        cmd_export_one(api_key, args.transcript_id, output_dir)
    else:
        cmd_export_all(api_key, output_dir, args.meeting_filter)


if __name__ == "__main__":
    main()
