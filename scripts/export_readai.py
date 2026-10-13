#!/usr/bin/env python3
"""Export meeting transcripts from Read AI for the Hyperon Wiki pipeline.

Read AI sells static API keys only on GA plans, so this exporter authenticates
with the OAuth 2.1 credentials established by scripts/readai_oauth.py (dynamic
client registration + PKCE). Run that first:

    python scripts/readai_oauth.py register
    python scripts/readai_oauth.py authorize --open
    python scripts/readai_oauth.py exchange --redirect-url "<post-approval URL>"

Then:

    python scripts/export_readai.py --list
    python scripts/export_readai.py --output DIR
    python scripts/export_readai.py --id <ULID> --output DIR

No API key is ever read from argv or the environment: the token comes from the
credential store outside the repository, and a fresh bearer token is minted per
request because Read AI access tokens expire in ~10 minutes — shorter than a
full transcript walk over a large account.

DEFAULT OUTPUT IS OUTSIDE THE REPOSITORY. Transcripts are private meeting
content; writing them into the work tree invites an accidental commit. Pass
--output explicitly to override.
"""

import os
import sys
import json
import argparse
from pathlib import Path
from datetime import datetime, timezone

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts import readai_oauth
from scripts.pipeline.transcript_sources import (
    READAI_EXPAND_SECTIONS,
    READAI_MAX_PAGE_SIZE,
    readai_list_meetings,
    readai_get_meeting,
    readai_to_record,
    readai_has_transcript,
    save_transcripts_json,
)

# Private meeting content stays out of the git work tree by default.
DEFAULT_ARTIFACT_ROOT = Path(
    os.environ.get("MAGI_TRANSCRIPT_ARTIFACTS")
    or Path(__file__).resolve().parents[2] / "_transcript_artifacts"
)


def default_output_dir() -> Path:
    stamp = datetime.now(tz=timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return DEFAULT_ARTIFACT_ROOT / f"readai_{stamp}"


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


def _iso_bound(value: str, end_of_day: bool = False) -> str:
    """Normalise a YYYY-MM-DD CLI date into the ISO form Read AI expects."""
    if not value:
        return ""
    if "T" in value:
        return value
    return f"{value}T23:59:59Z" if end_of_day else f"{value}T00:00:00Z"


def _token_provider():
    """Return a callable minting a valid access token, refreshing as needed.

    Called once per HTTP request on purpose. Read AI refresh tokens are
    single-use and rotate, and readai_oauth serialises rotation behind a lock
    file, so this stays safe while keeping long exports from dying mid-walk on
    an expired token.
    """
    return readai_oauth.get_access_token


def cmd_list(from_date: str, to_date: str) -> int:
    meetings = readai_list_meetings(
        _token_provider(),
        limit=READAI_MAX_PAGE_SIZE,
        start_datetime_gte=_iso_bound(from_date),
        start_datetime_lte=_iso_bound(to_date, end_of_day=True),
    )
    print(f"Read AI meetings visible to this account: {len(meetings)}")
    starts = sorted(m.get("start_time_ms") or 0 for m in meetings)
    if starts and starts[-1]:
        fmt = lambda ms: datetime.fromtimestamp(  # noqa: E731
            ms / 1000, tz=timezone.utc).strftime("%Y-%m-%d")
        print(f"Date range: {fmt(starts[0])} .. {fmt(starts[-1])}")
    platforms = {}
    for m in meetings:
        platforms[m.get("platform") or "unknown"] = (
            platforms.get(m.get("platform") or "unknown", 0) + 1)
    print(f"Platforms: {platforms}")
    print("Transcript availability is only known after expansion; "
          "run the export to count.")
    return 0


def cmd_export(output_dir: Path, from_date: str, to_date: str,
               meeting_id: str = None, limit: int = 0,
               skip_empty: bool = True) -> int:
    _assert_outside_repo(output_dir)

    provider = _token_provider()

    if meeting_id:
        listing = [{"id": meeting_id}]
        print(f"Exporting 1 meeting by id")
    else:
        listing = readai_list_meetings(
            provider,
            limit=READAI_MAX_PAGE_SIZE,
            start_datetime_gte=_iso_bound(from_date),
            start_datetime_lte=_iso_bound(to_date, end_of_day=True),
        )
        print(f"Listed {len(listing)} meetings")
        if limit:
            listing = listing[:limit]
            print(f"Limited to first {len(listing)}")

    records = []
    no_transcript = []
    failures = []

    for index, row in enumerate(listing, start=1):
        mid = row.get("id")
        if not mid:
            continue
        try:
            meeting = readai_get_meeting(mid, provider,
                                         sections=READAI_EXPAND_SECTIONS)
        except RuntimeError as exc:
            # One meeting the account cannot expand must not abandon the rest
            # of the walk; record it and continue.
            failures.append({"id": mid, "error": str(exc)})
            print(f"  [{index}/{len(listing)}] FAILED {mid}: {exc}")
            continue

        if not readai_has_transcript(meeting):
            no_transcript.append(mid)
            if skip_empty:
                print(f"  [{index}/{len(listing)}] no transcript, skipped")
                continue

        record = readai_to_record(meeting)
        records.append(record)
        print(f"  [{index}/{len(listing)}] {record.date} "
              f"turns={len(record.sentences)} chars={len(record.full_text)}")

    if not records:
        print("No exportable transcripts found.")

    save_transcripts_json(records, output_dir)

    manifest = {
        "exported_at": datetime.now(tz=timezone.utc).isoformat(),
        "source_service": "read.ai",
        "auth": "oauth2.1-dcr-pkce",
        "meetings_listed": len(listing),
        "records_written": len(records),
        "meetings_without_transcript": len(no_transcript),
        "fetch_failures": failures,
        "expand_sections": list(READAI_EXPAND_SECTIONS),
        "page_size": READAI_MAX_PAGE_SIZE,
    }
    (output_dir / "readai_export_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"\nWrote {len(records)} transcript records to {output_dir}")
    print(f"  without transcript: {len(no_transcript)}  "
          f"failures: {len(failures)}")
    return 0 if not failures else 1


def main():
    parser = argparse.ArgumentParser(
        description="Export Read AI meeting transcripts (OAuth 2.1)")
    parser.add_argument("--output", default=None,
                        help="Output directory (default: timestamped dir "
                             "outside the repo)")
    parser.add_argument("--list", action="store_true", dest="do_list",
                        help="List meeting counts/date range only")
    parser.add_argument("--id", default=None,
                        help="Export a single meeting by ULID")
    parser.add_argument("--from-date", default=None,
                        help="Only meetings starting on/after YYYY-MM-DD")
    parser.add_argument("--to-date", default=None,
                        help="Only meetings starting on/before YYYY-MM-DD")
    parser.add_argument("--limit", type=int, default=0,
                        help="Export at most N meetings (0 = all)")
    parser.add_argument("--include-empty", action="store_true",
                        help="Also write records with no transcript content")
    args = parser.parse_args()

    if args.do_list:
        return cmd_list(args.from_date, args.to_date)

    output_dir = Path(args.output) if args.output else default_output_dir()
    return cmd_export(output_dir, args.from_date, args.to_date,
                      meeting_id=args.id, limit=args.limit,
                      skip_empty=not args.include_empty)


if __name__ == "__main__":
    sys.exit(main())
