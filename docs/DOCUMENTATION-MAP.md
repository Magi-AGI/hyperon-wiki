# Documentation Map

An index of the documentation in this repository, grouped by who needs it. Use this page
to find the right document instead of browsing `docs/` directly — filenames alone do not
tell you whether a document is current, a generic template, or a completed phase record.
Completed records live in [`archive/`](archive/).

**New here?** Read [`../ONBOARDING.md`](../ONBOARDING.md) first.

> **Naming note.** This file is the *documentation map*. The repository root
> [`../README.md`](../README.md) is the conventional *developer guide*. They were briefly
> both named `README.md`; this one was renamed so the two are never confused in a link or
> a conversation.

---

## Canonical location

The preference for this project is that **canonical long-form documentation lives on a
wiki** — the Hyperon Wiki (`wiki.hyperon.dev`) or the Magi Archive — with the repository
holding a versioned bootstrap copy for people who do not yet have wiki or MCP access, and
for offline reading.

Some documents already work this way and say so in their own headers: `AGENT-READ-API.md`
and `AGENT-READ-YOUR-WRITES.md` both open by naming the wiki card as the source of truth
and asking you to update the card rather than the file. That is the pattern to follow as
more pages are mirrored.

Until a given page has been published to a wiki, **the repository copy is the current
version**. Where a document names a canonical card, that card wins.

---

## Legend

| Marker | Meaning |
|---|---|
| **current** | Believed accurate and maintained. |
| **historical** | Describes a completed phase, a past investigation, or a superseded plan. Kept for the record, in [`archive/`](archive/). It may read as current — check the date before acting on it. |
| **template** | A generic Decko/Rails procedure carried over from a sibling deck, now fully parameterized with `<placeholder>` values. The *procedure* is reusable; every concrete value must come from the server-access handoff. |
| *(to be confirmed)* | Not yet verified against the running production system. |

Historical documents were moved to [`archive/`](archive/) rather than deleted. Documents
that described a *different product* — a sibling deck's game-design corpus — were removed
from this branch; they remain in git history and in that deck's own repository.

---

## Follow-up tasks

Tracked here so they are not forgotten. These are **open work items**, not descriptions of
the current state.

### 1. Finish or retire the remaining inherited templates

Three documents survive as parameterized generic templates. They are safe to read — all
sibling infrastructure has been replaced with placeholders — but they have not been
rewritten to describe *this* wiki. Each should either be made Hyperon-specific and
verified, or folded into the planned `OPERATIONS.md` and retired.

| Document | Remaining work |
|---|---|
| [`AWS-DEPLOYMENT.md`](AWS-DEPLOYMENT.md) | Generic EC2 + RDS walkthrough. Decide whether this wiki wants its own deployment doc or whether `OPERATIONS.md` supersedes it. |
| [`DECKO-DATABASE-ACCESS.md`](DECKO-DATABASE-ACCESS.md) | The remote-console procedure is sound and reusable. Confirm it against this wiki's deployment and drop the template banner. |
| [`EMAIL_SETUP.md`](EMAIL_SETUP.md) | Generic SMTP provider guidance. Confirm which provider this wiki uses and rewrite around it. |

**Until a document has actually been updated and verified, its banner stays.** Removing the
label is the last step, not the first.

### 2. Review the private/local boundary before publication or handoff

`ONBOARDING.md` §9 defines what is deliberately excluded from these docs — secrets,
personal local setups, internal orchestration tooling. That boundary should get a final
read-through immediately before this documentation set is published to a wiki or handed to
an external party, since the risk of something private leaking in grows with every editing
pass.

### 3. Write the missing documents

See [Planned, not yet written](#planned-not-yet-written) below.

---

## Start here / current

| Document | What it covers | Status |
|---|---|---|
| [`../ONBOARDING.md`](../ONBOARDING.md) | Front door: content model, roles, editorial workflow, trust markers, audience paths. | current (draft) |
| [`../README.md`](../README.md) | Developer guide: setup, running, testing, mods, Decko gotchas, UI layout. | current |
| `DOCUMENTATION-MAP.md` (this file) | The documentation map. | current (draft) |
| [`DELIVERABLES-SCOPE-MAPPING.md`](DELIVERABLES-SCOPE-MAPPING.md) | Handoff status map: each described Phase 1 deliverable against what is observably present in the running system, plus later-proposed and future scope kept separate, and the open follow-ups. Useful for anyone taking the system over and wanting to know what exists versus what is still an open decision. | current |
| [`FEATURES-AND-COMPONENTS.md`](FEATURES-AND-COMPONENTS.md) | Feature/component reference for newcomers and SNET technical owners: base Decko concepts and Hyperon-specific features, each with what/who/where/status/verify. | current (draft) |

---

## Editor / reviewer

The day-to-day editorial experience is described in [`../ONBOARDING.md`](../ONBOARDING.md)
§4 and §5. The specifications below are the authoritative detail behind it.

| Document | What it covers | Status |
|---|---|---|
| [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) | Administrator onboarding (first-admin bootstrap vs. current production handoff), how accounts and roles are created/assigned/verified, and per-role workflows for Editor, Raw Data Analyst, Expert, AI agent/MCP operator, and the operator/SNET technical-owner function. Includes the live permission matrix and its seed-vs-production caveat. | current |
| [`ws6-merge-editor-design.md`](ws6-merge-editor-design.md) | **The design document for the merge workflow.** Why `+proposal` exists and is separate from `+AI`; the three-way merge model; the human-approval governance rule. The single best explanation of how editing actually works. | current |
| [`ws6-merge-editor-phase4-ui-contract.md`](ws6-merge-editor-phase4-ui-contract.md) | The merge workbench interface contract — panes, hunks, payload shape. | current |
| [`ws6-merge-editor-phase6-apply-gate.md`](ws6-merge-editor-phase6-apply-gate.md) | The verification gate that runs before a merge touches a published card. | current |
| [`ws6-merge-editor-phase5-tinymce-gate.md`](ws6-merge-editor-phase5-tinymce-gate.md) | The polish step and why the merge draft is kept separate from the proposal. | current |
| [`ws6-merge-editor-phase8-capability-gating.md`](ws6-merge-editor-phase8-capability-gating.md) | Permission gating for merge actions. | current |
| [`DECKO-SECTION-PATTERN.md`](DECKO-SECTION-PATTERN.md) | The hierarchical section pattern used for structured articles. | current |

The May 2026 content usability pass (inventory, checklist, audit log) is a useful worked
example of a review pass and now lives in [`archive/`](archive/).

Also see `mod/review_queue_ui/README.md` for Review Queue behaviour, and
`mod/editorial_review/` for the workflow implementation — its source files carry detailed
rationale comments, and `mod/editorial_review/data/real.yml` is where cardtypes, roles,
codenames, and tag vocabulary are declared.

---

## AI / MCP

| Document | What it covers | Status |
|---|---|---|
| `mod/mcp_api/README.md` | The MCP API mod: authentication, roles, CRUD, search, batch operations, rate limiting. | current |
| [`AGENT-READ-API.md`](AGENT-READ-API.md) | AtomSpace mirror agent read API. **Canonical version is a wiki card**, named in the file header. | current (mirror) |
| [`AGENT-READ-YOUR-WRITES.md`](AGENT-READ-YOUR-WRITES.md) | Read-your-writes consistency for agents. **Canonical version is a wiki card**, named in the file header. | current (mirror) |

The `mcp_api` build-out record — phase plans, completion notes, and the phase-2 testing
guide — is in [`archive/`](archive/).

**Client setup for the wiki's MCP server lives in the separate `hyperon-wiki-mcp`
repository** — <https://github.com/Magi-AGI/hyperon-wiki-mcp> — not here. That repo holds the per-client installers and profile documents
(Claude, Codex, Gemini, ChatGPT), the tool specification, operations notes, and a
known-quirks list. Claude, Codex, and Gemini/agy are the paths with months of production
use behind them.

---

## Operator / admin

Read the status column carefully. The three **template** files carry generic procedures
with `<placeholder>` values throughout — real hosts, keys, endpoints, and paths come from
the server-access handoff (the Administrator card and its children), never from a
repository file.

| Document | What it covers | Status |
|---|---|---|
| [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) | Administrator onboarding and account/role assignment — the section an operator or SNET technical owner needs to grant the first accounts and confirm the live permission matrix. Also indexed under Editor / reviewer above. | current |
| [`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md) | The Stage A ingestion tooling: the script inventory grouped by source family, the two-stage export/ingest model, the `HYPERON_WIKI_*` host/key variables, what an operator must supply out-of-band, and a safe first-run posture. | current |
| [`ATOMSPACE-MIRROR-DEPLOYMENT.md`](ATOMSPACE-MIRROR-DEPLOYMENT.md) | Deployment and operations runbook for the Decko → Hyperon AtomSpace write-through mirror. Names its canonical wiki cards. | current |
| [`DECKO-DATABASE-ACCESS.md`](DECKO-DATABASE-ACCESS.md) | Running Decko/ActiveRecord scripts against a deck via remote console: environment bootstrap, `script/card runner`, quoting, Windows and Linux stdin workflows, troubleshooting. | template — see [Follow-up tasks](#follow-up-tasks) item 1 |
| [`AWS-DEPLOYMENT.md`](AWS-DEPLOYMENT.md) | EC2 + RDS deployment walkthrough: server preparation, application server, TLS, backups, deploy procedure, troubleshooting. | template — see [Follow-up tasks](#follow-up-tasks) item 1 |
| [`EMAIL_SETUP.md`](EMAIL_SETUP.md) | SMTP configuration for a Decko deck: provider options, environment variables, verification. | template — see [Follow-up tasks](#follow-up-tasks) item 1 |

A file-upload bug investigation is in [`archive/`](archive/) — **its fix may still be
load-bearing**, so check before removing anything it describes.

Deployment basics — the code-versus-cards distinction and the code-before-cards ordering
rule — are in the root [`../README.md`](../README.md) and summarized in
[`../ONBOARDING.md`](../ONBOARDING.md) §7.

---

## Developer / architecture

| Document | What it covers | Status |
|---|---|---|
| [`ws6-merge-editor-impl-plan.md`](ws6-merge-editor-impl-plan.md) | Implementation plan for the merge editor — the phased build behind the design document. | current |
| [`ws6-merge-editor-phase7-plan.md`](ws6-merge-editor-phase7-plan.md) | Lifecycle, entry points, and the legacy `+AI` bridge. Explains why two paths coexist during the phase-out. | current |
| [`ws6-merge-editor-phase4_1-ribbons.md`](ws6-merge-editor-phase4_1-ribbons.md) | Workbench visual design note — connector ribbons and resizable bands. | current |
| [`ws6-merge-editor-prod-deploy-notes.md`](ws6-merge-editor-prod-deploy-notes.md) | Production deploy and migration notes for the merge editor. | current |
| [`ATOMSPACE-INTEGRATION.md`](ATOMSPACE-INTEGRATION.md) | AtomSpace backend integration architecture. **Self-described as a conceptual sketch** — its own header warns that code blocks are not necessarily runnable. Read that warning first. | current, explicitly aspirational |
| [`../CLAUDE.md`](../CLAUDE.md) | Agent guide: what this repository is, the two deploy layers, working rules for agents writing to the wiki, and codebase orientation. | current |
| [`../AGENTS.md`](../AGENTS.md) | Repository conventions: structure, build/test commands, coding style, testing, commit and PR guidelines. | current |

Shipped-fix records (URL parsing, right-hand column plan, one merge-editor PR summary) are
in [`archive/`](archive/). An email-verification fix summary was **retired** rather than
archived — see the Archive section below.

The root [`../README.md`](../README.md) holds the practical developer material: mod
structure, adding a mod, overriding a view, the testing tracks, and a table of Decko
pitfalls worth reading before your first change.

---

## Archive

[`archive/`](archive/) holds completed phase records and shipped-fix write-ups: the
`mcp_api` build-out, the May 2026 usability pass, the URL-parsing fix, the file-upload bug
investigation, the right-column plan, and one merge-editor PR summary.
[`archive/README.md`](archive/README.md) indexes them.

**Two records were retired, not archived** — an MCP deployment-status snapshot and an
email-verification fix summary. Both documented a sibling deck's production server and
carried its host, service account, and key details, so they were removed from this branch
entirely. They are not in `archive/`; they survive only in git history and in that deck's
own repository.

Nothing in the newcomer path points there. Read anything in it as a record of what was
believed at the time, not as instructions.

### What this map does *not* cover

`docs/archive/` is the documentation archive. It is **not** the same thing as
`scripts/archive/` at the repository root.

`scripts/archive/` holds a historical research corpus — roughly 300 files of cluster-pilot
extraction briefs, per-model findings, and reconciliations from April to September 2026. It
is **retained deliberately** as reference for future agents and maintainers: the reasoning
trail it preserves is expensive to reconstruct.

The directory is **gitignored**, so new files there are not added to version control, while
files tracked from earlier work remain tracked. A boundary pass replacing local paths and
private infrastructure references with placeholders was run over working-tree copies, but it
was not staged or committed, so the corpus as carried in this repository should be treated as
**not boundary-reviewed**.
[`archive/SCRIPTS-RESEARCH-ARCHIVE.md`](archive/SCRIPTS-RESEARCH-ARCHIVE.md) explains the
corpus, why it was kept, and what a future decision to share it would require.

It remains **not part of the SNET-facing documentation handoff package**. Nothing in this
documentation set links into it, newcomers have no reason to read it, and where an archived
conclusion disagrees with a current document, the current document wins.

---

## Planned, not yet written

Identified as missing during the onboarding review. Listed so the gap is visible rather
than discovered again later. **These files do not exist yet** — do not link to them as
though they do.

| Planned document | Would cover |
|---|---|
| `EDITORIAL-WORKFLOW.md` | A standalone editor-facing narrative of Stage A → B → C, with the full card-name contract (`+proposal`, `+base`, `+provenance`, `+mode`, `+merge draft`, `+audit`). Currently condensed into `ONBOARDING.md` §4. |
| `REVIEW-QUEUE-GUIDE.md` | A reviewer's task guide: reading the workbench banners and conflict bands, and recovering when the parent moved mid-review. |
| `CONTENT-MODEL.md` | The cardtypes, the index conventions, and the tag vocabulary in full. Currently condensed into `ONBOARDING.md` §3 and §5. Roles are covered in [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md), not here. |
| `ARCHITECTURE.md` | One section per mod, with the read path and the write path drawn separately. |
| `DECKO-GOTCHAS.md` | The hard-won Decko rules currently scattered across source comments — compound-card naming behaviour, set-loading constraints, event-stage behaviour on API paths, and asset-pipeline traps. |
| `OPERATIONS.md` | A this-wiki operator runbook, replacing reliance on the inherited deployment docs above. |

---

## A note on maintaining this map

When you add a document, add a row here. When a document stops being true, mark it
*historical* with a one-line reason rather than deleting it — the record of what was
believed, and when, has repeatedly turned out to be worth more than a tidy directory.

When you finish a rewrite listed under [Follow-up tasks](#follow-up-tasks), update the row
*and* remove the warning from the document itself. A warning that outlives the problem
teaches people to ignore warnings.
