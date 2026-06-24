# WS6 Phase 4 — Merge Workbench UI Contract

**Status:** RATIFIED by Codex + Gemini (2026-06-24). Open Q #1 → client-side preview
assembler (non-authoritative; Phase 6 verifies server-side). Open Q #5 → thin cut first
(3 panes + synced scroll + static connectors); animated Bézier ribbons deferred to a
polish pass (Phase 4.1 vs Phase 8 — Lake to time). Implementation cleared to begin.
**Companion to:** `ws6-merge-editor-design.md` (spec), `ws6-merge-editor-impl-plan.md` (Phase 4).
**Scope of Phase 4:** a **read-only** reconciliation surface. It renders hunks, lets the
editor toggle per-hunk selections, and previews the assembled draft **client-side**. It
does **not** write the parent, does **not** load TinyMCE, and does **not** retire the
blunt `merge_ai_draft` overwrite. Those are Phases 5–6. This document is the frozen
interface those phases build on; the goal is to agree the contract so the later code can't
quietly change merge semantics.

Per Codex's instruction this contract is six things: **(1) route/view name, (2) initial
read-only state, (3) hunk JSON payload shape, (4) selection defaults, (5) stale-base
warning behavior, (6) how TinyMCE arrives in Phase 5 without changing merge semantics.**

---

## 0. Design invariants carried in from Phases 1–3 (must not regress)

- **Human-explicit defaults.** AI changes are NEVER auto-accepted. `BlockMerge.default_side`
  already encodes this: `both_same | ai_only | human_only → :current`, `conflict → nil`.
  The UI *displays* these defaults; it does not compute its own.
- **Conflicts must be chosen.** `assemble` raises on an unresolved conflict. The UI must
  block "Assemble" until every conflict hunk has a selection (it must never pass
  `allow_unresolved: true`).
- **Server owns the diff math; client owns only the preview concatenation.** The browser
  NEVER re-implements diff3, block tokenization, classification, or nest detection — all of
  that is the Ruby `BlockMerge.merge` result, serialized once into the frozen payload (§3).
  The client-side preview assembler (Open Q #1, ratified by both reviewers) does only the
  trivial, deterministic step `assemble` does: walk `hunks[]` in order, concat the selected
  side's already-restored raw blocks, join by the format joiner, done. Because nests arrive
  pre-restored and blocks pre-tokenized, the client assembler is pure selection→concatenation
  with no merge logic to drift. **It is preview-only and non-authoritative.** Phase 6
  re-assembles server-side via `BlockMerge.assemble` and verifies parent/proposal/base hashes
  + `parent.ok?(:update)` before any write — the client preview never gates a write.
- **Stale base = hard stop.** `BaseResolver` withholds `base_content` for `:stale`. The
  workbench must refuse to offer a 3-way merge for a stale base and fall back to 2-way (or
  block, see §5). It never fabricates a base.

---

## 1. Route / view name

A **layout-free** HTML view on the `proposal` right-set (bypasses the standard card
513/layout chrome so the workbench is a clean full-width surface):

| Concern | Decision |
|---|---|
| Set | `Right::Proposal` (`set/right/proposal.rb`, the file that already exists) |
| Primary view | `view :merge_workbench` |
| Format | `format :html` |
| URL | `/<Parent>+proposal?view=merge_workbench` (Decko's standard `?view=` param; no new route/controller in Phase 4) |
| Layout | layout-free shell — the view explicitly opts out of the standard layout (`layout: false` / minimal viewport container), no card-513 nest; matches how other custom full-surface views render in this deck (Gemini #1) |
| Data API | **none yet.** Phase 4 server-renders the full hunk payload into the initial HTML (and a `<script type="application/json">` island). A JSON endpoint for re-assembly is introduced in §6 as an *optional* enhancement; the default is a server round-trip via the existing card update/`view` path with `selections` in params. |

**Why a named view, not a new controller:** Decko routes `?view=` to the set's format view
for free, inherits auth (`card.ok?(:read)`), and keeps Phase 4 inside the set file we
already load. A bespoke controller/route is deferred unless §6's live re-assembly needs it.

**Auth:** the view renders only if `card.ok?(:read)` on the proposal AND `parent` resolves.
The "this will eventually write the parent" capability is a Phase 6 concern; Phase 4 shows
the workbench to any reader but renders the (disabled) apply affordance per
`parent.ok?(:update)` so the eventual gate is visible from day one.

---

## 2. Initial read-only state

On load the view computes, server-side, in this order:

1. `res = BaseResolver.resolve(card)` → tier/mode/base_content/warning.
2. `current = parent.db_content`, `proposal = card.db_content`,
   `format = card.type_name == "Markdown" ? :markdown : :html`.
3. If `res[:mode] == :three_way` and `res[:base_content]`:
   `merge = BlockMerge.merge(base: res[:base_content], current:, proposal:, format:)`.
   Else (2-way / stale / unreliable): `merge = BlockMerge.merge(base: current, current:,
   proposal:, format:)` — i.e. a degenerate 3-way with base==current, which makes every
   proposal change surface as `:ai_only` or `:conflict` and nothing as `:human_only`. This
   is the documented 2-way fallback and reuses the same engine and the same payload shape.

### Target layout — p4merge-style columnar diff (preferred)

Lake's stated preference is the **P4Merge** comparison layout, and that is the Phase 4
target (not a stacked hunk-card list): **side-by-side panes** with **synchronized scrolling**,
each changed region drawn as a **resizable, color-highlighted band**, and the gutters between
panes filled with **animated Bézier connector ribbons** that flex to join a band in one pane
to its counterpart in the next even when the two blocks differ in height. Selecting a side for
a hunk visibly routes its ribbon toward the chosen pane.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ [tier banner]  Merge proposal into <Parent>        3-way (verified)           │  ← §5
│ N conflicts · M AI hunks · K human hunks      [Accept all AI] [Switch 2-way]  │
├──────────────┬──────────────────────┬──────────────────────┬──────────────────┤
│   BASE       )   CURRENT (human)     (   PROPOSAL (AI)       │   selection      │
│ (read-only)  )                       (                      │                  │
│              )                       (                      │                  │
│  <p>A</p>    ═════ <p>A</p> ══════════════ <p>A</p>         │  stable          │
│              )                       (                      │                  │
│ ░h3 old░ ────╮  ▓h3 human▓        ╭── ▓h3 ai▓               │  ( )cur (•)prop  │  ← conflict
│              ╰─ bezier ──╮      ╭──╯ (ribbons animate to    │  ⚠ choose        │
│              )          ╰──────╯     fit differing heights) │                  │
│              )                  ╭── ▒h5 NEW▒  (insert)      │  [ ] accept AI   │  ← ai_only
│              )            ──────╯                           │                  │
│  ▸ 4 unchanged blocks (collapsed, scroll-synced placeholder)│                  │
├──────────────┴──────────────────────┴──────────────────────┴──────────────────┤
│ [ Assemble Merge Draft ]   ▸ preview pane (empty until clicked) — read-only    │
│ [ Apply to parent ]  ← DISABLED in Phase 4 (tooltip: "available in Phase 6")   │
└────────────────────────────────────────────────────────────────────────────────┘
```

- **Columns:** 3 panes in 3-way mode (Base · Current · Proposal); the Base pane is dropped in
  2-way mode (§5), collapsing to 2 panes + 1 gutter. A 4th narrow rail on the right carries
  per-hunk selection controls aligned to each band's vertical center (so the control sits next
  to its ribbon).
- **Bands:** each non-stable hunk renders as a highlighted band in each pane it touches
  (insert → band only in Proposal; delete → band only in Base/Current; conflict → bands in all
  three). Band color encodes type (conflict = red, ai_only = blue/green add-or-remove,
  human_only = neutral). Bands are **vertically resizable** by the user; ribbons re-fit.
- **Bézier ribbons:** SVG paths in each gutter connect a band's top/bottom edge in the left
  pane to its counterpart edge in the right pane; they animate (CSS/`requestAnimationFrame`)
  when a band is resized, when a side is selected, or on synced scroll, so mismatched block
  heights are visually reconciled — the P4Merge signature.
- **Synchronized scroll:** scrolling any pane scrolls the others to keep counterpart bands
  aligned; ribbons recompute on scroll.
- **Stable runs** collapse to a single scroll-synced placeholder ("▸ 4 unchanged blocks") in
  all panes so counterpart bands stay aligned without rendering unchanged bodies.

This is a presentation layer over the **exact same** §3 payload and §4 selection model — the
ribbons/bands are a rendering of `hunks[]` and their `type`/`default`; nothing about the merge
math changes. (Build-cost note in Open Questions #5: the animated SVG ribbon layer is the
single biggest net-new piece of Phase 4 and may warrant a thin first cut — static connector
lines — before the animated Bézier polish, if we want to de-risk the engine wiring first.)

Read-only guarantees in Phase 4:
- No parent write path is reachable. "Apply to parent" is rendered **disabled** and labeled
  **"Simulation Mode — apply lands in Phase 6"** (Gemini #2), so the eventual location and
  labeling are reviewable now while it is wired to nothing.
- "Assemble Merge Draft" produces a **preview only** (server-assembled HTML/MD shown in a
  read-only pane). It does not persist anything — not even the proposal.
- Stable blocks are collapsed by default to keep large articles legible (risk register:
  "Large articles → lazy-render hunk bodies").

---

## 3. Hunk JSON payload shape

The server serializes the merge into a single JSON island the client reads. This is the
**frozen wire contract** — Phases 5–6 may add fields but must not repurpose these.

```jsonc
{
  "schemaVersion": 1,
  "proposal": "Glossary+Atom+proposal",
  "parent": "Glossary+Atom",
  "format": "html",                  // "html" | "markdown" — from BlockMerge result
  "mode": "three_way",               // "three_way" | "two_way"
  "tier": "verified",                // verified | estimated | stale | unreliable
  "warning": null,                   // string | null  (from BaseResolver.resolve)
  "baseHashOk": true,                // bool | null
  "counts": { "conflict": 1, "ai_only": 2, "human_only": 1, "both_same": 0, "stable": 4 },
  "hunks": [
    {
      "id": "h3",                    // BlockMerge chunk id; stable runs use id:null → omitted/aggregated
      "type": "conflict",            // stable | ai_only | human_only | both_same | conflict
      "base":     ["<p>old</p>"],    // raw block strings, nests already RESTORED for display
      "current":  ["<p>human</p>"],
      "proposal": ["<p>ai</p>"],
      "default":  null,              // "current" | "proposal" | "base" | null(conflict→must choose)
      "display": {                   // OPTIONAL, display-only; never fed back to assemble
        "currentVsProposal": "…<del>human</del><ins>ai</ins>…"  // BlockMerge.word_diff, nests restored
      }
    }
    // stable blocks are emitted as a single collapsed entry:
    // { "id": null, "type": "stable", "count": 4 }   // bodies fetched lazily if expanded
  ],
  "selectionDefaults": { "h5": "current", "h6": "current" }  // BlockMerge default_selection, conflicts ABSENT
}
```

**Field provenance (so review can audit there's no new merge logic in the view):**
- `hunks[].{id,type,base,current,proposal}` come verbatim from `BlockMerge.merge(...)[:chunks]`.
- `selectionDefaults` is `merge[:default_selection]` — conflicts are deliberately absent
  (no key) so the client can detect "must choose" as `id ∈ hunks where type==conflict and
  id ∉ selectionDefaults`.
- `display.currentVsProposal` is `BlockMerge.word_diff(current, proposal)` run server-side
  with nests restored; it is **advisory rendering only** and is never sent back to
  `assemble`. (Per the spec, `word_diff` is display-only and nest-atomic.)
- Nests: the payload shows **restored** `{{…}}` text (not sentinels). The sentinel/token map
  stays server-side inside the `merge` result; the client never sees or manipulates it.

**Round-trip contract (client → server):** to assemble, the client submits
`selections = { "h3": "proposal", "h5": "current", ... }` (only hunk ids; values in
`current|proposal|base`). The server merges them over `default_selection` and calls
`BlockMerge.assemble(merge, selections)`. The client cannot submit a selection for a stable
hunk (none have ids) and cannot bypass the unresolved-conflict guard (server calls
`assemble` WITHOUT `allow_unresolved`).

---

## 4. Selection defaults

Straight passthrough of Phase 3 semantics — the UI must not invent its own:

| Hunk type | Default shown | Toggle offered | Rationale |
|---|---|---|---|
| `stable` | n/a (no control) | none | unchanged; always emitted as `current` |
| `both_same` | `current` (≡ proposal) | none (informational) | both sides agree; nothing to decide |
| `human_only` | `current` | optional "revert to base" (advanced, default off) | human edit wins by default |
| `ai_only` | `current` (= reject) | **checkbox "accept AI change"** → flips to `proposal` | AI never auto-accepted |
| `conflict` | **none** (unselected) | **radio: keep current / take proposal** (and base as advanced) | must be chosen; blocks assemble |

UI rules:
- **Unresolved conflicts are impossible to miss (Codex).** Three redundant cues, not one:
  (a) "Assemble Merge Draft" AND the disabled "Apply" stay locked while any conflict is
  unresolved; (b) a persistent header count ("1 conflict unresolved") that links/scrolls to
  the next unresolved hunk; (c) each unresolved conflict hunk carries its own explicit
  "Unresolved — choose a side" state (red band + icon + label), distinct from a resolved
  conflict. Resolving the last conflict is what unlocks Assemble.
- **Hunk state never depends on animation or color alone (Codex).** Every hunk's
  type and selected side are conveyed in text + label/icon + keyboard-focusable control, so
  the workbench is fully usable with ribbons disabled, with color-vision differences, and via
  keyboard. Ribbons/bands are clarifying, never load-bearing for meaning.
- An "Accept all AI changes" bulk control MAY exist but starts unchecked and only affects
  `ai_only` hunks (never conflicts — those still require an explicit per-hunk choice).
- The selection state is the single source of truth the client serializes in §3's
  round-trip. No other UI state changes merge output.

---

## 5. Stale-base (and low-confidence) warning behavior

Driven entirely by `BaseResolver.resolve`'s `tier` + `warning`. Four tiers → four banners:

| Tier | mode | Banner | Behavior |
|---|---|---|---|
| `verified` | three_way | green: "Base verified (stamped, hash OK)." | full 3-way; normal workbench |
| `estimated` | three_way | yellow: "Base ESTIMATED from authoring time — switch to 2-way if blocks look misaligned." + **[Switch to 2-way]** button | 3-way, but one-click degrade to 2-way (re-renders with base==current) |
| `stale` | two_way | **red**: "Stamped base could not be verified (hash mismatch / action missing). 3-way is unsafe; showing 2-way (proposal vs current)." | base_content withheld; **forced 2-way**; 3-way controls not offered |
| `unreliable` | two_way | red: "Base could not be determined (ambiguous/pruned history). Showing 2-way." | forced 2-way |

Rules:
- The banner text is the resolver's `warning` string (verbatim), prefixed by a
  tier-appropriate headline — the UI does not author its own diagnostic.
- **Stale never offers a 3-way toggle.** Unlike `estimated` (which offers switch-to-2-way as
  a *convenience*), `stale` is already forced to 2-way and cannot be switched up.
- **Forced 2-way must be visually obvious, not banner-only (Codex + Gemini).** Dropping to
  2-way physically removes the Base pane (the layout reflows from 3 columns to 2), the header
  mode chip reads "2-way (no base)", and the diff is relabeled "proposal vs current" — so the
  absence of a base is structurally apparent at a glance, not just stated in the banner text.
- For `stale`, an info line surfaces the recorded vs reconstructed hashes (already in the
  resolver warning) so an admin can diagnose the drift — but there is no "force 3-way anyway"
  escape hatch in Phase 4 (deliberately; that would defeat the governance gate).

---

## 6. How TinyMCE arrives in Phase 5 WITHOUT changing merge semantics

The contract that protects merge integrity across the Phase 4→5 boundary:

- **Phase 4 is the merge boundary; Phase 5 is strictly downstream of it.** `BlockMerge.assemble`
  runs to completion and produces the merged string **before** TinyMCE exists in the page.
  TinyMCE is initialized in Phase 5 *only* on that already-assembled output, as a final
  free-form polish surface. It is never wired into hunk selection, diff3, or nest handling.
- **One-way handoff.** Selections → `assemble` → merged string → (Phase 5) TinyMCE initial
  content. There is no path back from TinyMCE into the hunk list. Re-toggling a hunk after
  polishing re-runs `assemble` and **replaces** the editor content (with a confirm if the
  editor is dirty) — it never tries to merge TinyMCE's HTML back through diff3.
- **Assembled preview pane is the seam.** In Phase 4 the "Assemble" output renders into a
  read-only preview pane. In Phase 5 that exact pane is upgraded in place to a single
  TinyMCE instance (`decko.initTinyMCE`, fullscreen config) seeded with the identical string.
  Same content in, same DOM slot — only editability is added. The JSON payload (§3),
  selection model (§4), and assemble round-trip (§3) are unchanged.
- **Nest survival is a Phase 5 gate, not a Phase 4 assumption.** Phase 4 keeps `{{nests}}` as
  literal restored text in a read-only pane (safe). Phase 5 must prove nests survive a
  TinyMCE round-trip (`valid_elements`/paste cleanup test) before relying on it, and fail
  closed (keep raw tokens) if not — per the risk register. Phase 4 takes no dependency on
  TinyMCE behavior.
- **Markdown parents:** Phase 4 previews Markdown as text; Phase 5 routes Markdown proposals
  to the existing Markdown edit surface (gated on `card.type_name`), not TinyMCE. The assemble
  output for `:markdown` format is already plain Markdown, so the seam is identical.

**Net:** everything that decides *what the merged bytes are* lives in Phases 1–4 (model +
engine + selection). Phase 5 only decides *how a human hand-tweaks those bytes afterward*.
A reviewer can verify this by checking that no Phase 5 code calls `BlockMerge.merge`,
`diff3`, or touches `nests` — it only consumes `assemble`'s return value.

---

## Open questions — RESOLVED by reviewers (Codex + Gemini, 2026-06-24)

1. **Re-assembly transport (§1/§3) — RESOLVED: client-side preview assembler.** Both reviewers
   chose client-side for instant toggle feedback (zero round-trips). **Binding caveat (Codex):**
   the client assembler MUST be deterministic from the frozen hunk payload + selection state —
   it is preview-only and non-authoritative. Phase 6 performs the authoritative server-side
   `assemble` + parent/proposal/base hash verification + `parent.ok?(:update)` before any write.
   Encoded in §0 (invariant #3) and §6. Drift risk is low because the client step is pure
   selection→concatenation over pre-tokenized, nest-restored blocks (no merge logic client-side).
2. **Layout-free shell mechanics:** confirm the right idiom in *this* deck for a layout-free
   set view (the "bypass card 513" note in the plan) — is there an existing custom view to
   mirror, or do we add a `layout: :none` render path?
3. **2-way visual:** drop the Base column entirely (current proposal §5) vs. show it greyed
   with a "not used" label? Recommendation: drop it — less misleading.
4. **Stable-run expansion:** lazy-fetch expanded stable block bodies via a follow-up request,
   or ship them in the payload collapsed-but-present? Recommendation: present-but-collapsed
   for v1 (simpler), switch to lazy only if payload size bites on large articles.
5. **P4Merge ribbon layer staging — RESOLVED: thin cut first.** Both reviewers chose a thin
   first cut for Phase 4: **3 panes (Base · Current · Proposal), synchronized scroll, hunk
   bands, selection rail, static connectors, disabled "Apply"** — proving the
   payload→defaults→conflict-blocking→stale-state wiring end to end BEFORE any animation.
   The animated **Bézier ribbons + resizable bands (Lake's signature P4Merge look) are
   deferred to a later polish pass.** Minor divergence on timing: Codex says "after the
   payload/defaults/conflict/stale behavior are proven" (could be a Phase 4.1 follow-up once
   the thin cut lands); Gemini says defer to the Phase 8 hardening pass (citing Decko asset-
   pipeline/SVG brittleness risk). Either way it does NOT block Phase 4 completion and the
   §3/§4 contract is identical. **Lake to pick the timing** of the ribbon polish (Phase 4.1
   vs Phase 8) — flagged because the ribbons are the specific look Lake asked for, so we want
   it scheduled, not dropped.
6. **Ribbon implementation surface (applies whenever #5's polish pass runs):** inline SVG
   `<path>` per gutter with cubic-Bézier `d` recomputed in JS on scroll/resize/select (no
   chart lib), CSS-literal styling (no `hsl(var())` per the plan's JS gotchas), hand-rolled
   vanilla-JS module in the mod's assets (no diff-view dependency). Animation stays
   **non-semantic** (Codex): hunk meaning is fully carried by text + label/icon + color +
   keyboard focus, so the tool is complete and usable with ribbons absent or disabled.
```
