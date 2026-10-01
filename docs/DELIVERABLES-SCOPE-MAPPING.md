# Hyperon Wiki — Built-Work Record and Deliverables Mapping

> **Draft, for handoff review.** This document maps the terms described across the Hyperon
> Wiki engagement to the work that is currently evidenced as built, so that whoever operates
> the wiki next can see what exists, what it maps to, how to use it, and what remains open.
>
> It transfers no credentials and no access. Server access, source-service tokens, and
> account transfer are handled through a separate access handover and are deliberately not
> present in these files. Nothing here describes private or local support infrastructure.
>
> Where this document and the running system disagree, the running system is correct.

---

## How to read this document

### Source strata

Terms come from four sources, which carry different weight and are kept apart:

| Stratum | What it is | Standing |
|---|---|---|
| **Contract 1** | The $16,000 three-week option, its informal bullet terms, and the formal Phase 1 RFP | Paid. This is the baseline under which the Hyperon Wiki work is being handed over |
| **Contract 2** | The remaining $29,000 of the original $45,000 two-month option | Proposed; not accepted or signed |
| **Contract 3** | First month of a later $30,000 two-contract proposal, labelled in its own source text as "Contract 1 — Month 1: Build" | Proposed; not accepted or signed |
| **Contract 4** | Second month of the same proposal, labelled in its own source text as "Contract 2 — Month 2: Clean, Content & Handover" | Proposed; not accepted or signed |

Contracts 2, 3, and 4 are included because they are the clearest written statements of the
scope that was discussed after the paid baseline, and because a good deal of work relevant
to them was built. They are listed to show what was and was not completed relative to those
discussions. They do not redefine the paid baseline, and nothing in this document treats
them as binding obligations.

### Status labels

| Label | Meaning |
|---|---|
| **Built and operating** | Present and in use; verifiable today |
| **Built and operating, with limits** | Present and in use, but narrower than the source wording; the limit is stated |
| **Partially built** | Some clauses of the term are built and others are not; the split is stated per clause |
| **Built by a different means** | The outcome the term described is achieved, through a different mechanism than the one described |
| **Designed, not built** | A design record or specification exists; the implementation does not |
| **Not built / not evidenced** | No implementation found in the reviewed repositories, documentation, wikis, or source material |
| **Not performed** | Used for terms that describe an activity rather than an artifact |
| **Unverified** | Neither demonstrated nor ruled out by the checks performed |

No status implies acceptance, and no status implies a payment obligation.

Negative findings are stated as "not evidenced in reviewed sources." That is a statement
about what these checks found, not a claim that no such work exists anywhere.

Card counts and live observations are point-in-time and will change as work continues.

---

## Executive summary

**The paid Contract 1 platform is built and operating.** The wiki is deployed and public at
`wiki.hyperon.dev`, with accounts, history, index navigation, and the standard Decko
authoring layer. The MCP tool is deployed and has been in reliable use for months from
Claude, Codex, and Gemini/agy. The Master Index taxonomy is present as structured index
cards. The editorial state model exists: Draft and Published cardtypes, a review queue,
approval metadata, trust markers, and an expert endorsement action. Basic source and trust
labelling is automated. Documentation existed only as a minimal technical baseline at the
first-contract checkpoint and is being completed now.

**Substantial work was built above that baseline.** A content corpus of Primer and Deep Dive
articles across the Hyperon algorithm, application, and ecosystem areas. A proposal and
merge workbench with base and provenance records, three-way merge, a verifying apply gate,
and merge audit records. Ingestion connectors for chat archives, meeting transcripts, and
publications, reconciled against what is deployed. A Wiki Assistant chat panel and a MeTTa
Playground on the live site. An experimental AtomSpace mirror and sidecar foundation. The
documentation package this file belongs to.

**Several proposed areas were not built, and this record says so plainly.** The two-tier
private staging plus born-clean public wiki was not built. The content-safety cleaning
pipeline with a local model on Magi hardware was not built. The migration of curated content
into a clean wiki did not occur, because there was no clean wiki to migrate into. Cleaning
calibration with SNET was not performed. The Zoom and Google Meet meeting note-taker was not
built. Dedicated model training was not delivered. The handover itself — final publication,
packaging, and access transfer — has not been executed.

The most useful way to read the later proposals is that they split in two. The
store-and-clean subproject was not launched. The ingestion and editorial work around it was
substantially built and is running today.

---

## Contract 1 — paid $16,000 three-week baseline

| Term | Status | What was built | Limits / handoff notes |
|---|---|---|---|
| **D1. Hyperon Wiki Site.** A functional wiki covering the Hyperon ecosystem at a high level | Built and operating | The wiki is deployed and public at `wiki.hyperon.dev`. It supports the standard Decko affordances: sign-up and sign-in, user accounts, article creation and editing, edits associated with accounts, retained revision history, and index navigation into topic and article pages. Live card types include `User`, `Role`, `Sign up`, `History`, `Draft`, `Published`, `IndexSection`, `IndexSubtopic`, and `Search`. Account email and Recaptcha infrastructure is configured in the application | `wiki.hyperon.dev` is the wiki; `hyperon.dev` is the separate Hyperon landing site. That split is the intended arrangement, not a gap. Deeper workflow, content depth, assistant, playground, and AtomSpace work are recorded in their own rows. A fresh end-to-end sign-up and email smoke test was not run during this documentation pass |
| **D2. Content Versioning System.** Expert-reviewed entries with AI draft updates and a merge workflow | Built and operating, with limits; later strengthened | Two pieces exist. Decko provides inspectable revision history for every card, with actors, dates, and changed fields. On top of that sits an editorial state model: `Draft` and `Published` cardtypes, approval metadata (`+approved by`, `+approved at`), expert endorsement metadata (`+expert approved by`, `+expert approved at`), and trust tags. AI and source-derived material is routed through review rather than written straight into published content. Later work added the `<Card>+proposal` convention and merge workbench: base and provenance sidecards, a three-way base/current/proposal view, a separate merge draft, hash and optimistic-lock checks, and merge audit records | The published body is protected by workflow and policy rather than by a hard technical lock; the proposal route is the intended path for changing published content, and the permission configuration on the target wiki should be confirmed before relying on it as an access control. Applying a merge does not refresh expert endorsement; expert approval is a separate action. The merge workbench is later strengthening above the first-contract expectation, not part of the baseline |
| **D3. Transcript Ingestion Pipeline.** Manual and automated transcript processing into proposed edits | Partially built | What existed was an operator-driven path from source material to proposed content: RawData source categories on the wiki, export and ingestion scripts for meeting transcripts and chat archives, a standard transcript JSON format, ingestion into RawData cards through the Decko runner, and a human and agent assisted route from RawData into drafts and proposals. Live `RawData+mattermost` and `RawData+transcripts` parents date from early April 2026, with transcript records created at the same time | This is not continuous folder-watch ingestion, automatic cleanup, or automatic incorporation into published entries. Productionization — scheduled runs, service accounts, logging and health checks, a staging tier, and cleaning — belongs to the later proposal rows in Contract 3. The meeting note-taker path depended on SNET-provided meeting access that is not evidenced as arranged |
| **D4. MCP Tool.** Search and content creation integrated with major AI assistants | Built and operating | The wiki exposes a standard MCP-compatible tool server supporting search, read, and query operations alongside card creation and update. It has been in sustained, reliable production use for months from Claude, Codex, and Gemini/agy. Later work hardened the integration, expanded and verified the tool surface, and connected MCP workflows to the proposal and merge workbench | Gemini's web interface does not accept MCP tools; the CLI path does. Per-client setup, the tool specification, and a known-quirks list live in the separate `hyperon-wiki-mcp` repository and should travel with the handoff |
| **D5. Tagging & Labeling Engine.** Automatic classification by source type and topic | Built and operating for source and trust labels; topic classification assisted rather than automatic | A controlled marker vocabulary is declared in the editorial mod: `ai generated`, `ai reviewed`, `human authored`, `transcript derived`, `needs review`, `human approved`, and `expert approved`. Assignment is automated at the workflow points that matter: creating a Draft adds `needs review`; publication adds `human approved` and removes `needs review`; expert endorsement adds `expert approved`. Live cards carry `<Card>+tag` Pointer cards, rendered in the card UI. Topic and category organization is carried by the Master Index taxonomy through `IndexSection` and `IndexSubtopic` placement | Robust fully automatic semantic topic classification was attempted but was not reliable, and should not be read into this row. Topic placement is curated, or assisted by an agent, rather than classifier-driven. Prominent top-of-card trust banners, contributor and person attribution, and richer source association are later work above the baseline |
| **D6. Expert Review Queue.** Oldest-first review surface with an expert approval seal | Built and operating | `Review Queue` exists as a Decko Search card listing Draft cards, sorted by creation date ascending. Draft cards render an **Approve & Publish** action for signed-in users. Publication stamps `+approved by` and `+approved at`, adds `human approved`, and removes `needs review`. Holders of the `Expert` role see an **Expert Approve** action that stamps expert metadata, adds the `expert approved` tag, and renders a visible Expert Approved indicator. `Editorial Sidebar Nav` links to the queue | The queue is fundamentally an editor-facing surface for working through unreviewed content. Domain experts endorse specific cards case-by-case once content is ready, rather than working one undifferentiated backlog; experts are typically expert in particular areas. The queue has since been widened beyond the baseline: its current live query also surfaces cards carrying a `+proposal` that has not yet been merged, so the queue covers agent-authored change requests as well as Drafts. That is later strengthening, not part of the Contract 1 baseline described here. The rendered ordering was not re-checked in a browser during this pass, though the query specifies ascending creation order. Reject, request-edits, and merge actions, and the audit machinery, are later strengthening rather than baseline |
| **D7. Documentation.** Technical documentation, administrator guide, reviewer onboarding | Partially built at the baseline; substantially strengthened later | At the first-contract checkpoint there was a minimal baseline: repository README and technical notes, mod-level notes for the MCP API and review queue UI, and detailed rationale comments in source files. That was enough for a maintainer or an agent-assisted operator to reconstruct how the system worked. It was not a newcomer-oriented onboarding package | The fuller documentation package is being completed now and is recorded under Contract 4 D3. The gap at the first-contract checkpoint is recorded here as a real one rather than presented as delivered |
| **D8. Master Index Import.** Bulk import of the Hyperon Master Index as the taxonomy backbone | Built and operating for the taxonomy baseline; later strengthened | The Hyperon Master Index is represented on the wiki as top-level section cards and subtopic cards, forming the taxonomy backbone. Live `IndexSection` cards include `MeTTa Programming Language`, `Knowledge Representations`, `Hyperon AI Algorithms`, `Cognitive Architecture & Research`, and `ASI:Chain Runtime Environment`, with `IndexSubtopic` children beneath them. The live sidebar renders these as collapsible sections with nested subtopic links | The original import was careful manual work rather than a productionized bulk-import tool. The Master Index text was preserved word-for-word, including errors or omissions in the supplied reference, because the index was to be represented as written; the first-pass additions were Primer and Deep Dive links. The typed `IndexSection` / `IndexSubtopic` card types and the polished navigation and design-matching layer came later, in response to post-contract feedback. The current text and UI match the references and feedback supplied, to the best of our knowledge; if SNET identifies a newer authoritative Master Index, updating against it is straightforward |

---

## Contract 2 — proposed $29,000 follow-up; not accepted

These terms were the Lake-authored follow-up to the paid baseline. They are recorded to show
which above-baseline work was built.

| Term | Status | What was built | Limits / handoff notes |
|---|---|---|---|
| **D1. Mid-to-high level detail on each SNET project and the wider ecosystem** | Partially built; substantially advanced | A first substantial content-population pass above the Master Index scaffold. The live wiki holds dozens of Deep Dive articles across MeTTa, PLN, PRIMUS, MORK, DAS, MetaMo, ECAN, ASI:Chain Runtime Environment, MOSES, AtomSpace, Semantic Parsing, TransWeave, WILLIAM, Self-Modification and Safety, AIRIS, NACE, AI-DSL, and MeTTa-NARS, plus published ecosystem and application cards. Primer articles were added later as onboarding expectations became clearer | This is not complete coverage of every SNET project, and it is not final domain-expert-approved content. The work was produced as best-effort AI-assisted and human-reviewed drafts on the assumption that SNET editors and domain experts would correct and complete it. Deep Dive content in particular was not accepted as final and should be treated as requiring domain-expert adjudication before it is relied on as a reference; the wiki's own trust markers already distinguish approved from unapproved material. Completeness and correctness depended on access to current SNET source material and people, specific content feedback, and reviewer participation |
| **D2. Distributed AtomSpace + MORK backend to enable research and self-improving intelligence loops** | Partially built as an experimental track; not a production backend | A real card-to-AtomSpace path exists. The AtomSpace Mirror mod encodes Decko card events into atoms with reference and provenance structure, backed by mirror tables and outbox, bootstrap, drain, and drift-reconciliation machinery. A Python Hyperon Space sidecar implements apply, bulk-load, and read/query operations over a real Hyperon space. An MCP and HTTP read surface exposes query, get, provenance, reference, type, and statistics endpoints behind readiness gates and scope checks. Work continues on the bidirectional layer | This term carried an explicit caveat in its own source text: extremely experimental, with no guarantees on full capability. That caveat travels with this row. A production Distributed AtomSpace or MORK-backed backend, a full symbolic perception pipeline, semantic parsing, and inference control are not complete and are not claimed. This track is separate from the ordinary live wiki product, and the wiki does not depend on it |
| **D3. In-app chat so the assistant can help from inside the wiki** | Built and operating, with scope limits | The Wiki Assistant is live: a right-column chat panel on the wiki, wired to an assistant endpoint backed by a Node sidecar that uses the Claude agent SDK together with the Hyperon Wiki MCP read tools. The public health endpoint reports healthy, and an end-to-end chat turn has returned a grounded answer from wiki content | This is a V1 navigation, search, and summarization aid. It is not a dedicated fine-tuned model and not a general wiki-editing agent. It falls back gracefully when the backend is unavailable |
| **D4. MeTTa Playground** *(additional feature built in the same workstream)* | Built and operating | A live right-column MeTTa Playground panel wired to a playground endpoint, backed by a FastAPI sidecar that evaluates submissions in a per-request Docker sandbox running a pinned Hyperon runtime. The public health endpoint reports healthy and identifies the runtime version and image. The sandbox runs with a read-only root filesystem, memory and process limits, dropped capabilities, and no privilege escalation | A V1 evaluator with ephemeral per-request state. It is not the persistent signed-in AtomSpace session design, which was deferred, and it is separate from the AtomSpace backend track in D2 |
| **D5. Dedicated model training on wiki content** | Not built / not evidenced | No fine-tuning or training implementation was found in the assistant, playground, or wiki repositories | What exists instead is the Wiki Assistant, which uses a general model together with MCP read tools over wiki content. That is real product value and a reasonable foundation for a future trained-model path, but it is a different thing and is not presented as this term |
| **D6. Ongoing maintenance and editorial work** | Workflow infrastructure built; ongoing service not active | The wiki includes what makes editorial maintenance possible: roles, review queue, trust markers, approval workflow, ingestion tooling, and documentation. Substantial maintenance and editorial work was performed during buildout and handoff | Ongoing maintenance is a continuing activity rather than an artifact that can be complete. No continuing maintenance arrangement is in place. Whoever owns the wiki will need to operate this themselves or arrange for it |
| **D7. Access to SNET workspace, drive, mailing lists, chat, publications, and people** | Collaboration dependency, not a build item | — | These were requests for access needed to populate and validate the wiki, not deliverables. They are recorded because they explain what full ecosystem coverage and domain-expert validation depended on. Tooling built to use the sources that were available is recorded in the ingestion rows |

---

## Contract 3 — proposed first month of a later $30,000 proposal; not accepted

| Term | Status | What was built | Limits / handoff notes |
|---|---|---|---|
| **D1. Productionize the existing ingestion scripts: deploy from version control, scheduled runs, logging and health checks, service accounts** | Partially built | The ingestion tooling is maintained in version control: 26 scripts covering export, ingest, and sync across chat archives, meeting transcripts, and publications, plus a shared Python pipeline package. A read-only comparison against the deployed host found 25 ingestion-related scripts there, all tracked in git and identical to the repository copies once line endings are normalized, so the deployed and repository tooling are the same artifacts. The Mattermost export path was made self-contained during this pass, removing a dependency on a separate repository. Offline regression tests cover the exporter and the sync wrappers' path handling and run without network access or credentials. Operator documentation is in `docs/INGESTION-WORKFLOWS.md` | Two clauses are not evidenced. Scheduled runs are documented — the server-side sync wrapper carries a cron entry in its setup comments — but no installed or running schedule was evidenced. Logging exists as start and finish output with a documented log redirect; no separate health-check or alerting mechanism was found. Service-account credentials are not evidenced: the wrappers accept a token from the environment but prompt if it is absent, and the setup comments still illustrate a personal access token. The tooling as built runs on demand, by an operator |
| **D2. Stand up the two-tier store: private staging plus a fresh born-clean public wiki** | Not built / not evidenced; one adjacent capability in place | — | The two-tier architecture was not built. The wiki runs as a single Decko instance; no separate staging instance and no rebuilt born-clean public wiki are evidenced in the reviewed sources, and the application environment configuration defines production, development, and test environments only. One property the staging tier was meant to provide does exist by a different mechanism: raw source material is held in `RawData` cards under role gating, so it is not publicly readable. That is a meaningful access control and is recorded as adjacent value. It is not a staging tier, and it does not address the born-clean requirement, which concerns what a public wiki's page history has ever contained and can only be satisfied by building fresh |
| **D3. Migrate the current wiki's curated non-raw content into the clean wiki** | Not built / not evidenced; the curated content exists in place | — | This was not performed as written. It depends on the clean public wiki in D2, which was not built, so there was no destination. No migration tooling or completed migration run is evidenced. The curated, non-raw content the term would have moved does exist on the current wiki: Published and Draft articles plus the `IndexSection` and `IndexSubtopic` taxonomy. Published and index content is publicly readable. Draft read-visibility depends on the current permission configuration and should be checked on the target wiki before relying on it either way. `RawData` remains permission-gated on the same instance. The separation between curated content and raw source material is therefore realized through cardtypes, trust states, and role gating on one wiki rather than through separate instances |
| **D4. Build the cleaning pipeline (rules plus a local AI model on Magi hardware)** | Not built / not evidenced | — | No content-safety cleaning pipeline was built. Searches across the wiki repository, this documentation branch, and the pipeline repository for cleaning, redaction, sanitization, span-level decision logging, sensitivity tuning, and local-model or GPU inference found no implementation. Unlike D2 and D3, this term did not depend on the clean wiki; a cleaning stage could have been built against the existing store, so the finding stands on its own. Two nearby components should not be read as partial coverage: the autolinker artifact cleaner repairs malformed HTML anchors in stored content, and the pipeline extractor performs rule-based topic and signal classification without redacting anything. The outcome this pipeline was meant to support is currently served by a different route: raw material stays permission-gated, and public content is human-reviewed synthesis rather than cleaned raw text |
| **D5. Connectors writing into staging: Mattermost, meeting transcripts, publications, and the meeting note-taker** | Partially built | Three of the four source families have working connectors. **Mattermost**: a self-contained exporter, a Decko-runner ingester writing complete, unfiltered RawData cards, sync wrappers chaining export, upload, and ingest, and a separate extractor for PDF attachments posted in channels. **Meeting transcripts**: a Fireflies exporter for full transcripts with speakers, timestamps, summaries, and action items; Otter paths in both API and manual-export forms; a Read.ai report parser; a shared module normalizing these into a common record; and a matching ingester and sync wrapper. **Publications and books**: fetchers that download and extract source text, and an ingester creating canonical publication RawData cards with provenance-aware bibliographic metadata, updating in place on re-run | The meeting note-taker for Zoom and Google Meet is not evidenced: no meeting-join mechanism, calendar integration, or post-meeting capture was found. The source term made this item conditional on SNET-provided access, and that access is likewise not evidenced as arranged; both facts are recorded, without asserting a relationship between them. "Writing into staging" could not be satisfied as written because the staging tier in D2 was not built; the connectors write to permission-gated RawData on the existing wiki instead. Otter depends on an unofficial API and account-level access, so it is less robust than Fireflies; Read.ai is a parser for exported report data rather than a live connector. Productionization caveats belong to D1 |
| **D6. Set up the editorial workflow: drafting, editor review, expert review, publish, using the wiki's existing review tooling** | Built and operating | The workflow is implemented in the wiki's own code and is in use. The editorial mod defines the Draft and Published cardtypes, the `Expert` role, approval and provenance sidecards, the trust-marker vocabulary, and the Review Queue. New material is authored as a Draft; publication stamps approval metadata and trust tags automatically and idempotently. For changes to published content, the `<Card>+proposal` convention records base revision and provenance at creation time inside the save transaction and keeps proposal hashes current; a reviewer works a three-pane base/current/proposal workbench, assembles a separate merge draft so the original proposal stays immutable, and applies through a gate that checks update permission, already-merged state, concurrent-edit drift, and content-hash integrity, re-deriving the merged text server-side from hunk selections before writing an audit record. Published cards render approval indicators, trust tags, and attribution | Expert review is implemented as an optional post-publication endorsement rather than a gate that blocks publication. That was the intended design. Approval stamps record who performed publication and do not by themselves establish that a second person independently reviewed the content. The Review Queue is a minimal listing surface rather than a task-management system. Seed-declared permissions and live production permissions should both be checked before relying on role boundaries operationally. The workflow provides tooling, not staffing |

---

## Contract 4 — proposed second month of the later proposal; not accepted

| Term | Status | What was built | Limits / handoff notes |
|---|---|---|---|
| **D1. Calibrate the cleaning: review sample output, tune sensitivity to approval, clean the raw corpus into the public wiki** | Not performed | — | This activity was not performed. It depends on two pieces recorded as not built: the cleaning pipeline in Contract 3 D4 and the clean public destination in Contract 3 D2. With no cleaning pipeline there was no sample output to review and no sensitivity to tune; with no clean public wiki there was no destination. No calibration artifact, sensitivity setting, sign-off record, or cleaning run is evidenced. The proposal also named cleaning categories and a sign-off point of contact as SNET-supplied inputs, and those are not evidenced as provided; both facts are recorded, without asserting a relationship between them. The calibration half of this term was collaborative by construction. Adjacent controls — RawData permission gating, and human editorial review before publication — are recorded elsewhere and are a different kind of control, not partial performance of this term |
| **D2. Content and editorial: analyze the source material, AI-assisted drafting of synthesis articles with provenance, route through editor and domain-expert review, publish an initial body of approved content and a running editorial pipeline** | Substantially built, against a different input premise | The analysis, drafting, provenance, review, and publication work was performed and is visible on the live wiki. At the time of the evidence pass the wiki held 48 Published cards and 160 Draft cards, including 25 Primer and 23 Deep Dive articles. AI-assisted drafting with provenance is implemented rather than ad hoc: changes to published content are authored as proposals that stamp base revision and a provenance record — parent identity and type, base act and action ids, content hashes, actor, source, and timestamp — inside the save transaction, with a human reviewer assembling and applying the merge through the verifying gate. Provenance also exists at the content level: synthesis passes produced publication-derived cards, Deep Dive articles cite those synthesis cards by recorded policy rather than raw source chunks, source-navigation maps chart primary references onto grounded cards, and published articles carry inline citations. Published cards display approver and date alongside trust tags | Because no cleaning pipeline was built, the material analysed was permission-gated RawData and publication full text rather than cleaned output. The editorial process is a human-triggered workflow supported by tooling, not an automated pipeline: AI drafts and proposes, and a person decides what is reviewed, merged, and published. The domain-expert endorsement mechanism is built but is not evidenced as applied across the published corpus; the proposal named SNET as the source of editor and domain-expert reviewers, and reviewer participation is not evidenced. The Draft count is not a backlog figure: the recorded policy returns a published article to Draft after a comprehensive synthesis pass, pending human re-review |
| **D3. Documentation and handover** | Partially built: documentation substantially built and in progress; handover prepared but not executed | The documentation package this file belongs to. `ONBOARDING.md` is the front door for reviewers, editors, agent operators, administrators, and developers. `docs/ROLES-AND-PERMISSIONS.md` covers first-administrator bootstrap on a new deck, the current production path, account creation and role assignment, per-role workflows, and permission boundaries. `docs/FEATURES-AND-COMPONENTS.md` documents base Decko concepts and Hyperon-specific features with what, who, where, status, and how to verify. `docs/INGESTION-WORKFLOWS.md` documents the export-then-ingest model, a safe first-run posture, the credential boundary, and the script inventory. `docs/DOCUMENTATION-MAP.md` routes readers toward current material and away from historical or inherited material. `README.md`, `CLAUDE.md`, and `AGENTS.md` provide developer, agent, and contributor entry points. Superseded documents were retired, archived, or warning-labelled, and references to unrelated or private infrastructure were removed or replaced with placeholders | The handover has not been executed. The documentation exists as local branch work that has not been committed, pushed, published, or packaged. `ONBOARDING.md` still carries its draft notices and sections not yet confirmed against production, and its final private and local boundary review is outstanding. The canonical publication location has not been chosen. This mapping document is itself in review and should not be treated as final until that review closes. Server access, source-service credentials, and account transfer belong to a separate access handover |

---

## How SNET can use what exists now

### Start with the documentation

| If you want to | Read |
|---|---|
| Understand the system and how the editorial workflow runs | [`../ONBOARDING.md`](../ONBOARDING.md) |
| Know which document covers what, and what is current | [`DOCUMENTATION-MAP.md`](DOCUMENTATION-MAP.md) |
| Create the first administrator, add accounts, assign roles | [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) |
| See what features exist, and which are base Decko | [`FEATURES-AND-COMPONENTS.md`](FEATURES-AND-COMPONENTS.md) |
| Bring source material into the wiki | [`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md) |
| Understand the versioning and merge model in depth | [`merge-editor/ws6-merge-editor-design.md`](merge-editor/ws6-merge-editor-design.md) |
| Set up a development environment and run the tests | [`../README.md`](../README.md) |
| Operate an AI assistant against this repository | [`../CLAUDE.md`](../CLAUDE.md) and [`../AGENTS.md`](../AGENTS.md) |

### Use the wiki and the editorial surfaces

Published content is publicly readable and displays its approval information and trust tags.
Signed-in editors can open the Review Queue, work through unreviewed Drafts, and use
**Approve & Publish**. Agent-authored changes to published articles arrive as proposals and
are reviewed in the merge workbench, where a reviewer sees base, current, and proposed
content side by side and applies selected changes through a verifying gate. Human editors
review and merge those proposals, and may also edit published cards directly where the live
permissions and policy allow — a direct edit is quicker but creates no proposal base,
provenance, or merge-audit record, so substantial rewrites are better routed through review.
Holders of the `Expert` role see an **Expert Approve** action on published cards, which adds
the visible expert seal.

### Use the MCP tool

The MCP surface lets an AI assistant search, read, and query the wiki, and create and update
cards, from the assistant a person already uses. It has been in sustained production use
from Claude, Codex, and Gemini/agy. Per-client setup, the tool specification, and a
known-quirks list live in the separate `hyperon-wiki-mcp` repository and should travel with
the handoff. Agents should follow the workflow conventions in `CLAUDE.md`: one writer at a
time, verify writes by reading the card back, route changes to published cards through
proposals, and never apply human or expert approval markers.

### Use the ingestion tooling

The scripts in `scripts/` export from source services and ingest into RawData cards, in two
stages: export on an operator's machine, then ingest on the wiki host.
`docs/INGESTION-WORKFLOWS.md` describes a first run that does not write to the wiki, and the
offline regression tests in `scripts/tests/` run with no network access and no credentials.

Two handling rules apply. Operators supply their own source-service credentials out of band;
no credentials or tokens are kept in the documentation or the ingestion scripts. New exports
and source-service working data should be kept outside the repository unless they are
deliberately reviewed and included. Separately, `scripts/archive/` retains historical
research and extraction material for reference; it sits outside the active documentation and
ingestion handoff and should not be read as part of it.

---

## Open follow-ups and dependencies

### Before the handoff package is final

- Complete the final private, local, and secrets boundary review of `ONBOARDING.md` and the
  package as a whole.
- Close review on this mapping document.
- Decide the canonical publication location: the wiki, or the repository with the wiki as a
  mirror. This determines what the documents point at as authoritative.
- Commit and package the documentation once review closes. The branch is currently behind
  its base by one commit and should be reconciled first.

### Handled outside these documents

- **Access handover.** Server access, source-service tokens, account transfer, and
  operational credentials are a separate track and are deliberately absent from these files.
- **Editor and domain-expert staffing.** The workflow supports editor review and expert
  endorsement but does not supply the people. If SNET wants the expert seal applied across
  the content, or wants published content reviewed at a steady rate, that needs named
  reviewers.
- **Content adjudication.** Deep Dive content needs domain-expert review before it is relied
  on as a reference. Per-article triage would be more useful than an aggregate judgement,
  because it distinguishes an article needing a correctness pass from one needing a rewrite.

### Operationally necessary before a fresh install

A fresh install from this repository does not reproduce the live wiki. The seed data defines
the `Draft`, `Published`, and `RawData` cardtypes and the `Expert` role; the `IndexSection`
and `IndexSubtopic` cardtypes, additional roles, and all card content exist as live database
state. Standing up a new instance therefore needs either a database restore or new seed
data. This is the single most consequential operational fact in this document.

### Optional future work, if SNET wants it

**Not built and not in progress.** The two-tier private staging plus born-clean public wiki;
the content-safety cleaning pipeline and its calibration loop; the migration of curated
content into a clean wiki; the Zoom and Google Meet meeting note-taker; dedicated model
training on wiki content; and continued content population under a new arrangement. Each of
these would be new work.

**A continuing experimental track.** Development on the AtomSpace integration, including the
bidirectional layer described in Contract 2 D2, may continue as research. It is separate
from the live wiki product, which does not depend on it. A production Distributed AtomSpace
or MORK-backed backend is not delivered as part of this handoff, and nothing in the handover
is contingent on that work reaching completion.

---

## Evidence and verification pointers

Everything below can be checked without private infrastructure.

| Area | Where to look |
|---|---|
| Live wiki, content, taxonomy, trust markers | The public wiki: published articles, their approval information and tags, and the Master Index sections and subtopics |
| Editorial workflow implementation | `mod/editorial_review/` — seed data for cardtypes, roles, tags, and the Review Queue; the publication event; the published-card rendering; the proposal and merge-draft set files |
| Merge model design record | `docs/merge-editor/ws6-merge-editor-design.md` and the related implementation and deployment notes |
| MCP API | `mod/mcp_api/` in this repository; client setup in the separate `hyperon-wiki-mcp` repository |
| AtomSpace mirror | `mod/atomspace_mirror/` and `docs/atomspace/ATOMSPACE-MIRROR-DEPLOYMENT.md` |
| Ingestion tooling | `scripts/` for export, ingest, and sync tools; `scripts/tests/` for offline regression tests; `docs/INGESTION-WORKFLOWS.md` for the operator model |
| Documentation package | `ONBOARDING.md`, `README.md`, and the documents listed in `docs/DOCUMENTATION-MAP.md` |

Checks run while preparing this record: the offline ingestion test suite and the shell
argument-quoting checks pass with no network access or credentials; Ruby syntax checks pass
on the editorial workflow set files; the documentation link check found 26 relative links
across 61 Markdown files with none broken. These confirm that particular artifacts exist and
behave as described in narrow respects. They do not exercise the system end to end, and they
will drift.
