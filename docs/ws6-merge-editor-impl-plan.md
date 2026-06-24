# WS6 — 3-Way Merge Editor: Implementation Plan

**Companion to:** `ws6-merge-editor-design.md` (spec). **Mod:** `editorial_review`. **Branch:** `feature/ws6-merge-editor` off `main`.
**Principle:** each phase is an independently testable, reviewable increment that leaves the wiki working. Model/engine layers land and are spec-covered **before** any UI; the blunt `merge_ai_draft` overwrite stays in place until Phase 6 replaces it, so there's never a window with no merge path.

---

## Phase 0 — Branch & spec landing *(no behavior change)*
- Create `feature/ws6-merge-editor` off clean `main` (isolated git worktree — see §"Branching" below — so the teammate's untracked files on `feature/page-attribution-render` are untouched).
- Land `docs/ws6-merge-editor-design.md` + this plan.
- **Exit:** branch exists, spec in repo, `bundle exec rspec` green (unchanged).

## Phase 1 — `+proposal` convention + base stamping *(model layer, no UI)*
- New `mod/editorial_review/set/right/proposal.rb`:
  - `event :stamp_proposal_base, on: :create` — authoring-time parent `act_id` (read-time proxy); idempotent; override no-op if `+base` already present.
  - `event :align_proposal_type, on: :create` — set proposal `type_id` to parent's content format (§3.5).
  - Write `<Parent>+proposal+provenance` — parent id/name, base + proposal content hashes, actor/source, timestamp, `override_reason`.
  - Override guard: restricted + audited + requires `reason`; never a silent free-write (anti-spoof).
- **Specs:** create stamps base+provenance; override path (no-op + audit + reason required); type mirrors RichText vs Markdown parent; hashes recorded.
- **Exit:** every new `+proposal` carries verifiable base provenance. No merge behavior yet.

## Phase 2 — `BaseResolver` (tier logic) *(lib, no UI)*
- Extract a shared `snapshot_at_action` helper from `mcp_api`'s `build_snapshot_at_action` (DRY) into `mod/editorial_review/lib/` (or a shared lib); reuse for base reconstruction.
- `BaseResolver.call(proposal)` → `{ base_content, tier, warning }`:
  - Tier 1 stamped → reconstruct from `+base` act_id.
  - Tier 2 unstamped, single unambiguous parent rev ≤ `created_at` → reconstruct + caveat.
  - Tier 3 ambiguous/pruned → no base; signal 2-way fallback.
- **Specs:** stamped→T1; one rev→T2; multiple-in-window→T3; pruned history→T3; legacy bridge→forced T2/3.
- **Exit:** deterministic base + confidence for any proposal.

## Phase 3 — `BlockMerge` diff engine *(pure Ruby, no UI — most heavily tested)*
- `mod/editorial_review/lib/block_merge.rb`:
  1. **Nest-protect** `/\{\{[^}]+\}\}/` → opaque tokens (restore on assemble).
  2. **Tokenize:** HTML→Nokogiri top-level block nodes (outerHTML strings; tables/lists/`pre`/media atomic); Markdown→blank-line paragraphs.
  3. **diff3** over the three block arrays (`diff-lcs` LCS primitive) → hunks classified AI-only / human-only / both-same / **conflict**.
  4. **Within-block display diff** (word/char `<ins>/<del>`) — display only, never splits a nest token.
  5. **Assemble**(selections) → merged content (restore nests).
- **Specs (testing matrix §10):** insert, delete, both-same, real conflict, nested lists, tables, inline tags, `{{nest}}` preservation incl. nest-inside-changed-block, Markdown cards, empty proposal.
- **Exit:** `(base,current,proposal) → hunks`; `(hunks,selections) → merged HTML/MD`. No I/O.

## Phase 4 — Workbench view, Phase-1 reconciliation UI *(read-only; no save)*
- `view :merge_workbench` on the `proposal` right-set; **layout-free shell** (bypass card 513).
- Renders: tier banner, conflict count, 3-way block hunk list (Base · Current · Proposal), per-hunk accept/reject toggles, safe defaults (no auto-accept AI), one-click 2-way switch (Tier 2).
- Client JS: toggle state + "Assemble Merge Draft" → compile selected blocks client-side (restore nests). **TinyMCE not loaded.**
- JS gotchas: `String.fromCharCode(92)` for any `\`; `node --check` embedded scripts; CSS literals (no `hsl(var())`).
- **Exit:** editor reconciles hunks and previews assembled HTML. Still no parent write.

## Phase 4.1 — P4Merge ribbon polish *(presentation only; same contract)*
- Upgrade the thin-cut gutters to **animated cubic-Bézier connector ribbons** (inline SVG
  `<path>`, recomputed in JS on scroll/resize/select; no chart lib, CSS-literal styling) plus
  **user-resizable highlighted bands** that re-fit the ribbons to differing block heights —
  Lake's signature P4Merge look, scheduled here (not Phase 8) per the 2026-06-24 decision.
- **Strictly non-semantic (Codex):** hunk meaning stays fully carried by text + label/icon +
  color + keyboard focus; the tool must remain complete and usable with ribbons disabled.
- No change to the §3 payload, §4 selection model, or the client assembler — pure rendering.
- **Exit:** the workbench shows animated P4Merge-style connections; thin-cut behavior unchanged.

## Phase 5 — TinyMCE polish pane (Phase-2 UI)
- On "Assemble", instantiate **one** TinyMCE via the deck's `decko.initTinyMCE` with the merged content (reuse fullscreen config). Markdown parents → existing Markdown edit surface, gated on `card.type_name`.
- Verify/extend `{{nest}}` survival through TinyMCE (`valid_elements`/`extended_valid_elements`, paste cleanup).
- **Exit:** editor hand-tweaks merged output in the familiar editor; stable undo stack (single instantiation).

## Phase 6 — Verifying merge-apply *(replaces blunt overwrite)*
- New apply event/controller on `proposal` set; **retire `event :merge_ai_draft`**. Inside one transaction:
  1. `parent.ok?(:update)` (parent perms, not the proposal's).
  2. Optimistic lock: reject if `parent.last_act_id != params[:parent_act_id]`.
  3. Hash match: parent + proposal + base vs `+provenance`; reject on drift.
  4. Write parent = final TinyMCE HTML; stamp `+approved by/at`; write `+merge audit`.
  5. Idempotent: double-submit cannot reapply/corrupt.
- **Mutual-exclusion gate (Codex):** when this apply path lands, the old blunt overwrite must be **removed / hidden / hard-rerouted in the same change** — production must never simultaneously expose both a "safe merge workbench" and a "clobber parent" path for the same proposal.
- **Specs:** perm-denied; stale-parent reject; hash-mismatch reject; double-submit idempotent; happy path writes + audits; **no surviving blunt-overwrite entry point**.
- **Exit:** end-to-end human-approved merge with full guards. **This is the governance gate from the Khellar call.**

## Phase 7 — Lifecycle, entry points, legacy bridge
- Archive on merge: add `merged` tag, drop `ai_generated` if present, ensure `+merge audit` written.
- Repoint `view :ai_draft_link` / `view :merge_button` to the workbench; surface a `+proposal` launch entry; optional right-column (card 17242) status + launch button only.
- "Open as proposal" bridge for stray `+AI`/candidate → explicitly unstamped, Tier 2/3, lower-confidence session (no silent promotion).
- **Exit:** full UX wired; legacy `+AI` path safe; blunt overwrite fully gone.

## Phase 8 — Hardening & deploy
- Run full testing matrix; manual QA on **dev** wiki (incl. parent rename between author & merge, large-article perf); accessibility of the diff UI.
- PR review (Codex/Gemini advisory) → merge to `main`.
- Deploy per the Administrator+Hyperon Wiki Server Guide (git pull → `decko update` → `rake decko:mod:symlink` → restart `hyperon-wiki.service`). Verify on prod; one-writer convention — verify each write.

---

## Branching (Codex condition)
Use an **isolated worktree** so the active branch's 18 untracked files are never entangled:
```
git -C E:/GitHub/Magi-AGI/hyperon-wiki worktree add ../hyperon-wiki-ws6 -b feature/ws6-merge-editor main
```
Work happens in `../hyperon-wiki-ws6` off clean `main`. (Confirm `origin/main` is fetched before any push — local `origin/main` did not resolve during inspection.)

## Risk register
- **TinyMCE nest mangling** → Phase 5 explicit `valid_elements` test before relying on it; fail closed (keep raw nest tokens) if unsafe.
- **diff3 on malformed legacy HTML** → Nokogiri fragment parse + normalize; fall back to coarser block split; never crash the view.
- **Tier-2 inference wrong** → caveat banner + one-click 2-way; never authoritative.
- **Large articles** → block-level keeps hunk counts sane; lazy-render hunk bodies if needed.
- **Rollback:** each phase is its own commit; Phases 0–5 add only new surfaces (blunt overwrite still live), so any pre-Phase-6 revert is clean.

## Open items folded from review
Stamp at authoring (not merge-open) time · override restricted/audited/reasoned · rich base provenance (ids, hashes, actor, ts) · perms+lock+hash in the **save path** not just UI · archive-don't-delete.
