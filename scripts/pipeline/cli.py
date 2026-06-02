"""CLI entry point for the Hyperon Wiki raw data pipeline.

Usage:
    python -m scripts.pipeline.cli ingest-mattermost [--token TOKEN] [--channel FILTER]
    python -m scripts.pipeline.cli ingest-github org/repo
    python -m scripts.pipeline.cli sync-master-doc
    python -m scripts.pipeline.cli report

Environment variables:
    MATTERMOST_TOKEN  — MMAUTHTOKEN for chat.singularitynet.io
"""

import os
import sys
import json
import argparse
from pathlib import Path
from datetime import datetime, timezone

from .sources import (
    fetch_mattermost_channels, mattermost_channel_to_raw_text,
    fetch_github_readme, fetch_google_doc,
    HYPERON_CHANNELS, MASTER_DOC_ID,
)
from .transcript_sources import (
    fireflies_list_transcripts,
    fireflies_get_transcript,
    fireflies_to_record,
    save_transcripts_json,
)
from .writer import write_raw_data, create_raw_data_card, card_exists
from .topics import TOPICS


def cmd_ingest_mattermost(args):
    """Pull channels directly from Mattermost API and store as raw data."""
    token = args.token or os.environ.get("MATTERMOST_TOKEN")
    if not token:
        print("Error: Mattermost token required.")
        print("Set MATTERMOST_TOKEN env var or use --token")
        return 1

    channel_filter = HYPERON_CHANNELS
    if args.channel:
        channel_filter = [args.channel]

    print(f"Connecting to chat.singularitynet.io...")
    print(f"Channel filter: {channel_filter}")

    channels = fetch_mattermost_channels(
        token=token,
        channel_filter=channel_filter,
    )

    print(f"\nFetched {len(channels)} channels")

    for channel_data in channels:
        channel_info = channel_data.get("channel", {})
        name = channel_info.get("display_name", "unknown")
        post_count = channel_info.get("post_count", 0)

        print(f"\n  {name}: {post_count} posts")

        # Convert to complete raw text (no filtering)
        raw_text = mattermost_channel_to_raw_text(channel_data)

        # Also store the raw JSON for machine consumption
        raw_json = json.dumps(channel_data, indent=2, ensure_ascii=False)

        # Create card with both human-readable and machine-readable content
        card_name = f"Raw Data+mattermost+{name}"
        content = (
            f'<p><strong>Source:</strong> Mattermost — {name}</p>\n'
            f'<p><strong>Fetched:</strong> {datetime.now(timezone.utc).isoformat()}Z</p>\n'
            f'<p><strong>Posts:</strong> {post_count}</p>\n'
            f'<p><strong>Threads:</strong> {channel_info.get("thread_count", 0)}</p>\n'
            f'<hr>\n'
            f'<pre>{_escape_html(raw_text)}</pre>\n'
        )

        if card_exists(card_name):
            print(f"    Updating {card_name}")
        else:
            print(f"    Creating {card_name}")

        create_raw_data_card(card_name, content)

        # Also save JSON locally for backup
        json_dir = Path("raw_data_exports") / "mattermost"
        json_dir.mkdir(parents=True, exist_ok=True)
        safe_name = name.replace(" ", "_").replace("/", "_")
        json_path = json_dir / f"{safe_name}.json"
        json_path.write_text(raw_json, encoding="utf-8")
        print(f"    JSON saved: {json_path}")


def cmd_ingest_github(args):
    """Fetch a GitHub repository README and store as raw data."""
    parts = args.repo.split('/')
    if len(parts) != 2:
        print(f"Expected org/repo format, got: {args.repo}")
        return 1

    org, repo = parts
    print(f"Fetching README from {org}/{repo}...")
    content = fetch_github_readme(org, repo)
    if not content:
        print("  Could not fetch README.")
        return 1

    card_name = f"Raw Data+github+{repo}"
    html = (
        f'<p><strong>Source:</strong> https://github.com/{org}/{repo}</p>\n'
        f'<p><strong>Fetched:</strong> {datetime.now(timezone.utc).isoformat()}Z</p>\n'
        f'<pre>{_escape_html(content)}</pre>'
    )

    create_raw_data_card(card_name, html)
    print(f"  Written to {card_name}")


def cmd_sync_master_doc(args):
    """Fetch the Google Doc master index and store as raw data."""
    print("Fetching master doc...")
    content = fetch_google_doc(MASTER_DOC_ID)
    if not content:
        print("  Could not fetch.")
        return 1

    print(f"  Fetched {len(content)} bytes")
    card_name = "Raw Data+google-doc+master-index"
    html = (
        f'<p><strong>Source:</strong> Google Docs master index</p>\n'
        f'<p><strong>Fetched:</strong> {datetime.now(timezone.utc).isoformat()}Z</p>\n'
        f'<p><strong>Size:</strong> {len(content)} bytes</p>\n'
        f'<pre>{_escape_html(content)}</pre>'
    )

    create_raw_data_card(card_name, html)
    print(f"  Written to {card_name}")


def cmd_ingest_transcripts(args):
    """Pull transcripts from Fireflies.ai API and export as JSON."""
    api_key = args.key or os.environ.get("FIREFLIES_API_KEY")
    if not api_key:
        print("Error: Fireflies API key required.")
        print("Set FIREFLIES_API_KEY env var or use --key")
        print("Get your key: https://app.fireflies.ai/integrations/custom/fireflies")
        return 1

    if args.list_only:
        print("Fetching transcript list from Fireflies.ai...")
        transcripts = fireflies_list_transcripts(api_key)
        if not transcripts:
            print("No transcripts found.")
            return
        print(f"\n{'ID':<28} {'Date':<12} {'Dur':<8} {'Title'}")
        print("-" * 80)
        from .transcript_sources import _parse_fireflies_date
        for t in transcripts:
            tid = t.get("id", "?")
            title = t.get("title", "?")
            dur = t.get("duration", 0) or 0
            dur_str = f"{round(dur / 60)}m" if dur else "?"
            date_str = _parse_fireflies_date(t.get("date", ""))
            print(f"{tid:<28} {date_str:<12} {dur_str:<8} {title}")
        print(f"\nTotal: {len(transcripts)} transcripts")
        return

    print("Fetching transcripts from Fireflies.ai...")
    transcripts = fireflies_list_transcripts(api_key)
    if not transcripts:
        print("No transcripts found.")
        return

    if args.filter:
        filter_lower = args.filter.lower()
        transcripts = [
            t for t in transcripts
            if filter_lower in (t.get("title", "")).lower()
        ]
        print(f"Filtered to {len(transcripts)} matching '{args.filter}'")

    print(f"Exporting {len(transcripts)} transcripts with full text...\n")

    records = []
    for i, t in enumerate(transcripts, 1):
        tid = t.get("id", "")
        title = t.get("title", "?")
        print(f"  [{i}/{len(transcripts)}] {title}...", end=" ", flush=True)

        full = fireflies_get_transcript(tid, api_key)
        if not full:
            print("FAILED")
            continue

        record = fireflies_to_record(full)
        records.append(record)

        word_count = len(record.full_text.split()) if record.full_text else 0
        print(f"OK ({word_count} words)")

    if records:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_dir = Path(f"transcript_exports/fireflies_{timestamp}")
        save_transcripts_json(records, output_dir)
        print(f"\nExported {len(records)} transcripts to {output_dir}")

        # Also save JSON locally for backup
        json_dir = Path("raw_data_exports") / "transcripts"
        json_dir.mkdir(parents=True, exist_ok=True)
        for record in records:
            safe = record.meeting_name.replace(" ", "_").replace("/", "_")
            backup = json_dir / f"{record.date}_{safe}.json"
            data = record.to_dict()
            data.pop('sentences', None)
            backup.write_text(
                json.dumps(data, indent=2, ensure_ascii=False),
                encoding='utf-8',
            )
        print(f"Backups saved to {json_dir}")


def cmd_report(args):
    """Print a coverage report of wiki topics."""
    print("Hyperon Wiki Raw Data Pipeline — Topic Registry")
    print("=" * 60)
    print(f"{'Topic':<30} {'Card Name'}")
    print("-" * 60)

    for topic in TOPICS:
        print(f"{topic.display_name:<30} {topic.card_name}")

    print(f"\nTotal topics: {len(TOPICS)}")
    print(f"\nMattermost channels tracked: {len(HYPERON_CHANNELS)}")
    for ch in HYPERON_CHANNELS:
        print(f"  - {ch}")


def _escape_html(text: str) -> str:
    """Escape HTML special characters."""
    return (text
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;'))


def main():
    parser = argparse.ArgumentParser(
        description="Hyperon Wiki raw data pipeline",
        prog="python -m scripts.pipeline.cli",
    )
    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # ingest-mattermost
    mm = subparsers.add_parser("ingest-mattermost",
                               help="Pull channels from Mattermost API")
    mm.add_argument("--token", help="MMAUTHTOKEN (or set MATTERMOST_TOKEN env var)")
    mm.add_argument("--channel", help="Filter to a specific channel name")
    mm.set_defaults(func=cmd_ingest_mattermost)

    # ingest-transcripts
    tr = subparsers.add_parser("ingest-transcripts",
                               help="Pull transcripts from Fireflies.ai API")
    tr.add_argument("--key", help="Fireflies API key (or set FIREFLIES_API_KEY)")
    tr.add_argument("--list", dest="list_only", action="store_true",
                    help="List available transcripts without exporting")
    tr.add_argument("--filter", help="Filter by meeting name (substring)")
    tr.set_defaults(func=cmd_ingest_transcripts)

    # ingest-github
    gh = subparsers.add_parser("ingest-github", help="Fetch a GitHub README")
    gh.add_argument("repo", help="org/repo (e.g. trueagi-io/PLN)")
    gh.set_defaults(func=cmd_ingest_github)

    # sync-master-doc
    sd = subparsers.add_parser("sync-master-doc",
                               help="Fetch Google Doc master index")
    sd.set_defaults(func=cmd_sync_master_doc)

    # report
    rp = subparsers.add_parser("report", help="Show topic coverage report")
    rp.set_defaults(func=cmd_report)

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        return

    args.func(args)


if __name__ == "__main__":
    main()
