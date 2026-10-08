#!/usr/bin/env python3
"""Build one ingest-ready transcript set from several provider exports.

Otter, Fireflies and Read.ai all watch the same calendar, so the combined
exports contain the same meeting two or three times over. Per operator
policy only the longest and most complete capture of a meeting is
ingested. This tool applies that policy and writes the result as a new
export directory, leaving every source export byte-for-byte intact.

Output (default `<out>/`):
    *.json                  the selected records, copied verbatim
    selection_manifest.json the full audit: what was selected, what was
                            skipped, why, and which capture superseded it

The output directory is a drop-in export dir: point TRANSCRIPT_EXPORT_DIR
at it and the ingest sees exactly the selected set.

Usage:
    python scripts/select_transcripts.py OUT_DIR EXPORT_DIR [EXPORT_DIR ...]
        [--scope cross-provider|all] [--near-tie-ratio 0.02] [--dry-run]

Reads and writes local files only; contacts nothing.
"""

import argparse
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pipeline.transcript_selection import (  # noqa: E402
    NEAR_TIE_RATIO, SCOPES, SCOPE_CROSS_PROVIDER, duplicate_groups, select,
)

#: Sidecar files an exporter writes next to its records. Kept in step with
#: NON_TRANSCRIPT_FILES in scripts/ingest_transcripts.rb, plus the
#: per-provider manifests, so they are skipped quietly rather than
#: reported as malformed transcripts.
NON_TRANSCRIPT_FILES = {
    "export_summary.json", "verification_report.json",
    "manifest.json", "_manifest.json", "export_manifest.json",
    "otter_export_manifest.json", "readai_export_manifest.json",
    "fireflies_export_manifest.json", "selection_manifest.json",
}


def load_entries(export_dirs):
    """Load every transcript record from the given export directories."""
    entries, problems = [], []
    for raw_dir in export_dirs:
        export_dir = Path(raw_dir)
        if not export_dir.is_dir():
            problems.append(f"not a directory: {export_dir}")
            continue
        for path in sorted(export_dir.glob("*.json")):
            if path.name in NON_TRANSCRIPT_FILES:
                continue
            try:
                record = json.loads(path.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError) as exc:
                problems.append(f"unparseable: {path.name}: {exc}")
                continue
            # Mirror the ingest's own filter so selection sees exactly the
            # records the ingest would.
            if not (isinstance(record, dict)
                    and (record.get("meeting_name") or record.get("full_text"))):
                problems.append(f"not a transcript: {path.name}")
                continue
            entries.append({
                "record": record,
                "path": str(path),
                "source_export": export_dir.name,
                "provider": str(record.get("source_service") or ""),
            })
    return entries, problems


def summarize(entries):
    """Per-provider record and character counts."""
    by_provider = {}
    for entry in entries:
        bucket = by_provider.setdefault(
            entry["provider"], {"records": 0, "chars": 0})
        bucket["records"] += 1
        bucket["chars"] += entry["metrics"]["chars"]
    return dict(sorted(by_provider.items()))


def build_manifest(selected, skipped, groups, args, problems):
    collapsed = [g for g in groups if g["collapsed"]]
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "policy": (
            "ingest only the longest and most complete transcript per meeting"
        ),
        "scope": args.scope,
        "near_tie_ratio": args.near_tie_ratio,
        "source_exports": [str(Path(d)) for d in args.export_dirs],
        "totals": {
            "input_records": len(selected) + len(skipped),
            "selected_records": len(selected),
            "skipped_records": len(skipped),
            "meeting_groups": len(groups),
            "collapsed_groups": len(collapsed),
            "selected_chars": sum(e["metrics"]["chars"] for e in selected),
            "skipped_chars": sum(e["metrics"]["chars"] for e in skipped),
        },
        "selected_by_provider": summarize(selected),
        "skipped_by_provider": summarize(skipped),
        "load_problems": problems,
        "groups": groups,
        "selected": [
            {
                "transcript_id": e["record"].get("transcript_id"),
                "provider": e["provider"],
                "date": e["record"].get("date"),
                "source_export": e["source_export"],
                "source_path": e["path"],
                "output_file": e.get("output_file"),
                "selection_reason": e["selection_reason"],
                "metrics": e["metrics"],
            }
            for e in selected
        ],
        "skipped": [
            {
                "transcript_id": e["record"].get("transcript_id"),
                "provider": e["provider"],
                "date": e["record"].get("date"),
                "source_export": e["source_export"],
                "source_path": e["path"],
                "skipped_because": e["skipped_because"],
                "superseded_by": e["superseded_by"],
                "metrics": e["metrics"],
            }
            for e in skipped
        ],
    }


def main(argv):
    parser = argparse.ArgumentParser(
        description="Select the longest/most complete transcript per meeting.")
    parser.add_argument("out_dir", help="directory to write the selected set")
    parser.add_argument("export_dirs", nargs="+",
                        help="provider export directories to combine")
    parser.add_argument("--scope", default=SCOPE_CROSS_PROVIDER, choices=SCOPES,
                        help="collapse only multi-provider duplicate meetings "
                             "(default) or every duplicate meeting")
    parser.add_argument("--near-tie-ratio", type=float, default=NEAR_TIE_RATIO,
                        help="treat transcripts within this fraction of the "
                             "longest as length-equivalent "
                             f"(default {NEAR_TIE_RATIO})")
    parser.add_argument("--dry-run", action="store_true",
                        help="report the selection without writing anything")
    args = parser.parse_args(argv[1:])

    if not 0.0 <= args.near_tie_ratio < 1.0:
        parser.error("--near-tie-ratio must be in [0, 1)")

    entries, problems = load_entries(args.export_dirs)
    if not entries:
        print("ERROR: no transcript records found", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1

    selected, skipped, groups = select(
        entries, scope=args.scope, near_tie_ratio=args.near_tie_ratio)

    out_dir = Path(args.out_dir)
    if not args.dry_run:
        out_dir.mkdir(parents=True, exist_ok=True)
        used = {}
        for entry in selected:
            source = Path(entry["path"])
            # Two providers can export the same meeting under the same
            # file name; keep both resolvable by suffixing the provider.
            name = source.name
            if name in used:
                name = f"{source.stem}__{entry['provider'] or 'unknown'}.json"
            suffix = 2
            while name in used:
                name = f"{source.stem}__{suffix}.json"
                suffix += 1
            used[name] = True
            entry["output_file"] = name
            shutil.copy2(source, out_dir / name)

    manifest = build_manifest(selected, skipped, groups, args, problems)
    if not args.dry_run:
        (out_dir / "selection_manifest.json").write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    totals = manifest["totals"]
    print("=" * 66)
    print("TRANSCRIPT SELECTION — longest/most complete per meeting")
    print("=" * 66)
    print(f"source exports    : {len(args.export_dirs)}")
    print(f"scope             : {args.scope}")
    print(f"input records     : {totals['input_records']}")
    print(f"selected records  : {totals['selected_records']}")
    print(f"skipped duplicates: {totals['skipped_records']}")
    print(f"meeting groups    : {totals['meeting_groups']} "
          f"({totals['collapsed_groups']} collapsed)")
    print(f"selected chars    : {totals['selected_chars']:,}")
    print(f"skipped chars     : {totals['skipped_chars']:,}")
    print()
    print("selected by provider:")
    for provider, stats in manifest["selected_by_provider"].items():
        print(f"  {provider or '(unknown)':14s} "
              f"{stats['records']:4d} records  {stats['chars']:>12,} chars")
    if manifest["skipped_by_provider"]:
        print("skipped by provider:")
        for provider, stats in manifest["skipped_by_provider"].items():
            print(f"  {provider or '(unknown)':14s} "
                  f"{stats['records']:4d} records  {stats['chars']:>12,} chars")

    reasons = {}
    for entry in skipped:
        reasons[entry["skipped_because"]] = (
            reasons.get(entry["skipped_because"], 0) + 1)
    if reasons:
        print("skip reasons:")
        for reason, count in sorted(reasons.items()):
            print(f"  {reason:38s} {count}")

    win_reasons = {}
    for group in groups:
        if group["collapsed"]:
            win_reasons[group["reason"]] = win_reasons.get(group["reason"], 0) + 1
    if win_reasons:
        print("selection reasons (collapsed groups):")
        for reason, count in sorted(win_reasons.items()):
            print(f"  {reason:38s} {count}")

    if problems:
        print(f"load problems     : {len(problems)}")

    remaining = duplicate_groups(selected, scope=args.scope)
    print("-" * 66)
    if remaining:
        print(f"FAIL: {len(remaining)} duplicate meeting group(s) survived "
              f"selection")
        return 1
    if args.dry_run:
        print("DRY RUN: nothing written.")
    else:
        print(f"Wrote {len(selected)} records + selection_manifest.json to")
        print(f"  {out_dir}")
    print("Source exports untouched; skipped records retained with provenance.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
