# Transcript date shift — root cause and decision

Date: 2026-10-12
Branch: `phase5/atomspace-go-live-hardening` (unpushed)
Status: **root cause identified; no live code defect; data reconciliation still owed**

No wiki writes, no ingest, and no production contact were involved in producing this.
Everything below comes from the repository source, git history, and the local export
artifacts.

## The observation

The report-only orphan classifier labels 59 live cards `date_shifted` (23 index + 36
chunk, ~1,453,993 chars). 22 of the 23 index cards sit **exactly one day after** the
date the current export assigns to the same meeting series.

## Root cause

The shift is **not produced by the current code path**. It is a legacy artifact.

- `scripts/export_otter.py:128-131` (and the same conversion at `:185-186`) derives the
  meeting date as `datetime.utcfromtimestamp(created_at).strftime('%Y-%m-%d')` — a naive
  **UTC** date from an epoch instant.
- A meeting's identity is its **local calendar date**. For a series that starts late in
  the local evening, the UTC instant falls on the *next* calendar day, so every
  occurrence is filed one day late. Confirmed arithmetically: a 21:30 America/Los_Angeles
  start on 2026-01-22 renders as `2026-01-23` under `utcfromtimestamp`.
- The affected series is the **Otter** "Meeting @ Elowyn AI" evening series. The shift is
  *selective*, which is itself the signature of this bug: pairing legacy against current
  Otter records on identical title + identical duration gives a shift distribution of
  `{0 days: 28, +1 day: 15}`, and all 15 shifted records are that one evening series
  while 7 other Otter series are unshifted. A global exporter regression would have moved
  everything.
- Corroborating: the 22 shifted index cards fall on Fri/Tue/Wed in the deck but
  Thu/Mon/Tue in the current export — i.e. the live dates break the series' own weekly
  recurrence — and the transcript bodies carry evening greetings, consistent with a
  late local start.

**The current exporter is correct.** `scripts/export_otter_mcp.py` no longer reads
`created_at` at all: `parse_start_date` (`:744-764`) reads Otter's `start_time`, an
already-local wall-clock string, via `strptime(...).strftime('%Y-%m-%d')` with no
timezone conversion. The Ruby side is not implicated — `ingest_transcripts.rb` does no
date arithmetic; it only sanitizes the exporter-supplied date into a card name part.

History: `export_otter.py` was UTC-naive from the commit that introduced it (`1a12dec`);
it was superseded wholesale, not patched, by `de17e09`, which added the MCP exporter. No
commit ever turned a working local conversion into a UTC one.

## Decision

**No behavioural code fix.** There is no defect in the live path to repair, and the
legacy script is deliberately *not* "corrected":

- No raw timezone information survives anywhere in the stored exports. Every exported
  transcript JSON carries only a pre-formatted `date: "YYYY-MM-DD"`; a scan of all legacy
  export directories found zero time/created/start/epoch/tz fields, and no raw Otter API
  or MCP response is retained.
- So any replacement offset in `export_otter.py` would be a **guess**, and a
  plausible-looking wrong date is worse than an obviously stale script.

What was done instead:

1. `scripts/export_otter.py` — the defect is documented in place as a
   **WARNING / DO NOT RE-RUN**, naming the consequence and pointing at the replacement.
2. `docs/INGESTION-WORKFLOWS.md` — the script is marked **Superseded, do not run** in the
   exporter table.
3. `scripts/tests/test_otter_mcp.py` — four regression tests pin the *correct* current
   behaviour, because this failure is silent (a shifted date still looks valid):
   a 21:30 start keeps its own date; midnight and 23:59:59 stay on their own day; the
   result is independent of the exporting machine's `TZ` (checked at +14 and -11); and the
   record date comes from `start_time`, not `created_at`.

## Still owed — the actual risk

The 59 live `date_shifted` cards are **not** resolved by any of the above. They are a
data-reconciliation decision, and it is the one thing that must happen before a write:

> If an ingest runs as-is, each affected meeting gets a second, correctly-dated card
> while the mis-dated one stays orphaned — baking ~1.45M chars of duplication into the
> deck.

Under the standing keep-stale / prefer-duplication-over-loss policy that outcome is
*safe* but messy. The recommended path is an explicit, reviewed rename manifest mapping
the 23 legacy `+1`-day index cards (and their 36 chunks) onto the corrected dates — a
separate, approved, reviewable operation, not a side effect of an ingest.

Two items do **not** belong to this root cause and need separate triage:

- `RawData+transcripts+Magi Weekly+2025-12-29` — the 23rd shifted index card. Magi Weekly
  is exported via read.ai/fireflies, **not** Otter, and no 2025-12-29 or 2025-12-28 Magi
  Weekly export exists. Unexplained by this defect.
- `scripts/pipeline/transcript_sources.py:413,428` retain `utcfromtimestamp` in
  `_parse_fireflies_date`. For a *string* date the ISO formats are tried first, so this
  did not cause the observed cards; it is reached for a numeric epoch, or for a string
  that parses as one. `:877` uses `datetime.utcnow()` for the export stamp. Latent
  instances of the same anti-pattern; both calls are also deprecated as of Python 3.12.
  Worth tightening, not urgent.
