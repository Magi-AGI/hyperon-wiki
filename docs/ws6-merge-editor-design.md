# WS6 — 3-Way Merge Editor for AI Drafts: Design Document

**Status:** Draft for Lake's sign-off · **Mod:** `editorial_review` · **Wiki:** wiki.hyperon.dev (Decko 0.20 / Rails 7)
**Reviewers:** Codex, Gemini (advisory, proposal-only). Both confirmed the architecture below.
**Governance anchor:** 2026-06-16 Lake↔Khellar call — *"once an article is published, it's not touched by AI except through a process that still requires a human to approve the changes."* WS6 **is** that human-approval gate.

---

## 1. Problem & Goal

Historically, AI suggestions were stored as `<Parent>+AI` (cardtype Draft, tagged `ai_generated`). The current "merge" (`event :merge_ai_draft`, `set/right/ai_draft.rb:19`) does a **blunt overwrite**: `parent.content = ai_draft.content; parent.save!` — discarding any human edits made to the parent since the draft was authored.

**Convention change (see §3.5):** WS6 does **not** overload `+AI`. `+AI` remains the catch-all for *any* AI-generated content (notes, summaries, ad-hoc suggestions). WS6 introduces a dedicated, author-neutral **`<Parent>+proposal`** convention — a structured, reviewable replacement for the parent's content — as the merge workbench's trigger. This is the wiki's "pull request": usable by AI *and* human editors.

**Goal:** a real **3-way merge** — `base` (parent revision the AI draft was authored against) × `AI` (`+AI` content) × `current` (live human-edited parent) — in a `git mergetool`-style UI where an editor accepts/rejects hunks and produces the merged parent content, applied **only** via explicit human approval. Content is mixed HTML/RichText (with `{{nest}}` inclusions) and Markdown, so diffing must be structure-aware, not plain-text line-based.

---

## 2. Current state (what we replace)

| Element | Location | Fate |
|---|---|---|
| `view :ai_draft_link` ("Merge AI Draft → Parent" button) | `set/all/ai_draft_aware.rb:23` | Repoint to merge workbench |
| `view :merge_button` ("Merge into Parent" button) | `set/right/ai_draft.rb:34` | Repoint / deprecate |
| `event :merge_ai_draft` (blunt overwrite) | `set/right/ai_draft.rb:19` | Replace with verifying merge-apply event |
| `event :tag_parent_needs_review` | `set/right/ai_draft.rb:4` | Keep (pattern template for base-stamp event) |
| Approval stamping (`+approved by/at`) | `set/all/editorial_events.rb`, `set/right/ai_draft.rb:27` | Keep; merge-apply continues to stamp |

Revision history is fully available via Decko `Card::Action`/`Card::Act`; reuse the snapshot reconstruction already implemented in `mod/mcp_api/.../cards_controller.rb#build_snapshot_at_action` (line 1243) to fetch `base`.

---

## 3. Architecture: compose with TinyMCE, don't extend it

WS6 is **not** a TinyMCE plugin. The installed editor is `card-mod-tinymce_editor` 0.20.0 (deck already customizes it via `decko.initTinyMCE` in `mod/hyperon_ui/assets/script/tinymce_fullscreen.js.coffee`). TinyMCE's own track-changes/revision-history are paid Tiny Cloud plugins — not available. So the 3-way logic, hunk state, conflict handling, and provenance live **outside** TinyMCE; TinyMCE is reused **only** as the final editable merged-output pane.

```
 SERVER (Ruby — where the data lives)          CLIENT (browser)
 ┌───────────────────────────────┐            ┌────────────────────────────────────┐
 │ fetch base / AI / current     │            │ Phase 1: Reconciliation            │
 │ block-level 3-way diff        │  hunks →   │  read-only hunk list, accept/reject │
 │ (Nokogiri + diff-lcs)         │            │  (TinyMCE NOT loaded)               │
 │ emit structured hunk list     │            │        │ "Assemble Merge Draft"      │
 └───────────────────────────────┘            │        ▼                             │
 ┌───────────────────────────────┐            │ Phase 2: Polish                     │
 │ merge-apply (thin + verifying)│  ← final   │  assemble merged HTML, load ONE     │
 │ perms, optimistic lock, hash, │    HTML     │  TinyMCE instance, hand-tweak       │
 │ transaction, audit, archive   │            │        │ "Approve & Apply"           │
 └───────────────────────────────┘            └────────────────────────────────────┘
```

**Why two phases (Gemini):** programmatically calling `editor.setContent()` on every toggle resets TinyMCE's undo stack, jumps the cursor/scroll, and lags on large articles. So the diff/hunk UI is plain read-only HTML; TinyMCE is instantiated **once**, after reconciliation, with the assembled result.

**Server/client split:** server **computes** the diff (data-local, trustworthy); client **selects + assembles + polishes**. The backend is thin but **not** "dumb" (Codex) — it never trusts client hunk state; it accepts the final HTML as a normal human-authored edit *only after* verifying the integrity checks in §7.

---

## 3.5 Subcard convention — `<Parent>+proposal`

`+AI` was historically a catch-all for AI-generated content; overloading it would make the workbench fire on generic notes. WS6 defines a dedicated, **author-neutral** convention instead (works for AI bots *and* human peer-reviewed drafts — the wiki's "pull request"). `+AI` is left untouched.

| Card | Type | Role |
|---|---|---|
| `<Parent>+proposal` | **mirrors the parent's content format** (RichText for HTML parents, Markdown for Markdown parents) — see below | Proposed replacement content — the "suggestion" leg of the 3-way merge |
| `<Parent>+proposal+base` | Number | Base stamp: parent `act_id` the proposal was authored against (§4) |
| `<Parent>+proposal+provenance` | (json/basic) | Authoring-time provenance: parent id/name, base + proposal content hashes, actor/source, timestamp, override reason (§4.1) |
| `<Parent>+proposal+merge audit` | (basic) | Merge-time provenance written on apply (§7); clearly named, not ambiguous whitespace |

**Mechanism — right-set, not a new cardtype (v1).** The canonical trigger is the **`set/right/proposal.rb`** right-set, so *any* `X+proposal` card participates regardless of its cardtype. **Decisive reason:** proposal content must be diffed/rendered/edited in the *parent's own format*; a single `Proposal` cardtype would force one format and break Markdown parents. The right-set lets each proposal independently mirror its parent's type while sharing all workbench behavior (views, state-transition events, `+base` validation, permissions). On proposal creation, an event sets the proposal's `type_id = parent.type_id` (or the parent's content format) so formats stay aligned. *A dedicated `Proposal` cardtype is deferred to **v2**, considered only if/when WS6 is packaged as a standalone mod.*

**Activation rules (Codex):**
- **Automatic** workbench activation requires **both** the `+proposal` name **and** a valid proposal shape (content present; base resolvable per §4).
- **Legacy/ad-hoc bridge — no silent promotion.** An "Open as proposal" affordance can run a stray `+AI` (or any candidate) through the workbench on demand, but the session is created/treated as **explicitly unstamped** and **visibly lower-confidence** (Tier 2/3, §4.2). Generic `+AI` notes are never auto-promoted into merge proposals.

---

## 4. The three inputs & base-source resolution

### 4.1 Base stamp (new proposals) — server-enforced
New event on the `proposal` right-set (mirrors `tag_parent_needs_review`):

```ruby
# set/right/proposal.rb (the +proposal set)
event :stamp_proposal_base, :integrate, on: :create do
  parent = left
  return unless parent
  base_name = "#{name}+base"
  return if Card.fetch(base_name)&.content.present?   # explicit override wins; idempotent
  Card::Auth.as_bot do
    Card.create!(name: base_name, type_id: Card::NumberID,
                 content: parent.last_act_id.to_s)     # read-time proxy = creation-time parent act
  end
end
```

- **Read-time proxy:** the parent revision current when the proposal is created — i.e. **authoring/read time, never merge-open time** (Codex). Monotonic — later human edits to the parent register as `current ≠ base`.
- **Override (restricted + audited, Codex):** a generator that knows its true read-time `act_id` may write `<Parent>+proposal+base` itself before/at creation; the event is then a no-op (guards on existing content). The override path is **permission-restricted, logged, and requires a recorded `reason`** — it must not be a silent free-write of arbitrary base values (also closes the "spoof another card's history" hole).
- **No upstream changes required:** the floor is enforced where content is written (MCP API + scripts + hand-creation all pass through card create), which is stronger governance than per-generator stamping.
- A companion `on: :create` event aligns the proposal's `type_id` to the parent's content format (§3.5).

**Metadata schema (rich enough to reconstruct *and* verify, Codex):**

| Card | Type | Stamped | Contents |
|---|---|---|---|
| `<Parent>+proposal+base` | Number | authoring time | parent `act_id` the proposal was authored against (primary key for snapshot reconstruction) |
| `<Parent>+proposal+provenance` | (json/basic) | authoring time | parent card id + name, parent revision/action/act identifier, **base content hash**, **proposal content hash**, actor/source, timestamp, `override_reason` (if overridden) |

`<Parent>+proposal+merge audit` (added on apply, §7) records the merge-time counterpart. The two together prove the chain: *what base was claimed at authoring* → *what was applied at merge* → *by whom*.

### 4.2 Three-Tier Confidence (Gemini) — covers legacy / ambiguous

| Tier | Trigger | Behavior |
|---|---|---|
| **1 — Verified** | `<Parent>+proposal+base` present & valid | Full 3-way merge, no warning |
| **2 — Estimated** | No stamp; parent has a single unambiguous revision at/before proposal `created_at` | 3-way merge **+ yellow caveat banner** + one-click "switch to safe 2-way (Proposal vs Parent)" |
| **3 — Unreliable** | No stamp; multiple parent revisions in a tight window around proposal creation, or history pruned | **Refuse 3-way**; fall back to 2-way (Current Parent vs Proposal) with prominent notice |

Inference (Tier 2/3) queries `Card::Action` for the parent; degrade to Tier 3 on any ambiguity. **Never present an inferred 3-way as authoritative** (Codex). The legacy "Open as proposal" bridge (§3.5) always enters at Tier 2/3 (unstamped).

---

## 5. Diff engine — block-level 3-way over structural blocks

1. **Fetch** `base`, `ai`, `current` content strings (per §4).
2. **Protect nests first (Codex+Gemini):** before any HTML parse/normalize, replace every `/\{\{[^}]+\}\}/` occurrence with an opaque placeholder token (e.g. `\x00NEST_0\x00`); restore after assembly. Nokogiri/reverse_markdown must never rewrite inside `{{…}}`, and visual `<ins>/<del>` must never split a `{{…}}` boundary.
3. **Tokenize into blocks:**
   - HTML: Nokogiri → ordered list of top-level block nodes (`p, h1–h6, ul, ol, li, blockquote, table, pre, figure, …`); each block = its serialized outerHTML string. Tables/lists/`pre`/media treated as atomic units.
   - Markdown: split on blank lines into paragraph blocks.
4. **3-way block merge:** diff3 over the three block-token arrays (LCS primitive = `diff-lcs`, already present). Classify each hunk: *AI-only*, *human-only*, *both-same* (no-op), *both-different* (**conflict**).
5. **Within-block display diff:** for a changed block, a secondary word/char-level diff rendered with `<ins>/<del>` — **display only**, respecting nest placeholders. The merge unit accepted/rejected is always the **whole block** (or an explicit manual edit in Phase 2), never a synthesized partial-HTML block (Codex).
6. **Defaults are safe:** non-conflict hunks default to *current/base-safe*; AI changes are **never** auto-accepted. Editor opts in per hunk or via an explicit bulk action.

---

## 6. UI surface — dedicated full-width view, layout-free (bypass card 513)

Custom Decko view in the `editorial_review` mod, `view :merge_workbench` on the `proposal` right-set, reached at `<Parent>+proposal?view=merge_workbench`. Rendered in a minimal/layout-free shell so it does **not** depend on or modify layout card **513** (owned by the Left Sidebar Layout workstream — do not touch). The right-column tool (card 17242) may expose status (conflict count, tier badge) and a **launch button**, but the actual editor is full-width.

- **Phase 1 (Reconciliation):** 3-way block view (Base · Current · AI), per-hunk accept/reject, conflict count, tier banner. TinyMCE not loaded.
- **Phase 2 (Polish):** "Assemble Merge Draft" → compile selected blocks (+restore nests) → init one standard TinyMCE instance → hand-tweak → "Approve & Apply."

**Embedded JS gotcha (CLAUDE.md):** MCP find_and_replace/append collapses a literal backslash — use `String.fromCharCode(92)` for any `\` in injected JS; `node --check` embedded scripts. CSS cards are SASS-compiled — use literal values, not `hsl(var(--x))`.

---

## 7. Save path — thin but verifying backend contract

On "Approve & Apply", client POSTs the **final assembled HTML** (not hunk decisions) + the `parent_act_id` captured when the workbench was opened. The merge-apply event/controller MUST, inside a single transaction:

1. **Permission:** assert `parent.ok?(:update)` under the current session — **not** the draft's permissions (prevents escalation: write access to `+AI` must not grant write to a restricted parent). (Codex+Gemini Risk 3.)
2. **Optimistic lock:** reload parent; if `parent.last_act_id != params[:parent_act_id]` → reject with "parent changed while merging, please reload." (Gemini Risk 2 / Codex.)
3. **Integrity (hash match, Codex):** verify the **parent**, **proposal**, and **base** content hashes still match the session that produced this merge (against `<Parent>+proposal+provenance`). If the proposal or base shifted under the editor, reject — permissions and locking live in the **save path**, not just the UI.
4. **Write** parent content (the human-authored final HTML).
5. **Idempotent / transactional:** double-submit must not reapply or corrupt; wrap in `card.transaction`.
6. **Audit metadata (persist provenance):** base revision act_id, parent pre-merge act_id, AI draft revision/hash, resulting parent act_id, actor, timestamp — proving *explicit human approval*, not silent AI overwrite. Continue stamping `+approved by/at`.

---

## 8. Draft lifecycle — archive, don't delete (Gemini Risk 4)

On successful merge: **do not delete** `<Parent>+proposal` (breaks audit/history). Instead transition state: add `merged` tag (and drop `ai_generated` if present — proposals may be human-authored), write `<Parent>+proposal+merge audit` with the merge provenance (§7). This marks it inactive/archived and prevents re-merge confusion / re-processing by later AI runs.

---

## 9. Markdown cards

Markdown-type cards: tokenize by blank-line paragraphs (no Nokogiri); same diff3 + nest protection. Phase 2 editor for Markdown cards uses the existing Markdown edit surface (not TinyMCE) — gate the editor choice on `card.type_name`.

---

## 10. Testing matrix

Insert · delete · both-same change · real conflict · nested lists · tables · inline tags (`<strong>/<a>`) · `{{nest}}` preservation (incl. nest inside a changed block) · Markdown cards · parent rename between author & merge · stale parent revision (optimistic-lock reject) · duplicate submit (idempotency) · permission escalation attempt (draft-writer w/o parent write) · Tier 1/2/3 base resolution · legacy unstamped draft · empty AI draft. RSpec (`decko-rspec` present).

---

## 11. File inventory / PR scaffold

- `mod/editorial_review/set/right/proposal.rb` (**new**) — `stamp_proposal_base` + type-align events; verifying merge-apply event; `view :merge_workbench` + Phase 1/2 markup; archive-on-merge lifecycle.
- `mod/editorial_review/set/right/ai_draft.rb` — retire `merge_ai_draft` blunt overwrite; repoint/retire `merge_button` (legacy `+AI` path → "Open as proposal" bridge).
- `mod/editorial_review/lib/` — `BlockMerge` (nest-protect, tokenize, diff3, classify) + `BaseResolver` (tier logic).
- `mod/editorial_review/set/all/ai_draft_aware.rb` — repoint `ai_draft_link`; surface `+proposal` workbench launch.
- `mod/<mod>/assets/script/` — Phase 1 hunk-toggle + Phase 2 assemble/TinyMCE-init JS.
- `spec/` — engine + controller/event specs per §10.
- Branch `feature/ws6-merge-editor` off `main`; PR (no direct commits to `main`). Prod deploy per server guide only after merge.

---

## 12. Decision log & open questions

**Settled (reviewer-confirmed):** TinyMCE composition (reuse for final pane, not a plugin) · two-phase UI (reconcile → polish) · block-level diff w/ nest protection · dedicated layout-free view (bypass card 513) · verifying-not-dumb backend (perms, optimistic lock, hash, transaction, idempotency, audit) · archive-don't-delete lifecycle · three-tier base confidence · **tag word `+proposal`** (unanimous).

**Recommended, pending Lake's confirm:**
1. **Proposal shape** — right-set `set/right/proposal.rb` with per-card type mirroring the parent's format (Codex), deferring a dedicated `Proposal` cardtype to v2 (vs Gemini's cardtype-now). *Implementer's lean: right-set v1, for content-format polymorphism.*
2. **Generator stamp** — server-enforced `stamp_proposal_base` event (read-time proxy + override) over per-generator stamping. *(Recommended.)*
3. **Where to commit** — create `feature/ws6-merge-editor` off `main` in `E:\GitHub\Magi-AGI\hyperon-wiki` and land this doc under `docs/` there? (Repo is currently on `feature/page-attribution-render`; confirm before I touch its working tree.)

**Next deliverable:** implementation plan (sequenced, testable increments) — after the above are confirmed.
