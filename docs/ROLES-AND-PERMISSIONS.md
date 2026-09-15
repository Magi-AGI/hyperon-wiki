# Roles and Permissions

## What this document is — and is not

This document explains **who can do what on the Hyperon Wiki**: how the first
Administrator account comes into existence, how additional accounts and roles are
granted afterward, and what each role's normal working process looks like.

It is **not** a permission implementation spec, a Decko internals reference, or a
roster of who currently holds which role — role membership is deliberately not
enumerated here (see [Sensitive/out-of-scope](#sensitiveout-of-scope-here)). It is
also not a substitute for checking the live wiki: role names, exact grants, and the
permission matrix below can all change, and where this document says *(to be
confirmed)* or gives a verification step, that step is the authoritative answer, not
the paragraph next to it.

`ONBOARDING.md` §3–§5 covers the content model and editorial workflow this document's
roles operate within; read that first if you have not. This document goes one layer
deeper: accounts, roles, and CRUD permissions.

---

## 1. Administrator onboarding

There are two different things that can be called "becoming the Administrator," and
they should not be conflated:

1. **Base Decko's clean-install bootstrap** — what happens automatically the first
   time anyone signs up on a brand-new deck with no existing accounts.
2. **The current Hyperon production handoff** — how an SNET (or any new) contributor
   gets an account and a role on the wiki that is already running at
   `wiki.hyperon.dev`.

Almost everyone reading this cares about (2). (1) is included because it explains
*why* Decko's role model looks the way it does, and because it is the relevant path
if you are ever standing up a fresh deck rather than joining the existing one.

### 1a. Clean/new deck: the first administrator

On a brand-new Decko deck with no accounts yet, the first person to sign up is not a
specially privileged permanent "root" account. Per Decko's own documentation:

> "There's nothing super special about the first user. These things happen when you
> set up a wagn: 1. you're given the 'Administrator' role. (that can be edited away)
> 2. your name is added to the `*to` field of the 'signup alert email'. (that too)
> That's about it."

In other words: on a clean deck, the first successful signup is granted the
Administrator role and is registered as the recipient of new-signup notifications,
both of which are ordinary, editable card state — not a hardcoded superuser. This
only applies to a fresh deck with zero existing accounts; it does not describe
joining a wiki that is already running with existing Administrators, which is the
Hyperon Wiki's actual situation today.

### 1b. Current Hyperon production handoff path

The Hyperon Wiki at `wiki.hyperon.dev` already has Administrator accounts. A new
contributor — SNET or otherwise — gets access through one of two paths:

- **Secure access handover.** An existing Administrator account is handed over
  through the project's secure access-handover process. This never happens through
  files in this repository: no credentials, passwords, tokens, or account details are
  ever committed here. See `ONBOARDING.md` §9 for the boundary.
- **New account, granted by an existing Administrator.** A new person signs up for
  their own account, and an existing Administrator approves and/or grants it the
  appropriate role(s). This is the normal path for a new team member and is described
  below.

If you are unsure which path applies to you, ask whoever is coordinating the
handoff — do not assume either path.

### 1c. Create / approve a new account

Base Decko's account model, which the Hyperon Wiki uses unmodified:

- Accounts are represented as cards. Signing up creates a `<Name>` card plus account
  subcards such as `<Name>+*account`, `<Name>+*account+*email`, and
  `<Name>+*account+*password`.
- The Hyperon UI labels the relevant links `Register`, `Login 🔑`, `Logout ⏻`, and
  `Account 👤` (a Hyperon-specific relabeling of Decko's generic sign-up/sign-in/
  account links — see `mod/hyperon_ui/set/self/account_links.rb`).
- Clicking `Register` creates a Sign Up card and the account subcards above. By
  default, anyone can create a Sign Up.
- What happens next depends on permissions: if the signing-up user's account already
  has permission to create User cards, a verification email finalizes the signup into
  a full User account automatically. Otherwise, someone holding that permission (in
  practice, an Administrator) needs to approve it.
- If a user loses access to their verification email, they need an Administrator to
  help — there is no self-service bypass.

**Practical steps for an Administrator approving a new contributor.** These are two
different branches, not one fixed sequence — do not assume email verification always
comes before approval, or vice versa; which branch applies depends on whether the
signing-up account already holds permission to create User cards (§1c above).

*Branch 1 — self-completing signup (the account can create User cards):*

1. Confirm the person has completed `Register` and that a Sign Up / account card
   exists for them.
2. Confirm their verification email arrived and was actioned (see the SMTP dependency
   below — if email is not delivering, verification cannot complete on its own). Once
   actioned, the signup finalizes into a full User account automatically — no separate
   Administrator approval action is needed for this branch.
3. Grant whatever role(s) the person needs (§1d).

*Branch 2 — approval-required signup (the account cannot create User cards):*

1. Confirm the person has completed `Register` and that a Sign Up / account card
   exists for them.
2. An Administrator finalizes the account from the account/User card's admin actions.
   **This approval step may need to happen before the verification email is sent or
   actioned** — do not block on "email verified" as a precondition here, since in this
   branch finalization is what makes the account a full User in the first place. If
   verification email delivery is itself failing, that is a separate SMTP problem (see
   below), not a reason to withhold approval.
3. Grant whatever role(s) the person needs (§1d).

If you are not sure which branch applies, check whether the signup account already has
`*create` permission on `User` cards before deciding an approval is "blocked" on email —
treating the two branches as one sequence is how onboarding gets stuck.

### 1d. Assign roles

Role capabilities are defined by [Global permissions and the CRUD rules in §4](#4-live-permission-matrix),
except for the Administrator role, which — per Decko's documentation — has all
permissions unconditionally.

The supported, human-facing way to grant a role is through the account/role management
UI on the *target contributor's own User card* — not the Administrator's. **The
`Account 👤` link in the navbar is not that path**: it is a Hyperon-specific relabeling
of Decko's account dropdown, implemented with `link_to_mycard` (see
`mod/hyperon_ui/set/self/account_links.rb`), so it always opens the *signed-in user's
own* card, whoever is signed in. Clicking it as an Administrator opens the
Administrator's card, not the new contributor's — it cannot be used to reach someone
else's account/roles menu.

To grant a role, an Administrator instead needs to navigate directly to the target
contributor's User card (for example via search, or a direct URL to their card name)
and use the account/role management UI reachable from that card. That is the path this
document recommends.

**Technical gotcha, for anyone touching this at the card level:** Decko resolves a
user's roles by reading the *role's* member list, not anything stored on the user.
Concretely, `Self::Role.generate_rolehash` looks for `<Role>+*members` (for example
`Administrator+*members`, `Editor+*members`) and treats that as the source of truth.
`<User>+*roles` is a **virtual card Decko computes** from that membership — useful to
*read* when checking what someone has, but not an input: creating one as a shortcut grants
nothing, because role resolution never consults it as a source. Administrator membership is
tracked separately and is not reliably visible there, so check `Administrator+*members`
directly when that is the role in question. If you ever
need to inspect or script role membership at the card level, look at `<Role>+*members`
on the relevant role card — but for ordinary role grants, use the account/role UI, not
manual card edits, so you don't have to reason about this by hand.

Saving `<Role>+*members` updates Decko's cached role hash automatically; no separate
cache-reset step is needed.

### 1e. Verify the account and role

After granting access, verify it rather than assuming the UI action succeeded:

- Confirm the new User card exists and is not still a pending Sign Up.
- Read `<Role>+*members` for the role(s) you granted (e.g. `Administrator+*members`,
  `Editor+*members`, `Raw Data Analyst+*members`, `Expert+*members`) and confirm the
  new account appears there.
- Ask the person to sign in and confirm they see the capability you intended (for
  example, a Raw Data Analyst should be able to read a `RawData` card; an Editor
  should see review/publish actions).
- If something doesn't match, re-check the role card directly rather than guessing —
  role state lives on the role card, not on the user.

### 1f. SMTP dependency

Account verification emails, password-reset emails, and the signup-alert email to
Administrators all depend on SMTP being configured and working. If new accounts are
not completing verification, or password resets aren't arriving, check SMTP delivery
before assuming a permissions problem.

Provider setup, environment variables, and troubleshooting steps are in
[`operations/EMAIL_SETUP.md`](operations/EMAIL_SETUP.md). That document is an inherited generic template —
the SMTP *procedure* it describes is reusable, but concrete values (which provider,
which credentials, which domain) are not reproduced here or there; they come from the
server-access handoff, never from a repository file.

---

## 2. Base Decko concepts this document depends on

A short reference list, so the sections above don't have to re-explain each concept
inline:

- **Accounts are cards.** There is no separate user table outside the card system —
  a User's identity, email, and password all live as cards and subcards under that
  user's name.
- **Roles.** Each user has one or more roles. Each role's capabilities come from
  Global permissions, except Administrator, which can create, read, update, and
  delete any card unconditionally.
- **CRUD rules.** Permissions are expressed as four rule types per cardtype or card:
  `*create`, `*read`, `*update`, `*delete`. Rules can be assigned to specific Users or
  to Roles.
- **Permissions on sets.** A permission rule can target a broad set (e.g. "all
  cards") or a narrower one (e.g. one cardtype, or one specific card). A narrower rule
  overrides a broader default — for example, Layout cards can be restricted to
  Administrators even if most cards are editable by any signed-in user.
- **Compound-card inheritance.** A compound card `A+B` can inherit permissions from
  `A`. Relatedly, the `permission_propagation` mod repairs cached read-permission
  state on descendants when a parent's `*read` rule changes — see
  [§5](#5-permission-propagation-what-changing-a-parent-rule-can-do), because this
  matters operationally, not just as trivia.
- **History and rollback.** Every card edit is versioned and can be rolled back.
  This document doesn't cover that mechanism in detail; a feature-level walkthrough of
  history/rollback belongs in a later documentation pass (see
  `docs/DOCUMENTATION-MAP.md` → Planned, not yet written).

---

## 3. Role workflows

Each entry below covers: prerequisites, what the role can do, the normal working
process, safety boundaries, how to verify/read back your own actions, and where to
escalate.

### Administrator

- **Prerequisites:** granted by an existing Administrator (§1), or the first-signup
  bootstrap on a clean deck (§1a — not the Hyperon Wiki's current situation).
- **What they can do:** per Decko, create, read, update, and delete any card,
  unconditionally. In practice on this wiki that includes: approving/finalizing new
  accounts, granting and revoking roles via `<Role>+*members`, reading and managing
  `RawData`, deleting content, and any destructive or site-configuration action no
  other role has.
- **Normal workflow:** account/role administration (§1), unblocking anything another
  role is correctly prevented from doing, and holding final authority for destructive
  operations (card deletion, role revocation). Administrators are not expected to do
  routine editorial review themselves — that's the Editor workflow — though they are
  permitted to.
- **Safety boundaries:** Administrator power is unconditional, which is exactly why it
  should be used narrowly. Prefer the proposal/merge workflow (`ONBOARDING.md` §4) for
  ordinary content changes even though an Administrator account technically could
  write directly — direct writes bypass the audit trail the merge workflow provides.
  Never apply human-only review markers (`human_approved`, `expert_approved`) as an
  automated or AI-driven action; those are earned through the approval actions by a
  person.
- **Verification:** after any role grant/revoke, read the role's `<Role>+*members`
  card back and confirm the change landed. After any permission-rule change, check
  the rendered page as the audience you intended (e.g. load it signed out, or as a
  non-privileged account) rather than trusting the rule alone.
- **Escalation:** there is no higher role to escalate to on this wiki; ambiguous or
  irreversible decisions should go to whoever is coordinating the project
  (currently Lake), not be resolved unilaterally.

### Editor / reviewer

- **Prerequisites:** a signed-in account; elevated review/publish capability is
  granted by an Administrator if the live permission configuration requires it beyond
  ordinary sign-in (see the [live matrix](#4-live-permission-matrix) — Draft/Published
  create and update currently show `Anyone Signed In`, so the `Editor` role's exact
  marginal grant beyond baseline sign-in should be confirmed against the live role
  configuration rather than assumed).
- **What they can do:** the editorial workflow in `ONBOARDING.md` §4 — review Drafts
  and proposals in the Review Queue and merge workbench, edit Draft content, and move
  content toward a published state via the proposal/merge process.
- **Normal workflow:** work the Review Queue; for each item, open the merge workbench,
  review the three-way diff (base / current / proposal), select hunks, assemble a
  merge draft, optionally polish it, and apply. For new Drafts without a competing
  proposal, review and use the *Approve & Publish* action.
- **Safety boundaries:** Editors do not apply `expert_approved` — that marker is
  reserved for the `Expert` role. On changing published content: the `+proposal` and
  merge-workbench path is the governed route and is what AI agents must use, but it was
  built primarily for agents and is not yet a comfortable human authoring workflow. Where
  the live permissions allow it, a direct editorial edit to a published card is a
  legitimate human route; it simply carries no base, provenance, or merge-audit record, so
  prefer the reviewed route for substantial rewrites. See `ONBOARDING.md` §4.
- **Verification:** applying a merge and approving/publishing a card are two different
  actions with two different sets of evidence — do not check for one and assume the
  other happened.
  - **After applying a merge:** reload the parent card and confirm its content matches
    the merge draft you assembled, and that `<Card>+proposal+merge audit` (or
    equivalent merged-state evidence) now exists recording who applied it. Applying a
    merge does **not**, by itself, change the parent's cardtype, stamp `human_approved`,
    or clear `needs review` — those are consequences of a separate approval action, not
    side effects of the merge. Confirm the proposal is archived or locked as applicable
    to your workflow rather than assuming merging alone finished the job.
  - **After Approve & Publish (a Draft with no competing proposal, or a merged draft you
    are now approving):** reload the card and confirm the approval evidence — the
    `human_approved` tag is present and `needs review` is removed, the approval banner
    renders, and `<Card>+approved by` / `+approved at` are populated. If the cardtype is
    expected to change (e.g. Draft to Published), confirm that too rather than assuming
    the tag change implies it.
- **Escalation:** contested content decisions, or anything touching policy rather than
  a single card, go to an Administrator or the project coordinator.

### Raw Data Analyst

- **Intent:** this role serves two related purposes. It is for people who read the wiki's
  source material and write grounded content from it, and it is for **researchers who need
  AtomSpace backend access to run their own experiments** over that material. The broad
  `RawData` read access is deliberate rather than accidental: someone working directly
  against the AtomSpace already has wide visibility into the mirrored material, so
  restricting the corresponding wiki cards would not create a real boundary. Treat this as
  a high-trust role and grant it deliberately.
- **Implementation caveat, current code:** holding the role does **not** by itself open the
  AtomSpace read API. This is high-trust backend access, and it requires an
  `mcp:atomspace:read` scope granted per principal *in addition to* ordinary card
  permissions. In the current code that grant is arranged explicitly rather than following
  from a role — holding Administrator does not imply it either — and it fails closed when
  nothing is configured. So the role and the backend access must currently be arranged
  separately. Whether the scope should become role-derived is an open
  alignment item — see `docs/DOCUMENTATION-MAP.md` → Follow-up tasks.
- **Prerequisites:** the `Raw Data Analyst` role, granted by an Administrator.
- **What they can do:** per the live permission matrix, `RawData` read access is
  currently scoped to the `Raw Data Analyst` role (and Administrators). Create,
  update, and delete on `RawData` currently remain Administrator-only in production
  (§4) — if your workflow requires a Raw Data Analyst to create or edit RawData
  directly, verify that against the live `RawData+*type+*create` /
  `RawData+*type+*update` rules before relying on it, since the seed configuration and
  current production diverge here (§4).
- **Normal workflow:** the ingestion/synthesis end of the pipeline described in
  `ONBOARDING.md` §4 Stage A/B — reading raw source material (transcripts, chat
  archives, publications) that has already landed as `RawData` cards, and using it as
  the grounding for Draft summaries or proposals.
- **Safety boundaries:** do not "fix" RawData content to match what you think a source
  should have said — RawData preserves the source verbatim; editorial commentary
  belongs in the Draft/proposal you produce from it, not in the RawData card itself.
- **Verification:** confirm you can actually read a `RawData` card before relying on
  the role for a task; if read access unexpectedly fails, that's a signal to check
  `RawData+*type+*read` and your own role membership rather than assuming a bug.
- **Escalation:** if RawData needs correcting at the source (not just annotated),
  raise it with an Administrator rather than editing it directly, since RawData
  create/update is Administrator-only in current production.

### Expert

- **Prerequisites:** granted by an Administrator "based on demonstrated expertise"
  (per the role's own description card). This is a judgment call by Administrators,
  not a self-service or automatic grant.
- **What they can do:** apply the `expert_approved` trust marker to published content
  via the *Expert Approve* action — the strongest endorsement marker the wiki has.
- **Normal workflow:** review content within the Expert's domain and apply *Expert
  Approve* when it merits the endorsement. This is a human-judgment action; it is not
  and should not be automated.
- **Safety boundaries:** `expert_approved`, like `human_approved`, is never applied by
  an AI agent, regardless of how confident an agent's assessment might be — it's a
  human-only marker, applied through the approval action, by a person holding the
  `Expert` role.
- **Verification:** after applying the marker, confirm `<Card>+expert approved by` and
  `+expert approved at` are populated and the Expert seal banner renders.
- **Escalation:** disputes about whether content merits expert endorsement go to the
  Administrator who granted the role, or the project coordinator.

### AI agent / MCP operator

- **Prerequisites:** an MCP client (Claude, Codex, Gemini/agy, or ChatGPT) configured
  against the wiki's MCP server, authenticated as a Decko account with whatever
  permissions that account holds. Setup lives in the separate `hyperon-wiki-mcp`
  repository, not here.
- **What they can do:** exactly what the authenticating Decko account's roles and CRUD
  permissions allow — nothing more. Card operations run *as* that Decko account and check
  its permission on the card, so content access is governed by Decko roles together with
  the specific card and set rules that apply. **The MCP layer has no access model of its
  own**, and nothing about it widens what the account can see. Destructive operations —
  delete, rename, listing trash — carry a narrow additional guard requiring Administrator
  standing rather than an ordinary card permission. Note also that **card and set
  permission rules supersede broad role defaults** — a one-off card can be restricted to
  Administrators even when the account's role would normally grant access (§4, §5).
  Separately, AtomSpace backend reads require an explicit `mcp:atomspace:read` scope
  granted per principal in addition to card permissions; see the Raw Data Analyst entry
  above. A sufficiently privileged account can bypass the intended
  proposal/merge route entirely — nothing about the MCP layer prevents that
  technically. It's prevented by configuring agent accounts with least privilege and
  by editorial policy, not by a hard technical wall.
- **Normal workflow:** read cards and history, search/query, create and update cards,
  manage tags, and author `+proposal` cards that feed the human review workflow
  (`ONBOARDING.md` §4). One writer at a time when multiple sessions are active on the
  same wiki; sequential writes, not parallel batches; verify every write by reading
  the card back rather than trusting the API response.
- **Safety boundaries:** never apply `human_approved` or `expert_approved`. Never
  write directly to a Published card — author a `+proposal` instead. Do not "fix"
  RawData. Do not assume an "already exists" error on create is accurate without
  checking with a read — it can be spurious.
- **Verification:** read-your-writes is the standing rule: every write gets a
  follow-up read against the same card before the agent (or the human directing it)
  treats the write as done.
- **Escalation:** anything ambiguous about scope, authorization, or whether an action
  should route through a human goes to the human directing the session, not to a
  unilateral judgment call by the agent.

### Operator / SNET technical owner

- **This is an operational function, not a Decko role.** There is no `Operator` role
  card on the wiki; "operator" here describes a job — keeping the deployed application
  running — that in practice requires an Administrator-level Decko account plus
  server/infrastructure access that lives entirely outside Decko's permission system
  (SSH, database access, deployment credentials).
- **Prerequisites:** Administrator-level Decko access (§1) for the card-content side,
  and separate server-access handoff for the infrastructure side. These are two
  different handoffs; having one does not imply the other.
- **What they do:** deploy code (`git pull` + asset refresh + app-server reload),
  apply migrations, monitor the running application, and handle the operational
  runbooks indexed in `docs/DOCUMENTATION-MAP.md`.
- **Normal workflow:** deploy code before updating cards when both change together, so
  a card never references a view that doesn't exist yet (`ONBOARDING.md` §7). Treat
  card content changes (layouts, headers, sidebars, index structure) as database
  state, changed through the wiki UI, MCP tools, or runner scripts — not through git.
- **Safety boundaries:** no credentials, hosts, or infrastructure specifics belong in
  this repository, ever. `docs/OPERATIONS.md` records what is confirmed about running
  this wiki and marks the rest as open; the two inherited template docs behind it
  (`operations/DECKO-DATABASE-ACCESS.md` and `operations/EMAIL_SETUP.md`)
  describe reusable *procedures* with placeholders. Real values come
  only from the server-access handoff.
- **Verification:** after a deploy, confirm the application is actually serving the
  new code (not just that the deploy commands exited 0) before touching dependent
  card content.
- **Escalation:** infrastructure incidents and access problems go through the
  server-access handoff channel, not through wiki card edits.

---

## 4. Live permission matrix

This is what the running production wiki reports for the three editorial cardtypes,
read directly via MCP. It is **current production state as of the dates below**, not
a specification — permissions can change, and this table can go stale. If your
decision depends on getting this exactly right, re-read the rule cards
(`<Cardtype>+*type+*read`, etc.) directly rather than trusting this table.

| Cardtype | `*read` | `*create` | `*update` | `*delete` |
|---|---|---|---|---|
| `Draft` | Anyone | Anyone Signed In | Anyone Signed In | Administrator |
| `Published` | Anyone | Anyone Signed In | Anyone Signed In | Administrator |
| `RawData` | Raw Data Analyst | Administrator | Administrator | Administrator |

(Source: `Draft+*type+*read`, `Draft+*type+*create`, `Draft+*type+*update`,
`Draft+*type+*delete`, `Published+*type+*read`, `Published+*type+*create`,
`Published+*type+*update`, `Published+*type+*delete`, `RawData+*type+*read`,
`RawData+*type+*create`, `RawData+*type+*update`, `RawData+*type+*delete`, all read
live via MCP. `Draft+*type+*read` was last updated 2026-04-10T19:12:49Z;
`RawData+*type+*read` was last updated 2026-04-10T10:42:03Z.)

An anonymous HTTP request to a known Draft card (`Publications`) returned HTTP 200
with no sign-in or permission prompt, which is consistent with the live
`Draft+*type+*read = Anyone` reading above.

### Seed vs. production — read this before assuming the repo matches live

The repository's seed data, `mod/editorial_review/data/real.yml`, describes a
**different** configuration from what production currently reports:

| Cardtype | Seed `*read` | Seed `*create`/`*update` | Seed `*delete` |
|---|---|---|---|
| `Draft` | Anyone Signed In | Anyone Signed In | Administrator |
| `Published` | Anyone | Anyone Signed In | Administrator |
| `RawData` | Administrator | Administrator | Administrator |

The differences that matter most:

- **Draft read:** seed says `Anyone Signed In`; production currently says `Anyone`.
  A guest (not signed in) can currently read Draft content on production, which the
  seed alone would not lead you to expect.
- **RawData read:** seed says `Administrator`; production currently says
  `Raw Data Analyst` (in addition to Administrator). The `Raw Data Analyst` role's
  read access is a production configuration change on top of the seed default, not
  something the seed file documents.

Do not assume the seed file describes the running site. If you need to know what a
freshly-seeded deck would do versus what `wiki.hyperon.dev` does *right now*, they are
not the same, and this table is where that discrepancy is recorded.

**If the intended policy is actually the seed's narrower Draft-read rule** (signed-in
only, not public), that is a live configuration question for whoever owns wiki policy
to confirm and correct — this document reports current production behavior as
observed, and deliberately does not silently restate the old, narrower claim as if it
were still accurate.

**Status as of this writing:** the current `Anyone`-read state on Drafts was previously
an intentional change made at a stakeholder's (Ben's) request. Lake has since said it
can probably be changed back to `Anyone Signed In`, the seed default. That reversion is a
live-configuration change, not a documentation change, and it has **not** been performed
as part of this documentation pass. Until it is made and read back, treat
`Draft+*type+*read = Anyone` as the operative production state, and re-check
`Draft+*type+*read` directly on the production wiki before placing restricted or
source-derived material in a Draft.

### 5. Permission propagation — what changing a parent rule can do

Two mods handle permission propagation — how a `*read` rule change ripples through
the card tree:

- When a `+*read` rule is created or updated directly on a card (e.g.
  `Parent+*self+*read`), a finalize hook repairs the cached read-permission state on
  that card **and all its descendants**.
- When a new compound card is created under a parent that already has a
  non-default `*read` rule, the new child inherits the parent's restriction
  automatically.
- The `*right`-rule case (as opposed to a direct `*self` rule) is explicitly marked
  **TODO** in the mod's own source — its propagation behavior should not be assumed
  without checking the current code.

Practical implication: changing a `*read` rule on a card with descendants can change
visibility for all of them, not just the card you edited. Before narrowing or
widening a parent's read rule, consider what it inherits, and verify the rendered
result for the audience you intend (signed out, signed in, or role-specific) rather
than assuming the rule change did only what you expected.

---

## Sensitive/out-of-scope here

This document deliberately does not include:

- Credentials, passwords, tokens, API keys, or MFA details of any kind.
- Real SMTP values — see [`operations/EMAIL_SETUP.md`](operations/EMAIL_SETUP.md) for the procedure, and the
  server-access handoff for actual values.
- Current role membership rosters. The mechanism (`<Role>+*members`) is documented
  above because understanding it is necessary to reason about how role grants work;
  who currently holds a given role is not reproduced here.
- Concrete production hosts, keys, or paths.

---

## Where to go next

| Question | Go to |
|---|---|
| What's the editorial workflow these roles operate in? | `ONBOARDING.md` §4–§5 |
| How do I set up an MCP client? | The [`hyperon-wiki-mcp`](https://github.com/Magi-AGI/hyperon-wiki-mcp) repository |
| How is SMTP configured? | [`operations/EMAIL_SETUP.md`](operations/EMAIL_SETUP.md) |
| Where does this fit in the wider documentation set? | `docs/DOCUMENTATION-MAP.md` |
