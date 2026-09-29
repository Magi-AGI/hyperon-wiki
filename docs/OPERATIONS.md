# Operations

**What is confirmed about running the Hyperon Wiki, and what is still open.**

> **This is a skeleton, deliberately.** Everything below under *Confirmed* is verifiable from
> this repository or from the public site. Everything under *(to be confirmed via
> server-access handoff)* is a real gap — it has not been checked, and nobody should act on a
> guess in its place.
>
> The document exists in this form because waiting for a complete picture kept it at nothing
> for a long time. A partial runbook that is honest about its edges is more useful than an
> absent one. Fill the gaps in as they are confirmed; do not fill them in from memory.

**This document does not contain operational specifics, and must not acquire them.** Hosts,
IP addresses, key paths, database endpoints, service names, provider accounts, and
credentials live in the **server-access handoff** — the Administrator card and its children —
never in a repository file. What belongs here is the shape of the system and the procedures,
with placeholders where values go.

---

## Confirmed

### What the system is

The Hyperon Wiki is a [Decko](https://decko.org) deck — a Rails application — served at
`wiki.hyperon.dev`.

`hyperon.dev` is a **separate landing site** with its own content and lifecycle. The split is
intentional. Do not treat it as a misconfiguration or try to merge the two.

### The database is PostgreSQL, in every environment

`config/database.yml` uses the `postgresql` adapter for development, test, and production,
and the `Gemfile` depends on `pg`. Decko's generic installation documentation frequently
recommends MySQL; **that does not apply to this deck.** Environments defined there are
production, development, and test — there is no staging environment.

### Two layers deploy differently, and the order matters

| Layer | Lives in | Changes by |
|---|---|---|
| Ruby code, views, styles, scripts | This git repository | Pull, refresh assets, reload the app server |
| Card content — layouts, headers, sidebars, index structure, the articles themselves | The database | The wiki UI, MCP tools, or runner scripts |

**When both change together, deploy the code first**, then update the cards, so the view a
card references already exists when the card starts referencing it. This is the single
ordering rule most likely to cause a confusing failure if ignored.

### Server access and wiki administration are two separate handoffs

"Operator" is a job, not a Decko role — there is no `Operator` role card. Doing the job needs
an Administrator-level Decko account **and** server or infrastructure access that sits
entirely outside Decko's permission system. **Holding one does not imply the other**, and
they are granted through different processes.

Decko-side account and role administration is documented in
[`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §1. Infrastructure access comes
through the server-access handoff.

### Access control, at the level an operator needs

Permissions are cards. Each cardtype or individual card can carry `*create`, `*read`,
`*update`, and `*delete` rules assigned to users or roles, and **a narrower rule beats a
broader default** — so an access surprise is usually a rule on a more specific card than the
one being examined. Roles resolve from the role card's member list, not from anything stored
on the user.

An MCP request authenticates as a Decko account and runs as that account, so API access
follows the same rules as the browser. Destructive operations — delete, rename, listing trash
— require Administrator standing.

Two live-configuration facts worth knowing before making an access decision, both recorded
with their caveats in [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §4: the
repository's seed data and production have diverged on `Draft` read visibility and on
`RawData` read scope. **Re-read the live rule cards rather than trusting the seed file or a
document.**

### Ingestion touches production

Source ingestion is human-triggered, not scheduled — nothing watches the sources. The ingest
stage **writes to the live content database**, so treat any run as a production change.
[`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md) carries the safe first-run posture and is
required reading before running anything; the remote-console procedure the Ruby ingesters
rely on is in [`operations/DECKO-DATABASE-ACCESS.md`](operations/DECKO-DATABASE-ACCESS.md).

### The AtomSpace mirror is not running

The mirror implementation — mod code, migrations, encoder, outbox writer, read surface —
exists at source level in `mod/atomspace_mirror/`. **It is not activated in production.**
Activation is a separate, explicitly approved operation with its own runbook at
[`atomspace/ATOMSPACE-MIRROR-DEPLOYMENT.md`](atomspace/ATOMSPACE-MIRROR-DEPLOYMENT.md), whose
own header states that nothing in it activates anything. Do not activate the mirror as a side
effect of a deploy.

### A dirty working tree on the server is not automatically a problem

Several agent sessions may be working at once, and uncommitted changes during that work are
expected. Investigate it as ordinary hygiene on its own schedule, not as a blocker to
onboarding or to reading these documents.

### Email is enabled, and the provider is Gmail

Confirmed via a read-only production evidence check on 2026-09-15: `delivery_method: smtp`,
`perform_deliveries: true`, provider Gmail via `smtp.gmail.com` port `587`, plain
authentication. SMTP username and password are set in `.env.production` but their values
were not read and are never recorded here — they live in the server-access handoff. That
check also performed sign-up/account card lookups, confirming several cards exist — it did
not confirm email delivery itself or a working UI-based recovery procedure. Details and the
card lookup are in [`operations/EMAIL_SETUP.md`](operations/EMAIL_SETUP.md), which marks the
administrator recovery path as unverified.

### The remote-console procedure is verified, with one correction

Confirmed via the same 2026-09-15 check: `.env.production` exists, rbenv shims exist and
must be prepended to `PATH`, and `ruby script/card runner -` works via stdin — **but only
when invoked as `ruby script/card runner`**, since `script/card` is not executable in this
deployment's checkout. That check covered the environment bootstrap, the rbenv PATH shape,
`.env.production` presence, and the stdin runner form itself, run directly over SSH — not
the platform-specific (PowerShell/Linux) example scripts as written. The full procedure,
corrected command templates, and troubleshooting are in
[`operations/DECKO-DATABASE-ACCESS.md`](operations/DECKO-DATABASE-ACCESS.md).

---

## Open — *(to be confirmed via server-access handoff)*

Each of these is a real gap. None should be guessed at, and none of the answers belongs in
this file as a concrete value — record that the procedure was confirmed, and keep the values
in the access handoff.

| Area | What needs confirming |
|---|---|
| **Service and restart procedure** | How the application server is supervised, and the correct way to reload or restart it after a deploy |
| **Deploy procedure** | The exact sequence for pulling code, refreshing assets, and reloading — beyond the ordering rule above |
| **Backup procedure** | What is backed up, how often, where it goes, and how a restore is performed and tested |
| **Monitoring and alerting** | What is watched, what alerts, and who receives it |
| **Credential rotation** | How source-service tokens, database credentials, and account access are rotated, and on what cadence |
| **Escalation contacts** | Who to reach for a deploy, an outage, or an access problem, and through which channel |

Until an item here is confirmed, **treat the corresponding template as a worked example
rather than an instruction.**

---

## Where the real specifics live

The **server-access handoff** — the Administrator card and its children — is the source of
truth for hosts, keys, paths, endpoints, service names, provider accounts, and credentials.
It is a separate process from this documentation, and deliberately so. If you need production
access, that is an access-handover conversation, not a documentation one.

Two supporting procedures remain in [`operations/`](operations/), each checked against this
deployment on 2026-09-15 within the scope described in that document — still placeholdered
for concrete access values. A third — a
from-scratch EC2 and RDS deployment walkthrough — was retired to
[`archive/AWS-DEPLOYMENT.md`](archive/AWS-DEPLOYMENT.md), since it described building a new
deployment on a platform this wiki already runs on.

## Related reading

| Question | Document |
|---|---|
| What is my job as an operator, in the first week? | [`ROLE-BASED-ONBOARDING.md`](ROLE-BASED-ONBOARDING.md) → Operator / SNET technical owner |
| How do I set up a development environment and run the tests? | [`../README.md`](../README.md) |
| Who can do what, and how do I grant it? | [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) |
| How do I bring source material in safely? | [`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md) |
| What is the system made of? | [`FEATURES-AND-COMPONENTS.md`](FEATURES-AND-COMPONENTS.md) |
| Which document covers a topic not listed here? | [`DOCUMENTATION-MAP.md`](DOCUMENTATION-MAP.md) |
