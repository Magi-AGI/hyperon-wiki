# Feature Primers

**Short introductions to each feature of the Hyperon Wiki, for someone meeting it for the
first time.**

Each entry gives you a mental model, who uses the feature, one concrete thing to try, what
usually goes wrong, and where the real reference is. It is deliberately not exhaustive:
[`FEATURES-AND-COMPONENTS.md`](FEATURES-AND-COMPONENTS.md) is the full inventory with code
locations and status detail, and this page links into it rather than repeating it.

If you want the same material organized by job rather than by feature, read
[`ROLE-BASED-ONBOARDING.md`](ROLE-BASED-ONBOARDING.md).

> **Status:** draft, part of the onboarding documentation pass. Items marked
> *(to be confirmed)* have not been verified against the running production wiki.

**Start with §1.** Everything else assumes it.

---

## 1. Cards, compound names, and cardtypes

**Mental model.** There is only one kind of object in this system: a card. A page is a
card. A user is a card. A tag, a layout, a saved search, and a permission rule are all
cards. Each has a name, a type, content, and a full revision history.

Names compose with `+`, and that is how the wiki expresses both hierarchy and metadata:

```
PLN (Probabilistic Logic Networks)          ← a topic card
PLN (Probabilistic Logic Networks)+PLN Primer   ← an article under it
PLN (Probabilistic Logic Networks)+tag          ← that card's tags
```

So when you see `Something+something-else`, read it as "this thing, belonging to that
thing." A card's tags live at `<Card>+tag`, its authors at `<Card>+author`. The pattern
nests further where it needs to.

The **type** of a card is not a decorative label. On this wiki the type carries the
editorial state: `Draft` means unreviewed, `Published` means a human approved it, `RawData`
means verbatim source material. Changing a card's type is a meaningful act.

**Who uses it.** Everyone. This is the one concept the rest of the system is built on.

**First useful action.** Open any article on the wiki and look at its name. Identify the
parent, then find the parent card. Then look at the page's tags and understand that they
live in their own card at `<Card>+tag`.

**What can go wrong.** Compound-name handling has real sharp edges. Case-only renames can
be no-ops because the underlying key is shared; singular and plural forms can fold together
and silently collide with an existing card. If you are about to rename a compound card and
you are not sure, ask first.

**Status.** Base Decko behaviour, shipped and current.

**Deeper.** [`../ONBOARDING.md`](../ONBOARDING.md) §3;
[`FEATURES-AND-COMPONENTS.md`](FEATURES-AND-COMPONENTS.md) Part 1 §1–§3; Decko's own
[Concepts](https://decko.org/concepts) documentation.

---

## 2. The index and navigation

**Mental model.** The wiki has a curated spine: top-level sections (`IndexSection`) with
subtopics beneath them (`IndexSubtopic`). These are navigation *and* content — they behave
like published cards for review and approval purposes, and they are deliberately managed
rather than accumulating on their own.

The left sidebar renders this hierarchy as collapsible sections. What you see in the
sidebar is driven by a `*sidebar` card in the database, not by a template in the code.

**Who uses it.** Readers finding their way around; editors placing new material; anyone
wondering where a new article should live.

**First useful action.** Open a top-level section such as *Hyperon AI Algorithms* and walk
down into one of its subtopics, then into an article beneath that. Three levels is usually
enough to feel the shape.

**What can go wrong.** The most common mistake is inventing new index scaffolding for a new
write-up. The index is curated; the convention is to place substantial new material in a
neutral namespace and cross-link it rather than adding topic or subtopic cards.

Also: there is an older `wiki_nav_tree` mod in the codebase with its own README describing
a server-rendered nav tree. It carries an explicit deprecation header dated 2026-05-08
saying its view family is no longer referenced by any wiki card. Read that README as a
record of how the mod was designed, not as a description of what the wiki renders today.

**Status.** Live sidebar navigation: shipped and current. The `wiki_nav_tree` mod:
deprecated. The `IndexSection`, `IndexSubtopic`, and `Contributor` cardtypes are observed in
use but are not declared by any seed file in this repository, so where they are defined is
*(to be confirmed)*.

**Deeper.** [`FEATURES-AND-COMPONENTS.md`](FEATURES-AND-COMPONENTS.md) Part 2 §7;
[`DECKO-SECTION-PATTERN.md`](DECKO-SECTION-PATTERN.md) for the structured-article pattern.

---

## 3. The content lifecycle: Draft, Published, RawData

**Mental model.** Content moves through states, and the cardtype *is* the state.

| Type | Means |
|---|---|
| `RawData` | Verbatim source material. Never edited to "fix" what a source said |
| `Draft` | Written up, not yet approved. The normal working state |
| `Published` | A human approved it |

The usual path is: source material arrives as `RawData` → a person reads it and writes a
`Draft` → an editor reviews and publishes it. Changes to something already published take a
different route (§5).

**Who uses it.** Everyone who writes or reviews.

**First useful action.** Find a Draft and a Published card and compare their banners. The
Draft carries an amber "not approved for publication" notice; the Published card carries
approval information.

**What can go wrong — read this one carefully.** A Draft is **not a private workspace**.
Production currently reports `Draft+*type+*read = Anyone`, so an unapproved Draft is
readable by anyone including signed-out guests. The repository's seed data says
`Anyone Signed In`, so the live setting differs from what the seed would lead you to
expect. Reverting it has been discussed and **has not been done**.

Before putting restricted or source-derived material into a Draft, check
`Draft+*type+*read` on the production wiki yourself.

`RawData` is the genuinely restricted type: read is scoped to the `Raw Data Analyst` role
plus Administrators, and create, update, and delete are Administrator-only.

**Status.** Shipped and current, with the Draft-visibility policy question open.

**Deeper.** [`../ONBOARDING.md`](../ONBOARDING.md) §3;
[`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §4 for the live matrix and the
seed-versus-production table.

---

## 4. The Review Queue

**Mental model.** A saved search card, not a separate application. It answers one question:
what is waiting for a human?

It lists two things, oldest first: `Draft` cards, and cards carrying a `+proposal` child
that has not yet been merged. This is the live query, read back from the wiki:

```json
{"or":{"type":"draft","right_plus":["proposal",{"not":{"right_plus":"merge audit"}}]},
 "sort":"create","dir":"asc"}
```

The `not right_plus merge audit` clause is what makes the queue self-clearing: applying a
merge writes a `+merge audit` child, and the item drops out of the queue. If you ever need
a queue for proposals alone, that inner clause is the whole recipe —
`{"right_plus":["proposal",{"not":{"right_plus":"merge audit"}}],"sort":"create","dir":"asc"}`
as the content of a new `Search` card.

**Who uses it.** Editors and reviewers, as their daily starting point.

**First useful action.** Open the Review Queue and click a row. It opens in a new browser
tab rather than loading in place, which is deliberate — reviewers can queue several cards
up at once. Modifier keys and the dropdown items inside a row behave normally.

**What can go wrong.** The queue is a listing surface, not a task manager. There is no
assignment, no claiming, and no status beyond what the cards themselves carry — two
reviewers can pick up the same item without the queue noticing.

If a proposal you expect is not listed, check whether it already has a `+merge audit`
child: a merged proposal is intentionally gone from the queue. You can always open
`<Card>+proposal` directly.

**Status.** Shipped and current. The one documented presentation behaviour, open-in-new-tab
on click, is implemented and current.

**Deeper.** [`../ONBOARDING.md`](../ONBOARDING.md) §3; `mod/review_queue_ui/README.md`.

---

## 5. Proposals and the merge workbench

**Mental model.** This is the wiki's pull request.

Rather than writing straight into a published card, an author creates a `<Card>+proposal`
describing how it should change. A reviewer opens that proposal in a **three-way merge
workbench** showing:

- **base** — the version of the parent the proposal was written against,
- **current** — the live parent, which may have moved since,
- **proposal** — what is being suggested.

The reviewer picks what to keep hunk by hunk, assembles a **merge draft**, optionally
polishes it in the normal editor, and applies it. The original proposal stays intact, so
the record of what was suggested survives what was accepted.

**Who it was built for.** Primarily AI agents. The proposal path exists so that
agent-authored changes to published content carry provenance and pass a verifying gate
before landing. It is technically author-neutral — a person can open a proposal as a peer
review exactly as an agent can — but it has not been made comfortable for human authoring
yet, so **humans are not expected to reach for it as the normal route**. The ordinary human
path is editing a `Draft` and publishing it, or raising the change with whoever owns the
card. Human proposal authoring is fair to explore; it is not the expected workflow today.

**Who uses it.** Editors and reviewers read proposals here every day, because this is where
agent-authored changes arrive. AI agent operators write them. Developers touching the
editorial workflow need to understand the whole lifecycle.

**First useful action.** Find an existing proposal card on the wiki and open the workbench
view. Reading a three-way view once teaches more than any description of it.

**What can go wrong.**

- **Merging is not approving.** Applying a merge updates the parent's content and writes an
  audit record. It does *not* change the card's type, stamp `human approved`, or clear
  `needs review`. Those come from a separate approval action. Check for the evidence of the
  action you actually took.
- **A proposal can refuse to merge, by design.** The merge tool only acts on a proposal
  explicitly recorded as `full-replacement` in its `<Card>+proposal+mode` sidecar, because
  merging replaces the parent body wholesale. Anything else — including a proposal with no
  mode recorded — is refused with an explanation and no merge controls at all. That is
  intentional fail-closed behaviour, not a bug.
- **The parent can move under you.** If someone else changes the parent while you are
  reviewing, the apply gate will stop you rather than silently overwriting their work.

**What the system guarantees.** Applying a merge passes a gate that checks, inside a single
transaction: that you may update the parent, that the parent has not changed since you
started, and that the draft you are applying is byte-for-byte what you last saved. If any
check fails the whole thing rolls back — there are no partial writes. A completed merge
leaves an audit record and cannot be silently re-applied.

**What it does not guarantee.** The gate checks permissions, locks, and hashes. It does not
check whether a human is at the keyboard. Human authorization is editorial policy enforced
by this workflow, not a technical impossibility — a sufficiently privileged account can
write to a card outside this path. Configure accounts, especially agent accounts, with that
in mind.

**Status.** Shipped and current. The old direct-overwrite path is **removed from the
checked-in code**, not merely deprecated.

**Deeper.** [`merge-editor/ws6-merge-editor-design.md`](merge-editor/ws6-merge-editor-design.md) is the design record
and the single best explanation of why this is shaped as it is. Phase-specific documents
for the workbench contract, the polish gate, the apply gate, and capability gating are
indexed in [`DOCUMENTATION-MAP.md`](DOCUMENTATION-MAP.md) under *The merge editor (WS6)*.

---

## 6. Trust markers and banners

**Mental model.** Every card can carry tags at `<Card>+tag`. They render as pills at the
top of the page and some drive banners. As a reader, this is how you calibrate how much
weight to give what you are reading.

| Marker | Means |
|---|---|
| `needs review` | Applied automatically when a Draft is created. Nobody has approved this |
| `ai generated` | Produced by an AI agent. Provenance, not a verdict |
| `human authored` | Written by a person |
| `transcript derived` | Derived from source material such as a meeting transcript |
| `ai reviewed` | An AI pass reviewed it. **Not** approval |
| `human approved` | A human approved and published it. Applied automatically on publication; `needs review` is removed at the same time |
| `expert approved` | A domain expert endorsed it. The strongest marker here |

Approval also records `<Card>+approved by` and `+approved at`; expert endorsement records
`<Card>+expert approved by` and `+expert approved at`. The history is auditable rather than
living only in a tag.

**Banners.** A Draft shows an amber "not approved for publication" notice with an *Approve
& Publish* action for users who can edit it. An approved card shows a green "Human Approved
— by *name* on *date*" banner for the first week, then settles into a quiet grey line. An
expert endorsement shows an amber seal. The merge workbench shows a not-mergeable notice
when a proposal has not been characterized as a full replacement, explaining why.

**Who uses it.** Readers, constantly. Editors and experts, when they apply them.

**First useful action.** Open a published article and read its pills top to bottom. Work out
from them how the content was produced and how far it got through review.

**What can go wrong.** The two markers that mean a person made a judgement — `human
approved` and `expert approved` — are **never** applied by an AI agent, regardless of how
confident an agent's assessment is. They are applied through the approval actions, by
people. An agent applying them defeats the entire point of the workflow.

Also worth knowing: some hand-written provenance notes in card bodies may lag the
automatically stamped tags, because the tags update on a type change and the prose does
not.

**Status.** Shipped and current.

**Deeper.** [`../ONBOARDING.md`](../ONBOARDING.md) §5;
`mod/editorial_review/data/real.yml` for the exact tag vocabulary.

---

## 7. `+AI` versus `+proposal`

**Mental model.** One sentence: **`+AI` is notes; `+proposal` is a change request.**

You may meet `+AI` in two forms, because its meaning is changing.

**The old use, being phased out.** Historically `<Card>+AI` held an AI draft that could be
merged straight into its parent, overwriting it. That direct path is gone from the code. A
bridge lets an existing legacy `+AI` draft be re-opened as a proper proposal, and existing
`+AI` cards are being worked through.

**The intended future use.** Going forward, `+AI` is meant to be scratch space for an AI
agent's own working notes — uncertain conclusions, competing hypotheses, reasoning that is
still open — kept deliberately separate from the article a reader sees. Contradictory
findings can coexist there while evidence settles, without any of it leaking into content.

**Who uses it.** AI agent operators, primarily; editors who encounter either form.

**First useful action.** If you find a card with both an `+AI` child and a `+proposal`
child, you are looking at a migration in progress rather than a fault. Work through the
proposal.

**What can go wrong.** Treating `+AI` scratch content as authorized to publish. It is not.
The sanctioned route for changing published content is `+proposal` plus the merge workbench,
and that has not changed.

**Status.** The `+proposal` convention and the merge workbench: shipped and current. The
legacy `+AI` bridge: shipped, transitional. `+AI` as agent scratch space: the intended
direction, **not** fully realized product behaviour today — do not cite it as a current
enforced feature.

**Deeper.** [`../ONBOARDING.md`](../ONBOARDING.md) §4, "A note on `<Card>+AI`";
[`FEATURES-AND-COMPONENTS.md`](FEATURES-AND-COMPONENTS.md) Part 2 §5 for the three separate
statuses; `merge-editor/ws6-merge-editor-phase7-plan.md` for the bridge mechanics.

---

## 8. Source ingestion

**Mental model.** A two-stage, human-triggered process that brings outside material into
the wiki as `RawData` cards.

**Stage one, export:** a script running on an operator's machine pulls material from a
source service — chat archives, meeting transcripts, publications, books — using that
service's credentials, and writes JSON to local disk.

**Stage two, ingest:** a runner script on the wiki host reads that JSON and creates
`RawData` cards under source parents such as `RawData+transcripts`,
`RawData+mattermost`, and `RawData+Publications`.

Two stages, two trust boundaries, two different sets of credentials. Neither set lives in
this repository.

**Who uses it.** Raw Data Analysts and Administrators running a pass; operators supplying
credentials out of band.

**First useful action.** Read [`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md) before
running anything. Then read the specific script you intend to run — each carries a usage
docstring naming its inputs, environment variables, and output location.

**What can go wrong.** The ingest stage writes to the live content database. **Treat a
first run as a change to production, because it is one.** The documented safe posture, in
order: read the script; use a listing or read-only mode if one exists; run the export stage
alone and inspect the JSON on disk; run the ingest stage only with an authorized operator
present and on a deliberately small batch; verify in the wiki before running a full one.

The other common misunderstanding: **nothing is scheduled.** There is no importer watching
the sources. Someone decides material should come in and runs the process. Describing this
as an automated pipeline sets the wrong expectation.

**Status.** Shipped and current. All tracked ingestion scripts are in this repository; the
one self-containment gap, an exporter that used to depend on a separate checkout, has been
closed. Offline regression tests under `scripts/tests/` run with no network access and no
credentials.

**Deeper.** [`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md);
[`../ONBOARDING.md`](../ONBOARDING.md) §4 Stage A.

---

## 9. MCP and API access for agents

**Mental model.** The wiki exposes a Model Context Protocol tool surface, so an AI
assistant can read and write cards directly instead of being handed pasted text. Agents can
read cards and history, search and query, create and update cards, manage tags, and author
`+proposal` cards that feed the human review workflow.

**Who uses it.** Anyone driving the wiki from Claude, Codex, Gemini/agy, or ChatGPT.

**First useful action.** Set up a client using the per-client installers in the separate
[`hyperon-wiki-mcp`](https://github.com/Magi-AGI/hyperon-wiki-mcp) repository, then read a
card through it. Read that repository's known-quirks list before filing a bug.

**What can go wrong.**

- **Expecting the MCP layer to have an access model of its own.** It does not. An MCP
  request authenticates as a Decko account and runs as that account, so access comes from
  that account's Decko roles and the `*read` / `*create` / `*update` / `*delete` rules that
  apply to the card — exactly what the same person would see signed in to the browser.
  Destructive operations (delete, rename, listing trash) carry a narrow additional guard
  and require Administrator standing. Nothing in the MCP layer widens what content an
  account can see.
- **Assuming a role is the last word on a specific card.** Card and set permission rules
  supersede broad role defaults, so a one-off card can be restricted to Administrators even
  when the reader's role would normally grant access. If a read fails unexpectedly, check
  the card's own rules before suspecting the tool.
- **Assuming the API enforces the editorial workflow.** It does not. The API grants exactly
  what the authenticating account's permissions allow. A sufficiently privileged account can
  write to published content directly. Give agent accounts the least privilege that lets
  them do their job.
- **Trusting a write response.** Read the card back. "Read-your-writes" is the standing
  rule for a reason, and an "already exists" error on create can be spurious — check with a
  read before acting on it.
- **Parallel writers.** One writer at a time when several sessions are active; sequential
  writes rather than parallel batches.

**AtomSpace reads are a third thing again.** The AtomSpace read API is gated by an explicit
`mcp:atomspace:read` scope granted per principal, which in the current code is deliberately
*not* derived from any role — holding administrator does not imply it, and it fails closed
so that nothing is granted by default. Card-scoped results are still filtered by the
account's read permission on top of that. Whether this should instead follow from the
`Raw Data Analyst` role is an open alignment question, recorded in
[`DOCUMENTATION-MAP.md`](DOCUMENTATION-MAP.md) under Follow-up tasks.

**Status.** Shipped and current. Claude, Codex, and Gemini/agy are the paths with months of
production use; a ChatGPT setup path is also documented. Note that
`mod/mcp_api/README.md` carries role names and terminology from a sibling deck's template,
so read that file for the endpoint list rather than for the permission model.

**Deeper.** [`../ONBOARDING.md`](../ONBOARDING.md) §6; `mod/mcp_api/README.md` for the
endpoint list; the `hyperon-wiki-mcp` repository for setup.

---

## 10. History and revision

**Mental model.** Decko versions every card edit. Each card has a history you can read, and
edits can be rolled back. Because everything is a card, this applies to layouts and
permission rules as much as to articles.

**Who uses it.** Editors auditing what changed; anyone recovering from a bad edit; agents
checking whether a write actually landed.

**First useful action.** Open a card that has been edited more than once and read its
history: who changed it, when, and which fields moved.

**What can go wrong.** History is also why some content properties are permanent. Removing
text from a card's current body does not remove it from the card's revision history. If
something must never have been visible, deleting it later is not equivalent to never having
added it.

**Status.** History and revert: base Decko, shipped and current, and used operationally.
Recent-changes and watch/follow affordances are base Decko features that were **not
verified on this wiki** in the current documentation pass — check the UI directly rather
than assuming they are wired up *(to be confirmed)*.

**Deeper.** [`HISTORY-AND-ROLLBACK.md`](HISTORY-AND-ROLLBACK.md) is the feature-level
walkthrough — reading revisions, reverting a bad edit, recovering a deleted card, and what
history means for content that should never have been visible. It carries the same
*(to be confirmed)* caveat on UI affordances.
[`FEATURES-AND-COMPONENTS.md`](FEATURES-AND-COMPONENTS.md) Part 1 §9 has the inventory entry.

---

## 11. Roles, permissions, and the card menu

**Mental model.** Permissions are cards too. Each cardtype or individual card can carry four
rule types — `*create`, `*read`, `*update`, `*delete` — assigned to users or to roles. A
narrower rule beats a broader default, so a surprise is usually a rule on a more specific
card than the one you are looking at.

Roles are resolved from the **role's** member list, not from anything stored on the user.
`Editor+*members` is the source of truth for who is an Editor.

Every card has a menu offering page, edit, history, and advanced/rules actions, varying by
your permissions and the card's type. The advanced/rules view is where permission rules are
edited.

**Who uses it.** Administrators granting access; developers debugging "why can they do
that?"; anyone auditing the live matrix.

**First useful action.** Open the card menu on a card you can already edit and look at its
rules. Seeing permissions as cards makes the model click.

**What can go wrong.**

- **Assuming the repository describes the running site.** It does not, in at least two
  places. The live matrix and the seed data differ on Draft read and on RawData read. The
  seed file is seed data, not a mirror of production.
- **Assuming a role is a technical wall.** Some capabilities are genuinely role-gated:
  reading `RawData`, applying the expert seal, destructive operations. Editorial
  responsibility largely is not — `Draft` and `Published` create and update currently show
  `Anyone Signed In`. The `Editor` role describes who is *expected* to do that work, not
  who is *able* to.
- **Changing a parent's read rule without considering its children.** Permission changes
  propagate to descendants, and the `*right`-rule case is explicitly marked TODO in the
  mod's own source. Verify the rendered result for the audience you intend.
- **Creating a `<User>+*roles` card.** It looks like it should work. Decko never consults
  it, and it grants nothing.

**Status.** Shipped and current, with the seed-versus-production differences documented
rather than resolved.

**Deeper.** [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) — §1 for administrator
onboarding, §3 for per-role workflows, §4 for the live matrix, §5 for propagation.
[`ROLE-BASED-ONBOARDING.md`](ROLE-BASED-ONBOARDING.md) for the first-day version.

---

## 12. The AtomSpace mirror

**Mental model.** A write-through mirror that encodes Decko card state into Hyperon
AtomSpace atoms, so wiki content can be queried as a knowledge graph rather than only as
pages. Card events feed an outbox; a drain worker applies them to a Hyperon space held by a
sidecar process; a read surface exposes queries back.

**Who uses it.** Developers and operators on the AtomSpace integration track. It is not
part of anyone's editorial day.

**First useful action.** Read the deployment runbook's topology section before assuming any
mirror process is running anywhere.

**What can go wrong.** The most important thing to get right here is what is real and what
is not:

- The mirror **implementation** — mod code, migrations, encoder, outbox writer, read
  surface — exists in this repository at source level. **It is not activated in
  production.** Its own runbook states that nothing in it activates the mirror; activation
  is a separate, explicitly approved operation.
- `atomspace/ATOMSPACE-INTEGRATION.md` is a **broader architecture sketch, self-described as
  conceptual**. Its own reframing section lists corrections, including an import that does
  not exist in the real Hyperon package. Do not cite its diagrams or code blocks as a
  description of what runs today.
- Do not conflate "code exists in this repository" with "this is running."

**Status.** Mirror implementation: source-level current, not activated. Integration
architecture document: explicitly aspirational.

**Deeper.** [`atomspace/ATOMSPACE-MIRROR-DEPLOYMENT.md`](atomspace/ATOMSPACE-MIRROR-DEPLOYMENT.md) (read the
topology section first); [`atomspace/ATOMSPACE-INTEGRATION.md`](atomspace/ATOMSPACE-INTEGRATION.md) (read its
reframing section first); `mod/atomspace_mirror/README.md`.

Two related documents in this repository, [`AGENT-READ-API.md`](AGENT-READ-API.md) and
[`AGENT-READ-YOUR-WRITES.md`](AGENT-READ-YOUR-WRITES.md), are **pointer stubs only**. Their
canonical content lives on wiki cards that have not yet been published to
`wiki.hyperon.dev`, so the files carry no content of their own. Ask an administrator for
access, or wait for the cards to be republished.

---

## 13. Smaller behavioural fixes worth knowing about

Several small mods exist purely to correct behaviour you would otherwise find confusing.
You do not need to understand their implementations; you need to know they exist so you do
not mistake their effects for bugs.

| Mod | What it does for you |
|---|---|
| `markdown_fixes` | Corrects Markdown card rendering behaviour |
| `url_fixes` | Stops the automatic link-maker from corrupting links you authored deliberately |
| `math_rendering` | Renders `\(...\)` and `\[...\]` math in the browser, including after content loads asynchronously |
| `email_fixes` | Account-related email behaviour |
| `permission_propagation` | Repairs cached read-permission state on a card's descendants when a parent's `*read` rule changes; new child cards inherit a restricted parent's rule |
| `hyperon_ui` | Layout, theming, the dark/light toggle, and the account link labels |

**What can go wrong.** `permission_propagation`'s own source marks the `*right`-rule case as
TODO, so do not assume its propagation behaviour without checking the current code. And
file uploads depend on a fix recorded in the documentation archive that **may still be
load-bearing** — check before removing anything it describes.

**Status.** Shipped and current.

**Deeper.** [`FEATURES-AND-COMPONENTS.md`](FEATURES-AND-COMPONENTS.md) Part 2 §9 and §10;
[`../README.md`](../README.md) for the Decko gotchas table.

---

## 14. The right-column panels: Wiki Assistant and MeTTa Playground

**Mental model.** Two interactive panels live in the wiki's right-hand column. Neither is
part of the Decko application itself — each is a separate service the wiki page talks to.
If one of them is unavailable, the wiki keeps working.

### Wiki Assistant

A chat panel that helps you find and understand things on the wiki. It is backed by a
service that uses a Claude agent together with the wiki's own MCP **read** tools, so its
answers are grounded in actual wiki content rather than recalled from training.

**Who uses it.** Readers and newcomers, mainly — it is a good first stop when you know what
you want to know but not where it lives.

**First useful action.** Ask it where a topic is covered on the wiki, then follow the cards
it names and confirm they say what it reported.

**What can go wrong.** Know what it is not. It is a **V1 navigation, search, and
summarization aid** — not a dedicated fine-tuned model, and not a general wiki-editing
agent. It reads; it is not the route by which content gets written or changed. If its
backing service is unavailable the panel degrades gracefully rather than breaking the page.
As with any assistant, verify a claim against the card before relying on it.

### MeTTa Playground

A panel for evaluating MeTTa expressions in the browser. Submissions run in a sandbox
against a pinned Hyperon runtime, one sandbox per request.

**Who uses it.** Anyone reading about MeTTa who wants to try an expression rather than take
the article's word for it.

**First useful action.** Run the example it offers, then modify it and run it again.

**What can go wrong.** State does **not** persist between runs. Each request is evaluated
in a fresh sandbox, so you cannot build up a session across several submissions — a
persistent signed-in AtomSpace session was a deferred design, not what this is. It is also
separate from the AtomSpace mirror track in §12; do not read one as the other.

**Status.** Both are live on the wiki and both are V1 with the limits above. **This
repository holds only the handoff-status summary for them, not an operator runbook** — the
implementing services live outside this repository, and setup, deployment, and operational
detail for them are not documented here.

**Deeper.** [`DELIVERABLES-SCOPE-MAPPING.md`](DELIVERABLES-SCOPE-MAPPING.md), Contract 2
rows D3 and D4, which record what each panel is, what backs it, and the limits stated above.

---

## What is not covered here

One thing a newcomer might reasonably expect and should not assume:

- **Comments and discussion.** Base Decko supports commentable cards. Whether this wiki has
  them wired into its UI is **not verified** — treat as *(to be confirmed)* and test on a
  card before relying on it.

---

## Where to go next

| Question | Go to |
|---|---|
| What is my job here, day one? | [`ROLE-BASED-ONBOARDING.md`](ROLE-BASED-ONBOARDING.md) |
| What is this system, in five minutes? | [`../ONBOARDING.md`](../ONBOARDING.md) §3 |
| Full component inventory with code locations | [`FEATURES-AND-COMPONENTS.md`](FEATURES-AND-COMPONENTS.md) |
| Who can do what, right now? | [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §4 |
| How does the merge model really work? | [`merge-editor/ws6-merge-editor-design.md`](merge-editor/ws6-merge-editor-design.md) |
| How do I set up a development environment? | [`../README.md`](../README.md) |
| Which document covers a topic not listed here? | [`DOCUMENTATION-MAP.md`](DOCUMENTATION-MAP.md) |

If a primer here does not match what you find on the wiki, the wiki is right and this page
needs correcting. Say so rather than working around it.
