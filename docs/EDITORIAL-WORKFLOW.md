# Editorial Workflow

**How content gets from a source into a published article, and the card-name contract behind
it.**

[`../ONBOARDING.md`](../ONBOARDING.md) §4 tells this as a narrative. This document is the
editor-facing reference: the same three stages, plus the exact names of every card the
workflow writes, so you can inspect state rather than infer it.

> **Status:** current, drawn from `mod/editorial_review/` and the WS6 design record in
> [`merge-editor/`](merge-editor/). Where this describes a server behaviour, it is describing
> the checked-in code.

**This is a workflow, not a pipeline.** Some stages are automated and enforced by the server;
others are started by a person. The distinction is marked throughout, because calling it an
automated pipeline sets the wrong expectation.

---

## Stage A — Source ingestion (a human starts it)

Someone decides a body of source material should come in and runs the ingestion process.
Material lands as `RawData` cards under source parents such as `RawData+transcripts`,
`RawData+mattermost`, `RawData+google-doc`, and `RawData+Publications`.

- **Automation:** the tooling is scripted but runs on demand. Nothing watches the sources.
- **Rule:** RawData preserves the source as-is. It is not edited to correct what a source
  said; editorial commentary belongs in the synthesis card written from it.
- **Caution:** the ingest stage writes to the live content database. Treat any run as a
  production change. [`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md) carries the safe
  first-run posture and is required reading first.

## Stage B — Synthesis (a human starts this too)

A person decides the material should be worked up. An AI agent may do the reading and
drafting; it does not decide the work is done.

| If the material is… | The output is… |
|---|---|
| A topic the wiki does not cover | A **`Draft`** card, auto-tagged `needs review` |
| A change to an existing **published** card | A **`<Card>+proposal`** |

**Who writes proposals.** The proposal path was built primarily for AI agents, so that
agent-authored changes to published content carry provenance and pass a verifying gate. It is
technically author-neutral, but it is not yet a comfortable human authoring workflow. A human
editor's normal route is a Draft, or a direct edit to a published card where the live
permissions allow it — which is quicker but creates no base, provenance, or merge-audit
record, so substantial rewrites are better routed through review.

### What the server does automatically here

When a proposal is created, the server stamps its base and provenance **inside the same
database transaction as the proposal itself**. There is no window in which an unstamped
proposal exists.

## Stage C — Review, merge, approval

A reviewer opens the proposal in the **merge workbench**: a three-way view of *base*, *current*,
and *proposal*. They select hunk by hunk, assemble a merge draft, optionally polish it, and
apply. [`REVIEW-QUEUE-GUIDE.md`](REVIEW-QUEUE-GUIDE.md) is the task guide for that work.

**Merging and approving are two separate actions** with two separate sets of evidence. This
is the most common misunderstanding in the workflow. Applying a merge does not change the
card's type, stamp `human approved`, or clear `needs review`.

---

## The card-name contract

Every artifact the workflow writes, in one place.

| Card | Type | Written | Holds |
|---|---|---|---|
| `<Card>+proposal` | matches the parent's content type | Authoring | The proposed content |
| `<Card>+proposal+base` | Number | Authoring, in the same transaction | The parent `act_id` the proposal was written against |
| `<Card>+proposal+provenance` | PlainText, rendered raw | Authoring; proposal hash refreshed on every proposal edit | Compact JSON: parent id, name and type, base and proposal content hashes, actor, source, stamp source, override information, timestamp |
| `<Card>+proposal+mode` | — | Authoring | The merge mode. The merge tool acts only on `full-replacement` |
| `<Card>+proposal+merge draft` | — | Review | The reviewer's assembled and optionally polished result, kept separate so the original proposal stays immutable |
| `<Card>+proposal+merge draft+audit` | — | Assembly | Assembled and polished hashes, hunk selections, optimistic-lock anchors |
| `<Card>+proposal+merge audit` | PlainText | Apply | Merge-time provenance: what was applied, by whom |
| `<Card>+approved by` / `+approved at` | Phrase / Date | Publication | Who approved, and when |
| `<Card>+tag` | Pointer | Throughout | Trust markers |

Read together, `+base` → `+provenance` → `+merge audit` prove the chain: what the proposal
claimed to be written against, what was actually applied, and by whom.

### Why the proposal is never deleted

On a successful merge the proposal is **not** removed — deleting it would break the audit
trail. Instead it transitions: a `merged` tag is added, and the merge audit is written. The
workbench then detects the completed merge and renders a locked screen with no Apply,
Assemble, or Reset controls, linking to the final article and the immutable audit instead.

---

## The apply gate

**Two different things happen at two different times, and conflating them overstates what
Apply guarantees.**

**At assembly**, the merged text is derived server-side from your recorded hunk selections
rather than from content posted by the client. Re-assembling re-derives it. This is where the
merge logic runs.

**At Apply**, the gate verifies the saved merge draft and writes *that content* to the
parent. It does **not** re-run the merge or re-check the proposal and base hashes.

Apply runs these checks, **all inside one database transaction** — if any fails, the whole
act rolls back and the parent is not written:

| Check | What it verifies |
|---|---|
| **Mode, re-read at apply time** | The proposal is still recorded as `full-replacement`. Deliberately re-read from the proposal rather than trusted from when the draft was seeded, so a draft assembled while the mode was mergeable cannot be applied after the mode changed or was removed |
| **Audit present** | A `+merge draft+audit` record exists; without it there is nothing to verify against |
| **Already merged** | A `+merge audit` on the proposal rejects with a 409 |
| **Permission** | The acting user may update the **parent** card — checked on the parent, not the draft or proposal |
| **Optimistic lock** | The parent's latest act id still matches the one recorded when the draft was assembled |
| **Draft integrity** | The draft content about to be written hashes to the recorded `polished_hash` — so a draft altered in the database since it was last saved is refused |
| **Identity** | Whether the applier is the polishing author or someone else. Recorded in the audit as a note; it does not block |

On success the parent is written with the draft's content, normalized to LF line endings, and
the merge audit is written in the same transaction.

**What this means in practice:** Apply guarantees that *what you saved is what gets written*,
that the parent has not moved underneath you, and that the proposal is still mergeable. It
does not re-validate the merge itself — that correctness came from assembly, which is why
re-assembling after the parent moves matters.

**What the gate does not check** is whether a human is at the keyboard. It verifies
permissions, locks, and hashes. Human authorization is editorial policy enforced by this
workflow, not a technical impossibility — a sufficiently privileged account can write to a
card outside this path. Configure agent accounts with least privilege accordingly.

### Fail-closed by design

A proposal merges only if its `+proposal+mode` is explicitly recorded as `full-replacement`,
because merging replaces the parent body wholesale. Anything else — including a proposal with
no mode recorded — is refused with an explanation and no merge controls at all. A refusal
here is the system working.

---

## `+AI` versus `+proposal`

**`+AI` is notes; `+proposal` is a change request.**

Historically `<Card>+AI` held an AI draft that could be merged straight into its parent,
overwriting it. **That path is gone from the checked-in code**, not merely deprecated — the
overwrite event and its button were both removed.

What remains mid-migration is legacy content. A `<Card>+AI` card with no companion proposal
offers an **"Open as proposal"** action to users who can update the parent and create the
proposal. Promotion creates the proposal, estimates the base from the legacy draft's creation
time, and stamps an explicitly estimated provenance marked as coming from the legacy bridge —
so the audit never overclaims. The resulting workbench opens with the estimated-base caveat
banner active and offers a two-way or estimated three-way merge, never a verified-tier claim.

Going forward, `+AI` is intended as scratch space for an agent's own working notes and
competing hypotheses, kept out of the article a reader sees. That is the stated direction,
not fully realized product behaviour today.

## Where to go next

| Question | Document |
|---|---|
| I am reviewing something — what do I actually do? | [`REVIEW-QUEUE-GUIDE.md`](REVIEW-QUEUE-GUIDE.md) |
| What are the cardtypes and tags in full? | [`CONTENT-MODEL.md`](CONTENT-MODEL.md) |
| Why is the merge model shaped this way? | [`merge-editor/ws6-merge-editor-design.md`](merge-editor/ws6-merge-editor-design.md) |
| Who is allowed to do each step? | [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) |
| How do I bring source material in? | [`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md) |
