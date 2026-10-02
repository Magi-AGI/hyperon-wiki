# Hyperon Wiki — Onboarding

**Start here.** This is the front door for anyone new to the Hyperon Wiki: reviewers,
editors, AI-agent operators, administrators, and developers.

> **About this copy.** This file is a **bootstrap / offline handoff copy** kept in the
> repository so a newcomer can read it before they have wiki or MCP access. The
> preference for this project is that canonical long-form documentation lives on a
> wiki — the Hyperon Wiki itself or the Magi Archive. Once these pages are published
> there, the wiki page becomes the source of truth and this file becomes a mirror.
> Some existing docs already follow that pattern and say so in their own headers (see
> `docs/AGENT-READ-API.md`). Until a page is published, treat this file as current.
>
> **Status of this document:** draft, not yet reviewed or published. Sections marked
> *(to be confirmed)* have not been verified against the running production wiki.

---

## 1. What this is

The Hyperon Wiki is a [Decko](https://decko.org)-based wiki for the Hyperon / AtomSpace
ecosystem. Decko is a Rails application in which **everything is a card** — pages,
fields, tags, layouts, queries, and permissions are all cards. If you learn one concept
first, learn that one; most of the system follows from it.

The wiki holds curated encyclopedic content about Hyperon (MeTTa, PLN, ECAN, AtomSpace,
MORK, and related work), the source material that content was derived from, and an
editorial workflow that keeps AI-assisted contributions under human approval.

### The domains and access surfaces are deliberately separate

There are several related surfaces around the Hyperon Wiki. Some are public web domains,
some are development targets, and some are tool/API domains used by agents. Keep them
separate when reading, operating, or debugging the system:

| Surface | Role |
|---|---|
| `wiki.hyperon.dev` | **The production wiki.** This Decko system, its public pages, its cards, and the editorial workflows described in this document. |
| `hyperon.dev` | **A separate landing site.** A different property with its own content and lifecycle. It is not the wiki, and this handoff does not operate it. |
| Local or private development wiki targets, such as `http://localhost:3000` or a private dev clone | **Development and verification surfaces.** Use these for local code work, tests, and safe reproduction. Do not treat a local/dev result as production evidence unless the step explicitly says it was checked against `wiki.hyperon.dev`. |
| This git repository | **The code and offline handoff source.** Merging here changes source files and documentation. It does not by itself publish card content, deploy production, restart services, or activate experimental systems. |
| The wiki database / cards | **The live content layer.** Layouts, sidebars, permission rules, index structure, and articles are cards. They are changed through the wiki UI, MCP tools, or runner scripts, not by editing Markdown files in this repository. |
| `mod/mcp_api` in this repository | **The server-side JSON API behind the MCP tool surface.** It enforces the wiki's authentication, roles, permissions, rate limits, and card operations. |
| The `hyperon-wiki-mcp` client/tooling repository and configured MCP tool names | **Agent access surfaces.** Claude, Codex, Gemini/agy, ChatGPT, or another MCP client may expose tools under client-local names. Those names are not web domains; they point wherever that client's profile is configured to point, so verify the target before writing. |

This separation is **intentional, not a gap**. Do not file these boundaries as defects or
"fix" them by merging the landing site, production wiki, dev clones, source repository,
card database, and MCP tooling into one mental bucket. Most operational mistakes here come
from treating one surface as evidence for another.

---

## 2. Pick your path

Read section 3 (the content model) first — it is short and everything else assumes it.
Then follow the row that matches you.

| You are… | Read next | Then |
|---|---|---|
| A **reviewer or editor** — you will read, write, and approve content | §3 content model, §4 editorial workflow, §5 trust markers | The Review Queue on the wiki |
| An **AI agent operator / MCP user** — you drive the wiki from Claude, Codex, Gemini/agy, or ChatGPT | §6 MCP overview | `hyperon-wiki-mcp` repo docs; `docs/DOCUMENTATION-MAP.md` → *AI and MCP* |
| An **operator, admin, or SNET technical owner** — you keep it running | §7 running the system | `docs/ROLE-BASED-ONBOARDING.md` → Operator; `docs/DOCUMENTATION-MAP.md` → *Operations — inherited templates* |
| A **developer extending the system** | §8 extending the system | `README.md` (developer guide), then `docs/DOCUMENTATION-MAP.md` → *Subsystem and deep dive* for the merge-editor and AtomSpace design records |

**Two companion primers go further than this file does**, and both assume §3 below:

- [`docs/ROLE-BASED-ONBOARDING.md`](docs/ROLE-BASED-ONBOARDING.md) — a first-day and
  first-week guide for each job: Administrator, Editor/reviewer, Expert, Raw Data Analyst,
  AI agent operator, and operator/SNET technical owner. What the role is for, the normal
  work loop, what not to do, and how to verify your own actions.
- [`docs/FEATURE-PRIMERS.md`](docs/FEATURE-PRIMERS.md) — the same system introduced one
  feature at a time, with a mental model, a first thing to try, and what usually goes wrong.

Read whichever matches how you prefer to learn. This file stays the front door; those two
are where the teaching happens.

`docs/DOCUMENTATION-MAP.md` is the full documentation map. When you want "which file covers X", go
there rather than browsing `docs/` directly — several files in that directory are
historical or inherited, and the map says which.

---

## 3. The content model in five minutes

Content lives in cards. A card has a **name**, a **type** (cardtype), and **content**.
Names compose with `+`: `PLN (Probabilistic Logic Networks)+PLN Deep Dive` is a child of
`PLN (Probabilistic Logic Networks)`. That compound-name convention is how the wiki
expresses both hierarchy and per-card metadata — a card's tags live at `<Card>+tag`, its
authors at `<Card>+author`, and so on.

### The cardtypes you will meet

| Cardtype | What it holds | Who can see it |
|---|---|---|
| **Draft** | Unpublished content pending review. The normal working state for new or in-progress articles. | Current production: read is open to everyone, including guests, with create/update requiring sign-in. See `docs/ROLES-AND-PERMISSIONS.md` §4 — this is a live-configuration fact, not a design claim, and should be re-verified before publication if a narrower policy is intended. |
| **Published** | Human-approved content. | Everyone, including guests. |
| **RawData** | Raw source material — transcripts, chat logs, meeting notes, publication text. Preserved verbatim; not edited to "fix" what a source says. | Read: Raw Data Analysts and Administrators. Create/update/delete: Administrators. See `docs/ROLES-AND-PERMISSIONS.md` §4. |
| **IndexSection** | A curated top-level section landing page in the wiki's index (for example *Knowledge Representations*, *MeTTa Programming Language*). | Everyone. |
| **IndexSubtopic** | A curated subtopic page under a section (for example *PLN*, *MORK*, *DAS*). | Everyone. |
| **Contributor** | A person who authored, contributed to, or edited content. Referenced from `+author` / `+contributor` / `+editor` pointers. | Everyone. |

`IndexSection` and `IndexSubtopic` are **curated navigation**, not a general dumping
ground. They share the same review and approval behaviour as `Published` cards, and the
index structure is deliberately managed. If you are adding a substantial new write-up,
the convention is to place it in a neutral namespace and cross-link it rather than
inventing new index scaffolding.

### The Review Queue

**Review Queue** is a saved search card, not a separate application. It lists the work that
is waiting for a human: **Draft cards, and cards carrying an open proposal that has not yet
been merged.** Both are in the live query, read back from the wiki:

```json
{"or":{"type":"draft","right_plus":["proposal",{"not":{"right_plus":"merge audit"}}]},
 "sort":"create","dir":"asc"}
```

Read that as: *drafts, or cards with a `+proposal` child that does not yet have a
`+merge audit` child* — in other words, proposals disappear from the queue once they have
been merged. Oldest first.

Clicking a queue row opens that card in a new tab, so you can queue several up at once.

---

## 4. How an edit actually happens

This is a **workflow** — a partially automated toolchain with humans at the decision
points. It is **not** a fully scheduled, end-to-end automated pipeline, and it should not
be described as one. Some stages are automated and enforced by the server; others are
initiated by a person. The table below is explicit about which is which.

### Stage A — Source ingestion (a human triggers it)

**Usually a human starts this.** Someone decides that a body of source material should be
brought in, and triggers the ingestion process. Source material (meeting transcripts, chat
archives, shared documents, publications) lands as **RawData** cards under source parents
such as `RawData+transcripts`, `RawData+mattermost`, `RawData+google-doc`, and
`RawData+Publications`.

- **Automation:** the ingestion machinery is scripted, but it is *run on demand*. There is
  no continuously scheduled importer watching the sources.
- **Rule:** RawData preserves the source as-is. Editorial commentary belongs in synthesis
  cards, not in the raw body.
- **The tooling:** the export and ingest scripts live in `scripts/` and are **part of this
  repository handoff** — see [`docs/INGESTION-WORKFLOWS.md`](docs/INGESTION-WORKFLOWS.md)
  for the inventory, the two-stage export/ingest model, and a safe first-run posture. The
  source-service credentials and the exported source files are **not** part of the handoff;
  those come through the secure access handover.

### Stage B — Synthesis and analysis (a human triggers it too)

Once material is ingested, **a human triggers the synthesis and analysis step**. This is
where the content is actually read, cross-referenced, and turned into something a reader
can use. The output depends on what the material turns out to be:

| If the material is… | The process produces… |
|---|---|
| A **new concept or domain** the wiki does not cover yet | A **Draft** card summarizing it. Drafts are the working state, tagged `needs review`, and not yet approved for publication. That is an **editorial** status, not a technical access restriction: the live setting is `Draft+*type+*read = Anyone`, so an unapproved Draft is readable by anyone, including guests not signed in (see §7 and `docs/ROLES-AND-PERMISSIONS.md` §4). The seed default is `Anyone Signed In`, so the live setting differs from it. Whether Drafts should stay publicly readable is an unresolved policy decision, and no change has been made — **verify `Draft+*type+*read` on the target wiki before placing restricted or source-derived material in a Draft.** |
| Something that concerns an **existing published card** | A **proposal** at `<Card>+proposal`, authored with AI support, proposing how that card should change. |

Either way, a person decides that the step should happen and a person reviews what came
out of it. The AI does the reading and drafting; it does not decide that the work is done.

**What the server does automatically here** is the bookkeeping, and it is strict: when a
proposal is created, the system stamps `<Card>+proposal+base` (the parent revision the
proposal was written against) and `<Card>+proposal+provenance` (content hashes, the
author, the source) inside the same database transaction as the proposal itself. There is
no window in which an unstamped proposal exists.

- `+proposal` is **author-neutral**: a human can open one as a peer review exactly as an
  agent can. Think of it as this wiki's pull request.
- A proposal also carries a **mode** sidecar at `<Card>+proposal+mode`. The merge tool
  only acts on a proposal explicitly recorded as `full-replacement`, because merging
  replaces the parent body wholesale. Anything else — including a proposal with no mode
  recorded — is refused with an explanation rather than guessed at. This is deliberate
  fail-closed behaviour.

### Stage C — Review, merge, approval

The reviewer opens the proposal in the **merge workbench**: a three-way view of *base*
(what the proposal was written against), *current* (the live card, which may have moved),
and *proposal*. The reviewer chooses, hunk by hunk, what to keep, assembles the result
into a merge draft, optionally polishes it in the normal editor, and applies it.

- **Automation:** the verification is automatic and strict. Applying a merge passes a
  gate that checks, inside a single transaction: that you have permission to update the
  parent; that the parent has not changed since you began reviewing; that the draft you
  are applying is byte-for-byte what you last saved; and it records who applied it. If
  any check fails, the whole thing rolls back — there is no partial write. A completed
  merge leaves an audit record and cannot be silently re-applied.
- **The ultimate publication decision belongs to a human.** This is the governing rule of
  the workflow, and it holds regardless of how much of the drafting an AI did. Understand
  it as an *editorial policy* enforced by this workflow, rather than as a technical
  impossibility: the merge gate checks permissions, locks, and hashes, not whether a human
  is at the keyboard, and a sufficiently privileged account can write to a card outside
  this path. The proposal/merge workbench is the intended governed route for changing
  published content, and agent accounts should be permissioned so that it is the route
  they actually take.

### A note on `<Card>+AI`

`+AI` is changing meaning, so you may encounter it in two forms.

**The old use, being phased out.** Historically `<Card>+AI` held an AI draft that could be
merged straight into its parent, overwriting it. That direct-overwrite path is being
retired in favour of the proposal/merge workflow above, and existing `+AI` cards are being
worked through. A bridge lets you re-open a legacy `+AI` draft as a proper proposal. If you
find both paths present, neither is broken — you are looking at a migration in progress.

**The intended future use.** Going forward, `+AI` is meant to be **scratch space for AI
agents' own notes**, kept deliberately separate from card content. It is somewhere an agent
can record working notes, uncertain conclusions, and competing hypotheses while an
investigation is still open — supporting paraconsistent reasoning, where contradictory
findings can coexist until the evidence settles, without any of that provisional thinking
leaking into the article a reader sees.

The distinction that matters: **`+AI` is notes; `+proposal` is a change request.** An agent
changing published content authors a `+proposal` and routes it through the merge workflow;
`+AI` scratch notes are not themselves a change request and are never authorized to
publish.

**Who is expected to author proposals.** This path was built primarily for AI agents, so
that agent-authored changes to published content carry provenance and pass the verifying
gate. Human editors mostly *review and merge* proposals rather than writing them; their own
work normally happens in Drafts, and where policy allows a direct edit to a published card,
that remains a legitimate human route — it simply carries no base, provenance, or merge
audit, so a substantial rewrite is worth routing through review. Humans can author a
proposal when they want that audit trail; it is an advanced route rather than the default.

---

## 5. Trust markers — what the tags and banners mean

Every card can carry tags at `<Card>+tag`. These render as pills at the top of the page,
and some also drive banners. As a reader, this is how you tell how much weight to give
what you are reading.

| Marker | Meaning |
|---|---|
| `needs review` | Applied automatically when a Draft is created. Nobody has approved this yet. |
| `ai generated` | The content was produced by an AI agent. Provenance, not a verdict — it may be excellent or unreviewed. |
| `human authored` | Written by a person. |
| `transcript derived` | Derived from source material such as a meeting transcript. |
| `ai reviewed` | An AI pass has reviewed it. This is **not** approval. |
| `human approved` | A human approved and published it. Applied automatically when a card is approved into a published state; `needs review` is removed at the same time. |
| `expert approved` | A domain expert with the `Expert` role has endorsed it — the strongest marker here. Applied when an expert uses the *Expert Approve* action. |

### Banners you will see

- **Draft banner** (amber): "This content has not been approved for publication." Shown on
  every Draft, with an *Approve & Publish* action for users who can edit it.
- **Approval banner** (green): "Human Approved — by *name* on *date*." Shown for the first
  7 days after approval, then it settles into a quiet grey line so it stops shouting.
- **Expert seal** (amber badge): "Expert Approved by *name* on *date*."
- **Not-mergeable notice**: shown in the merge workbench when a proposal has not been
  characterized as a full replacement. It explains *why* it is refused, and offers no
  merge controls at all.

Approval also records `<Card>+approved by` / `+approved at`, and expert endorsement
records `<Card>+expert approved by` / `+expert approved at`, so the history is auditable
rather than living only in a tag.

---

## 6. Working with AI agents (MCP)

The wiki exposes a Model Context Protocol (MCP) tool surface, so an AI assistant can read
and write cards directly rather than being handed pasted text.

This has been in routine production use for months from **Claude**, **Codex**, and
**Gemini / agy**; those three are the well-trodden paths. A **ChatGPT** setup path also
exists and is documented in the MCP repository.

What agents can do, at a high level: read cards and their history, search and query,
create and update cards, manage tags, and author `+proposal` cards that feed the review
workflow described in §4.

**On publishing:** the proposal/merge workbench is the *intended, governed path* for
changing published content, and the merge gate applies to agent-authored proposals exactly
as it does to human ones. But be precise about what enforces this. The API grants whatever
the authenticating account's permissions allow — a sufficiently privileged account can
update content and types directly, and the merge gate verifies permissions, locks, and
hashes rather than whether a human is at the keyboard. **Human authorization is required by
editorial policy and workflow, not by a technical impossibility.** Configure agent accounts
with that in mind: give them the least privilege that lets them do their job, and route
published-content changes through proposals.

**Setup lives in the `hyperon-wiki-mcp` repository, not here** —
<https://github.com/Magi-AGI/hyperon-wiki-mcp>. That repo holds the
per-client installers and a profile document for each client (Claude, Codex, Gemini, and
ChatGPT), plus the tool specification and a list of known server quirks worth reading
before you file a bug. See the *AI and MCP* section of `docs/DOCUMENTATION-MAP.md`. This
document deliberately does not duplicate setup instructions, because duplicated setup
docs drift.

**Working conventions for agents**, learned the hard way:

- One writer at a time. When several sessions edit the same wiki, the orchestrating
  session performs the writes; advisory sessions do not write wiki state.
- Verify after every write. Read the card back rather than trusting the response.
- Published cards are not edited directly — propose a change instead (§4).
- Do not "fix" RawData to match what you think a source should have said.

---

## 7. Running the system (operator / admin / SNET technical owner)

The wiki is a Decko/Rails application backed by **PostgreSQL**, deployed on a server and
served at `wiki.hyperon.dev`. Functionality is organized into **mods** — self-contained
bundles of Ruby, views, and assets under `mod/`.

PostgreSQL is the engine in every environment — `config/database.yml` uses the
`postgresql` adapter for development, test, and production, and the `Gemfile` depends on
`pg`. Decko's generic installation documentation often recommends MySQL; that does not
apply to this deck.

Two things deploy differently and this trips people up:

| Layer | Lives in | How it changes |
|---|---|---|
| Ruby code, views, styles, scripts | The git repository | `git pull` + asset refresh + reload the app server |
| Card content — layouts, headers, sidebars, index structure, the articles themselves | The database | Edited through the wiki UI, MCP tools, or runner scripts |

When both change together, **deploy the code first**, then update the cards, so the view a
card references already exists when the card starts referencing it.

**A dirty working tree on the server is not automatically a problem.** Several agent
sessions may be actively working at once, and uncommitted changes during that work are
expected. Do not treat a clean server working tree as a prerequisite for onboarding, for
reading these docs, or for getting started. Investigate it as part of normal operational
hygiene, on its own schedule.

Deployment specifics — server setup, database access, the mirror runbook — are indexed in
`docs/DOCUMENTATION-MAP.md` under *Subsystem and deep dive*. Read the caveats there first: some of
those files were inherited from a sibling Decko deck and still describe that system's
hosts, database names, and defaults rather than this one. The database *engine* is not in
doubt — it is PostgreSQL — but the host-specific values in those inherited files are, and
they are queued for rewrite.

### Roles and permissions

Access has two layers, and it helps to keep them apart.

**Baseline access comes from CRUD rules on each cardtype**, and it is not the same for
every cardtype. Current production: guests (not signed in) can read both Draft and
Published content; creating or updating either requires signing in; RawData read is
restricted to the `Raw Data Analyst` role (plus Administrators), and RawData
create/update/delete are Administrator-only. These are live-configuration facts, not
design intentions — the repository's seed data describes a narrower Draft-read rule
than what production currently runs. See `docs/ROLES-AND-PERMISSIONS.md` §4 for the
full matrix and the seed-vs-production discrepancy, and re-verify against the running
site if you are relying on this for an access decision, or if a narrower policy is
actually intended.

**Some elevated capabilities are technically role-gated; others are assigned editorial
responsibility enforced by workflow, not by CRUD rules — keep the two apart.**
Administrators grant roles for both kinds:

- **reading RawData** and other restricted source material — technically enforced: RawData
  `*read` is scoped to the `Raw Data Analyst` role (plus Administrators) in the live CRUD
  rules.
- **applying trust markers** such as the expert endorsement — technically enforced: the
  *Expert Approve* action is gated to the `Expert` role.
- **destructive administrative operations** — technically enforced: Administrator-only.
- **editorial review and publishing responsibility** — moving content toward a published
  state through the Review Queue and merge workbench is the `Editor` role's assigned job,
  but it is **not** currently locked behind that role at the CRUD layer: the live matrix
  (`docs/ROLES-AND-PERMISSIONS.md` §4) shows `Draft`/`Published` create and update as
  `Anyone Signed In`. In practice, any signed-in account can technically edit a Draft or a
  Published card directly; the proposal/merge workflow and the `Editor` role describe who
  is *expected* to do that work and through what route, not a technical wall that prevents
  anyone else. Do not assume a signed-in contributor is blocked from touching published
  content just because they lack the `Editor` role — check the live CRUD rule if that
  matters for a specific decision.

So if a new contributor can't do something role-gated — no *Expert Approve* button, no
RawData access — that's the role layer, and an administrator needs to grant it. **Where
access differs for a specific card, check that card's permissions and the live role
configuration** rather than inferring from this page.

Roles you are likely to encounter:

| Role | Broadly, what it is for |
|---|---|
| **Administrator / Admin** | Site administration: creates/approves accounts, assigns roles, holds RawData access and destructive operations. |
| **Editor** | Reviews, edits, and publishes content according to site policy. |
| **Raw Data Analyst** | Works with RawData and source material — the ingestion and synthesis end of the workflow. |
| **Expert** | Grants the expert endorsement action: a domain expert can apply the `expert approved` trust marker. Assigned on the basis of demonstrated domain expertise. |

**`docs/ROLES-AND-PERMISSIONS.md`** is the full reference: how the first Administrator
account comes to exist on a clean deck versus the current production handoff path, how
an administrator creates/approves an account and assigns roles, per-role workflows
(including the AI agent/MCP operator and the SNET technical-owner operational
function), and the live permission matrix with its seed-vs-production caveat. Read it
before making an access decision — the roster above is orientation, not a permission
specification.

---

## 8. Extending the system (developer)

`README.md` at the repository root is the developer guide: local setup, running tests,
mod structure, adding a mod, overriding a view, and a table of Decko gotchas. Start there.

The parts of the codebase most worth understanding early:

| Mod | What it does |
|---|---|
| `editorial_review` | The workflow in §4 and §5 — cardtypes, roles, tags, the `+proposal` convention, the merge workbench, and the apply gate. |
| `mcp_api` | The JSON API behind the MCP tool surface — authentication, roles, rate limiting, card CRUD, search, and rendering. |
| `review_queue_ui` | Presentation for the Review Queue, kept separate from the workflow rules on purpose. |
| `hyperon_ui`, `wiki_nav_tree` | Layout, theming, navigation tree, sidebars. |
| `atomspace_mirror` | The Decko → Hyperon AtomSpace mirror work. |
| `markdown_fixes`, `url_fixes`, `math_rendering`, `email_fixes`, `permission_propagation` | Targeted behavioural fixes. |

The merge-editor design record is substantial and lives in `docs/merge-editor/ws6-merge-editor-*.md` —
design document, implementation plan, per-phase specifications for the workbench UI, the
editor gate, and the apply gate, plus deployment notes. If you are going to touch the
editorial workflow, read the design document before the code.

The source files themselves carry unusually detailed rationale comments explaining *why*
things are shaped as they are (several encode expensive lessons about Decko's loading and
event model). Read them before refactoring.

---

## 9. What is deliberately not here

This document and the repository documentation cover the shared system. The following are
**out of scope** and must not be added to these files:

- Any credential, password, API key, token, MFA seed, database URL with a password, or
  billing detail. These belong in a secrets manager and in a separate access handover,
  never in a repository.
- Individual contributors' local development setups, personal machine paths, local ports,
  local container configurations, and personal backup runbooks. These vary per person and
  are not part of the handoff.
- Internal relay and orchestration tooling that individual operators use to coordinate
  their own agent sessions.

The handoff documentation set is this file, `README.md`, `CLAUDE.md`, `AGENTS.md`, and the
documents indexed in `docs/DOCUMENTATION-MAP.md`. It does **not** include the historical
research corpus under `scripts/archive/`, which is unreviewed internal working material and
is not part of what these docs describe.

If you need production access, that is an access-handover conversation, not a
documentation one.

---

## 10. Next-reader checklist

Work through this in order. It should take well under an hour.

- [ ] You can state why `wiki.hyperon.dev` and `hyperon.dev` are separate, and that it is intentional.
- [ ] You can name the six cardtypes in §3 and say who can see each.
- [ ] You understand that a card's tags, authors, and metadata live at `<Card>+something`.
- [ ] You can explain the difference between `ai generated`, `human approved`, and `expert approved`.
- [ ] You know that the publication decision belongs to a human — as editorial policy enforced by the proposal/merge workflow, not as a technical impossibility.
- [ ] You can describe Stage A → B → C in your own words, **without** calling it a fully automated pipeline.
- [ ] You have opened `docs/DOCUMENTATION-MAP.md` and know where to look up a topic.
- [ ] If you will use MCP: you have found the per-client setup docs in the `hyperon-wiki-mcp` repository.
- [ ] If you will operate the system: you have read the code-before-cards rule in §7.
- [ ] If you will develop: you have read `README.md` and skimmed the WS6 design document.

---

## 11. Where to go next

| Question | Go to |
|---|---|
| What is my job here, and how do I start doing it? | `docs/ROLE-BASED-ONBOARDING.md` |
| How does each feature work, one at a time? | `docs/FEATURE-PRIMERS.md` |
| Which document covers X? | `docs/DOCUMENTATION-MAP.md` |
| What was described as a deliverable, and what exists today? | `docs/DELIVERABLES-SCOPE-MAPPING.md` |
| What features/components exist, and how current are they? | `docs/FEATURES-AND-COMPONENTS.md` |
| I need the cardtypes, names, and tags in full | `docs/CONTENT-MODEL.md` |
| I need every card the editorial workflow writes | `docs/EDITORIAL-WORKFLOW.md` |
| I am reviewing something right now | `docs/REVIEW-QUEUE-GUIDE.md` |
| I need to undo an edit or recover a deleted card | `docs/HISTORY-AND-ROLLBACK.md` |
| How is the system put together? | `docs/ARCHITECTURE.md` |
| Something in Decko behaved unexpectedly | `docs/DECKO-GOTCHAS.md` |
| How do I set up a development environment? | `README.md` |
| How does the merge editor actually work? | `docs/merge-editor/ws6-merge-editor-design.md` |
| How do I connect my AI client? | The [`hyperon-wiki-mcp` repository](https://github.com/Magi-AGI/hyperon-wiki-mcp) |
| What are the known MCP server quirks? | `SERVER-BUGS.md` in the [`hyperon-wiki-mcp` repository](https://github.com/Magi-AGI/hyperon-wiki-mcp) |

Open questions, corrections, and anything this document got wrong: raise them rather than
working around them. This is a first draft and the fastest way to improve it is to be told
where it failed you.
