# WS6 Phase 7 — Lifecycle, entry points & legacy bridge (plan)

**Status:** PLAN ONLY (reviewer-ratified scope; no Phase 7 code until this is reviewed).
**Prereqs:** Phases 0–6 complete. Phase 6 (verifying apply) is the governance gate; Phase 7
makes it the *daily* path — clean post-merge state, discoverable entry points, and an opt-in
on-ramp for legacy `+AI` drafts — **without ever resurrecting the blunt overwrite.**
**Verification:** isolated `:3001` / worktree runner only; do NOT touch `:3000`.

Phase 6 deferred four things into here: the **merged tag / drop ai_generated**, the
**post-merge "already merged" workbench state**, the **legacy `+AI` bridge**, and
**entry-point links** (carrying `layout=none`). Each below is an independently testable
increment that leaves the wiki working.

---

## 7.1 Post-merge lifecycle state machine

When Phase 6 applies a merge, the proposal is "done." Make that state explicit and terminal.

- **Tags (auditable):** on apply, set the `merged` tag on `<Parent>+proposal+tag` and drop
  `ai generated` if present. Must use the in-act write pattern proven in Phase 6 (no nested
  `Card#save!` of an existing card mid-act, no `+applied`-style shared-simple-card subcard
  that collides — see the Phase 6 lessons). Likely: compute the new pointer item list and
  write it as part of the apply act, or a dedicated post-apply `:integrate` step that runs
  only on the real web apply. Spec must cover the "tag already exists with other items" case.
- **Already-merged workbench view:** `view :merge_workbench` detects a completed merge
  (a `<Parent>+proposal+merge audit` exists) and renders a **clean locked screen** instead of
  the diff:
  > "This proposal has been merged. View the final article: [parent] · Inspect the immutable
  > merge audit: [audit]." — no Apply, no Assemble, no Reset.
- **Idempotency safeguard (already proven, keep it):** the apply event already rejects with a
  409 ("already been merged") when `+merge audit` exists; Phase 7 just surfaces it as the
  locked view so the human never reaches the button.
- **Draft archiving (decide):** options — leave the `+merge draft` as-is (its `+audit` records
  it), OR mark it archived. Do NOT silently delete (archive-don't-delete). Recommend: leave it,
  and the locked view links to it read-only.

## 7.2 Legacy `+AI` → `+proposal` bridge (opt-in on-ramp)

Existing un-stamped `+AI` drafts predate WS6. Give them a deliberate, low-confidence on-ramp —
never a silent promotion, never the blunt overwrite.

- **Affordance:** on a `<Parent>+AI` card that has NO companion `<Parent>+proposal`, render an
  **"Open as proposal"** action (admin/editor only). Nothing automatic.
- **Promotion (server-side, one action):**
  1. Create `<Parent>+proposal`, seeding content from the `<Parent>+AI` draft.
  2. `BaseResolver` estimates the base from the legacy draft's creation time → **Tier 2/3**
     (estimated/unreliable), never "verified".
  3. Stamp the estimated `+base` (act id) + an **explicitly estimated** `+provenance`
     (`stamp_source: "legacy_bridge"`, low confidence), so the audit never overclaims.
  4. Redirect to `…+proposal?view=merge_workbench&layout=none` with the **yellow estimated-base
     caveat banner** already active (the §5 stale/estimated banner).
- **Opt-in & visibility:** the resulting proposal is visibly marked legacy/estimated; the
  workbench shows 2-way or estimated-3-way per the tier. No verified-tier claims.

## 7.3 Entry-point link standardization

- Repoint every link that opens the workbench — `view :ai_draft_link` / any review buttons /
  notification cards / the editorial dashboard / the right-column status on card 17242 — to
  `<Parent>+proposal?view=merge_workbench&layout=none`.
- **Enforce `layout=none` through redirects** (Phase 4 finding: without it the workbench
  renders wrapped in the card-513 layout). Centralize the URL builder so the param can't be
  dropped.
- Surface a `+proposal` launch entry where proposals are authored (so the workbench is
  reachable without hand-typing the URL).

## 7.4 Mutual-exclusion preservation (hard invariant)

- The blunt `merge_ai_draft` event + button were removed in Phase 6. Phase 7 must NOT
  reintroduce any parent-overwrite path — not via the bridge (which only creates a proposal,
  never writes the parent), not via lifecycle actions (which only tag/lock), not via entry
  points. The ONLY parent write remains the Phase 6 verifying apply.
- A regression test asserts there is no code path (event, view, controller, param) that writes
  a parent's content outside `apply_merge_draft`.

## 7.5 Test matrix (write with the code)

- **already-merged:** workbench shows the locked view; Apply/Assemble/Reset absent; a direct
  apply post returns 409; no second parent act.
- **lifecycle tags:** apply adds `merged`, drops `ai generated`, preserves other tags;
  re-running is idempotent.
- **legacy bridge:** "Open as proposal" creates a Tier 2/3 proposal seeded from `+AI`, stamps
  estimated base + low-confidence provenance, redirects with `layout=none` + caveat banner;
  shown only when no `+proposal` exists; admin/editor-gated.
- **direct old-path attempt:** a `?merge_draft=true` post (the retired trigger) does NOT
  overwrite the parent (event is gone).
- **entry links:** every workbench link includes `layout=none`.

---

# WS6 Phase 8 — Hardening & deploy (outline)

- Full testing matrix; manual QA on dev (parent renamed between author & apply, very large
  articles + ribbon perf, Markdown parents end-to-end, accessibility of the diff/apply UI).
- Decide the parked UI niceties: **bulk accept/reject** (Q3) and the **live 4th-pane TinyMCE
  editor** (Q1) — schedule or defer explicitly.
- PR review (Codex/Gemini advisory) → merge `feature/ws6-merge-editor` to `main`.
- Deploy per Administrator+Hyperon Wiki Server Guide (git pull → `decko update` →
  `rake decko:mod:symlink` → restart `hyperon-wiki.service`). The `proposal`/`merge_draft`
  codenames already seeded on dev become correct on a real deploy. Verify on prod; one-writer
  convention — verify each write.

## Sequencing

7.1 (post-merge state) → 7.3 (entry links) → 7.2 (legacy bridge) → 7.4 invariant test
throughout. 7.1 and 7.3 are the smallest/highest-value (make the gate usable daily); the
legacy bridge is the largest. Each lands as its own commit; mutual exclusion is asserted in
every one.
