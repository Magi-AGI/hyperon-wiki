#!/usr/bin/env python
"""Process raw Gmail thread JSON dumps into clean RawData JSON files.

Reads Gmail API thread responses (saved as JSON files by the MCP tool),
strips HTML/tracking URLs, and outputs clean JSON for ingest_transcripts.rb.

Usage:
    python scripts/process_gmail_threads.py INPUT_DIR OUTPUT_DIR

Example:
    python scripts/process_gmail_threads.py raw_data_exports/opencog_threads raw_data_exports/opencog_json
"""

import json
import os
import re
import sys
from pathlib import Path
from datetime import datetime, timezone


def clean_body(body):
    """Strip tracking URLs, HTML artifacts, and email noise from body text."""
    if not body:
        return ""

    # Remove tracking URLs (sendgrid, google groups links)
    body = re.sub(r'\(\s*https?://u\d+\.ct\.sendgrid\.net/[^\s)]+\s*\)', '', body)
    body = re.sub(r'https?://u\d+\.ct\.sendgrid\.net/\S+', '', body)
    body = re.sub(r'https?://groups\.google\.com/d/\S+', '', body)

    # Remove invisible characters and zero-width spaces
    body = re.sub(r'[͏‌­]+', '', body)

    # Remove Google Groups footer
    body = re.sub(r'--\s*\nYou received this message because you are subscribed.*$', '', body, flags=re.DOTALL)
    body = re.sub(r'To unsubscribe from this group.*$', '', body, flags=re.DOTALL)
    body = re.sub(r'To view this discussion on the web.*$', '', body, flags=re.DOTALL)

    # Remove email signature lines
    body = re.sub(r'\n-- \n.*$', '', body, flags=re.DOTALL)

    # Clean up excessive whitespace
    body = re.sub(r'\r\n', '\n', body)
    body = re.sub(r'\n{4,}', '\n\n\n', body)
    body = re.sub(r'[ \t]+\n', '\n', body)
    body = body.strip()

    return body


def extract_messages(thread_data):
    """Extract clean messages from a Gmail thread response."""
    messages = []

    # Handle different JSON structures
    if isinstance(thread_data, list):
        # MCP tool wraps in [{type, text}]
        for item in thread_data:
            if isinstance(item, dict) and 'text' in item:
                try:
                    inner = json.loads(item['text'])
                    if isinstance(inner, dict) and 'messages' in inner:
                        raw_msgs = inner['messages']
                    elif isinstance(inner, list):
                        raw_msgs = inner
                    else:
                        continue
                except (json.JSONDecodeError, TypeError):
                    continue

                for msg in raw_msgs:
                    extracted = extract_single_message(msg)
                    if extracted:
                        messages.append(extracted)
    elif isinstance(thread_data, dict):
        if 'messages' in thread_data:
            for msg in thread_data['messages']:
                extracted = extract_single_message(msg)
                if extracted:
                    messages.append(extracted)

    # Sort by date
    messages.sort(key=lambda m: m.get('date_ts', 0))
    return messages


def extract_single_message(msg):
    """Extract clean data from a single Gmail message."""
    if not isinstance(msg, dict):
        return None

    headers = msg.get('headers', {})
    body = msg.get('body', '')

    from_addr = headers.get('From', 'Unknown')
    date = headers.get('Date', '')
    subject = headers.get('Subject', '')

    # Clean the from address
    from_addr = re.sub(r'<[^>]+>', '', from_addr).strip().strip('"')

    # Clean body
    body = clean_body(body)

    if not body or len(body) < 10:
        return None

    # Parse date for sorting
    date_ts = 0
    try:
        # Try common formats
        for fmt in ['%a, %d %b %Y %H:%M:%S %z', '%a, %d %b %Y %H:%M:%S %Z',
                     '%a, %d %b %Y %H:%M:%S %z (%Z)']:
            try:
                dt = datetime.strptime(date.strip(), fmt)
                date_ts = dt.timestamp()
                break
            except ValueError:
                continue
    except Exception:
        pass

    return {
        'from': from_addr,
        'date': date,
        'date_ts': date_ts,
        'subject': subject,
        'body': body,
    }


def format_thread_text(subject, messages):
    """Format a thread's messages into clean readable text."""
    lines = []
    lines.append(f"OpenCog Mailing List Thread: {subject}")
    lines.append(f"Messages: {len(messages)}")
    if messages:
        lines.append(f"Date range: {messages[0]['date']} to {messages[-1]['date']}")
    lines.append("")
    lines.append("=" * 60)

    for i, msg in enumerate(messages, 1):
        lines.append("")
        lines.append(f"--- Message {i}/{len(messages)} ---")
        lines.append(f"From: {msg['from']}")
        lines.append(f"Date: {msg['date']}")
        lines.append(f"Subject: {msg['subject']}")
        lines.append("")
        lines.append(msg['body'])
        lines.append("")

    return '\n'.join(lines)


def process_thread_file(input_path, output_dir):
    """Process a single thread JSON file into an ingestion-ready JSON."""
    try:
        raw = json.loads(Path(input_path).read_text(encoding='utf-8'))
    except Exception as e:
        print(f"  ERROR reading {input_path}: {e}")
        return None

    messages = extract_messages(raw)
    if not messages:
        print(f"  SKIP (no messages): {input_path}")
        return None

    subject = messages[0].get('subject', 'Unknown')
    # Clean subject for card naming
    clean_subject = re.sub(r'^\[opencog-dev\]\s*', '', subject)
    clean_subject = re.sub(r'^Re:\s*', '', clean_subject, flags=re.IGNORECASE)
    clean_subject = clean_subject.strip()

    # Get date from first message
    first_date = 'unknown'
    if messages[0].get('date'):
        try:
            # Extract just YYYY-MM
            date_match = re.search(r'(\d{1,2}\s+\w+\s+(\d{4}))', messages[0]['date'])
            if date_match:
                first_date = date_match.group(0)
        except Exception:
            pass

    full_text = format_thread_text(clean_subject, messages)
    word_count = len(full_text.split())

    # Safe filename
    safe_name = re.sub(r'[^\w\-]', '_', clean_subject)[:60]

    record = {
        "meeting_name": f"OpenCog ML - {clean_subject}",
        "card_name": f"Raw Data+opencog-ml+{clean_subject}",
        "transcript_url": "opencog@googlegroups.com",
        "source_url": "opencog@googlegroups.com",
        "type": "mailing_list",
        "full_text": full_text,
        "fetched_at": datetime.now(timezone.utc).isoformat(),
        "word_count": word_count,
        "message_count": len(messages),
    }

    output_path = Path(output_dir) / f"{safe_name}.json"
    output_path.write_text(
        json.dumps(record, indent=2, ensure_ascii=False),
        encoding='utf-8',
    )

    print(f"  OK: {clean_subject[:50]} ({len(messages)} msgs, {word_count} words)")
    return record


def main():
    input_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("raw_data_exports/opencog_threads")
    output_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("raw_data_exports/opencog_json")
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Input: {input_dir}")
    print(f"Output: {output_dir}\n")

    thread_files = sorted(input_dir.glob("*.json"))
    if not thread_files:
        print("No thread JSON files found.")
        return

    success = 0
    total_words = 0

    for tf in thread_files:
        result = process_thread_file(tf, output_dir)
        if result:
            success += 1
            total_words += result['word_count']

    print(f"\n{'=' * 60}")
    print(f"Processed: {success}/{len(thread_files)} threads")
    print(f"Total words: {total_words:,}")
    print(f"{'=' * 60}")


if __name__ == "__main__":
    main()
