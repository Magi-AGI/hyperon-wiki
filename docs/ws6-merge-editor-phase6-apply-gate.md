# WS6 Phase 6 — Verifying merge-apply (gate spec)

**Status:** SPEC / planning only. **No apply code until the logged-in Phase 5 e2e is green**
(Codex). This is the governance gate from the 2026-06-16 Khellar↔Lake call: the only path by
which an AI/human proposal ever reaches a parent card, behind a verifying transaction that
replaces the blunt `merge_ai_draft` overwrite.

**Companion:** `ws6-merge-editor-design.md`, `…-impl-plan.md` (Phase 6),
`…-phase5-tinymce-gate.md` (the `+merge draft` + two-hash `+audit` artifact this consumes).

## What Phase 6 applies, and from where

The artifact chain Phase 5 produced (all dev-verified):
- `<Parent>+proposal` — the **immutable** original suggestion; hash in `+proposal+provenance`.
- `<Parent>+proposal+merge draft` — the human-assembled+polished content to apply.
- `<Parent>+proposal+merge draft+audit` (schema v2) — `assembled_hash` (immutable seed-time
  origin), `polished_hash` (refreshed each native save), `hunk_selections`, `parent_act_id`,
  `base_act_id`, `base_hash`, `proposal_hash`, actor/source/timestamps.

Phase 6 writes the **merge draft's current content** to the parent, only after the gate below.

## The four-fold gate (all checks inside ONE DB transaction; abort → no parent write)

1. **Permission.** `parent.ok?(:update)` for the acting user — checked on the PARENT, not the
   proposal/draft. (The user must also be allowed to act on the draft.)
2. **Optimistic lock.** Parent's current latest act id == audit `parent_act_id` (the act the
   reviewer assembled against). Mismatch ⇒ someone edited the parent underneath the review ⇒
   reject with a "parent changed, re-review" conflict. (Re-checked here even though Phase 5's
   seed already drift-gated — the parent can move between seed and apply.)
3. **Draft integrity (two-hash).** `sha256(merge_draft.db_content) == audit.polished_hash` —
   proves what is about to hit the parent is exactly what the human last polished+saved (no
   intermediate DB tampering). The immutable `audit.assembled_hash` is ALSO surfaced in the
   apply record as the provenance origin (it is not the apply target — Codex).
4. **Identity.** The user executing apply is the polishing author, or an editor of
   equal/greater clearance. Recorded in the audit.

Supporting integrity (recorded, used to explain a rejection, not necessarily hard-fail):
- `base_hash` still reconstructs (BaseResolver) — base provenance intact.
- `proposal_hash` of the (immutable) `+proposal` unchanged since authoring — the reviewed
  suggestion didn't drift.

**If ANY gate fails: no byte is written to the parent.** The user gets a specific, actionable
message (perm / stale-parent / integrity / identity).

## On success — transactional apply + lifecycle (one transaction)

1. Write `parent.content = merge_draft.db_content`; capture `parent_pre_merge_act_id` and
   `parent_post_merge_act_id`.
2. Lifecycle transition (idempotent): mark `<Parent>+proposal` (and `+merge draft`)
   **closed/merged**; drop the `ai_generated` tag if present, add `merged`.
3. Write the apply audit `<Parent>+proposal+merge audit` with the full provenance schema
   (Gemini): `merged_by_id`, `merged_by_name`, `merged_at`, `parent_pre_merge_act_id`,
   `parent_post_merge_act_id`, `hunk_selections` (verbatim from the draft audit),
   `original_base_act_id`, `original_proposal_hash`, `assembled_hash`, `polished_hash`.

## Idempotency / retry

- The merge-draft name is deterministic; apply is a state transition, not an append.
- A second apply on an already-merged/closed proposal returns **409 Conflict**
  ("already merged or closed") and writes nothing. Double-submit cannot reapply or corrupt.

## Mutual exclusion — retire the blunt overwrite (Codex's standing condition)

When this apply path lands, the old `event :merge_ai_draft` blunt overwrite in
`set/right/ai_draft.rb` and its `view :merge_button` must be **removed / hidden / hard-rerouted
in the same change**. Production must never simultaneously expose a "safe verifying merge" and
a "clobber the parent" path for the same content. The Phase 7 entry points already repoint to
the workbench; Phase 6 removes the legacy write itself.

## Spec / test matrix (to write with the code, after e2e green)

- perm-denied (non-updater) → reject, no write.
- stale-parent (parent act moved since seed) → reject, no write.
- draft-integrity (merge draft content hash != polished_hash, e.g. tampered) → reject.
- identity mismatch → reject.
- happy path → parent updated, lifecycle transitioned, apply audit written.
- double-submit / already-merged → 409, idempotent (no second parent act).
- no surviving blunt-overwrite entry point (grep + behavior test).
- Markdown parent path (apply markdown content) parallels the HTML path.

## Open items folded from review

Two-hash audit (Codex) settled in Phase 5 (`assembled_hash` immutable, `polished_hash`
applied). Capture parent act at workbench load (done) AND re-check at apply (gate 2).
Everything verifying happens in the SAVE transaction, never only in the UI.
