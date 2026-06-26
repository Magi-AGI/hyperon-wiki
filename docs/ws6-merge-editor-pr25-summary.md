# WS6 — 3-Way Merge Editor + Governance Gate (PR #25 summary)

Branch: `feature/ws6-merge-editor` → `main`. PR: https://github.com/Magi-AGI/hyperon-wiki/pull/25

## What this delivers

Replaces the blunt **"Merge AI Draft → Parent"** one-click overwrite in
`mod/editorial_review` with a real **base × proposal × current-parent** 3-way merge
workbench and a **verifying, human-approved apply gate** — the governance gate agreed
in the 2026-06-16 Khellar↔Lake call. After this, AI-proposed changes can only reach a
published article through review + an explicit, permission-checked, audited apply.

## Phase-by-phase

- **P0 — Design.** `docs/ws6-merge-editor-design.md` + impl plan. New
  **`<Parent>+proposal`** subcard convention (author-neutral "pull request"); `+AI`
  stays the generic AI-content catch-all.
- **P1 — Provenance + base stamping.** `ProposalProvenance` (newline-agnostic content
  hashing, CRLF→LF only), server-stamped `+proposal+base` (parent revision at authoring
  time) + `+proposal+provenance` (hashes/actor/ts). Registered the `proposal` codename
  (right-set binding).
- **P2 — Base resolver.** `BaseResolver` three-tier confidence
  (verified/estimated/unreliable/stale) + `RevisionSnapshot` (canonical content-at-action).
- **P3 — Merge engine.** `BlockMerge` pure-Ruby 3-way: protect `{{nests}}` → tokenize
  blocks (Nokogiri HTML / Markdown) → diff3 → classify (stable/ai_only/human_only/
  both_same/conflict) → assemble from selections. AI never auto-accepted; conflicts block
  assembly.
- **P4 / 4.1 / 4.2 — Workbench UI.** `view :merge_workbench` (reachable at
  `/<Parent>+proposal?view=merge_workbench&layout=none`): P4Merge-style columnar 3-way,
  animated Bézier ribbons over resizable bands, base-centered (**Current Parent | Base |
  Proposal**), tier banners, conflict-gated selection rail, client-side preview
  (non-authoritative — the server re-verifies). No parent write here.
- **P5 — Polish handoff (Fork B).** `<Parent>+proposal+merge draft` holds the
  human-assembled+polished output (original `+proposal` stays immutable for audit).
  Authenticated `fetch` POST seeds it; **the server re-runs assembly from the submitted
  selections — never trusts client HTML.** Two-hash audit: immutable **`assembled_hash`**
  (origin proof) + refreshed **`polished_hash`** (tracks each native save). TinyMCE reused
  as the polish pane; `{{nests}}` survive. Registered the `merge_draft` codename.
- **P6 — Verifying apply gate.** `apply_merge_draft` writes the parent in ONE transaction
  only after a four-fold gate: (1) `parent.ok?(:update)`, (2) optimistic lock vs the audit's
  `parent_act_id`, (3) integrity `sha256(content) == polished_hash`, (4) identity. Records a
  `+merge audit` (`ws6-merge-apply/1`: merged_by, pre/post act ids, hashes, selections);
  idempotent 409 on re-apply. **Mutual exclusion:** removed the blunt `merge_ai_draft` event.
- **P7 — Lifecycle, bridge, entry points.** Locked "already merged" workbench view; on
  apply, `merged` tag added / `ai generated` dropped (web `:integrate`). Opt-in legacy
  **+AI → +proposal bridge** (estimated base, low-confidence caveat). Entry links carry
  `layout=none`. Hard mutual-exclusion invariant: only `apply_merge_draft` writes a parent.
- **P8.1 — Capability gating + bypass close.** Bridge and apply both gated on
  **`parent.ok?(:update)`** (no role name hard-coded — resolves to whatever role edits
  articles, e.g. `Editor` in prod), enforced server-side (`guard_legacy_bridge`), not just
  UI. **Option A:** the merged-in `ai_draft_aware.rb` "Merge AI Draft → Parent" button no
  longer overwrites the parent — it routes through the workbench (active proposal) or the
  capability-gated bridge (none yet), restoring mutual exclusion while keeping that panel's
  layout.

## Integration note

Reconciled cleanly with `origin/main` (`cbfc859`, the page-attribution work): zero merge
conflicts; the two mods are decoupled apart from the shared `ai_draft_aware.rb` button,
resolved via Option A above.

## Verification (dev runner + authenticated web on :3000)

- Pure/engine: BlockMerge 20/20; provenance/base resolver green.
- Apply gate: fresh-process 6/6; newline/tamper 5/5.
- **Authenticated web (Lake, :3000):** Phase 5 polish e2e; **Phase 6 real apply** (parent
  merged, audit `merged_by="Lake Watkins"`, proposal immutable, 409 on re-apply); **Phase 7**
  merged-tag + locked view + legacy bridge (estimated base, parent untouched).
- Phase 8.1 capability gating 16/16; mutual-exclusion invariant 6/6; bridge model 9/9.
- Integration spec: `spec/integration/editorial_review_capability_gating_spec.rb` (+ the
  Phase 5 `editorial_review_merge_draft_spec.rb`). NB: `spec/integration/` is not yet wired
  into CI (out of scope for WS6).

## Deferred (not in this PR)

Review Queue union query (post-deploy, see deploy notes); bulk accept/reject (Q3); live
4th-pane TinyMCE editor (Q1, v2). See `docs/ws6-merge-editor-prod-deploy-notes.md`.
