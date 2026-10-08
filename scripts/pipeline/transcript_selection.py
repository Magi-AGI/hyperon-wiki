"""Cross-provider transcript selection: one record per meeting.

Otter, Fireflies and Read.ai are all pointed at the same calendar, so the
same meeting is frequently captured two or three times. Ingesting every
capture would put near-duplicate transcripts of one conversation on the
wiki under disambiguated card names — technically collision-free, but
wrong for a corpus meant to hold *the* record of a meeting.

The operator's policy: **ingest only the longest and most complete
transcript for a given meeting.** This module implements that as a
non-destructive selection layer that runs *before* ingest. Nothing is
deleted; losing captures are recorded as skipped alternates with the
reason and the winner they lost to, so a selection can always be audited
or reversed.

Grouping (conservative by design)
---------------------------------
Two records are the same meeting when their normalized titles and their
dates are equal. Normalization is case/punctuation/whitespace only — no
fuzzy or near-match title logic, because a false merge silently discards
a real transcript and is far more costly than a missed merge (which just
leaves a duplicate for a human to spot).

Scope
-----
`SCOPE_CROSS_PROVIDER` (the default) only collapses groups whose records
come from two or more providers. Two captures of the same title and date
from a *single* provider are left alone: Otter genuinely records split or
rescheduled sessions under one title, and the ingest already gives those
distinct card names. `SCOPE_ALL` additionally collapses same-provider
groups, which is the right choice only once someone has confirmed those
really are redundant captures rather than separate sessions.

Ranking
-------
"Longest" is primary, but a transcript 1% longer than another is not
meaningfully longer, while a summary and action items are meaningfully
more complete. So the longest capture defines a band: every record within
`NEAR_TIE_RATIO` of the group's maximum transcript length counts as
length-equivalent, and completeness decides inside the band. Ordering is
total and deterministic — the final tie-break is the transcript id — so
the same inputs always select the same winner regardless of file order.
"""

import re
import unicodedata

#: Records within this fraction of the group's longest transcript are
#: treated as the same length, letting completeness pick the winner.
NEAR_TIE_RATIO = 0.02

SCOPE_CROSS_PROVIDER = "cross-provider"
SCOPE_ALL = "all"
SCOPES = (SCOPE_CROSS_PROVIDER, SCOPE_ALL)

#: Completeness signals, each worth one point. Presence is what counts
#: here; the magnitudes act as later tie-breaks in `rank_key`.
COMPLETENESS_FIELDS = (
    "summary", "action_items", "participants", "keywords", "duration_minutes",
)


def normalize_title(text):
    """Normalize a meeting title for grouping.

    Case, punctuation and whitespace only. "Lake <> Sandra" and
    "Lake - Sandra" normalize alike because providers render the same
    calendar title with different separators, but no attempt is made to
    match titles that merely resemble each other.
    """
    normalized = unicodedata.normalize("NFKC", str(text or "")).casefold()
    normalized = re.sub(r"[^\w\s]+", " ", normalized)
    return re.sub(r"\s+", " ", normalized).strip()


def group_key(record):
    """Return the meeting identity of a record: (normalized title, date)."""
    return (normalize_title(record.get("meeting_name")),
            str(record.get("date") or "").strip())


def _text_len(record):
    return len(record.get("full_text") or "")


def _word_count(record):
    return len((record.get("full_text") or "").split())


def _count(record, field):
    value = record.get(field)
    if isinstance(value, (list, tuple, dict, str)):
        return len(value)
    if isinstance(value, (int, float)):
        return int(value)
    return 0


def completeness_points(record):
    """How many completeness signals this record actually carries."""
    return sum(1 for field in COMPLETENESS_FIELDS if _count(record, field) > 0)


def metrics(record):
    """The numbers behind a selection, recorded in the manifest."""
    return {
        "chars": _text_len(record),
        "words": _word_count(record),
        "completeness_points": completeness_points(record),
        "summary_chars": _count(record, "summary"),
        "action_items": _count(record, "action_items"),
        "participants": _count(record, "participants"),
        "keywords": _count(record, "keywords"),
        "duration_minutes": _count(record, "duration_minutes"),
    }


def rank_key(record):
    """Completeness ordering used *within* a length band (higher wins).

    Length is deliberately absent: the band has already established that
    these records are length-equivalent, so including it would let a
    trivial length edge outvote a real completeness difference.
    """
    m = metrics(record)
    return (
        m["completeness_points"],
        m["action_items"],
        m["participants"],
        m["keywords"],
        m["summary_chars"],
        m["duration_minutes"],
        m["words"],
    )


def _tie_break(entry):
    """Total, input-order-independent ordering for genuine ties."""
    record = entry["record"]
    return (str(record.get("transcript_id") or ""),
            str(record.get("source_service") or ""),
            str(entry.get("path") or ""))


def select(entries, scope=SCOPE_CROSS_PROVIDER, near_tie_ratio=NEAR_TIE_RATIO):
    """Pick one record per meeting.

    `entries` is an iterable of dicts with at least ``record`` (the parsed
    transcript) and optionally ``path`` and ``provider``. Returns
    ``(selected, skipped, groups)``:

    * ``selected`` — entries to ingest, in input order, each annotated
      with ``group``, ``metrics`` and ``selection_reason``.
    * ``skipped`` — losing alternates, each annotated with the same plus
      ``skipped_because`` and ``superseded_by`` provenance.
    * ``groups`` — per-group audit rows.

    Every input appears in exactly one of ``selected`` or ``skipped``.
    """
    if scope not in SCOPES:
        raise ValueError(f"unknown scope {scope!r}; expected one of {SCOPES}")

    entries = [dict(e) for e in entries]
    for index, entry in enumerate(entries):
        entry["_index"] = index
        entry["group"] = group_key(entry["record"])
        entry["metrics"] = metrics(entry["record"])
        entry.setdefault(
            "provider", str(entry["record"].get("source_service") or ""))

    grouped = {}
    for entry in entries:
        grouped.setdefault(entry["group"], []).append(entry)

    selected, skipped, groups = [], [], []

    for key, members in grouped.items():
        providers = sorted({m["provider"] for m in members})
        collapsible = len(members) > 1 and (
            scope == SCOPE_ALL or len(providers) > 1)

        if not collapsible:
            # Singleton, or a same-provider group the conservative scope
            # leaves intact. Both pass through untouched.
            reason = "unique-meeting" if len(members) == 1 else (
                "same-provider-group-kept")
            for member in members:
                member["selection_reason"] = reason
                selected.append(member)
            groups.append({
                "normalized_title": key[0], "date": key[1],
                "providers": providers, "records": len(members),
                "collapsed": False, "kept": len(members),
                "reason": reason,
            })
            continue

        longest = max(m["metrics"]["chars"] for m in members)
        threshold = longest * (1.0 - near_tie_ratio)
        band = [m for m in members if m["metrics"]["chars"] >= threshold]

        # Resolve ties explicitly instead of letting max() fall back to
        # input order, so the winner never depends on directory listing
        # order.
        best = max(rank_key(m["record"]) for m in band)
        finalists = [m for m in band if rank_key(m["record"]) == best]
        winner = sorted(finalists, key=_tie_break)[0]

        if len(band) == 1:
            win_reason = "longest-transcript"
        elif len(finalists) == 1:
            win_reason = "most-complete-within-length-band"
        else:
            win_reason = "tie-broken-by-transcript-id"
        winner["selection_reason"] = win_reason
        selected.append(winner)

        provenance = {
            "provider": winner["provider"],
            "transcript_id": winner["record"].get("transcript_id"),
            "chars": winner["metrics"]["chars"],
            "completeness_points": winner["metrics"]["completeness_points"],
            "path": winner.get("path"),
        }
        for member in members:
            if member is winner:
                continue
            member["selection_reason"] = "skipped-duplicate-meeting"
            member["superseded_by"] = provenance
            member["skipped_because"] = (
                "shorter-transcript"
                if member["metrics"]["chars"] < threshold
                else "less-complete-within-length-band")
            skipped.append(member)

        groups.append({
            "normalized_title": key[0], "date": key[1],
            "providers": providers, "records": len(members),
            "collapsed": True, "kept": 1,
            "reason": win_reason,
            "longest_chars": longest,
            "band_size": len(band),
            "winner_provider": winner["provider"],
            "skipped_providers": sorted(
                m["provider"] for m in members if m is not winner),
        })

    selected.sort(key=lambda e: e["_index"])
    skipped.sort(key=lambda e: e["_index"])
    groups.sort(key=lambda g: (g["date"], g["normalized_title"]))
    for entry in entries:
        entry.pop("_index", None)
    return selected, skipped, groups


def duplicate_groups(entries, scope=SCOPE_CROSS_PROVIDER):
    """Groups a selection pass would still consider duplicated.

    Used by the acceptance check to prove the selected set is clean under
    the scope it was produced with.
    """
    grouped = {}
    for entry in entries:
        record = entry["record"] if "record" in entry else entry
        provider = str(
            (entry.get("provider") if isinstance(entry, dict) else None)
            or record.get("source_service") or "")
        grouped.setdefault(group_key(record), []).append(provider)

    offenders = {}
    for key, providers in grouped.items():
        if len(providers) < 2:
            continue
        if scope == SCOPE_ALL or len(set(providers)) > 1:
            offenders[key] = sorted(providers)
    return offenders
