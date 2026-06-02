#!/usr/bin/env python3
"""Ingest Otter.ai manual export files into the transcript pipeline.

Reads .txt transcript files exported from Otter.ai (via "Export All" or
individual exports) and converts them to the standard JSON format used
by ingest_transcripts.rb.

Supported input formats:
  - .txt files with speaker labels (Otter.ai default export format)
  - .srt subtitle files (speaker labels in subtitle text)
  - Directory of .txt/.srt files (batch mode)

Otter.ai .txt format:
    Meeting Title
    Date Time · Duration
    [Speaker labels may appear as "Speaker Name  HH:MM" lines]

    Speaker Name  00:00
    Transcript text here...

    Speaker Name  01:23
    More text...

Usage:
    python scripts/ingest_otter_export.py /path/to/otter/exports [--output DIR]
    python scripts/ingest_otter_export.py transcript.txt --output transcript_exports/otter

After running, sync to wiki with:
    # Copy output to server and run ingest_transcripts.rb
"""

import os
import sys
import json
import re
import argparse
from pathlib import Path
from datetime import datetime
from dataclasses import dataclass, field, asdict


def parse_otter_txt(filepath: Path) -> dict:
    """Parse an Otter.ai .txt export file into a transcript record.

    Returns a dict matching the JSON format expected by ingest_transcripts.rb.
    """
    text = filepath.read_text(encoding='utf-8', errors='replace')
    lines = text.split('\n')

    if not lines:
        return None

    # First line is typically the meeting title
    meeting_name = lines[0].strip()
    if not meeting_name:
        meeting_name = filepath.stem

    # Second line often has date and duration
    # Format: "Mar 6, 2026 · 1 hr 5 min" or "Jan 9, 2026  5:30 PM · 45 min"
    date_str = ""
    duration_minutes = 0
    if len(lines) > 1:
        meta_line = lines[1].strip()
        date_str, duration_minutes = _parse_meta_line(meta_line)

    # Parse speaker-labeled transcript lines
    # Pattern: "Speaker Name  HH:MM" or "Speaker Name  H:MM:SS"
    speaker_pattern = re.compile(
        r'^(.+?)\s{2,}(\d{1,2}:\d{2}(?::\d{2})?)\s*$'
    )

    sentences = []
    current_speaker = "Unknown"
    current_text_lines = []

    # Skip header lines (title, date, blank lines before transcript starts)
    transcript_start = 2
    for i in range(2, min(len(lines), 10)):
        if speaker_pattern.match(lines[i].strip()):
            transcript_start = i
            break
        if lines[i].strip() == '':
            continue

    for line in lines[transcript_start:]:
        stripped = line.strip()
        if not stripped:
            continue

        match = speaker_pattern.match(stripped)
        if match:
            # Save previous speaker's text
            if current_text_lines:
                sentences.append({
                    'speaker_name': current_speaker,
                    'text': ' '.join(current_text_lines),
                })
                current_text_lines = []
            current_speaker = match.group(1).strip()
        else:
            current_text_lines.append(stripped)

    # Don't forget the last block
    if current_text_lines:
        sentences.append({
            'speaker_name': current_speaker,
            'text': ' '.join(current_text_lines),
        })

    # Build full text from sentences
    full_text = '\n'.join(
        f"{s['speaker_name']}: {s['text']}" for s in sentences
    )

    # Extract unique participants
    participants = list(dict.fromkeys(
        s['speaker_name'] for s in sentences
        if s['speaker_name'] != 'Unknown'
    ))

    return {
        'meeting_name': meeting_name,
        'date': date_str,
        'source_service': 'otter.ai',
        'summary': '',  # Otter exports don't include the AI summary
        'action_items': [],
        'full_text': full_text,
        'duration_minutes': duration_minutes,
        'participants': participants,
        'keywords': [],
        'transcript_id': filepath.stem,
        'transcript_url': '',
        'sentences': [],  # We put structured data in full_text instead
    }


def parse_otter_srt(filepath: Path) -> dict:
    """Parse an Otter.ai .srt subtitle export file."""
    text = filepath.read_text(encoding='utf-8', errors='replace')

    # SRT format:
    # 1
    # 00:00:00,000 --> 00:00:05,000
    # Speaker Name: Text here
    #
    # 2
    # ...

    blocks = re.split(r'\n\n+', text.strip())
    sentences = []
    meeting_name = filepath.stem

    for block in blocks:
        block_lines = block.strip().split('\n')
        if len(block_lines) < 3:
            continue

        # Skip sequence number and timestamp
        text_lines = block_lines[2:]
        combined = ' '.join(t.strip() for t in text_lines)

        # Try to extract speaker from "Speaker: text" pattern
        speaker_match = re.match(r'^(.+?):\s+(.+)$', combined)
        if speaker_match:
            speaker = speaker_match.group(1).strip()
            content = speaker_match.group(2).strip()
        else:
            speaker = 'Unknown'
            content = combined

        if content:
            sentences.append({
                'speaker_name': speaker,
                'text': content,
            })

    full_text = '\n'.join(
        f"{s['speaker_name']}: {s['text']}" for s in sentences
    )

    participants = list(dict.fromkeys(
        s['speaker_name'] for s in sentences
        if s['speaker_name'] != 'Unknown'
    ))

    return {
        'meeting_name': meeting_name,
        'date': '',
        'source_service': 'otter.ai',
        'summary': '',
        'action_items': [],
        'full_text': full_text,
        'duration_minutes': 0,
        'participants': participants,
        'keywords': [],
        'transcript_id': filepath.stem,
        'transcript_url': '',
        'sentences': [],
    }


def _parse_meta_line(meta: str) -> tuple[str, int]:
    """Parse the date/duration metadata line from Otter exports.

    Returns (ISO date string, duration in minutes).
    """
    date_str = ""
    duration_min = 0

    # Try to extract date
    # Patterns: "Mar 6, 2026", "January 9, 2026", etc.
    date_match = re.search(
        r'(\w+\.?\s+\d{1,2},?\s+\d{4})', meta
    )
    if date_match:
        raw_date = date_match.group(1).strip()
        for fmt in [
            '%B %d, %Y', '%B %d %Y', '%b %d, %Y', '%b %d %Y',
            '%b. %d, %Y', '%b. %d %Y',
        ]:
            try:
                dt = datetime.strptime(raw_date.rstrip(','), fmt)
                date_str = dt.strftime('%Y-%m-%d')
                break
            except ValueError:
                continue

    # Try to extract duration
    # Patterns: "1 hr 5 min", "45 min", "2 hr"
    hr_match = re.search(r'(\d+)\s*hr', meta)
    min_match = re.search(r'(\d+)\s*min', meta)
    if hr_match:
        duration_min += int(hr_match.group(1)) * 60
    if min_match:
        duration_min += int(min_match.group(1))

    return date_str, duration_min


def process_file(filepath: Path) -> dict:
    """Process a single export file based on its extension."""
    ext = filepath.suffix.lower()
    if ext == '.txt':
        return parse_otter_txt(filepath)
    elif ext == '.srt':
        return parse_otter_srt(filepath)
    else:
        print(f"  Skipping unsupported format: {filepath.name}")
        return None


def main():
    parser = argparse.ArgumentParser(
        description="Ingest Otter.ai export files for Hyperon Wiki"
    )
    parser.add_argument("input", help="File or directory of Otter exports")
    parser.add_argument("--output", help="Output directory for JSON files")
    parser.add_argument("--filter", help="Only process files matching this substring")
    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"ERROR: {input_path} not found")
        sys.exit(1)

    # Collect input files
    if input_path.is_file():
        files = [input_path]
    else:
        files = sorted(
            f for f in input_path.rglob('*')
            if f.suffix.lower() in ('.txt', '.srt')
            and not f.name.startswith('.')
        )

    if args.filter:
        filter_lower = args.filter.lower()
        files = [f for f in files if filter_lower in f.name.lower()]

    if not files:
        print("No .txt or .srt files found.")
        sys.exit(1)

    print(f"Found {len(files)} transcript files\n")

    # Set up output directory
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = Path(args.output) if args.output else Path(
        f"transcript_exports/otter_export_{timestamp}"
    )
    output_dir.mkdir(parents=True, exist_ok=True)

    # Process each file
    records = []
    for i, filepath in enumerate(files, 1):
        print(f"  [{i}/{len(files)}] {filepath.name}...", end=" ", flush=True)

        record = process_file(filepath)
        if not record:
            continue

        word_count = len(record['full_text'].split()) if record.get('full_text') else 0
        if word_count == 0:
            print("EMPTY")
            continue

        records.append(record)
        print(f"OK ({word_count} words, {len(record['participants'])} speakers)")

        # Save individual JSON
        safe_name = re.sub(r'[^\w\-]', '_', record['meeting_name'])
        date_prefix = record['date'] or 'undated'
        filename = f"{date_prefix}_{safe_name}.json"
        out_path = output_dir / filename

        export_data = dict(record)
        export_data.pop('sentences', None)
        out_path.write_text(
            json.dumps(export_data, indent=2, ensure_ascii=False),
            encoding='utf-8',
        )

    # Write summary
    summary = {
        "exported_at": datetime.utcnow().isoformat() + "Z",
        "source": "otter.ai manual export",
        "total_transcripts": len(records),
        "date_range": {
            "earliest": min((r['date'] for r in records if r['date']), default=""),
            "latest": max((r['date'] for r in records if r['date']), default=""),
        },
    }
    (output_dir / "export_summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False),
        encoding='utf-8',
    )

    print(f"\n{'='*60}")
    print(f"Processed {len(records)} transcripts")
    print(f"Output: {output_dir.absolute()}")
    print(f"{'='*60}")
    print(f"\nTo sync to wiki:")
    print(f"  1. scp -r {output_dir} ubuntu@54.183.80.144:~/transcript_exports/")
    print(f"  2. ssh ... 'TRANSCRIPT_EXPORT_DIR=~/transcript_exports/{output_dir.name} ... decko runner scripts/ingest_transcripts.rb'")


if __name__ == "__main__":
    main()
