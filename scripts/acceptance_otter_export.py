#!/usr/bin/env python3
"""Offline acceptance pass over an Otter.ai MCP export directory.

Validates the artifacts WITHOUT contacting Otter or any wiki/Decko instance:
schema, date sanity, card-name uniqueness, transcript substance, conversation
id uniqueness and secret hygiene. Mirrors the offline acceptance used for the
Read AI and Fireflies exports.

Usage:
    python scripts/acceptance_otter_export.py <export_dir>
"""

import re
import sys
import json
from pathlib import Path
from datetime import datetime, timezone

REQUIRED_FIELDS = (
    "meeting_name", "date", "source_service", "summary", "action_items",
    "full_text", "duration_minutes", "participants", "keywords",
    "transcript_id", "transcript_url", "is_live",
)

# Anything that would mean credential material leaked into an artifact.
SECRET_MARKERS = (
    "access_token", "refresh_token", "client_secret",
    "registration_access_token", "Bearer ", "X-Amz-Signature",
    "code_verifier", "authorization_code", "Mcp-Session-Id",
)

NON_RECORD_FILES = (
    "export_summary.json",
    "otter_export_manifest.json",
)

SUMMARY_FIELDS = (
    "exported_at", "total_transcripts", "files_written", "live_transcripts",
    "services", "date_range",
)


def main(argv):
    if len(argv) == 2 and argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    if len(argv) != 2:
        print(__doc__)
        return 2
    export_dir = Path(argv[1])
    if not export_dir.is_dir():
        print(f"FAIL: not a directory: {export_dir}")
        return 2

    record_files = sorted(
        p for p in export_dir.glob("*.json")
        if p.name not in NON_RECORD_FILES
    )

    failures = []
    warnings = []
    card_names = {}
    conversation_ids = {}
    dates = []
    total_chars = 0
    empty_text = 0
    no_participants = 0
    no_summary = 0

    manifest_path = export_dir / "otter_export_manifest.json"
    manifest = (json.loads(manifest_path.read_text(encoding="utf-8"))
                if manifest_path.exists() else {})

    summary_path = export_dir / "export_summary.json"
    summary = (json.loads(summary_path.read_text(encoding="utf-8"))
               if summary_path.exists() else {})

    today = datetime.now(tz=timezone.utc).date()

    for path in record_files:
        raw = path.read_text(encoding="utf-8")

        for marker in SECRET_MARKERS:
            if marker in raw:
                failures.append(f"{path.name}: contains secret marker {marker!r}")

        try:
            record = json.loads(raw)
        except ValueError as exc:
            failures.append(f"{path.name}: invalid JSON ({exc})")
            continue

        for field in REQUIRED_FIELDS:
            if field not in record:
                failures.append(f"{path.name}: missing field {field!r}")

        if record.get("source_service") != "otter.ai":
            failures.append(
                f"{path.name}: source_service={record.get('source_service')!r}")

        date_value = record.get("date") or ""
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date_value):
            failures.append(f"{path.name}: bad date {date_value!r}")
        else:
            parsed = datetime.strptime(date_value, "%Y-%m-%d").date()
            dates.append(parsed)
            # A future date means a timestamp-unit mistake (seconds read as
            # milliseconds), which files meetings decades out and poisons any
            # date-ordered ingest.
            if parsed > today:
                failures.append(f"{path.name}: future date {date_value}")
            if parsed.year < 2015:
                failures.append(f"{path.name}: implausible date {date_value}")

        # Card name collisions would overwrite each other on ingest.
        name = record.get("meeting_name") or ""
        card = f"Raw Data+transcripts+{name}+{date_value}"
        card_names.setdefault(card, []).append(path.name)

        cid = record.get("transcript_id") or ""
        if not cid:
            failures.append(f"{path.name}: empty transcript_id")
        else:
            conversation_ids.setdefault(cid, []).append(path.name)

        text = record.get("full_text") or ""
        total_chars += len(text)
        if not text.strip():
            empty_text += 1
            warnings.append(f"{path.name}: empty full_text")
        elif ":" not in text.split("\n", 1)[0]:
            warnings.append(f"{path.name}: first line lacks a speaker label")

        if record.get("is_live"):
            failures.append(f"{path.name}: is_live true in a completed export")

        if not record.get("participants"):
            no_participants += 1
        if not (record.get("summary") or "").strip():
            no_summary += 1

        if not isinstance(record.get("action_items"), list):
            failures.append(f"{path.name}: action_items is not a list")
        if not isinstance(record.get("keywords"), list):
            failures.append(f"{path.name}: keywords is not a list")

        duration = record.get("duration_minutes")
        if not isinstance(duration, int) or duration < 0 or duration > 1440:
            warnings.append(f"{path.name}: odd duration {duration!r}")

        url = record.get("transcript_url") or ""
        if url and not url.startswith("https://"):
            failures.append(f"{path.name}: non-https transcript_url")

    for card, files in sorted(card_names.items()):
        if len(files) > 1:
            failures.append(
                f"card-name collision ({len(files)} files) -> would overwrite "
                f"on ingest: {files}")

    # The whole point of cross-sweep dedupe: one conversation, one record.
    for cid, files in sorted(conversation_ids.items()):
        if len(files) > 1:
            failures.append(
                f"duplicate conversation id {cid} in {len(files)} files "
                f"(cross-sweep dedupe failed): {files}")

    if summary:
        for field in SUMMARY_FIELDS:
            if field not in summary:
                failures.append(f"export_summary.json: missing {field!r}")
        written = summary.get("files_written")
        if written is not None and written != len(record_files):
            failures.append(
                f"export_summary.json files_written={written} but "
                f"{len(record_files)} record files on disk")
        services = summary.get("services") or []
        if record_files and services and services != ["otter.ai"]:
            failures.append(
                f"export_summary.json services={services!r}, expected "
                f"['otter.ai']")
    elif record_files:
        failures.append("export_summary.json is missing")

    if manifest:
        listed = manifest.get("records_written")
        if listed is not None and listed != len(record_files):
            failures.append(
                f"manifest records_written={listed} but "
                f"{len(record_files)} record files on disk")
        if manifest.get("fetch_failures"):
            warnings.append(
                f"manifest reports {len(manifest['fetch_failures'])} "
                f"fetch failures")
        if manifest.get("sweep_failures"):
            warnings.append(
                f"manifest reports {len(manifest['sweep_failures'])} "
                f"sweep failures — archive coverage may be incomplete")
        if manifest.get("source_service") not in (None, "otter.ai"):
            failures.append(
                f"manifest source_service={manifest.get('source_service')!r}")

    print("=" * 66)
    print("OTTER.AI MCP EXPORT — OFFLINE ACCEPTANCE (no Otter/wiki contact)")
    print("=" * 66)
    print(f"export dir        : {export_dir}")
    print(f"record files      : {len(record_files)}")
    if dates:
        print(f"date range        : {min(dates)} .. {max(dates)}")
        years = {}
        for d in dates:
            years[d.year] = years.get(d.year, 0) + 1
        print(f"per-year counts   : {dict(sorted(years.items()))}")
    print(f"transcript chars  : {total_chars:,}")
    print(f"empty transcripts : {empty_text}")
    print(f"no participants   : {no_participants}")
    print(f"no summary        : {no_summary}")
    print(f"unique card names : {len(card_names)}")
    print(f"unique conv ids   : {len(conversation_ids)}")
    if manifest:
        print(f"sweeps planned    : {manifest.get('sweeps_planned', '-')}")
        print(f"mcp calls         : {manifest.get('mcp_calls', '-')}")
    print(f"secret markers    : "
          f"{'NONE' if not any('secret marker' in f for f in failures) else 'FOUND'}")
    print("-" * 66)

    if warnings:
        print(f"WARNINGS ({len(warnings)}):")
        for warning in warnings[:15]:
            print(f"  - {warning}")
        if len(warnings) > 15:
            print(f"  ... {len(warnings) - 15} more")
        print("-" * 66)

    if failures:
        print(f"FAIL ({len(failures)} problems):")
        for failure in failures[:25]:
            print(f"  - {failure}")
        if len(failures) > 25:
            print(f"  ... {len(failures) - 25} more")
        return 1

    print("PASS: artifacts are schema-valid, collision-free, deduped and "
          "secret-free.")
    print("Ingest remains OPT-IN and was not run; no production contact.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
