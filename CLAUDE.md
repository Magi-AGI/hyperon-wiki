# CLAUDE.md — Hyperon Wiki agent guide

Guidance for AI coding assistants (Claude Code, Codex, Gemini/agy, and similar) working in
this repository.

**Read these first, in this order:**

1. [`ONBOARDING.md`](ONBOARDING.md) — the front door. Content model, editorial workflow,
   trust markers, roles, and audience paths.
2. [`docs/DOCUMENTATION-MAP.md`](docs/DOCUMENTATION-MAP.md) — which document covers what,
   and which are current, historical, or inherited.
3. [`README.md`](README.md) — the developer guide: setup, tests, mods, Decko gotchas.
4. [`AGENTS.md`](AGENTS.md) — repository conventions: structure, style, testing, PRs.

This file does not repeat those. It covers only what an agent needs that they do not say.

---

## What this repository is

The Hyperon Wiki: a [Decko](https://decko.org) (Rails) deck for the Hyperon / AtomSpace
ecosystem, served at `wiki.hyperon.dev` and backed by **PostgreSQL** (`postgresql` adapter,
`pg` gem, in development, test, and production alike). Decko's generic installation
documentation often recommends MySQL — that does not apply here.

In Decko, **everything is a card**. Pages, fields, tags, layouts, queries, and permissions
are all cards. Names compose with `+`: `PLN (Probabilistic Logic Networks)+PLN Deep Dive`
is a child of `PLN (Probabilistic Logic Networks)`, and a card's metadata lives at
`<Card>+tag`, `<Card>+author`, and so on. Learn that one idea and most of the system
follows. `ONBOARDING.md` §3 has the full content model.

## Two layers, deployed differently

| Layer | Lives in | How it changes |
|---|---|---|
| Ruby code, views, styles, scripts | This git repository | `git pull` + asset refresh + reload the app server |
| Card content — layouts, headers, sidebars, index structure, articles | The database | Wiki UI, MCP tools, or runner scripts |

When both change together, **deploy the code first**, then update the cards, so the view a
card references already exists when the card starts referencing it.

---

## Working rules for agents

These are the conventions that have repeatedly mattered. Follow them.

**Writing to the wiki**

- **One writer at a time.** When several sessions are active on the same wiki, the
  orchestrating session performs the writes; advisory sessions do not write wiki state.
- **Sequential calls, not parallel batches**, for wiki writes.
- **Verify after every write.** Read the card back rather than trusting the response.
- **Draft cards** can be edited directly. **Published cards** are not — author a
  `<Card>+proposal` and route it through the merge workbench (`ONBOARDING.md` §4).
- Treat an "already exists" error as real until you have checked with `get_card` and
  `get_card_history`. The MCP server can return it spuriously after a successful create.
- Tag subcards use `<Card>+tag` (Pointer type, plain newline-separated values such as
  `ai_generated`). The wiki aliases trailing-s plurals, so `+tag` and `+tags` resolve to
  the same card.
- **Never apply human review markers.** `human_approved` and `expert_approved` are applied
  by people, through the approval actions. An agent applying them defeats the workflow.

**Working with sources**

- **Do not "fix" RawData** to match what you think a source should have said. RawData
  preserves the source verbatim; editorial commentary belongs in synthesis cards.
- **Verify claims against the source.** Attribution, identity-between-artifacts, and
  "this was never implemented" claims all need checking. For the last one, `git log --all
  -S '<token>'` beats a grep of current HEAD — code is often removed, not absent.

**Writing documentation**

- Canonical long-form documentation belongs on a wiki (the Hyperon Wiki or the Magi
  Archive); repository files are the bootstrap/offline mirror. Where a document names a
  canonical card, that card wins.
- **Never commit secrets, credentials, tokens, or concrete infrastructure** — hosts, IPs,
  key filenames, database endpoints, env paths. Several documents here are inherited
  templates using `<placeholder>` values; keep them that way. Real access details come from
  the server-access handoff (the Administrator card and its children).
- Keep personal machine paths, local ports, individual backup runbooks, and private
  orchestration tooling out of these files. `ONBOARDING.md` §9 defines the boundary.

---

## Codebase orientation

The mods most worth understanding early:

| Mod | What it does |
|---|---|
| `editorial_review` | Cardtypes, roles, tags, the `+proposal` convention, merge workbench, apply gate |
| `mcp_api` | The JSON API behind the MCP tool surface — auth, roles, rate limiting, CRUD, search |
| `review_queue_ui` | Review Queue presentation, kept separate from the workflow rules |
| `hyperon_ui`, `wiki_nav_tree` | Layout, theming, navigation tree, sidebars |
| `atomspace_mirror` | The Decko → Hyperon AtomSpace mirror |
| `markdown_fixes`, `url_fixes`, `math_rendering`, `email_fixes`, `permission_propagation` | Targeted behavioural fixes |

Source files carry unusually detailed rationale comments — several encode expensive lessons
about Decko's loading and event model. Read them before refactoring.

The merge-editor design record is in `docs/merge-editor/ws6-merge-editor-*.md`. If you are going to
touch the editorial workflow, read `docs/merge-editor/ws6-merge-editor-design.md` first.

---

## MCP client setup

Setup for the wiki's MCP server lives in the separate
[`hyperon-wiki-mcp` repository](https://github.com/Magi-AGI/hyperon-wiki-mcp), not here —
per-client installers and profiles (Claude, Codex, Gemini, ChatGPT), the tool
specification, and a known-quirks list worth reading before filing a bug. This repository
deliberately does not duplicate those instructions, because duplicated setup docs drift.
