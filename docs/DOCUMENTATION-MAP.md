# Documentation Map

The index for this repository's documentation. Use it to find the right document instead of
browsing `docs/` directly — filenames alone do not tell you whether something is current, a
generic template, or a completed phase record.

> **Naming note.** This file is the *documentation map*. The repository root
> [`../README.md`](../README.md) is the conventional *developer guide*. They were briefly
> both named `README.md`; this one was renamed so the two are never confused in a link or a
> conversation.

---

## Read these first

Five documents, in this order. Under an hour, and enough to work with the wiki.

| # | Document | Why it is here |
|---|---|---|
| 1 | [`../ONBOARDING.md`](../ONBOARDING.md) | The front door. The content model, how an edit actually happens, trust markers, and which path to follow next. Everything else assumes §3. |
| 2 | [`ROLE-BASED-ONBOARDING.md`](ROLE-BASED-ONBOARDING.md) | Your job, specifically. First-day and first-week guidance for Administrator, Editor/reviewer, Expert, Raw Data Analyst, AI agent operator, and operator/SNET technical owner. |
| 3 | [`FEATURE-PRIMERS.md`](FEATURE-PRIMERS.md) | The system one feature at a time: mental model, first thing to try, what usually goes wrong. |
| 4 | [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) | Who can do what, how accounts and roles are granted, and the live permission matrix. Read before making any access decision. |
| 5 | [`FEATURES-AND-COMPONENTS.md`](FEATURES-AND-COMPONENTS.md) | The full component inventory with status and verification notes, once the primers have given you the shape. |

If you are setting up a development environment rather than using the wiki, start at
[`../README.md`](../README.md) instead.

---

## How this package is organized

| Tier | What it is | Where it lives |
|---|---|---|
| **Entry points** | The front door, the developer guide, and the contributor/agent conventions | Repository root |
| **Core handoff docs** | The five documents above. Small on purpose | `docs/` |
| **Reference** | Task-specific documents you consult when you need them | `docs/` |
| **Subsystem / deep dive** | Design records and runbooks for one subsystem. Valuable, but not on the newcomer path | [`merge-editor/`](merge-editor/), [`atomspace/`](atomspace/), [`operations/`](operations/) |
| **Historical** | Completed phases, past investigations, shipped fixes. Dated records, not instructions | [`archive/`](archive/) |
| **Not in the handoff** | Material this documentation set deliberately does not cover | see below |

The subsystem tier now lives in directories: [`merge-editor/`](merge-editor/),
[`atomspace/`](atomspace/), and [`operations/`](operations/), each with a short index of its
own. The remaining tiers are editorial groupings rather than directory names. The
reorganization is **complete** — see [Reorganization phases](#reorganization-phases) for what
each phase did. Work still outstanding is tracked under
[Follow-up tasks](#follow-up-tasks) and [Planned, not yet written](#planned-not-yet-written),
not as an unfinished phase.

---

## Entry points (repository root)

| Document | What it covers | Status |
|---|---|---|
| [`../ONBOARDING.md`](../ONBOARDING.md) | Front door: content model, roles, editorial workflow, trust markers, audience paths. | current (draft) |
| [`../README.md`](../README.md) | Developer guide: setup, running, testing, mods, Decko gotchas, UI layout. Also holds the code-versus-cards distinction and the code-before-cards ordering rule. | current |
| [`../CLAUDE.md`](../CLAUDE.md) | Agent guide: what this repository is, the two deploy layers, working rules for agents writing to the wiki, codebase orientation. | current |
| [`../AGENTS.md`](../AGENTS.md) | Repository conventions: structure, build and test commands, coding style, testing, commit and PR guidelines. | current |

---

## Core handoff docs

The five in **Read these first**, plus this map. Everything here is meant to be read by a
newcomer without prior context.

| Document | What it covers | Status |
|---|---|---|
| `DOCUMENTATION-MAP.md` (this file) | The index and the tiering. | current (draft) |
| [`ROLE-BASED-ONBOARDING.md`](ROLE-BASED-ONBOARDING.md) | Per-role first week: what the role is for, the normal work loop, what not to do, the verification habit, when to escalate. Includes Administrator walkthroughs for approving a signup when email is down, assigning roles, and recovering deleted cards. | current (draft) |
| [`FEATURE-PRIMERS.md`](FEATURE-PRIMERS.md) | Feature-by-feature primers: cards and compound names, the index, the Draft/Published/RawData lifecycle, Review Queue, proposals and the merge workbench, trust markers, `+AI` versus `+proposal`, ingestion, MCP, history, permissions, the AtomSpace mirror, and the right-column panels. | current (draft) |
| [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) | Administrator onboarding (first-admin bootstrap versus the current production handoff), account and role creation, per-role workflows, the live permission matrix and its seed-versus-production caveat, and permission propagation. | current |
| [`FEATURES-AND-COMPONENTS.md`](FEATURES-AND-COMPONENTS.md) | Component inventory: base Decko concepts and Hyperon-specific features, each with what it is, who needs it, where it lives, its status, and how to verify it. | current (draft) |

---

## Reference

Consult these when the task calls for them. None is required reading on day one.

| Document | Read it when | Status |
|---|---|---|
| [`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md) | You are bringing source material into the wiki. The script inventory by source family, the two-stage export-then-ingest model, what an operator supplies out of band, and the safe first-run posture. **Required reading before any ingest run.** | current |
| [`DELIVERABLES-SCOPE-MAPPING.md`](DELIVERABLES-SCOPE-MAPPING.md) | You are taking the system over and want to know what exists versus what is still an open decision. A built-work record mapping each described term to the work evidenced today. | current |
| [`DECKO-SECTION-PATTERN.md`](DECKO-SECTION-PATTERN.md) | You are building a structured, multi-section article and want the established card pattern. | current |
| [`SCRIPTS-RESEARCH-ARCHIVE.md`](SCRIPTS-RESEARCH-ARCHIVE.md) | You are wondering what the gitignored `scripts/archive/` corpus at the repository root is, or considering sharing the repository externally. States a boundary that applies today — not a historical record. | current |

Also useful, outside `docs/`: `mod/review_queue_ui/README.md` for Review Queue behaviour, and
`mod/editorial_review/` for the workflow implementation — its source files carry detailed
rationale comments, and `mod/editorial_review/data/real.yml` is where cardtypes, roles,
codenames, and the tag vocabulary are declared.

---

## Subsystem and deep dive

Real documentation for one part of the system. Skip until you need the subsystem.

### The merge editor (WS6) — [`merge-editor/`](merge-editor/)

The editorial workflow's design record, in its own directory with a short index at
[`merge-editor/README.md`](merge-editor/README.md). **If you are going to touch the
editorial workflow, read the design document first.**

| Document | What it covers | Status |
|---|---|---|
| [`merge-editor/ws6-merge-editor-design.md`](merge-editor/ws6-merge-editor-design.md) | **Start here.** Why `+proposal` exists and is separate from `+AI`; the three-way merge model; the human-approval governance rule. The single best explanation of how editing actually works. | current |
| [`merge-editor/ws6-merge-editor-impl-plan.md`](merge-editor/ws6-merge-editor-impl-plan.md) | The phased build behind the design document. | current |
| [`merge-editor/ws6-merge-editor-phase4-ui-contract.md`](merge-editor/ws6-merge-editor-phase4-ui-contract.md) | The merge workbench interface contract — panes, hunks, payload shape. | current |
| [`merge-editor/ws6-merge-editor-phase4_1-ribbons.md`](merge-editor/ws6-merge-editor-phase4_1-ribbons.md) | Workbench visual design note — connector ribbons and resizable bands. | current |
| [`merge-editor/ws6-merge-editor-phase5-tinymce-gate.md`](merge-editor/ws6-merge-editor-phase5-tinymce-gate.md) | The polish step, and why the merge draft is kept separate from the proposal. | current |
| [`merge-editor/ws6-merge-editor-phase6-apply-gate.md`](merge-editor/ws6-merge-editor-phase6-apply-gate.md) | The verification gate that runs before a merge touches a published card. | current |
| [`merge-editor/ws6-merge-editor-phase7-plan.md`](merge-editor/ws6-merge-editor-phase7-plan.md) | Lifecycle, entry points, and the legacy `+AI` bridge. Explains why two paths coexist during the phase-out. | current |
| [`merge-editor/ws6-merge-editor-phase8-capability-gating.md`](merge-editor/ws6-merge-editor-phase8-capability-gating.md) | Permission gating for merge actions. | current |
| [`merge-editor/ws6-merge-editor-prod-deploy-notes.md`](merge-editor/ws6-merge-editor-prod-deploy-notes.md) | Production deploy and migration notes for the merge editor. | current |

### AtomSpace — [`atomspace/`](atomspace/)

Index: [`atomspace/README.md`](atomspace/README.md).

| Document | What it covers | Status |
|---|---|---|
| [`atomspace/ATOMSPACE-MIRROR-DEPLOYMENT.md`](atomspace/ATOMSPACE-MIRROR-DEPLOYMENT.md) | Deployment and operations runbook for the Decko → Hyperon AtomSpace write-through mirror. Names its canonical wiki cards. **Nothing in it activates the mirror** — activation is a separate, approved operation. | current |
| [`atomspace/ATOMSPACE-INTEGRATION.md`](atomspace/ATOMSPACE-INTEGRATION.md) | Broader backend integration architecture. **Self-described as a conceptual sketch** — its own header warns that code blocks are not necessarily runnable. Read that warning first. | current, explicitly aspirational |
| [`AGENT-READ-API.md`](AGENT-READ-API.md) | AtomSpace mirror agent read API. **Pointer only** — the canonical version is a wiki card named in the file header, not yet published to `wiki.hyperon.dev`. | current (mirror) |
| [`AGENT-READ-YOUR-WRITES.md`](AGENT-READ-YOUR-WRITES.md) | Read-your-writes consistency for agents. **Pointer only**, same caveat. | current (mirror) |

Implementation lives in `mod/atomspace_mirror/`.

### AI and MCP

`mod/mcp_api/README.md` documents the MCP API mod — authentication, roles, CRUD, search,
batch operations, rate limiting. Read it for the endpoint list rather than for the
permission model: it carries role names and terminology from a sibling deck's template. The
current picture is that an MCP request runs as the authenticated Decko account, so access
follows that account's Decko roles and the card and set rules that apply, with a narrow
Administrator guard on destructive operations.

**Client setup lives in the separate `hyperon-wiki-mcp` repository** —
<https://github.com/Magi-AGI/hyperon-wiki-mcp> — not here. That repository holds the
per-client installers and profile documents (Claude, Codex, Gemini, ChatGPT), the tool
specification, operations notes, and a known-quirks list worth reading before filing a bug.
Claude, Codex, and Gemini/agy are the paths with months of production use behind them.

The `mcp_api` build-out record — phase plans, completion notes, the phase-2 testing guide —
is in [`archive/`](archive/).

### Operations — inherited templates — [`operations/`](operations/)

**Start at [`OPERATIONS.md`](OPERATIONS.md)** — it records what is actually confirmed about
running this wiki and marks everything else as open. The two documents below are supporting
procedures behind it, indexed at [`operations/README.md`](operations/README.md).

Both carry generic procedures with `<placeholder>` values throughout. The *procedure* is
reusable; every concrete value — hosts, keys, endpoints, paths — comes from the
server-access handoff, never from a repository file. **Read the status column before
following either of them.**

| Document | What it covers | Status |
|---|---|---|
| [`OPERATIONS.md`](OPERATIONS.md) | What is confirmed about operating this wiki — the two deploy layers and their ordering, PostgreSQL everywhere, the two separate handoffs, access-control shape, ingestion touching production, the mirror being unactivated — plus an explicit list of what still needs server-access confirmation. | current (skeleton) |
| [`operations/DECKO-DATABASE-ACCESS.md`](operations/DECKO-DATABASE-ACCESS.md) | Running Decko/ActiveRecord scripts against a deck via remote console: environment bootstrap, `script/card runner`, quoting, Windows and Linux stdin workflows, troubleshooting. | template — see [Follow-up tasks](#follow-up-tasks) item 1a |
| [`operations/EMAIL_SETUP.md`](operations/EMAIL_SETUP.md) | SMTP configuration for a Decko deck: provider options, environment variables, verification. Referenced from `ROLES-AND-PERMISSIONS.md` when account verification email fails. | template — see [Follow-up tasks](#follow-up-tasks) item 1b |

A third inherited template, an EC2 and RDS deployment walkthrough, was **retired to
[`archive/AWS-DEPLOYMENT.md`](archive/AWS-DEPLOYMENT.md)** — see Follow-up task 1c.

---

## Historical — [`archive/`](archive/)

Completed phase records, past investigations, and shipped-fix write-ups: the `mcp_api`
build-out, the May 2026 content usability pass, the URL-parsing fix, the file-upload bug
investigation, the right-column plan, and one merge-editor PR summary.
[`archive/README.md`](archive/README.md) indexes them.

**These are dated records, not instructions.** They may read as current — check the date
before acting on anything in them. Nothing in the newcomer path points here.

Two things worth knowing about the contents:

- The **file-upload bug investigation** describes a fix that **may still be load-bearing**.
  Check before removing anything it describes.
- The **usability pass** (inventory, checklist, audit log) is a useful worked example of what
  a review pass looks like in practice.

**Two records were retired rather than archived** — an MCP deployment-status snapshot and an
email-verification fix summary. Both documented a sibling deck's production server and
carried its host, service account, and key details, so they were removed from this branch
entirely. They are not in `archive/`; they survive only in git history and in that deck's own
repository.

Historical documents were moved to `archive/` rather than deleted. Documents that described
a *different product* — a sibling deck's game-design corpus — were removed from this branch
for the same reason as the two above.

---

## Not in the handoff

**`scripts/archive/` is not documentation.** It is a historical research corpus at the
repository root — roughly 300 files of cluster-pilot extraction briefs, per-model findings,
and reconciliations from April to September 2026 — retained deliberately as reference for
future agents and maintainers, because the reasoning trail it preserves is expensive to
reconstruct. It is **not** the same thing as `docs/archive/`.

The directory is **gitignored**, so new files there are not added to version control, while
files tracked from earlier work remain tracked. A boundary pass replacing local paths and
private infrastructure references with placeholders was run over working-tree copies, but it
was not staged or committed, so the corpus as carried in this repository should be treated as
**not boundary-reviewed**.
[`SCRIPTS-RESEARCH-ARCHIVE.md`](SCRIPTS-RESEARCH-ARCHIVE.md) explains the corpus, why it was
kept, and what a future decision to share it would require. **That document is current
reference, not archived history** — it describes a boundary that applies today, which is why
it sits in `docs/` rather than in `docs/archive/`.

Nothing in this documentation set links into it, newcomers have no reason to read it, and
where an archived conclusion disagrees with a current document, the current document wins.

**Deliberately excluded content.** These documents do not contain, and must not acquire:
credentials, passwords, API keys, tokens, MFA seeds, database URLs with passwords, or
billing detail; individual contributors' local development setups, personal machine paths,
local ports, local container configurations, or personal backup runbooks; internal relay and
orchestration tooling. `ONBOARDING.md` §9 is the authoritative statement of that boundary.
Real access details come through the server-access handoff, which is a separate process.

---

## Canonical location

The preference for this project is that **canonical long-form documentation lives on a
wiki** — the Hyperon Wiki (`wiki.hyperon.dev`) or the Magi Archive — with the repository
holding a versioned bootstrap copy for people who do not yet have wiki or MCP access, and for
offline reading.

Two documents already work this way and say so in their own headers: `AGENT-READ-API.md` and
`AGENT-READ-YOUR-WRITES.md` both name the wiki card as the source of truth and ask you to
update the card rather than the file. That is the pattern to follow as more pages are
mirrored.

Until a given page has been published to a wiki, **the repository copy is the current
version**. Where a document names a canonical card, that card wins.

---

## Status markers

| Marker | Meaning |
|---|---|
| **current** | Believed accurate and maintained. |
| **current (draft)** | Accurate as far as it goes, but not yet reviewed or published; may carry its own unresolved notes. |
| **template** | A generic Decko/Rails procedure carried over from a sibling deck, fully parameterized with `<placeholder>` values. The procedure is reusable; every concrete value comes from the server-access handoff. |
| **historical** | Describes a completed phase, a past investigation, or a superseded plan. Kept for the record, in [`archive/`](archive/). |
| *(to be confirmed)* | Not yet verified against the running production system. |

---

## Follow-up tasks

Tracked here so they are not forgotten. These are **open work items**, not descriptions of
the current state.

### 1. Finish or retire the inherited templates

These were previously tracked as one decision about three documents. They are now three
separate decisions, because the documents differ in how much this repository actually
depends on them. [`OPERATIONS.md`](OPERATIONS.md) now exists as the this-wiki runbook they
were meant to feed into, and each item below says what would close it.

**1a. `operations/DECKO-DATABASE-ACCESS.md` — verify, then drop the banner.**
Load-bearing: [`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md) points at it for the
`decko runner` remote-console procedure the Ruby ingesters depend on. The procedure is sound
and reusable; what is missing is confirmation against *this* deployment — the rbenv shim path
shape, the production environment file, and `script/card runner` behaviour. **Needs server
access.** Record that the procedure was confirmed; keep the values in the access handoff.

**1b. `operations/EMAIL_SETUP.md` — confirm the provider, then rewrite around it.**
Load-bearing: referenced from [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §1f,
the path an administrator follows when signup verification email is failing. One fact —
which SMTP provider this wiki uses — collapses four generic options into a real document.
**Needs server access.** The provider name may be recorded; credentials never.

**1c. `AWS-DEPLOYMENT.md` — retired, done.** The EC2 and RDS walkthrough now lives in
[`archive/AWS-DEPLOYMENT.md`](archive/AWS-DEPLOYMENT.md). It described standing up a new
deployment from scratch on a platform this wiki already runs on, and nothing in the
documentation depended on it beyond a single environment note, which has been restated
directly where it was used. No further action.

**Until a document has actually been updated and verified, its banner stays.** Removing the
label is the last step, not the first.

### 2. Review the private/local boundary before publication or handoff

`ONBOARDING.md` §9 defines what is deliberately excluded from these docs. That boundary
should get a final read-through immediately before this documentation set is published to a
wiki or handed to an external party, since the risk of something private leaking in grows
with every editing pass.

### 3. Align AtomSpace read access with the Raw Data Analyst role

The `Raw Data Analyst` role is intended for researchers who need AtomSpace backend access for
their own experiments, and the broad `RawData` read access it carries follows from that
intent. The current code does not connect the two: the AtomSpace read API is gated by an
explicit `mcp:atomspace:read` scope granted per principal, deliberately not derived from any
role, and failing closed when nothing is configured.

Both statements are accurate — one is product intent, the other is current implementation.
Someone should decide whether the scope should become role-derived, and either implement that
or record the explicit-grant model as the intended design. Until then, granting the role does
**not** grant AtomSpace access, and operators should expect to arrange the two separately.

### 4. Write the missing documents

See [Planned, not yet written](#planned-not-yet-written) below.

### 5. Decide what happens to the two agent-read pointer files

[`AGENT-READ-API.md`](AGENT-READ-API.md) and
[`AGENT-READ-YOUR-WRITES.md`](AGENT-READ-YOUR-WRITES.md) are pointers with no content of
their own. Each names a canonical card held on an internal source wiki and **not published
to `wiki.hyperon.dev`**, so the material is unreachable to anyone without internal access.
Both were annotated during Phase 5 to say so plainly; the underlying decision was
deliberately left open and is **not** closed by that annotation.

Four options, and none is blocked by the others:

- **Mirror the content into these files**, keeping the card named as the source of truth.
  This is what the canonical-location policy above already describes — a repository copy for
  people without wiki or MCP access is the intended shape, not an exception to it. Needs a
  decision that the content is appropriate for this SNET-facing branch.
- **Publish the cards to `wiki.hyperon.dev`**, then link or mirror. Note that publishing
  alone leaves these files empty; it makes the content reachable online but gives the
  repository no offline copy. It is an independent choice about where canonical content
  lives, not a prerequisite for the option above.
- **Retire the stubs** and record the gap. More work than it looks: both are cited as the
  worked example of the canonical-location pattern in `../ONBOARDING.md` and in this
  document, so retiring them means rewriting that explanation as well.
- **Leave them as they are**, annotated. The current state.

**What the gap costs is not known.** The AtomSpace mirror being unactivated does not
establish that nobody needs this material — someone developing against the mirror,
onboarding to that subsystem, or planning activation may be held up by it. If that is you,
say so; that is the evidence this decision is missing.

---

## Planned, not yet written

Identified as missing during the onboarding review. Listed so the gap is visible rather than
discovered again later. **These files do not exist yet** — do not link to them as though they
do.

| Planned document | Would cover |
|---|---|
| `EDITORIAL-WORKFLOW.md` | A standalone editor-facing narrative of Stage A → B → C, with the **full card-name contract** (`+proposal`, `+base`, `+provenance`, `+mode`, `+merge draft`, `+audit`) — the part still missing. The narrative itself is now in `ONBOARDING.md` §4 and [`FEATURE-PRIMERS.md`](FEATURE-PRIMERS.md) §5. |
| `REVIEW-QUEUE-GUIDE.md` | A reviewer's task guide: reading the workbench banners and conflict bands, and **recovering when the parent moved mid-review** — the part still missing. The day-to-day loop and verification habits are now in [`ROLE-BASED-ONBOARDING.md`](ROLE-BASED-ONBOARDING.md) → Editor / reviewer. |
| `CONTENT-MODEL.md` | The cardtypes, index conventions, and tag vocabulary **in full**. Introduced in `ONBOARDING.md` §3 and §5 and in [`FEATURE-PRIMERS.md`](FEATURE-PRIMERS.md) §1–§3 and §6; a complete reference is still missing. Roles are covered in [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md), not here. |
| `HISTORY-AND-ROLLBACK.md` | A feature-level walkthrough of Decko's card history and rollback: reading a card's revisions, reverting a bad edit, and what history means for content that should never have been visible. Referenced as a gap by [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §2 and introduced at primer depth in [`FEATURE-PRIMERS.md`](FEATURE-PRIMERS.md) §10. |
| `ARCHITECTURE.md` | One section per mod, with the read path and the write path drawn separately. |
| `DECKO-GOTCHAS.md` | The hard-won Decko rules currently scattered across source comments — compound-card naming behaviour, set-loading constraints, event-stage behaviour on API paths, and asset-pipeline traps. |

---

## Reorganization phases

A record of how this documentation set reached its current shape. **All five phases are
complete**; every path in this document is current. Remaining open work is tracked under
[Follow-up tasks](#follow-up-tasks) and [Planned, not yet written](#planned-not-yet-written)
rather than as an unfinished phase.

| Phase | What it did |
|---|---|
| 1 | **Done.** This map was rewritten from a by-audience index into the tiered structure above, leading with a five-document *Read these first* path. An empty `TODO.md` was removed. No files moved. |
| 2 | **Done.** The nine WS6 documents now live in [`merge-editor/`](merge-editor/), with references updated across the documentation set and the `editorial_review` mod's source comments. `docs/` dropped from 24 files to 15. |
| 3 | **Done.** The two AtomSpace documents now live in [`atomspace/`](atomspace/) and the three inherited templates in [`operations/`](operations/), with references updated across the documentation, the `mcp_api` mod, the `Gemfile`, and the systemd unit examples. `docs/` dropped from 15 files to 10. The two pointer-only `AGENT-READ-*` files were left in place pending the Phase 5 decision. |
| 4 | **Done.** The single-file `archive/fixes/` directory was flattened into [`archive/`](archive/), and `SCRIPTS-RESEARCH-ARCHIVE.md` moved out of the historical archive to [`SCRIPTS-RESEARCH-ARCHIVE.md`](SCRIPTS-RESEARCH-ARCHIVE.md), since it describes a current boundary rather than recording something that finished. |
| 5 | **Done.** Decisions rather than moves. The two pointer-only `AGENT-READ-*` files were kept and annotated with an honest statement of the content gap; what to do about their canonical cards remains open as [Follow-up task 5](#5-decide-what-happens-to-the-two-agent-read-pointer-files). [`OPERATIONS.md`](OPERATIONS.md) was created as a skeleton of confirmed facts with explicit server-access gaps. The single inherited-template follow-up was split into per-document decisions (1a, 1b, 1c). The EC2 and RDS walkthrough was retired to [`archive/AWS-DEPLOYMENT.md`](archive/AWS-DEPLOYMENT.md), with its nine inbound references updated. `docs/` holds 12 files. |

Every move used **plain filesystem operations, deliberately not `git mv`**, so nothing is
staged while the reorganization awaits review. Git records each move as a delete plus an add
until the changes are staged together, at which point it detects the rename and history
follows the file. Every reference was updated and verified with a link check in the same
change.

---

## A note on maintaining this map

When you add a document, add a row here, in the tier where a reader would look for it. When a
document stops being true, mark it *historical* with a one-line reason rather than deleting it
— the record of what was believed, and when, has repeatedly turned out to be worth more than
a tidy directory.

When you finish a rewrite listed under [Follow-up tasks](#follow-up-tasks), update the row
*and* remove the warning from the document itself. A warning that outlives the problem
teaches people to ignore warnings.
