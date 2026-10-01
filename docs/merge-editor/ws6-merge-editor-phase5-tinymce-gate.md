# WS6 Phase 5 — TinyMCE polish pane (gate / mini-contract)

**Status:** RESOLVED (Codex + Gemini, 2026-06-24) — **Fork B (handoff)** to a **separate
`+merge draft` artifact**. Both reviewers chose Fork B; they conflicted on the storage
target and that conflict is resolved in Codex's favor (see below). Pending Lake's go to build.
**Scope:** add a final WYSIWYG polish step *downstream* of the assembled merge. NO parent
writes (that's Phase 6); NO change to the diff/merge engine, payload, or selection model.

## RESOLUTION — Fork B, write to `<Parent>+proposal+merge draft` (NOT overwrite the proposal)

Both reviewers picked **Fork B** (handoff to the standard editor, not loading TinyMCE assets
into the layout-free workbench). They **conflicted on storage**: Gemini said write the
assembled HTML back into `<Parent>+proposal` and update its provenance hash; Codex said that
**destroys the audit chain** — overwriting `+proposal` changes the original suggestion's hash,
so Phase 6 can no longer prove *what was reviewed*. **Resolved in Codex's favor** (the audit
chain is the point of WS6): store the assembled+polished output in a **separate**
`<Parent>+proposal+merge draft` card. This keeps every Gemini benefit — `+merge draft` is a
normal typed card, so the standard edit view gives it TinyMCE (RichText) or the Markdown
editor (Markdown) natively, with the same polymorphism, stale-base banner, and clean handoff.

**Resolved flow (the union of both reviews, Codex storage target):**
1. **Explicit** "Assemble & Polish" on the workbench (never automatic) → client assembles the
   merged HTML from the current selections (the proven assembler).
2. POST to a **non-destructive seed endpoint** on the proposal set that writes the assembled
   content to `<Parent>+proposal+merge draft` (creating/updating it; type mirrors the
   proposal's content type). **No write to `+proposal`; no write to the parent.** Requires
   write permission on the proposal.
3. Record audit/lock state for Phase 6 WITHOUT touching the original proposal provenance:
   write `+merge draft+provenance` (or a `+merge draft+audit`) with `assembled_hash`,
   `hunk_selections`, `parent_act_id` (parent's last act at workbench load), `base_hash`
   (from the proposal's provenance), `assembled_at`. The original `+proposal` content + its
   `+provenance` (original suggestion hash) stay **immutable**.
4. Redirect to `<Parent>+proposal+merge draft?view=edit` (full layout → native editor:
   TinyMCE for RichText, Markdown editor for Markdown). The reviewer polishes there.
5. **Stale-base banner** on that edit view (Gemini): if parent `last_act_id != base` stamp,
   warn that the parent drifted since authoring.
6. **Merge-context affordance** (Codex): the edit screen must visibly signal "you are
   polishing a MERGE DRAFT" (not an ad-hoc proposal edit) — e.g., a banner + back-to-workbench
   link.
7. **Re-merge** is an explicit "Reset draft & re-merge" that returns to the workbench and
   restarts from selections — never feeds the polished HTML back through diff3.

**Phase 6 then verifies three things (Codex):** original `+proposal` hash (reviewed suggestion
didn't drift before assembly) · `+merge draft` hash (polished output didn't drift before
apply) · parent/base optimistic locks (parent unchanged underneath the review).

## First-steps findings (read before building)

- The deck's WYSIWYG entry points are `decko.initTinyMCE(el_id)` (from the gem
  `card-mod-tinymce_editor`) + the global `decko.tinyMCEConfig`. The local
  `mod/hyperon_ui/assets/script/tinymce_fullscreen.js.coffee` wraps `initTinyMCE` to add the
  fullscreen plugin/toolbar. So the idiomatic way to get a TinyMCE instance is to render the
  textarea Decko expects and call `decko.initTinyMCE`.
- **Blocker:** those globals + the TinyMCE library are loaded by the **standard Decko layout's
  asset bundle.** Our workbench is served `&layout=none` (Phase 4 finding), whose bare page
  loads NONE of that JS (verified: the `layout=none` response is 8.6 KB with only our inline
  assets; the layout-wrapped response is 32 KB with the Decko/asset bundle). So on the
  layout-free workbench page, `decko` / `decko.initTinyMCE` / `decko.tinyMCEConfig` are
  **undefined** — we can't just call them from the current view.

## The fork to decide

| Option | How TinyMCE coexists with the layout-free workbench | Trade-off |
|---|---|---|
| **A — in-place, load assets into the bare page** | Include the deck's TinyMCE asset set (lib + `decko.tinyMCEConfig` + `initTinyMCE`, and the hyperon_ui fullscreen wrapper) in the `layout=none` workbench view, then upgrade the preview pane → one TinyMCE instance in place. Honors contract §6 ("the exact pane is upgraded in place"). | Must reproduce the deck's TinyMCE asset loading in a layout-free page (script/style tags, load order, version pinning). Heavier page. Risk of asset drift vs the gem. Best UX continuity (user never leaves the diff context). |
| **B — handoff to the standard editor** | "Assemble & Polish" assembles client-side, persists the merged draft to the proposal, then navigates to the proposal's **standard edit surface** (full layout, TinyMCE already present) seeded with the merged HTML. | Cleanest reuse (TinyMCE lives where it already works; no asset duplication). Loses the side-by-side diff context on the polish screen (acceptable — merge decisions are already made). A navigation, not an in-place upgrade — minor deviation from contract §6's "in place" wording. |
| **C — render workbench inside the layout only for polishing** | Drop `layout=none` (or switch to a layout that carries assets) when entering polish. | Hybrid/messy; reintroduces the card-513 chrome the ribbons were tuned without. Not recommended. |

**Recommendation:** **Option B** (handoff to the standard editor). It's the lowest-risk reuse
(Gemini's own "reuse decko.tinyMCEConfig" intent is satisfied natively), avoids duplicating /
drifting from the gem's asset bundle on a bare page, and keeps the workbench lightweight. The
"in place" wording in contract §6 is a nicety; the *substantive* §6 guarantees (one-way
handoff, no path back into diff/merge, nests survive) are fully preserved by a handoff. If
Lake prefers strict in-place continuity, Option A is viable but costs the asset-loading work
and ongoing version-pinning risk.

## Seed transport — RESOLVED (Codex + Gemini converged, 2026-06-24)

Both reviewers chose the **same** design (Gemini's "fetch POST + server-rendered CSRF" =
Codex's "custom server-side seed endpoint"); Codex added the integrity rule below.

**Authenticated `fetch` POST from the layout-free workbench to a server-side seed endpoint:**
1. Workbench renders `<meta name="csrf-token" content="<form_authenticity_token>">` and the
   parent's load-time `act_id` (data attribute). "Assemble & Polish" is explicit + gated on
   conflicts resolved (same as Assemble).
2. On click, JS POSTs `{ hunk_selections, parent_act_id }` (+ `X-CSRF-Token` header;
   same-origin cookies carry the session) — **NOT** the assembled HTML.
3. **Server re-derives the content (Codex integrity rule):** re-resolve base/current/proposal,
   re-run `BlockMerge.merge` + `assemble(selections)` server-side (client≡server already
   proven) → that is the authoritative `+merge draft` content. The client's HTML is never
   trusted as the artifact.
4. **parent_act_id drift gate (both):** if the parent's current act != submitted
   `parent_act_id`, **reject** and tell the user to reload — the audit must prove what parent
   state the reviewer assembled against. Captured at load, carried into `+audit`, and
   **re-checked again at Phase 6 apply** (not only at apply).
5. Write `+merge draft` + `+merge draft+audit` **transactionally**; **idempotent** — the draft
   name is deterministic (`<Parent>+proposal+merge draft`), so re-seeding updates/reuses the
   same card, never duplicates.
6. Respond with the redirect URL; client navigates to `<Parent>+proposal+merge draft?view=edit`
   (native layout → TinyMCE/Markdown editor). No parent writes.

**Implementation shape:** the server side is a `prepare_to_validate` event on the `merge_draft`
set that re-derives `self.content` from `Env.params[:hunk_selections]` (+ the drift gate),
plus the existing `+audit` finalize event — so the write goes through Decko's CardController
(native auth + CSRF + transaction). The client POSTs a create/update of the merge draft card.

## Constraints (reviewer-locked, apply to whichever option)

- **One-way handoff (Codex + Gemini):** assembled HTML → TinyMCE; from then on TinyMCE owns
  the canonical document. NO two-way binding back to hunk selections. Re-merging requires an
  explicit **"Reset draft & re-merge"** that destroys the TinyMCE instance, restores the
  selection UI, and restarts from the diff — never merges TinyMCE's HTML back through diff3.
- **No calls back into diff/merge** from the polish layer (Codex). A reviewer can verify by
  checking the Phase 5 code never calls `BlockMerge.*` or touches `nests`.
- **Nest survival (Gemini):** prove `{{nest}}` inclusions survive the TinyMCE round-trip via
  `valid_elements` / `extended_valid_elements` (inherit `decko.tinyMCEConfig`); fail closed
  (keep raw nest text) if not. Test before relying on it.
- **Optimistic-lock anchors (Gemini):** the polish form carries hidden inputs `parent_act_id`
  (parent's last act at workbench load) + `base_hash` (from provenance) — the exact payload
  Phase 6's transaction will check. Phase 5 only *plants* them; Phase 6 *enforces* them.
- **No parent writes until Phase 6.** Phase 5 may persist the *merged draft to the proposal*
  (so polish has somewhere to live) but must NOT write the parent. The blunt
  `ai_draft.rb` overwrite stays live until Phase 6 retires it.
- **Markdown parents:** route to the existing Markdown edit surface (gated on
  `card.type_name`), not TinyMCE — the assembled `:markdown` output is already plain Markdown.

## Exit

The human can hand-tweak the assembled merge in the familiar editor; nests survive; the
optimistic-lock anchors are in place for Phase 6; no parent has been written; re-merge is an
explicit, clean reset.
