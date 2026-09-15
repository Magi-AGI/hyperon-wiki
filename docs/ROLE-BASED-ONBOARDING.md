# Role-Based Onboarding

**A first-day and first-week guide for each job on the Hyperon Wiki.**

This document answers "what am I here to do, and how do I start doing it?" It is a primer,
not a reference. The authoritative detail on accounts, roles, and permissions is in
[`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md); this page tells you which parts of
that document you actually need, in what order, and what a normal working day looks like.

**Read [`../ONBOARDING.md`](../ONBOARDING.md) §3 first** — the content model in five
minutes. Everything below assumes it. If you want a feature-by-feature tour instead of a
role-by-role one, that is [`FEATURE-PRIMERS.md`](FEATURE-PRIMERS.md).

> **Status:** draft, part of the onboarding documentation pass. Items marked
> *(to be confirmed)* have not been verified against the running production wiki. Role
> membership is deliberately not listed anywhere in this repository.

---

## Before anything: the four facts everyone needs

Whatever your role, these four will save you the most confusion.

**1. Everything is a card.** Pages, users, tags, layouts, searches, and permission rules
are all cards. Names compose with `+`, so `PLN (Probabilistic Logic Networks)+PLN Primer`
is a child of the PLN card, and a card's metadata lives at `<Card>+tag`, `<Card>+author`,
and so on. Learn this one idea and most of the system follows.

**2. A cardtype is a content state, not just a category.** `Draft` means unreviewed.
`Published` means a human approved it. `RawData` means verbatim source material. Moving a
card between them is what the editorial workflow *is*.

**3. Most of the workflow is policy, not a technical wall.** Some things are genuinely
locked down — reading `RawData`, applying the expert seal, deleting cards. Much of the rest
is assigned responsibility enforced by convention and tooling. The live permission matrix
in [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §4 shows `Draft` and `Published`
create and update as `Anyone Signed In`. Do not assume someone is blocked from an action
just because it is not their job.

**4. Verify your own writes.** Read the card back after you change it. This is the single
habit that separates people who trust this system correctly from people who get surprised
by it. Every role section below has its own version of this.

### A caveat that affects everyone

**Draft cards are currently readable by anyone, including signed-out guests.** Production
reports `Draft+*type+*read = Anyone`; the repository's seed data says `Anyone Signed In`.
The live setting was an intentional change, and reverting it has been discussed but **has
not been done**. Whether Drafts should stay publicly readable is an open policy question.

Practical consequence: **a Draft is not a private space.** Before you put source-derived,
restricted, or sensitive material into a Draft, check `Draft+*type+*read` on the production
wiki yourself. Details and the seed-versus-production table are in
[`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §4.

---

## Administrator

**What the role is for.** You own accounts, roles, and anything destructive or
irreversible. Decko grants Administrators create, read, update, and delete on any card,
unconditionally. You are the person who unblocks everyone else.

**What success looks like in week one.** A new contributor can sign in, sees exactly the
capabilities you intended them to have, and you verified that rather than assuming it.

### First things to learn

1. **How the first administrator exists, and why it does not apply here.** On a brand-new
   deck, the first person to sign up is granted the Administrator role automatically. That
   is ordinary editable card state, not a hardcoded superuser — and it is not this wiki's
   situation, since `wiki.hyperon.dev` already has Administrators.
   ([`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §1a.)
2. **The two ways a new person gets access here:** a secure handover of an existing
   Administrator account, or a new signup that an Administrator approves and grants roles
   to. Ask the handoff coordinator which applies; do not guess. (§1b.)
3. **Signup has two branches, and confusing them is how onboarding gets stuck.** If the
   signing-up account can already create `User` cards, email verification finalizes the
   account by itself. If it cannot, an Administrator finalizes it — and that approval may
   need to happen *before* the verification email is actioned. Check whether the account
   holds `*create` on `User` before concluding an approval is "blocked on email." (§1c.)
4. **Roles are granted from the target contributor's own User card.** The `Account 👤` link
   in the navbar always opens *your own* card, whoever you are, so it cannot be used to
   reach someone else's role menu. Navigate to their card directly. (§1d.)
5. **Decko resolves roles from the role card, not the user card.** The source of truth is
   `<Role>+*members` — `Editor+*members`, `Expert+*members`, and so on. A `<User>+*roles`
   pointer looks plausible and grants nothing at all. (§1d.)

### Your normal work loop

Approve or finalize an account → grant the role → **verify** → tell the person what to
expect. Beyond that, you are handling exceptions: unblocking something another role is
correctly prevented from doing, revoking access, and holding final say on deletions.

You are *permitted* to do routine editorial review, but it is not your job — that is the
Editor loop below. Administrator access is unconditional, which is the reason to use it
narrowly.

### Common tasks, step by step

These are the four things administrators actually get called about. Where the flow is
standard Decko, the official documentation is linked and not restated; where this wiki
deviates or adds something, it is labelled **Hyperon-specific**.

#### Approve a sign-up when email delivery is down

The usual path is that a new person clicks `Register`, a verification email arrives, and
the account activates itself. When SMTP is broken, that path stalls — and the account is
*not* stuck, it is just waiting for a human. You can finalize it yourself.

1. **Go to `Sign_ups`.** Type or navigate to `Sign_ups` — the wiki folds underscores,
   spaces, and trailing-s plurals when resolving names, so `Sign_ups`, `Sign ups`, and
   `signups` all land on the same place: the `Sign up` cardtype card.
2. **Use its "Sign up Cards" listing to find the pending signup.** That card renders a list
   of every existing Sign up card. The person you are looking for is in it — a pending
   signup, not a finished `User` card.
3. **Open that pending signup and use its approval link/action.** Approving from here
   converts the signup into a full `User` account **without waiting on email
   verification**. That is the point: verification email and administrator approval are two
   branches to the same outcome, not two steps in sequence, so a dead mail server does not
   block you.

   (The exact label on that action can vary with the card menu and your permissions, so
   look for the approval action on the signup rather than a specific button name.)
4. **Grant whatever role they need** (next subsection). A finalized account with no role is
   a signed-in user and nothing more.
5. **Verify.** Confirm a `User` card now exists and there is no pending sign-up left over,
   then ask the person to sign in. If they cannot, that is a different problem from the one
   you just solved.
6. **Then fix the mail.** Approving around a broken mail server unblocks one person; it does
   not fix password resets or signup alerts for anyone else. SMTP troubleshooting is in
   [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §1f.

The two-branch model — self-completing versus approval-required, depending on whether the
signing-up account can create `User` cards — is explained in
[`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §1c. Decko's own account model is at
<https://decko.org/accounts>.

#### Assign a role

1. **Go to the target person's own `User` card.** Not yours. The `Account 👤` link in the
   navbar always opens the signed-in user's own card, so it cannot reach anyone else's role
   settings — **Hyperon-specific gotcha**, and the most common way this gets stuck. Reach
   their card by search or by its direct URL.
2. **Open the card menu and use the account/roles settings** reachable from that card. This
   is standard Decko: roles are assigned through the account item on a `User` card's menu
   (<https://decko.org/accounts>).
3. **Verify the grant**, per the verification habit below. Read `<Role>+*members` and
   confirm the account appears.

**If the UI path is unavailable or you are scripting**, the underlying truth is
`<Role>+*members`: Decko resolves a user's roles by reading the *role's* member list, so
`Administrator+*members`, `Editor+*members`, `Raw Data Analyst+*members`, and
`Expert+*members` are authoritative. Saving that card updates Decko's cached role hash
automatically; there is no separate cache step.

Two traps worth knowing:

- **Creating a `<User>+*roles` card grants nothing.** Decko computes `<User>+*roles` as a
  virtual card reflecting membership; it is a view, not an input. Reading it is a fair way
  to check what a user has. Writing one is not a way to give it to them.
- **Administrator is tracked separately.** Administrator membership is not reliably visible
  through `<User>+*roles`; check `Administrator+*members` directly when that is the role in
  question.

#### Find and recover a deleted card

Deleting in Decko **moves a card to trash rather than destroying it**
(<https://decko.org/deleting>). Every card also keeps a full revision history
(<https://decko.org/history>). Between those two facts, most "it's gone" reports are
recoverable.

1. **Confirm it was deleted rather than renamed or restricted.** A card you cannot see may
   be one you cannot *read* — see the permission subsection below before assuming deletion.
2. **Look in the trash.** **Hyperon-specific:** this deck's MCP surface exposes an
   administrator-only trash listing, which is often the quickest way to confirm a card is
   in trash and get its exact name when the UI path is not obvious.
3. **Recover it.** The standard Decko route is to recreate a card of the same name and
   restore its content from history. Get the name exactly right — compound names fold
   spaces, hyphens, and trailing-s plurals, so a near-miss silently creates a different
   card.
4. **Escalate rather than improvise** if the card was a rule card, a layout, or anything
   with children. Restoring content is easy; restoring a structural card into the wrong
   shape is how a working wiki starts rendering strangely.

Who may delete at all is governed by `*delete` rules — currently Administrator for the
editorial cardtypes.

#### When a permission does not behave the way the role suggests

Roles are the broad default. **Rules on a specific card or set are authoritative and
override them**, and the more specific rule always wins
(<https://decko.org/permissions>). That cuts both ways:

- A one-off card can be made readable only by Administrators even though its cardtype is
  readable by everyone. Someone holding the "right" role will still be denied.
- Equally, a permissive rule on a specific card can open something the cardtype default
  would have closed.

So when someone reports that access is wrong, **check the card's own rules before checking
their roles**. The card menu's advanced/rules view is where those live. Remember also that
compound cards can inherit from their parent, and that changing a parent's `*read` rule
propagates to descendants ([`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §5).

### What not to do

- **Do not make ordinary content changes with Administrator power just because you can.**
  Direct writes bypass the audit trail the proposal and merge workflow produces. Use the
  governed route (see the Editor section) for normal edits.
- **Never apply `human approved` or `expert approved` as an automated or agent-driven
  action.** Those markers exist to mean a person judged the content. Applying them any
  other way empties them of meaning.
- **Do not narrow or widen a `*read` rule on a card with children without thinking about
  the children.** Permission changes propagate to descendants
  ([`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §5), and the `*right`-rule case is
  marked TODO in the mod's own source, so do not assume its behaviour.
- **Do not put credentials anywhere in this repository.** Ever. Real values come from the
  server-access handoff.

### Verification habit

**Read `<Role>+*members` back after every change** — but check for the right thing, because
a grant and a revoke have opposite evidence.

*After granting a role:* confirm the account **appears** in `<Role>+*members`, then ask the
person to sign in and confirm they can do the thing you intended. A Raw Data Analyst should
be able to open a `RawData` card; an Expert should see the *Expert Approve* action on a
published card.

*After revoking a role:* confirm the account **no longer appears** in `<Role>+*members`,
then confirm the role-gated capability is actually gone — the `RawData` card no longer
opens, the *Expert Approve* action is no longer offered. A revocation that leaves the
capability in place is the failure mode worth catching, and you will only catch it by
testing for absence rather than reading the member list alone.

After any permission-rule change, **load the page as the audience you intended** — signed
out, or as a non-privileged account — rather than trusting the rule text.

### When to escalate

There is no higher role on this wiki, which means ambiguous or irreversible decisions
should go to whoever coordinates the project rather than being resolved unilaterally.

### Go deeper

[`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §1 (all of it), §3 Administrator,
§4 live matrix, §5 propagation. For SMTP problems blocking verification emails, §1f.

---

## Editor / reviewer

**What the role is for.** You decide what becomes published content. You work through
unreviewed material, judge it, improve it, and move it to a published state — or send it
back.

**What success looks like in week one.** You have taken one Draft through to publication
and one proposal through the merge workbench, and in both cases you checked the evidence
afterwards rather than assuming the button worked.

### First things to learn

1. **The Review Queue is a saved search card, not a separate application.** It lists two
   kinds of work, oldest first: `Draft` cards, and cards carrying a `+proposal` child that
   has not yet been merged. A proposal drops out of the queue once it has a `+merge audit`
   child, so the queue clears itself as you work. The exact query is in
   [`FEATURE-PRIMERS.md`](FEATURE-PRIMERS.md) §4 if you want to read or copy it.
2. **Clicking a queue row opens the card in a new tab** rather than loading it in place, so
   you can queue several up at once. Modifier keys and dropdown items behave normally.
3. **New content and changes to published content take different routes.** A genuinely new
   topic arrives as a `Draft` you can review and publish — **this is the normal human
   path, and most of your work will be here.** A change to an *existing published* card can
   arrive as a `<Card>+proposal`, which goes through the merge workbench.
4. **The proposal path was built primarily for AI agents.** It exists so that
   agent-authored changes to published content carry provenance and pass a verifying gate
   before landing. Humans *can* author a proposal as a peer review, and the workbench is
   worth understanding because you will review agent proposals in it — but it is not yet a
   comfortable human authoring workflow, and nobody expects you to reach for it by default.
   Treat it as advanced and exploratory for human-authored changes.
5. **The merge workbench is a three-way view**: *base* (what the proposal was written
   against), *current* (the live card, which may have moved since), and *proposal*. You
   choose hunk by hunk what to keep, assemble a merge draft, optionally polish it, and
   apply.
6. **Merging and approving are two different actions.** This is the single most common
   misunderstanding in this workflow. See the verification habit below.

### Your normal work loop

Open the Review Queue → take the oldest item → decide what kind of item it is.

*If it is a Draft* — the common case, and the one you should expect most days: read it,
check it against its sources, edit it directly if it needs work, then use **Approve &
Publish**. Drafts are ordinary editable cards; there is no ceremony here.

*If it is a proposal against published content* — usually agent-authored: open the merge
workbench, read the three-way view, select the hunks you want, assemble the merge draft,
polish it in the normal editor if needed, and apply. Then approve separately if the card
should move to a published state.

If you want to *propose* a change to a published card rather than review one, you can
author a proposal yourself, but you are not expected to. The honest position today is that
the proposal path is tuned for agents and has not been made comfortable for human authoring
yet. Editing a Draft, or raising the change with whoever owns the card, is the ordinary
route.

### What not to do

- **Do not apply `expert approved`.** That marker belongs to the `Expert` role. Approving
  and publishing is your job; endorsing domain accuracy is theirs.
- **Know what a direct edit to published content costs.** You are technically able to make
  one — the live matrix shows `Published` update as `Anyone Signed In` — and for a human
  editor that is currently a legitimate route, since the proposal path is not yet a
  comfortable human workflow. What you give up is the base/provenance record and the merge
  audit trail, so a substantial rewrite is worth routing through review even when a typo
  fix is not.
- **Do not "fix" a `RawData` card** to match what you think a source should have said.
  Source material is preserved verbatim; your reading of it belongs in the Draft you write
  from it.
- **Do not assume a merge that refuses to run is broken.** A proposal only merges if it is
  explicitly recorded as `full-replacement` in its `<Card>+proposal+mode` sidecar, because
  merging replaces the parent body wholesale. Anything else, including a proposal with no
  mode recorded, is refused with an explanation. That is deliberate fail-closed behaviour.

### Verification habit

**After applying a merge:** reload the parent card, confirm its content matches the merge
draft you assembled, and confirm a merge audit record now exists naming who applied it.
Applying a merge does **not** by itself change the card's type, stamp `human approved`, or
clear `needs review` — those come from the separate approval action.

**After Approve & Publish:** reload the card and confirm the `human approved` tag is
present, `needs review` is gone, the approval banner renders, and `<Card>+approved by` and
`+approved at` are populated. If you expected the cardtype to change, confirm that too.

Check for the evidence of the action you actually took. Do not check one and infer the
other.

### When to escalate

Contested content decisions, and anything that is about policy rather than a single card,
go to an Administrator or the project coordinator. Questions about whether content is
*technically correct* in a specialist domain go to an Expert.

### Go deeper

[`../ONBOARDING.md`](../ONBOARDING.md) §4 and §5 for the workflow narrative and the trust
markers. [`merge-editor/ws6-merge-editor-design.md`](merge-editor/ws6-merge-editor-design.md) is the design record
and the best explanation of why the merge model is shaped as it is.
[`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §3 Editor for the permission detail.

---

## Expert

**What the role is for.** You are a domain specialist. Your job is to say "this is
accurate" about content in your field, and to apply the wiki's strongest trust marker when
it is.

**What success looks like in week one.** You have reviewed content inside your own domain
and either endorsed it or explained specifically what is wrong with it.

### First things to learn

1. **Your endorsement is an endorsement, not a gate.** Content reaches the public wiki
   through the Editor's approval, not yours. The *Expert Approve* action adds a visible
   seal to content that is already published. This is the intended design, not a gap — it
   means publication does not stall waiting for a specialist, and readers can still see
   which articles a specialist has vouched for.
2. **You are not expected to work a general backlog.** Experts are expert in particular
   areas. The model is that editors bring you specific cards once they are ready for
   domain review, rather than you working through one undifferentiated queue.
3. **`expert approved` is the strongest marker the wiki has.** Below it: `human approved`
   means an editor approved and published it; `ai reviewed` means an AI pass looked at it
   and is explicitly **not** approval; `ai generated` describes provenance, not quality.

### Your normal work loop

An editor or coordinator brings you a card in your domain. You read it against what you
know and against its cited sources. If it is right, you apply **Expert Approve**. If it is
not, you say specifically what is wrong — a correction an editor can act on is worth far
more than a withheld seal with no explanation.

### What not to do

- **Do not endorse outside your domain.** The seal's value is that it means a specialist
  checked it.
- **Do not let an AI apply this marker on your behalf**, however confident its assessment
  looks. `expert approved` and `human approved` are human-only by design.
- **Do not treat absence of the seal as a defect.** Most content will not carry it, because
  most content has not been through specialist review.

### Verification habit

After applying the marker, confirm `<Card>+expert approved by` and
`<Card>+expert approved at` are populated and the Expert seal renders on the page. If the
action did not stick, that is a role-membership question — check that you appear in
`Expert+*members`.

### When to escalate

Disputes about whether content merits endorsement go to the Administrator who granted your
role, or to the project coordinator. Disagreements between two experts are a content
decision, not a permissions problem.

### Go deeper

[`../ONBOARDING.md`](../ONBOARDING.md) §5 for the full trust-marker vocabulary and what the
banners mean. [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §3 Expert.

---

## Raw Data Analyst

**What the role is for.** Two related jobs, and it is worth knowing both, because the second
explains why the first is granted as broadly as it is.

**Working from source material.** You read the transcripts, chat archives, publications, and
documents the wiki's articles are built from, and turn them into grounded drafts.

**Research against the backend.** The role is also intended for researchers who need access
to the AtomSpace backend to run their own experiments over the wiki's content — querying it
as a knowledge graph rather than reading it page by page.

**Why the access is broad.** This is a high-trust role by design. A researcher working
directly against the AtomSpace has effectively full visibility into the material mirrored
there, so gating them out of the corresponding `RawData` cards in the wiki UI would be
security theatre rather than a real boundary. The role is granted on trust, and it should be
granted deliberately.

**What success looks like in week one.** You can open a `RawData` card, trace an article
claim back to the source that supports it, and produce a Draft that cites its sources
rather than paraphrasing from memory.

### First things to learn

1. **What you can and cannot do with RawData.** Current production scopes `RawData` read to
   the `Raw Data Analyst` role plus Administrators. Create, update, and delete remain
   **Administrator-only**. If your workflow needs you to create or edit RawData directly,
   verify the live rules before relying on it — the seed configuration and production
   differ here.
2. **Holding the role does not by itself open the AtomSpace read tools.** In the code in
   this repository, the AtomSpace read API is gated by an explicit `mcp:atomspace:read`
   scope granted per principal, and that scope is deliberately *not* derived from any role,
   including Administrator. It fails closed: with no grant configured, nobody gets through.
   So if the research half of this role is why you were granted it, ask the operator to
   confirm the AtomSpace grant separately — being in `Raw Data Analyst+*members` will not
   be enough on its own. Whether that should become role-derived is an open handoff
   question, recorded in [`DOCUMENTATION-MAP.md`](DOCUMENTATION-MAP.md) under Follow-up
   tasks.
3. **Where source material lives.** Ingested material lands under source parents such as
   `RawData+transcripts`, `RawData+mattermost`, `RawData+google-doc`, and
   `RawData+Publications`.
4. **RawData is verbatim, on purpose.** It records what a source actually said, including
   where the source was wrong. Your reading, correction, and commentary belong in the Draft
   you produce, never in the raw body.
5. **Ingestion is human-triggered.** Nothing is watching the sources and importing
   continuously. Someone decides a body of material should come in and runs the process.
   ([`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md).)

### Your normal work loop

Read the raw material → identify what is worth saying → **write it up as a `Draft`** → cite
back to the source card so a reviewer can check you.

If what you have learned belongs in a card that is already published, raise it with an
editor or make the edit directly if policy allows, and note that a direct edit carries no
proposal provenance or merge audit — so a substantial rewrite is better routed through
review. Authoring a `<Card>+proposal` yourself is available if you want that audit trail,
but it is an advanced route and not what this role is expected to reach for.

Remember the Draft-visibility caveat at the top of this document: a Draft is not a private
workspace. If the source material is restricted, do not reproduce it into a Draft without
first checking who can read Drafts on the production wiki.

### If you also run ingestion

Running an ingestion pass is a separate, heavier activity than reading RawData, and
[`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md) is required reading before you do it.
The short version of its safe first-run posture: read the script first, use a listing or
read-only mode if one exists, run the export stage alone and inspect the output on disk,
then run the ingest stage only with an authorized operator present and on a deliberately
small first batch, and verify in the wiki before running a full one.

**Ingestion writes to the live content database. Treat any run as a production change,
because it is one.** Source-service credentials come to you out of band; they never live in
this repository.

### What not to do

- **Do not edit RawData to make it agree with the article.** If the raw card is genuinely
  wrong at the source — a corrupt import, not an inconvenient quote — raise it with an
  Administrator rather than editing it.
- **Do not paste large volumes of raw source text into Drafts.** Link to the RawData card.
- **Do not run an ingest stage to "see what happens."** There is no dry-run safety net
  once the ingest stage starts writing.

### Verification habit

Before you rely on your role for a task, confirm you can actually open a `RawData` card. If
read access fails unexpectedly, check `RawData+*type+*read` and your own membership in
`Raw Data Analyst+*members` rather than assuming a bug.

After an ingestion run, confirm cards landed under the expected parents with the expected
content before running anything larger.

### When to escalate

RawData that needs correcting at the source, ingestion that wrote something unexpected, and
anything involving source credentials all go to an Administrator or the operator.

### Go deeper

[`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md) for the tooling and the first-run
posture. [`../ONBOARDING.md`](../ONBOARDING.md) §4 Stage A and B.
[`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §3 Raw Data Analyst.

---

## AI agent operator (MCP)

**What the role is for.** You drive the wiki from an AI assistant — Claude, Codex,
Gemini/agy, or ChatGPT — through the Model Context Protocol tool surface, so the assistant
reads and writes cards directly instead of being handed pasted text.

**What success looks like in week one.** Your client is connected, you have read cards
through it, and you have authored one `+proposal` that a human reviewed. You have not
published anything directly.

### First things to learn

1. **Setup is not in this repository.** Per-client installers and profiles, the tool
   specification, and a known-quirks list live in the separate
   [`hyperon-wiki-mcp`](https://github.com/Magi-AGI/hyperon-wiki-mcp) repository. Read the
   quirks list before filing a bug. Claude, Codex, and Gemini/agy are the paths with months
   of production use behind them.
2. **Content access is your Decko account's access.** Ordinary card operations — read,
   update, search, render — run *as the authenticated Decko account* and check that
   account's permission on the card. Name-based filtering was removed; there is no separate
   "what agents may see" list. If you can read it in the browser signed in as that account,
   the tool can read it, and if you cannot, it cannot.
3. **Destructive operations carry a narrow extra guard.** A small set of operations —
   delete, rename, and trash listing among them — require Administrator standing rather
   than an ordinary card permission. That follows from your account's Decko roles; there is
   no separate MCP authorization to obtain. So the picture is: **your Decko account and the
   card rules govern content; Administrator standing governs the destructive actions.**
4. **AtomSpace reads need an additional explicit grant.** This is high-trust backend
   access, so the AtomSpace read API requires an `mcp:atomspace:read` scope granted
   per principal *on top of* ordinary card permissions. In the current code that grant is
   arranged explicitly rather than following from a role, so holding Administrator or
   `Raw Data Analyst` does not imply it, and it fails closed when nothing is configured.
   Card-scoped results are still filtered by the account's read permission as well.
5. **An agent can do exactly what its account can do — no more, and no less.** There is no
   separate "agent" restriction. A sufficiently privileged account can write directly to
   published content and bypass the intended route. Nothing technical prevents that, which
   is why agent accounts should be configured with least privilege.
6. **`+AI` is notes; `+proposal` is a change request.** Going forward, `<Card>+AI` is meant
   to be scratch space for an agent's own working notes and competing hypotheses, kept out
   of the article a reader sees. It is not a change request and not authorized to publish.
   You may also encounter legacy `+AI` cards from an older model, which can be re-opened as
   proposals — encountering both is a migration in progress, not a broken system.

### Your normal work loop

Read cards and history → search and query → draft → author a `<Card>+proposal` for anything
that changes published content → let a human review and merge it.

When a proposal is created, the server stamps `<Card>+proposal+base` and
`<Card>+proposal+provenance` inside the same transaction, so there is no window where an
unstamped proposal exists. You do not need to create those yourself.

### What not to do

- **Never apply `human approved` or `expert approved`.** Not under any circumstances, and
  not because an assessment seems confident.
- **Never write directly to a Published card.** Author a proposal.
- **Do not "fix" RawData.**
- **One writer at a time.** When several sessions are active on the same wiki, the
  orchestrating session performs the writes; advisory sessions do not write wiki state.
- **Sequential writes, not parallel batches.**
- **Do not trust an "already exists" error on create.** It can be spurious — check with a
  read before acting on it.

### Verification habit

**Read-your-writes is the standing rule.** Every write gets a follow-up read of the same
card before you or the agent treats it as done. Trusting the API response is how silent
failures survive.

### When to escalate

Anything ambiguous about scope or authorization goes to the human directing the session.
An agent should not resolve "should this be published?" on its own.

### Go deeper

[`../ONBOARDING.md`](../ONBOARDING.md) §6. `mod/mcp_api/README.md` for the endpoint list —
noting that some of its terminology reads as carried over from a sibling deck's template,
so verify role names against the live server rather than assuming
*(to be confirmed)*. [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §3 AI agent /
MCP operator.

---

## Operator / SNET technical owner

**What the role is for.** You keep the deployed application running. This is a job, not a
Decko role — there is no `Operator` role card. In practice it needs an Administrator-level
wiki account *plus* server and infrastructure access that lives entirely outside Decko's
permission system.

**What success looks like in week one.** You can deploy a code change and confirm the
running application is actually serving it, and you know which documents in this repository
describe *this* wiki versus which are generic templates.

### First things to learn

1. **Two layers deploy differently, and this trips people up.** Ruby code, views, styles,
   and scripts live in git and change by pull plus asset refresh plus an app-server reload.
   Card content — layouts, headers, sidebars, index structure, the articles themselves —
   lives in the database and changes through the wiki UI, MCP tools, or runner scripts.
2. **When both change together, deploy the code first**, then update the cards, so the view
   a card references already exists when the card starts referencing it.
3. **PostgreSQL is the engine in every environment.** Decko's generic installation
   documentation often recommends MySQL; that does not apply to this deck.
4. **Start at [`OPERATIONS.md`](OPERATIONS.md), and know what it does not yet say.** It
   records the facts about running this wiki that are actually confirmed, and lists the rest
   — SMTP provider, restart and deploy procedure, backups, monitoring, rotation, escalation
   — as explicit gaps needing server access. Behind it sit two **inherited templates**,
   `operations/DECKO-DATABASE-ACCESS.md` and `operations/EMAIL_SETUP.md`, which carry
   reusable procedures with `<placeholder>` values rather than descriptions of this wiki.
   Real hosts, keys, and paths come from the server-access handoff. Their status is tracked
   in [`DOCUMENTATION-MAP.md`](DOCUMENTATION-MAP.md) under Follow-up tasks.
5. **A dirty working tree on the server is not automatically a problem.** Several agent
   sessions may be working at once, and uncommitted changes during that work are expected.
   Investigate it as ordinary operational hygiene, not as a blocker to onboarding.

### Your normal work loop

Deploy code → confirm the application is serving it → then make any dependent card changes
→ verify those too. Between deploys: monitoring, migrations, and the runbooks indexed in
[`DOCUMENTATION-MAP.md`](DOCUMENTATION-MAP.md).

### What not to do

- **Never commit a credential, host, key, endpoint, or path to this repository.** This is
  the hardest boundary in the project and the easiest to erode by accident.
- **Do not treat "the deploy commands exited 0" as confirmation.** Confirm the running
  application is serving the new code.
- **Do not activate the AtomSpace mirror as a side effect of a deploy.** Its runbook states
  explicitly that nothing in it activates the mirror; activation is a separate, approved
  operation.

### Verification habit

After a deploy, check what the application is actually serving before touching dependent
card content. After a permission or rule change, load the page as the audience you intended
rather than trusting the rule.

### When to escalate

Infrastructure incidents and access problems go through the server-access handoff channel,
not through wiki card edits. Note that Decko access and server access are two separate
handoffs — holding one does not imply the other.

### Go deeper

[`../ONBOARDING.md`](../ONBOARDING.md) §7. [`../README.md`](../README.md) for setup, tests,
and the Decko gotchas table. [`DOCUMENTATION-MAP.md`](DOCUMENTATION-MAP.md) →
*Operations — inherited templates*, reading the status column first, and
*Subsystem and deep dive* for the AtomSpace mirror runbook.
[`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §3 Operator / SNET technical owner.

---

## Which role do I need?

A rough guide for whoever is granting access. The authoritative capability list is the live
permission matrix, not this table.

| If the person will… | They need | Granted by |
|---|---|---|
| Read public content | Nothing. Published content is public | — |
| Write drafts and review content | A signed-in account; the `Editor` role for the assigned responsibility | An Administrator |
| Endorse content in their specialist field | The `Expert` role | An Administrator, on demonstrated expertise |
| Read source material and work from it | The `Raw Data Analyst` role | An Administrator |
| Drive the wiki from an AI assistant | An account with least privilege for the job, plus MCP client setup | An Administrator, plus the MCP repository for setup |
| Deploy, migrate, and operate the server | An Administrator-level account *and* separate server access | Two separate handoffs |

---

## Where to go next

| Question | Go to |
|---|---|
| What is this system, in five minutes? | [`../ONBOARDING.md`](../ONBOARDING.md) §3 |
| How does each feature actually work? | [`FEATURE-PRIMERS.md`](FEATURE-PRIMERS.md) |
| Who can do what, exactly, right now? | [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §4 |
| What components exist and how current are they? | [`FEATURES-AND-COMPONENTS.md`](FEATURES-AND-COMPONENTS.md) |
| How do I run ingestion safely? | [`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md) |
| Which document covers a topic not listed here? | [`DOCUMENTATION-MAP.md`](DOCUMENTATION-MAP.md) |

If something in this document did not match what you found on the wiki, say so rather than
working around it. Several sections above ask you to verify against the live system
precisely because this document can go stale and the running system cannot.
