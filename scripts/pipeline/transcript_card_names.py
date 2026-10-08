"""Transcript card-name planning, mirrored from scripts/ingest_transcripts.rb.

The offline acceptance passes need to answer one question honestly: *would
this export overwrite one transcript with another on ingest?* Answering it by
reimplementing `"<parent>+<title>+<date>"` was correct only for the pre-fix
ingest script. `ingest_transcripts.rb` now disambiguates two transcripts of
the same recurring meeting on the same date (`assign_transcript_labels`), so a
checker built on the old shape reports collisions the ingest would never make
— and, worse, would stay silent if the real disambiguation ever broke.

This module is a faithful port of the Ruby naming helpers. Keep the two in
step: `scripts/tests/test_transcript_card_names.py` asserts the port's
behaviour on the exact recurring-meeting shapes seen in live exports.

Ruby counterparts:
    sanitize_name_part      -> sanitize_name_part
    name_key                -> name_key (offline approximation branch)
    assign_transcript_labels-> assign_card_names
"""

import re

PARENT_CARD = "Raw Data+transcripts"


def sanitize_name_part(text):
    """Port of `sanitize_name_part`: make a string safe as one Decko name part.

    Returns None when nothing usable survives, matching the Ruby nil.
    """
    if text is None:
        return None
    cleaned = str(text)
    cleaned = cleaned.replace("+", "-")          # name joint: would split parts
    cleaned = cleaned.replace("/", "-")          # path separator in pretty URLs
    cleaned = re.sub(r'[\[\]{}|<>#"]', "-", cleaned)  # nest/markup syntax
    cleaned = re.sub(r"\s+", " ", cleaned)
    cleaned = re.sub(r"-{2,}", "-", cleaned)
    cleaned = re.sub(r"^[*~]+", "", cleaned, count=1)  # reserved prefixes
    cleaned = re.sub(r"^[-\s]+|[-\s]+$", "", cleaned)
    return cleaned or None


def name_key(full_name):
    """Port of `name_key`'s offline approximation branch.

    Splits camelCase runs so "RawData" and "Raw Data" agree the way they do
    in the deck. This is an approximation of Decko's Cardname#key by design:
    both the Ruby offline tests and this module use it, so the acceptance
    verdict matches what the ingest script computes when run offline.
    """
    parts = []
    for part in str(full_name).split("+"):
        p = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", part)
        p = p.lower()
        p = re.sub(r"[^a-z0-9]+", "_", p)
        p = re.sub(r"^_+|_+$", "", p)
        parts.append(p)
    return "+".join(parts)


def assign_card_names(records, parent_card=PARENT_CARD):
    """Port of `assign_transcript_labels`.

    `records` is an iterable of dicts carrying at least `meeting_name`,
    `date` and `transcript_id`. Returns a list of plan dicts in input order:

        {"record", "card_name", "card_key", "label", "label_reason"}

    Preference order per the Ruby, so the planned names here are the names
    the ingest would actually create:
      1. sanitized meeting title        (kept when unambiguous)
      2. "<title> (<transcript id>)"    (disambiguates duplicates)
      3. the transcript id alone        (last resort, always unique)
      4. "<title> (<n>)"                (ordinal backstop)

    Raises ValueError if no candidate is free, mirroring the Ruby raise.
    """
    records = list(records)

    prepared = []
    for rec in records:
        base_label = (
            sanitize_name_part(rec.get("meeting_name"))
            or sanitize_name_part(rec.get("transcript_id"))
            or "Unknown Meeting"
        )
        date_part = sanitize_name_part(rec.get("date")) or "unknown-date"
        prepared.append((rec, base_label, date_part))

    base_counts = {}
    for _rec, base_label, date_part in prepared:
        key = name_key(f"{parent_card}+{base_label}+{date_part}")
        base_counts[key] = base_counts.get(key, 0) + 1

    taken = {}
    plans = []
    for rec, base_label, date_part in prepared:
        tid = sanitize_name_part(rec.get("transcript_id"))
        unambiguous = (
            base_counts[name_key(f"{parent_card}+{base_label}+{date_part}")] == 1
        )

        candidates = []
        if unambiguous:
            candidates.append((base_label, "meeting_name"))
        if tid:
            candidates.append((f"{base_label} ({tid})", "meeting_name+transcript_id"))
            candidates.append((tid, "transcript_id"))
        candidates.append((f"{base_label} ({len(taken) + 1})", "ordinal"))

        chosen = None
        for label, reason in candidates:
            if not label:
                continue
            key = name_key(f"{parent_card}+{label}+{date_part}")
            if key in taken:
                continue
            chosen = (label, reason, key)
            break

        if chosen is None:
            raise ValueError(
                "Unable to assign a unique card name for transcript "
                f"{rec.get('transcript_id')!r}"
            )

        label, reason, key = chosen
        taken[key] = rec
        plans.append({
            "record": rec,
            "card_name": f"{parent_card}+{label}+{date_part}",
            "card_key": key,
            "label": label,
            "label_reason": reason,
        })

    return plans
