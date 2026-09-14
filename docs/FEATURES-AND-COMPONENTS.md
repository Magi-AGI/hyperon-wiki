# Features and Components

A practical map of what the Hyperon Wiki is built from — base Decko features and
Hyperon-specific additions — for newcomers and SNET technical owners who need to know
what exists, who it's for, where it lives, and how current it is.

This is **not** a marketing page and **not** a deliverables/contract comparison. It is an
orientation map: read the status column before relying on anything here, and re-verify
against the running system where a row tells you to.

**Read first:** [`../ONBOARDING.md`](../ONBOARDING.md) (the front door) and
[`DOCUMENTATION-MAP.md`](DOCUMENTATION-MAP.md) (the full document index). This page
cross-links into both rather than repeating their content.

## Legend

| Status | Meaning |
|---|---|
| **shipped/current** | In production use, documented, and believed accurate. |
| **template** | A generic Decko/Rails procedure carried over with `<placeholder>` values, not yet rewritten for this wiki. |
| **aspirational/conceptual** | Explicitly marked by its own source as design sketch, not a working system. |
| **historical/archive** | Describes a completed or superseded phase. Kept for the record. |
| **planned/not yet written** | Identified as missing; no document exists yet. |
| *(to be confirmed)* | Not independently verified against the running production wiki as part of this pass. |

---

## Part 1 — Base Decko concepts relevant to SNET

These are generic [Decko](https://decko.org) features, not Hyperon-specific work. They
matter to SNET because Decko's own documentation is what this project builds on, and a
newcomer coming from a typical wiki or CMS background will not have these mental models
already.

### 1. Cards and "everything is a card"

- **What it is:** Decko's foundational model. Pages, users, images, files, layouts,
  searches, lists, rules, and permissions are all cards. Every card has a revision
  history, a name, and can be edited in place.
- **Who needs it:** everyone — it is the one concept the rest of the system assumes.
- **Where it lives:** this is Decko core behavior, not a mod. See `ONBOARDING.md` §3 for
  the Hyperon-specific cardtype list built on top of it.
- **Status:** shipped/current (base Decko).
- **Verify/next:** Decko's own [Concepts](https://decko.org/concepts) documentation.
- **Caveat:** none — this is the safest possible base to build a mental model on.

### 2. Compound names and fields

- **What it is:** `Parent+field` names express both hierarchy and per-card metadata.
  `John+image` is a subcard of `John`; a card's tags live at `<Card>+tag`, its authors at
  `<Card>+author`. Names can nest further (`John+image+discussion`).
- **Who needs it:** everyone; essential for reading a card name and knowing what it
  contains.
- **Where it lives:** base Decko naming convention, used throughout this repo's mods and
  the wiki's content.
- **Status:** shipped/current (base Decko).
- **Caveat:** compound-name folding has real gotchas (case-only renames are no-ops on
  shared keys, plural/singular folding can silently collide with an existing card) — see
  `docs/DOCUMENTATION-MAP.md` → Developer / architecture, and ask before renaming a
  compound card if you are unsure.

### 3. Cardtypes and structured content

- **What it is:** every card has exactly one type. Creating a `Cardtype` card defines a
  new type. `*structure`, `*default`, and `*guide` rule cards shape a type's editing form
  and default content.
- **Who needs it:** editors defining new content shapes; developers extending the schema.
- **Where it lives:** base Decko mechanism. This repository's cardtype **seed** file,
  `mod/editorial_review/data/real.yml`, declares exactly three cardtypes — `Draft`,
  `Published`, and `RawData` (codenames `draft`, `published`, `raw_data`). The other
  content-model types you will meet on the wiki — `IndexSection`, `IndexSubtopic`,
  `Contributor` — are **not** declared by that seed file; they are live wiki content
  referenced by mod code (for example `PUBLISHED_TYPE_NAMES` in
  `mod/editorial_review/set/all/editorial_events.rb` treats `IndexSubtopic` and
  `IndexSection` as publication types). Where those three are actually defined is
  *(to be confirmed)* — treat them as observed/used, not as repository-declared.
  See Part 2 below.
- **Status:** shipped/current (base Decko mechanism); the three seeded cardtypes are
  current. The three live-content types are in use but their declaring source is
  unverified in this pass.
- **Caveat:** `mod/editorial_review/data/real.yml` is **seed data**, not necessarily what
  production currently runs — see the seed-vs-production discrepancy documented in
  `ROLES-AND-PERMISSIONS.md` §4 before treating it as the live configuration. Do not read
  a type's absence from the seed as evidence it does not exist, or its presence as
  evidence production matches it.

### 4. Nests/includes and views

- **What it is:** `{{CardName|view:some_view}}` includes one card's rendered content
  inside another; the `view:` parameter controls how it renders (as a link, a list, a
  full page, etc.).
- **Who needs it:** editors building layouts and index pages; developers writing custom
  views.
- **Where it lives:** base Decko; this repo's custom views are defined across
  `mod/*/set/**/*.rb` (e.g. `mod/wiki_nav_tree/set/all/wiki_nav_tree.rb` defines
  `view :wiki_nav_tree`).
- **Status:** shipped/current (base Decko), with mod-specific views varying in status —
  see Part 2.
- **Caveat:** a known Decko quirk — `{{_main|viewA}}` and `{{_main|viewB}}` in one layout
  deduplicates; the second reference returns the cached first render. See `README.md` →
  Key Decko API Gotchas.

### 5. Sets, settings, and rules

- **What it is:** a "rule" is a card connecting a **Setting** (the behavior) to a **Set**
  (the cards it applies to — a cardtype, a specific card, "all cards"). A narrower rule
  overrides a broader default. Rules govern permissions, structured content, layouts,
  events, and help text alike.
- **Who needs it:** administrators and developers configuring or debugging behavior;
  editors indirectly, since rules shape what they see in an editing form.
- **Where it lives:** base Decko mechanism; this wiki's rules are partly seeded
  (`mod/editorial_review/data/real.yml`) and partly live database state.
- **Status:** shipped/current (base Decko).
- **Caveat:** because narrower rules win, a permission or layout surprise is often a rule
  on a more specific card than the one you're looking at — check the card's own rule
  cards before assuming a broad default applies.

### 6. Permissions and role rules

- **What it is:** the four CRUD rule types — `*create`, `*read`, `*update`, `*delete` —
  assignable per cardtype or per card, to users or to roles. Compound cards (`A+B`) can
  inherit permissions from `A`. File and image serving checks card permissions on every
  request; it is not security-through-obscurity.
- **Who needs it:** administrators granting access; developers reasoning about who can do
  what; SNET technical owners auditing the live matrix.
- **Where it lives:** base Decko mechanism, edited from the card menu's advanced/rules
  action. Hyperon-specific propagation behavior lives in `mod/permission_propagation/`.
- **Status:** shipped/current, **but the live matrix differs from the repository's seed
  data** — see the next item and `ROLES-AND-PERMISSIONS.md` §4 for the full table and the
  discrepancy.
- **Verify/next:** `ROLES-AND-PERMISSIONS.md` §4 (live permission matrix), re-read
  directly against the running wiki if a decision depends on it.
- **Caveat:** production's `Draft+*type+*read` was observed as `Anyone` (readable by
  guests), while the repository seed says `Anyone Signed In`. That was an intentional
  change at a stakeholder's (Ben's) request; Lake has said it can probably be reverted to
  `Anyone Signed In` on both production and local, but **that change has not been made**.
  Verify the live rule before relying on either state, and do not "fix" this
  discrepancy unilaterally.

### 7. Accounts and roles

- **What it is:** accounts are cards too — signup creates `<Name>`, `<Name>+*account`,
  `<Name>+*account+*email`, `<Name>+*account+*password`. Roles are granted from the
  target user's own card, not the administrator's.
- **Who needs it:** administrators onboarding new contributors.
- **Where it lives:** full detail in [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md)
  — this page deliberately does not duplicate it.
- **Status:** shipped/current.
- **Verify/next:** `ROLES-AND-PERMISSIONS.md` §1 and §3.

### 8. Comments/discussion

- **What it is:** base Decko supports commentable cards via `+discussion` subcards and a
  `comment_box` view, typically included with `{{+discussion|open}}`.
- **Who needs it:** editors/readers if enabled on a given card type.
- **Where it lives:** base Decko feature. This repository's `README.md` PROGRESS section
  lists "Comments via `card-mod-comment`" as **Phase 3, not yet checked off** — i.e. not
  confirmed wired into this wiki's UI as of this writing.
- **Status:** base Decko feature exists; **this wiki's current support/status is not
  verified** — treat as *(to be confirmed)* rather than assuming comments work end-to-end
  here. Do not overclaim this is live.
- **Verify/next:** check `README.md` → PROGRESS → Phase 3 checklist, and test
  `{{+*discussion|view:comment_box}}` directly on a card before relying on it.

### 9. History/revert/recent changes/watch/follow

- **What it is:** Decko versions every card edit and supports rollback. Base Decko also
  typically ships recent-changes and watch/follow features.
- **Who needs it:** editors auditing what changed; anyone recovering from a bad edit.
- **Where it lives:** base Decko mechanism (history/revert). `ROLES-AND-PERMISSIONS.md`
  §2 confirms history/rollback exists but explicitly defers a full walkthrough:
  "a feature-level walkthrough of history/rollback belongs in a later documentation
  pass."
- **Status:** history/revert — shipped/current (base Decko), confirmed used operationally
  (e.g. `get_card_history` in the MCP surface, Part 2 §6). Recent-changes and
  watch/follow — **not locally verified in this pass**; label as base Decko feature
  requiring live confirmation rather than assumed-present.
- **Verify/next:** check the wiki UI directly for a "Recent Changes" or watch/follow
  affordance before documenting it as available; do not infer from generic Decko docs.

### 10. Card dashboard / menu / advanced / rules UI

- **What it is:** every card has a menu (page, edit, advanced/rules, history, and similar
  actions depending on permissions). The advanced/rules view is where permission rules
  are edited (§6 above).
- **Who needs it:** administrators and editors, as their day-to-day entry point.
- **Where it lives:** base Decko UI, styled by `mod/hyperon_ui/`.
- **Status:** shipped/current (base Decko UI).
- **Caveat:** this document intentionally gives no screenshots — the card menu varies by
  permission and cardtype. Orient by trying it on a card you can already edit.

---

## Part 2 — Hyperon Wiki–specific features and components

### 1. Hyperon content model / cardtypes

- **What it is:** `Draft`, `Published`, `RawData`, `IndexSection`, `IndexSubtopic`,
  `Contributor`, plus Pointer-typed metadata fields (`+tag`, `+author`, `+contributor`,
  `+editor`).
- **Who needs it:** editors, reviewers, raw-data analysts, anyone reading or writing
  content.
- **Where it lives:** `ONBOARDING.md` §3 (the five-minute version). Provenance splits in
  two, and the split matters:
  - **Seed-declared in this repository:** `Draft`, `Published`, `RawData` — the three
    cardtypes in `mod/editorial_review/data/real.yml`, along with the `Expert` role, the
    right-set codenames (`proposal`, `merge draft`, `ai draft`, and the approval/authorship
    fields), the trust-marker tag vocabulary, and the `Review Queue` search card.
  - **Observed in the live content model, source to be confirmed:** `IndexSection`,
    `IndexSubtopic`, `Contributor`. Mod code references them as existing types — see
    `PUBLISHED_TYPE_NAMES` in `mod/editorial_review/set/all/editorial_events.rb` and the
    `+author` / `+contributor` / `+editor` rendering in
    `mod/editorial_review/set/all/ai_draft_aware.rb` — but no seed file in this repository
    declares them. Their defining configuration is *(to be confirmed)* against the running
    wiki.
- **Status:** shipped/current as a content model. Seed provenance is verified only for the
  three cardtypes above, and carries the seed-vs-production caveat noted in Part 1 §6.
- **Verify/next:** `ONBOARDING.md` §3; `ROLES-AND-PERMISSIONS.md` §4. To confirm the three
  unverified types, inspect the live cardtype cards on the wiki rather than searching this
  repository — absence here is not absence there.

### 2. Human-triggered ingestion workflows and scripts

- **What it is:** on-demand (not scheduled) scripts that bring source material —
  Mattermost chat archives, meeting transcripts (Fireflies/Otter/Read.ai), publications
  and books — into `RawData` cards. Two trust boundaries: export (operator's machine,
  source-service credentials) and ingest (`decko runner`, wiki database credentials).
- **Who needs it:** raw-data analysts and administrators running an ingestion pass;
  operators supplying credentials out-of-band.
- **Where it lives:** [`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md) (the full
  inventory, the two-stage model, safe first-run posture); scripts under `scripts/`.
- **Status:** shipped/current. As of the 2026-09-08 reconciliation recorded in that
  document, all 25 tracked ingestion-related scripts are git-tracked and present in this
  repository — no production-only script source was found, and the one real
  self-containment gap (a Mattermost exporter that used to live in a sibling checkout)
  has been closed.
- **Verify/next:** `INGESTION-WORKFLOWS.md` "Safe first-run posture" before ever running
  the ingest stage; `scripts/tests/` for the offline regression coverage.
- **Caveat:** ingestion writes to a live content database — treat any run as a
  production change. Source credentials, exported files, and RawData contents are never
  part of this repository handoff.

### 3. Synthesis/proposal/merge workbench

- **What it is:** the `<Card>+proposal` convention — an AI or human-authored change
  request against a published card, reviewed in a three-way merge workbench (base /
  current / proposal) and applied through a transactional gate.
- **Who needs it:** editors/reviewers (day-to-day use); developers touching the
  editorial workflow.
- **Where it lives:** `ONBOARDING.md` §4 (the narrative); the authoritative design detail
  is `docs/ws6-merge-editor-design.md`, with phase-specific docs
  (`ws6-merge-editor-phase4-ui-contract.md`, `-phase5-tinymce-gate.md`,
  `-phase6-apply-gate.md`, `-phase8-capability-gating.md`) in `docs/DOCUMENTATION-MAP.md`
  → Editor / reviewer.
- **Status:** shipped/current.
- **Verify/next:** `docs/ws6-merge-editor-design.md` before touching the editorial
  workflow's code.
- **Caveat:** the old direct-overwrite path is **gone from the checked-in code**, not
  merely deprecated. `mod/editorial_review/set/right/ai_draft.rb` records that the
  `merge_ai_draft` event and its merge button were both removed in WS6 Phase 6, so a
  direct `?merge_draft=true` post is no longer a usable bypass; the only authorized way to
  write a draft back into its parent is the verifying merge workbench and apply gate. What
  *does* remain mid-migration is legacy **content and conventions** — existing `+AI` cards
  authored under the old model, which are re-opened as proposals through the Phase 7
  bridge. Encountering both is a migration in progress, not a live overwrite path
  (`ONBOARDING.md` §4 "A note on `<Card>+AI`").

### 4. Review Queue and trust markers

- **What it is:** the Review Queue is a saved-search card (`Review Queue`, codename
  `review_queue`) listing Draft cards awaiting review — and, in live/newer
  configurations, possibly cards with an open unmerged proposal (confirm the current
  query on the wiki rather than assuming). Trust markers — `ai_generated`,
  `human_authored`, `transcript_derived`, `needs_review`, `ai_reviewed`,
  `human_approved`, `expert_approved` — render as pills and drive banners.
- **Who needs it:** editors/reviewers working the queue; readers deciding how much weight
  to give a card.
- **Where it lives:** `ONBOARDING.md` §3 (Review Queue) and §5 (trust markers);
  presentation behavior in `mod/review_queue_ui/README.md`; the tag/marker vocabulary is
  declared in `mod/editorial_review/data/real.yml`.
- **Status:** shipped/current. `mod/review_queue_ui`'s one documented behavior — opening a
  queue row in a new tab on click — is current and implemented in
  `assets/script/open_in_new_tab.js.coffee`.
- **Verify/next:** `mod/editorial_review/data/real.yml` for the exact tag codenames;
  `ONBOARDING.md` §5 for banner behavior.
- **Caveat:** `human_approved` and `expert_approved` are **never** applied by an AI agent
  — they are earned through the approval actions, by a person, regardless of an agent's
  confidence in its own assessment.

### 5. `+AI` scratch/future use vs `+proposal` change requests

- **What it is:** `+AI` is changing meaning, away from "legacy direct-overwrite draft" and
  toward "AI agent scratch space for working notes, kept separate from card content."
  `+proposal` is the only sanctioned change-request mechanism for published content.
- **Who needs it:** AI agent operators, to avoid conflating the two; editors encountering
  either form mid-migration.
- **Where it lives:** `ONBOARDING.md` §4 "A note on `<Card>+AI`"; migration mechanics in
  `docs/ws6-merge-editor-phase7-plan.md` (the legacy `+AI` bridge).
- **Status — three different things, three different statuses. Read them separately:**

  | Thing | Status |
  |---|---|
  | The `+proposal` convention and the WS6 merge workbench path | **shipped/current** — the sanctioned route for changing published content. |
  | The legacy `+AI` bridge ("Open as proposal") and the reviewable-draft behavior around existing `+AI` cards | **shipped/current, transitional** — implemented in `mod/editorial_review/set/right/ai_draft.rb`, where it requires parent-update and proposal-create permissions (which fixed roles satisfy those checks depends on wiki configuration), and still to be expected while legacy `+AI` content is worked through. |
  | `+AI` as **agent scratch space / working notes** (paraconsistent notes, competing hypotheses, provisional conclusions) | **intended future direction** — the stated goal for what `+AI` becomes. Do not read it as fully realized product behavior today. |

- **Caveat:** the distinction that matters: **`+AI` is notes; `+proposal` is a change
  request.** Do not treat `+AI` scratch content as authorized to publish. And do not cite
  the scratch-space model as a current, enforced feature — the sanctioned current mechanism
  is `+proposal` plus the merge workbench, described in §3 above.

### 6. MCP/API surface for agents

- **What it is:** a Model Context Protocol JSON API letting AI clients read and write
  cards directly — auth, CRUD, search, batch operations, rate limiting, card
  history/relationships.
- **Who needs it:** AI agent operators (Claude, Codex, Gemini/agy — production-proven;
  ChatGPT — also documented); developers extending the API.
- **Where it lives:** `mod/mcp_api/README.md` (mod-level detail); this repo's
  `docs/AGENT-READ-API.md` and `docs/AGENT-READ-YOUR-WRITES.md` (thin pointer files whose
  **canonical content is a wiki card** not yet published to `wiki.hyperon.dev` — see
  their caveat below); **client setup lives in the separate
  [`hyperon-wiki-mcp`](https://github.com/Magi-AGI/hyperon-wiki-mcp) repository**, not
  here.
- **Status:** shipped/current for the MCP API mod itself and for the well-trodden Claude/
  Codex/Gemini client paths. The two "Agent Read API" / "Agent Read-Your-Writes" docs in
  this repo are **pointer-only stubs** — their real content is on an internal card
  (17756 / 17758) that has not yet been published to the public wiki, so this
  SNET-facing branch deliberately does not link the internal host.
- **Verify/next:** `mod/mcp_api/README.md` for the current endpoint list; the
  `hyperon-wiki-mcp` repo for setup and a known-quirks list worth reading before filing a
  bug.
- **Caveat — read the role names carefully.** `mod/mcp_api/README.md` documents three
  **MCP-token roles** (`user`, `gm`, `admin`) that are a distinct authorization layer from
  the Decko content roles in `ROLES-AND-PERMISSIONS.md` (`Administrator`, `Editor`,
  `Raw Data Analyst`, `Expert`) — see `ROLES-AND-PERMISSIONS.md` §3 "AI agent / MCP
  operator" for how the two layers relate. Some of that README's terminology (`gm`,
  "player-visible content", `+GM` card naming) reads as carried over from a sibling
  game-content deck template rather than rewritten for Hyperon; treat the mechanism
  (token roles gating admin-only operations like delete/rename/trash) as current, but
  verify the exact role names and any "player"/"GM" framing against the live server
  rather than assuming the README's wording is Hyperon-native.

### 7. UI/navigation features

- **What it is:** a two-sidebar CSS Grid layout (left nav, article, right TOC), a
  dark/light theme toggle persisted in `localStorage`, a client-side breadcrumb + TOC
  builder, and a left-sidebar nav tree.
- **Who needs it:** everyone browsing the wiki; developers extending `hyperon_ui`.
- **Where it lives:** `mod/hyperon_ui/` (layout, theming); `mod/wiki_nav_tree/` (nav tree
  implementation and its own `README.md`).
- **Status — read carefully, current vs. legacy:** the **live** left sidebar nav is a
  Decko-native `*sidebar` card hierarchy using `{{...|view:link}}` inclusions, styled by
  a "sandra ui styles" CSS card. **`mod/wiki_nav_tree/` itself carries an explicit
  deprecation header dated 2026-05-08**, stating the `view:wiki_nav_tree` view family "is
  no longer referenced by any wiki card" and is "safe to remove ... in a follow-up
  cleanup commit." Do not present `mod/wiki_nav_tree` as the current live navigation
  mechanism without this caveat — its own `README.md` describes the mod as it was
  designed, not necessarily as the wiki currently renders.
- **Verify/next:** inspect the live `*sidebar` card content directly, or load a page and
  observe the rendered nav, rather than trusting either mod's README alone; `README.md`
  → PROGRESS for the two-sidebar layout, theme toggle, breadcrumbs, and TOC feature list
  (right-sidebar TOC and breadcrumbs are marked done there).

### 8. AtomSpace mirror status

- **What it is:** a write-through mirror from Decko/PostgreSQL to the Hyperon AtomSpace,
  plus a separate, explicitly aspirational architecture sketch for deeper AtomSpace backend
  integration.
- **Who needs it:** developers/operators working on the AtomSpace integration track;
  SNET technical owners assessing what is real versus conceptual.
- **Where it lives:**
  - [`ATOMSPACE-MIRROR-DEPLOYMENT.md`](ATOMSPACE-MIRROR-DEPLOYMENT.md) — the Phase 5
    deploy/ops runbook for the mirror. **Source-level and deploy-gated**: its own header
    states "nothing here activates the mirror... activation is a separate, user-approved
    operation." Canonical design lives in wiki cards 17120/17161.
  - [`ATOMSPACE-INTEGRATION.md`](ATOMSPACE-INTEGRATION.md) — a broader backend
    integration architecture. **Explicitly self-described as a conceptual sketch**: its
    own "Cluster-Pilot Reframing" section lists corrections including an apocryphal
    `from hyperon import MCP` import that does not exist in the real package, and states
    Phase 3 is locked to a **read-only** semantic mirror, not the write-through/dual-write
    architecture some of the document's own diagrams still show.
  - `mod/atomspace_mirror/README.md` — the implementation mod itself (models, migration
    path, deploy/rollback commands for the mirror tables).
- **Status:** the mirror **implementation** (mod code, migrations, encoder/outbox writer)
  is source-level current, not yet activated in production. The **broader integration
  architecture** document is aspirational/conceptual by its own admission — do not cite
  its diagrams or code blocks as a description of what runs today.
- **Verify/next:** read `ATOMSPACE-INTEGRATION.md`'s "Cluster-Pilot Reframing" section
  before citing anything else in that file; read `ATOMSPACE-MIRROR-DEPLOYMENT.md`'s
  topology section before assuming any mirror process is running.
- **Caveat:** do not conflate "code exists in this repository" with "mirror is active in
  production" — activation is a distinct, explicitly gated operational step this
  documentation pass does not perform.

### 9. Markdown/math/url/email/permission propagation fixes

Targeted behavioral fixes, each in its own small mod:

| Mod | What it fixes | Where |
|---|---|---|
| `markdown_fixes` | Markdown-type card rendering behavior | `mod/markdown_fixes/set/type/markdown.rb` |
| `url_fixes` | URL linkification and autolink guard behavior (prevents the linkifier from corrupting authored anchors) | `mod/url_fixes/lib/` (`url_linkifier.rb`, `chunk_autolink_guards.rb`, `html_format_url_fix.rb`) |
| `math_rendering` | Injects KaTeX CSS/JS for client-side `\(...\)` / `\[...\]` math rendering, re-rendering after Decko's AJAX slot loads | `mod/math_rendering/lib/math_rendering_head.rb` |
| `email_fixes` | Account-related email behavior | `mod/email_fixes/set/right/account.rb` |
| `permission_propagation` | Repairs cached read-permission state on a card's descendants when a parent's `*read` rule changes; new compound cards inherit a restricted parent's rule automatically | `mod/permission_propagation/set/all/permission_inheritance.rb`, `mod/permission_propagation/set/right/read.rb` |

- **Who needs it:** developers debugging rendering or permission-inheritance surprises;
  operators changing a parent card's `*read` rule.
- **Status:** shipped/current.
- **Caveat:** `permission_propagation`'s own source notes the `*right`-rule case (as
  opposed to a direct `*self` rule) is explicitly marked **TODO** — its propagation
  behavior should not be assumed without checking the current code. Changing a `*read`
  rule on a card with descendants can change visibility for all of them; verify the
  rendered result for the audience you intend before relying on a propagation change.

### 10. File/image/upload behavior

- **What it is:** Decko's two-stage browser upload (cache, then rehydrate into the File
  card) and its permission-checked serving of files/images on every request.
- **Who needs it:** editors uploading images/files; developers touching upload code.
- **Where it lives:** base Decko mechanism; a historical fix is recorded in
  `docs/archive/DECKO-FILE-UPLOAD-BUG.md` (a 2025-10-26 Decko 0.19.1 bug where the
  `assign_attachment_on_create` event did not run inside the expected context, patched
  via a Rails initializer).
- **Status:** historical/archive record, but **the fix it describes may still be
  load-bearing** — the archive's own index (`docs/archive/README.md`) flags this
  explicitly: check before removing anything that document describes.
- **Verify/next:** confirm the initializer described in `docs/archive/DECKO-FILE-UPLOAD-BUG.md`
  is still present in `config/initializers/` before assuming uploads work without it, and
  test an actual browser upload rather than relying on this record alone — it is dated
  2025-10-26 and describes a specific Decko version (0.19.1).
- **Caveat:** do not restate this as a currently-open bug — its status line says
  RESOLVED — but also do not assume the fix is permanently unnecessary; a Decko upgrade
  could reintroduce the underlying condition.

---

## Where to go next

| Question | Go to |
|---|---|
| What's the editorial workflow all of this operates inside? | `../ONBOARDING.md` §3–§5 |
| Who can do what, exactly? | `ROLES-AND-PERMISSIONS.md` |
| Which document covers a topic not listed here? | `DOCUMENTATION-MAP.md` |
| How do I run ingestion safely? | `INGESTION-WORKFLOWS.md` |
| How do I set up an MCP client? | The [`hyperon-wiki-mcp`](https://github.com/Magi-AGI/hyperon-wiki-mcp) repository |
| How does the merge workbench actually work? | [`ws6-merge-editor-design.md`](ws6-merge-editor-design.md) |

Open questions, gaps, or anything this page overclaims: raise them rather than working
around them — several rows above explicitly ask you to re-verify against the live system
before relying on this document alone.
