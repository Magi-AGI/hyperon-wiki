#!/usr/bin/env python3
"""Non-interactive Mattermost export for the Hyperon Wiki pipeline.

Exports all channels from chat.singularitynet.io using token auth.
No prompts — fully automated for use in sync scripts.

Usage:
    export MATTERMOST_TOKEN="your-token"
    python scripts/export_mattermost.py [--output DIR] [--no-files]

Or pass token directly:
    python scripts/export_mattermost.py --token YOUR_TOKEN
"""

import os
import sys
import json
import argparse
from pathlib import Path
from datetime import datetime

# Add magi-archive to path for the MattermostExporter
MAGI_ARCHIVE = Path(__file__).resolve().parents[1].parent / "magi-archive"
if MAGI_ARCHIVE.exists():
    sys.path.insert(0, str(MAGI_ARCHIVE))

try:
    from mattermost_export import MattermostExporter
except ImportError:
    print(f"ERROR: Could not import MattermostExporter.")
    print(f"Expected magi-archive repo at: {MAGI_ARCHIVE}")
    print(f"Install: pip install mattermostdriver")
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Export Mattermost channels for Hyperon Wiki")
    parser.add_argument("--token", help="MMAUTHTOKEN (or set MATTERMOST_TOKEN env var)")
    parser.add_argument("--output", help="Output directory")
    parser.add_argument("--no-files", action="store_true", help="Skip file downloads")
    args = parser.parse_args()

    token = args.token or os.environ.get("MATTERMOST_TOKEN")
    if not token:
        print("ERROR: Token required. Set MATTERMOST_TOKEN or use --token")
        sys.exit(1)

    host = "chat.singularitynet.io"
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = Path(args.output) if args.output else Path(f"mattermost_exports/sync_{timestamp}")
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Host: {host}")
    print(f"Output: {output_dir.absolute()}")
    print()

    # Connect
    exporter = MattermostExporter(host=host, token=token)
    exporter.initialize_user_data()

    # Export all teams and channels
    teams = exporter.list_teams()
    total_channels = 0
    total_posts = 0

    for team in teams:
        print(f"\nTeam: {team['display_name']}")

        # Get ALL public channels (not just ones user is a member of)
        all_public = []
        page = 0
        while True:
            batch = exporter.driver.channels.get_public_channels(
                team["id"], params={"per_page": 200, "page": page}
            )
            if not batch:
                break
            all_public.extend(batch)
            page += 1

        # Also get channels user is a member of (includes private channels)
        member_channels = exporter.driver.channels.get_channels_for_user(
            exporter.my_user_id, team["id"]
        )
        member_private = [c for c in member_channels if c["type"] == "P"]

        # Merge: all public + private channels user is in (skip DMs/groups)
        seen_ids = {c["id"] for c in all_public}
        channels = list(all_public)
        for c in member_private:
            if c["id"] not in seen_ids:
                channels.append(c)

        channels.sort(key=lambda c: c.get("display_name", "").lower())
        print(f"  {len(channels)} channels ({len(all_public)} public + {len(member_private)} private)")

        for channel in channels:
            try:
                exporter.export_channel(
                    channel, output_dir,
                    download_files=not args.no_files,
                )
                total_channels += 1
                total_posts += channel.get("total_msg_count", 0)
            except Exception as e:
                print(f"  ERROR exporting {channel['display_name']}: {e}")

    # Summary
    summary = {
        "host": host,
        "exported_at": datetime.utcnow().isoformat() + "Z",
        "teams": len(teams),
        "channels": total_channels,
        "output_dir": str(output_dir.absolute()),
    }
    (output_dir / "export_summary.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8"
    )

    print(f"\n{'='*60}")
    print(f"Export complete!")
    print(f"  Channels: {total_channels}")
    print(f"  Output: {output_dir.absolute()}")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
