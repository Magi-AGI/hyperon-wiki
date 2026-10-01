# Architecture

**What this system is made of, how a read differs from a write, and which layer each thing
lives in.**

[`FEATURES-AND-COMPONENTS.md`](FEATURES-AND-COMPONENTS.md) is the inventory with status and
verification notes. This document is the shape: the layers, the mods, and the two paths
through them.

> **Status:** current, drawn from repository source. Where a component exists in code but is
> not running in production, this document says so rather than implying deployment.

---

## The two layers

Everything here reduces to one distinction, and most operational confusion comes from
missing it.

| Layer | Contains | Changes by |
|---|---|---|
| **Code** | Ruby, views, styles, scripts, mod definitions | Git — pull, refresh assets, reload the app server |
| **Cards** | Layouts, headers, sidebars, index structure, permission rules, and every article | The database — the wiki UI, MCP tools, or runner scripts |

Both are "the system." Neither is deployable by the other's mechanism. **When both change
together, deploy the code first**, so the view a card references exists before the card
starts referencing it.

A corollary worth internalizing: **permission rules, layouts, and saved searches are card
state, not configuration files.** A fresh install from this repository does not reproduce the
running wiki — the seed declares three cardtypes and one role; everything else is live
database state. See [`OPERATIONS.md`](OPERATIONS.md).

---

## The read path

What happens when someone loads an article.

```
Request
  → Decko routing
  → Card lookup by name        (names fold case, space/hyphen, singular/plural)
  → Permission check           (*read rules on the cardtype or the specific card;
                                narrower rule wins; compound cards may inherit
                                from their left)
  → View resolution            (set-based: cardtype, right-name, or all)
  → Nest/inclusion expansion   ({{OtherCard|view:x}} — each inclusion re-enters
                                this path, permissions included)
  → Format fixes               (markdown_fixes, url_fixes, math_rendering)
  → Layout                     (hyperon_ui — grid, sidebars, theme)
```

Two things are easy to get wrong here. **Permissions are checked on inclusions, queries,
search results, and file requests** — not only on the top-level page, so a restricted card
does not leak through a nest. And **`{{_main|viewA}}` and `{{_main|viewB}}` in one layout
deduplicate**: the second reference returns the first render from cache.

## The write path

What happens when content changes. This is where the editorial rules live.

```
Write request  (wiki UI, MCP API, or decko runner)
  → Authenticate              (MCP requests run AS the Decko account)
  → Permission check          (*create / *update on the target card)
  → Decko event pipeline      (validate → store → integrate)
       ├─ Draft created       → auto-tag needs review
       ├─ Proposal created    → stamp +base and +provenance in the SAME transaction
       ├─ Draft assembled     → merge DERIVED server-side from hunk selections
       ├─ Merge applied       → gate, then parent write + merge audit
       └─ Type → published    → stamp +approved by/at, add human approved,
                                drop needs review (idempotent)
  → AtomSpace mirror hook     (source-level; NOT active in production)
```

**Derivation and application are separate steps.** The merged text is derived server-side
from recorded hunk selections at **assembly**, not at apply. The apply gate then verifies the
*saved draft* — proposal mode re-read at apply time, audit present, not already merged,
permission on the parent, the parent's act id unchanged, and the draft content hashing to the
recorded `polished_hash` — and writes that content. It does not re-run the merge or re-check
the proposal and base hashes. All of it runs in one transaction; any failure rolls the act
back with no partial parent write. [`EDITORIAL-WORKFLOW.md`](EDITORIAL-WORKFLOW.md) has the
per-check detail.

**What the write path does not enforce** is that a human is at the keyboard. It checks
permissions, locks, and hashes. Human authorization is editorial policy enforced by workflow,
which is why agent accounts should be configured with least privilege.

---

## The mods

Functionality is organized into self-contained bundles under `mod/`.

### Core

| Mod | Responsibility |
|---|---|
| `editorial_review` | The workflow: cardtypes, the `Expert` role, tag vocabulary, approval events, the `+proposal` convention, merge workbench, apply gate. `data/real.yml` is where the seeded vocabulary is declared |
| `mcp_api` | The JSON API behind the MCP tool surface — authentication, CRUD, search, batch operations, rate limiting. Read it for endpoints, not for the permission model |
| `review_queue_ui` | Review Queue presentation only, deliberately separate from the workflow rules so editor-facing UX changes do not tangle with them |
| `hyperon_ui` | Layout, theming, the dark/light toggle, account link labels |

### Behavioural fixes

Each exists because something was surprising. `markdown_fixes` (Markdown card rendering),
`url_fixes` (stops the auto-linker corrupting authored anchors), `math_rendering` (KaTeX,
re-rendering after async slot loads), `email_fixes` (account email behaviour),
`permission_propagation` (repairs cached read-permission state on descendants when a parent's
`*read` rule changes).

### Experimental

| Mod | Status |
|---|---|
| `atomspace_mirror` | Decko → Hyperon AtomSpace write-through mirror. **Source-level; not activated in production.** Encoder, outbox, drain worker, drift monitors, readiness gates |
| `wiki_nav_tree` | **Deprecated** as of 2026-05-08; its view family is no longer referenced by any wiki card. Live navigation is a `*sidebar` card |

### Reading the source

Source files carry unusually detailed rationale comments, several encoding expensive lessons
about Decko's loading and event model. **Read them before refactoring** — many of the
constraints they describe are not visible from the code alone.
[`DECKO-GOTCHAS.md`](DECKO-GOTCHAS.md) collects the ones that generalize.

---

## The AtomSpace track

A separate lane, not part of the editorial day. Card events encode into atoms through an
outbox; a drain worker applies them to a Hyperon space held by a sidecar process; a read
surface exposes queries back, gated by an explicit scope granted per principal.

**Nothing in it runs in production today.** The deployment runbook states that nothing in it
activates the mirror — activation is a separate, approved operation. The broader integration
architecture document is self-described as a conceptual sketch. See
[`atomspace/README.md`](atomspace/README.md), which leads with the distinction between the
two.

---

## Where things are

| Looking for | Path |
|---|---|
| The editorial workflow implementation | `mod/editorial_review/` |
| Seeded cardtypes, roles, tags, Review Queue | `mod/editorial_review/data/real.yml` |
| The MCP API | `mod/mcp_api/` |
| The AtomSpace mirror | `mod/atomspace_mirror/` |
| Merge editor design record | [`merge-editor/`](merge-editor/) |
| Ingestion tooling | `scripts/`, documented in [`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md) |
| Developer setup, tests, adding a mod | [`../README.md`](../README.md) |

## Where to go next

| Question | Document |
|---|---|
| What exists, and how current is it? | [`FEATURES-AND-COMPONENTS.md`](FEATURES-AND-COMPONENTS.md) |
| What will surprise me about Decko? | [`DECKO-GOTCHAS.md`](DECKO-GOTCHAS.md) |
| How do I run this thing? | [`OPERATIONS.md`](OPERATIONS.md) |
| What is a card, exactly? | [`CONTENT-MODEL.md`](CONTENT-MODEL.md) |
