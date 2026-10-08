#!/usr/bin/env python3
"""Offline acceptance pass over a transcript export directory.

Validates the artifacts WITHOUT contacting any wiki/Decko instance: schema,
date sanity, card-name uniqueness, transcript substance and secret hygiene.

Works for every transcript provider in the pipeline (Read AI, Fireflies,
Otter). The provider is not hard-coded: a mixed or unexpected
`source_service` is a real finding, but a *uniformly* Fireflies export is
not a failure just because the checker grew up around Read AI.

Usage:
    python scripts/acceptance_transcript_export.py <export_dir> [--service NAME]

    --service NAME   Require every record to carry this source_service.
                     Omit to infer it from export_summary.json (or from the
                     records themselves) and merely require consistency.
"""

import re
import sys
import json
import argparse
from pathlib import Path
from datetime import datetime, timezone

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pipeline.transcript_card_names import assign_card_names  # noqa: E402

REQUIRED_FIELDS = (
    "meeting_name", "date", "source_service", "summary", "action_items",
    "full_text", "duration_minutes", "participants", "keywords",
    "transcript_id", "transcript_url", "is_live",
)

# Providers this pipeline knows how to ingest. An export carrying anything
# else is suspect: either a new source nobody has mapped to card names yet,
# or a corrupted record.
KNOWN_SERVICES = ("read.ai", "fireflies.ai", "otter.ai")

# Sidecar files that are not transcript records.
NON_RECORD_FILES = (
    "export_summary.json",
    "readai_export_manifest.json",
    "otter_export_manifest.json",
    "fireflies_export_manifest.json",
)

# Anything that would mean credential material leaked into an artifact.
SECRET_MARKERS = (
    "access_token", "refresh_token", "client_secret",
    "registration_access_token", "Bearer ", "X-Amz-Signature",
    "code_verifier", "authorization_code",
)


def _load_manifest(export_dir: Path) -> dict:
    """Return the first provider manifest found, or {}."""
    for name in NON_RECORD_FILES:
        if name == "export_summary.json":
            continue
        path = export_dir / name
        if path.exists():
            try:
                return json.loads(path.read_text(encoding="utf-8"))
            except ValueError:
                return {}
    return {}


def _expected_service(export_dir: Path, override: str, records: list) -> str:
    """Resolve which source_service this export is supposed to carry.

    Explicit --service wins. Otherwise trust export_summary.json's
    `services` when it names exactly one provider. Failing that, fall back
    to the majority value in the records, which turns a stray mismatch into
    a pinpointed failure instead of flagging every single file.
    """
    if override:
        return override

    summary_path = export_dir / "export_summary.json"
    if summary_path.exists():
        try:
            services = json.loads(
                summary_path.read_text(encoding="utf-8")
            ).get("services") or []
        except ValueError:
            services = []
        if len(services) == 1:
            return services[0]

    counts = {}
    for record in records:
        value = record.get("source_service")
        if value:
            counts[value] = counts.get(value, 0) + 1
    if counts:
        return max(counts.items(), key=lambda kv: kv[1])[0]
    return ""


def main(argv):
    parser = argparse.ArgumentParser(
        description="Offline acceptance pass over a transcript export dir",
    )
    parser.add_argument("export_dir")
    parser.add_argument("--service",
                        help="Require this source_service on every record "
                             "(default: infer and require consistency)")
    args = parser.parse_args(argv[1:])

    export_dir = Path(args.export_dir)
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
    transcript_ids = {}
    dates = []
    total_chars = 0
    empty_text = 0
    no_participants = 0

    # Parse everything up front so the expected service can be inferred
    # from the real contents rather than guessed from the directory name.
    parsed_records = []
    for path in record_files:
        raw = path.read_text(encoding="utf-8")

        for marker in SECRET_MARKERS:
            if marker in raw:
                failures.append(
                    f"{path.name}: contains secret marker {marker!r}")

        try:
            record = json.loads(raw)
        except ValueError as exc:
            failures.append(f"{path.name}: invalid JSON ({exc})")
            continue
        parsed_records.append((path, record))

    expected_service = _expected_service(
        export_dir, args.service, [r for _, r in parsed_records])

    if expected_service and expected_service not in KNOWN_SERVICES:
        failures.append(
            f"unknown source_service {expected_service!r} "
            f"(known: {', '.join(KNOWN_SERVICES)})")

    manifest = _load_manifest(export_dir)
    today = datetime.now(tz=timezone.utc).date()

    for path, record in parsed_records:
        for field in REQUIRED_FIELDS:
            if field not in record:
                failures.append(f"{path.name}: missing field {field!r}")

        service = record.get("source_service")
        if expected_service and service != expected_service:
            failures.append(
                f"{path.name}: source_service={service!r} "
                f"(export is {expected_service!r})")

        date_value = record.get("date") or ""
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date_value):
            failures.append(f"{path.name}: bad date {date_value!r}")
        else:
            parsed = datetime.strptime(date_value, "%Y-%m-%d").date()
            dates.append(parsed)
            # A transcript dated in the future means an epoch-unit mistake
            # (seconds read as milliseconds), which would silently file
            # meetings decades out and poison any date-ordered ingest.
            if parsed > today:
                failures.append(f"{path.name}: future date {date_value}")
            if parsed.year < 2015:
                failures.append(f"{path.name}: implausible date {date_value}")


        # A repeated transcript_id means a merge deduped on the wrong key.
        tid = record.get("transcript_id")
        if tid:
            transcript_ids.setdefault(tid, []).append(path.name)

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

        if not isinstance(record.get("action_items"), list):
            failures.append(f"{path.name}: action_items is not a list")

        duration = record.get("duration_minutes")
        if not isinstance(duration, int) or duration < 0 or duration > 1440:
            warnings.append(f"{path.name}: odd duration {duration!r}")

        url = record.get("transcript_url") or ""
        if url and not url.startswith("https://"):
            failures.append(f"{path.name}: non-https transcript_url")

    # Plan card names with the real ingest algorithm (a port of
    # scripts/ingest_transcripts.rb). Two transcripts of the same recurring
    # meeting on the same date are normal and get disambiguated by
    # transcript id; only a name the real algorithm cannot make unique is a
    # genuine overwrite risk.
    disambiguated = 0
    try:
        plans = assign_card_names(r for _p, r in parsed_records)
    except ValueError as exc:
        failures.append(f"card-name planning failed: {exc}")
        plans = []

    for (path, _record), plan in zip(parsed_records, plans):
        card_names.setdefault(plan["card_key"], []).append(path.name)
        if plan["label_reason"] != "meeting_name":
            disambiguated += 1

    for card, files in sorted(card_names.items()):
        if len(files) > 1:
            failures.append(
                f"card-name collision ({len(files)} files) -> would overwrite "
                f"on ingest: {files}")

    for tid, files in sorted(transcript_ids.items()):
        if len(files) > 1:
            failures.append(
                f"duplicate transcript_id {tid!r} across {len(files)} files: "
                f"{files}")

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

    summary_path = export_dir / "export_summary.json"
    if summary_path.exists():
        try:
            summary = json.loads(summary_path.read_text(encoding="utf-8"))
        except ValueError as exc:
            failures.append(f"export_summary.json: invalid JSON ({exc})")
            summary = {}
        counted = summary.get("files_written")
        if counted is not None and counted != len(record_files):
            failures.append(
                f"export_summary files_written={counted} but "
                f"{len(record_files)} record files on disk")

    label = (expected_service or "transcript").upper()
    print("=" * 66)
    print(f"{label} EXPORT — OFFLINE ACCEPTANCE (no wiki/Decko contact)")
    print("=" * 66)
    print(f"export dir        : {export_dir}")
    print(f"source service    : {expected_service or '(none detected)'}")
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
    print(f"unique card names : {len(card_names)}")
    print(f"disambiguated     : {disambiguated} "
          f"(same title+date, split by transcript id)")
    print(f"unique transcript ids : {len(transcript_ids)}")
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

    print("PASS: artifacts are schema-valid, collision-free and secret-free.")
    print("Ingest remains OPT-IN and was not run; no production contact.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
