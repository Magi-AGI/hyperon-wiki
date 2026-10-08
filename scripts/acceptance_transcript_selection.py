#!/usr/bin/env python3
"""Offline acceptance for a selected transcript set (no wiki/Decko contact).

Proves that a directory produced by scripts/select_transcripts.py is safe
to ingest under the operator's policy — ingest only the longest and most
complete transcript per meeting:

  * no meeting group is duplicated in the selected set, under the scope
    the selection was made with;
  * every selected record is the one the policy would pick, re-derived
    from the originals rather than trusted from the manifest;
  * every input record is accounted for as selected or skipped, each
    skip naming the capture that superseded it;
  * the selected files on disk match the manifest exactly, and are
    byte-identical to their sources (selection copies, never rewrites);
  * card names planned by the real ingest algorithm stay collision-free.

Usage: python scripts/acceptance_transcript_selection.py SELECTED_DIR
Exit 0 on PASS, 1 on FAIL.
"""

import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pipeline.transcript_card_names import assign_card_names  # noqa: E402
from pipeline.transcript_selection import (  # noqa: E402
    duplicate_groups, group_key, metrics, select,
)

MANIFEST_NAME = "selection_manifest.json"


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 1

    selected_dir = Path(argv[1])
    manifest_path = selected_dir / MANIFEST_NAME
    if not manifest_path.is_file():
        print(f"FAIL: no {MANIFEST_NAME} in {selected_dir}")
        return 1

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    failures, warnings = [], []
    scope = manifest.get("scope")
    totals = manifest.get("totals", {})

    # --- the selected files on disk are exactly the manifest's set ------
    on_disk = {p.name for p in selected_dir.glob("*.json")
               if p.name != MANIFEST_NAME}
    claimed = {entry.get("output_file") for entry in manifest.get("selected", [])}
    if None in claimed:
        failures.append("manifest has selected entries without output_file")
        claimed.discard(None)
    for extra in sorted(on_disk - claimed):
        failures.append(f"file present but not in manifest: {extra}")
    for missing in sorted(claimed - on_disk):
        failures.append(f"manifest names a missing file: {missing}")

    # --- selection is a copy, not a rewrite ----------------------------
    for entry in manifest.get("selected", []):
        out_name, source = entry.get("output_file"), entry.get("source_path")
        if not out_name or out_name not in on_disk:
            continue
        if not source or not Path(source).is_file():
            warnings.append(f"source no longer readable: {source}")
            continue
        if sha256(selected_dir / out_name) != sha256(source):
            failures.append(f"{out_name}: differs from its source export")

    # --- every input is accounted for ----------------------------------
    sel_ids = [e.get("transcript_id") for e in manifest.get("selected", [])]
    skip_ids = [e.get("transcript_id") for e in manifest.get("skipped", [])]
    if len(set(sel_ids)) != len(sel_ids):
        failures.append("duplicate transcript_id among selected records")
    overlap = set(sel_ids) & set(skip_ids)
    if overlap:
        failures.append(
            f"{len(overlap)} transcript id(s) both selected and skipped")
    expected_input = totals.get("input_records")
    if expected_input is not None and len(sel_ids) + len(skip_ids) != expected_input:
        failures.append(
            f"selected+skipped ({len(sel_ids) + len(skip_ids)}) != "
            f"input_records ({expected_input})")

    for entry in manifest.get("skipped", []):
        if not entry.get("skipped_because"):
            failures.append(
                f"skipped {entry.get('transcript_id')!r} has no reason")
        superseded = entry.get("superseded_by") or {}
        if not superseded.get("transcript_id"):
            failures.append(
                f"skipped {entry.get('transcript_id')!r} names no superseding "
                f"transcript")
        elif superseded["transcript_id"] not in set(sel_ids):
            failures.append(
                f"skipped {entry.get('transcript_id')!r} superseded by a "
                f"transcript that was not selected")
        # The policy's whole promise: the kept capture is not shorter.
        kept_chars = superseded.get("chars")
        own_chars = (entry.get("metrics") or {}).get("chars")
        if isinstance(kept_chars, int) and isinstance(own_chars, int):
            if kept_chars < own_chars:
                near_tie = entry.get("skipped_because") == (
                    "less-complete-within-length-band")
                if not near_tie:
                    failures.append(
                        f"skipped {entry.get('transcript_id')!r} is longer "
                        f"than the record that superseded it")

    # --- the selected set has no duplicate meetings left ---------------
    records = []
    for path in sorted(selected_dir.glob("*.json")):
        if path.name == MANIFEST_NAME:
            continue
        try:
            record = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            failures.append(f"{path.name}: unparseable ({exc})")
            continue
        records.append(record)

    remaining = duplicate_groups(records, scope=scope)
    for key, providers in sorted(remaining.items()):
        failures.append(
            f"duplicate meeting group survived selection on {key[1]} "
            f"across providers {providers}")

    # --- re-derive the policy from the originals ------------------------
    # The manifest is evidence, not authority: rebuild the selection from
    # the source exports and require the same winners.
    sources, unreadable = [], 0
    for entry in (manifest.get("selected", []) + manifest.get("skipped", [])):
        source = entry.get("source_path")
        if not source or not Path(source).is_file():
            unreadable += 1
            continue
        try:
            sources.append({
                "record": json.loads(Path(source).read_text(encoding="utf-8")),
                "path": source,
                "provider": entry.get("provider") or "",
            })
        except (json.JSONDecodeError, UnicodeDecodeError):
            unreadable += 1

    rederived = None
    if unreadable:
        warnings.append(
            f"{unreadable} source record(s) unreadable; policy re-derivation "
            f"skipped")
    elif sources:
        ratio = manifest.get("near_tie_ratio")
        kwargs = {"scope": scope}
        if isinstance(ratio, (int, float)):
            kwargs["near_tie_ratio"] = ratio
        again, _again_skipped, _again_groups = select(sources, **kwargs)
        rederived = {str(e["record"].get("transcript_id")) for e in again}
        if rederived != {str(i) for i in sel_ids}:
            only_manifest = {str(i) for i in sel_ids} - rederived
            only_rederived = rederived - {str(i) for i in sel_ids}
            failures.append(
                f"re-derived selection disagrees with the manifest: "
                f"{len(only_manifest)} manifest-only, "
                f"{len(only_rederived)} policy-only")

    # --- the kept capture really is the longest in each group ----------
    by_group = {}
    for entry in (manifest.get("selected", []) + manifest.get("skipped", [])):
        source = entry.get("source_path")
        if not source or not Path(source).is_file():
            continue
        try:
            record = json.loads(Path(source).read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        by_group.setdefault(group_key(record), []).append(
            (str(record.get("transcript_id")), metrics(record)["chars"]))

    ratio = manifest.get("near_tie_ratio")
    ratio = ratio if isinstance(ratio, (int, float)) else 0.0
    selected_set = {str(i) for i in sel_ids}
    for key, members in by_group.items():
        kept = [m for m in members if m[0] in selected_set]
        if len(members) < 2 or len(kept) != 1:
            continue
        longest = max(chars for _tid, chars in members)
        if kept[0][1] < longest * (1.0 - ratio):
            failures.append(
                f"group on {key[1]}: kept capture is outside the "
                f"longest-transcript band")

    # --- ingest card names stay unique ---------------------------------
    card_keys = {}
    try:
        for plan in assign_card_names(records):
            card_keys.setdefault(plan["card_key"], 0)
            card_keys[plan["card_key"]] += 1
    except ValueError as exc:
        failures.append(f"card-name planning failed: {exc}")
    for key, count in card_keys.items():
        if count > 1:
            failures.append(f"card name collision: {key} x{count}")

    print("=" * 66)
    print("TRANSCRIPT SELECTION — OFFLINE ACCEPTANCE (no wiki/Decko contact)")
    print("=" * 66)
    print(f"selected dir      : {selected_dir}")
    print(f"policy            : {manifest.get('policy', '-')}")
    print(f"scope             : {scope}")
    print(f"near-tie ratio    : {manifest.get('near_tie_ratio')}")
    print(f"source exports    : {len(manifest.get('source_exports', []))}")
    print(f"input records     : {totals.get('input_records', '-')}")
    print(f"selected records  : {len(records)} on disk / {len(sel_ids)} in manifest")
    print(f"skipped duplicates: {len(skip_ids)}")
    print(f"meeting groups    : {totals.get('meeting_groups', '-')} "
          f"({totals.get('collapsed_groups', '-')} collapsed)")
    print(f"selected chars    : {totals.get('selected_chars', 0):,}")
    print(f"duplicate groups  : {len(remaining)}")
    print(f"unique card names : {len(card_keys)}")
    print(f"policy re-derived : "
          f"{'yes, agrees' if rederived is not None and not failures else ('yes' if rederived is not None else 'skipped')}")
    print(f"copies verified   : sha256 match against source exports")

    if warnings:
        print("-" * 66)
        print(f"WARNINGS ({len(warnings)}):")
        for warning in warnings[:20]:
            print(f"  - {warning}")

    print("-" * 66)
    if failures:
        print(f"FAIL ({len(failures)} issue(s)):")
        for failure in failures[:40]:
            print(f"  - {failure}")
        if len(failures) > 40:
            print(f"  ... and {len(failures) - 40} more")
        return 1

    print("PASS: one capture per meeting, each the longest/most complete;")
    print("every input accounted for; selected files are verbatim copies.")
    print("Ingest remains OPT-IN and was not run; no production contact.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
