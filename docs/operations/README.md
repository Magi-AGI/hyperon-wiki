# Operations — inherited templates

> **These documents are not an operations handoff for this wiki.**
>
> They are generic Decko and Rails procedures carried over from a sibling deck, fully
> parameterized with `<placeholder>` values. The *procedures* are reusable. The concrete
> values — hosts, keys, endpoints, database names, paths, providers — are **not in this
> repository and must not be added to it**. They come from the server-access handoff, which
> is a separate process.
>
> Neither has been rewritten to describe the Hyperon Wiki's actual deployment. Read them as
> worked examples, not as instructions for this system.

**Start at [`../OPERATIONS.md`](../OPERATIONS.md)**, which records what is actually confirmed
about operating this wiki and marks the rest as open. These two are supporting procedures
behind it.

| Document | What it covers |
|---|---|
| [`DECKO-DATABASE-ACCESS.md`](DECKO-DATABASE-ACCESS.md) | Running Decko/ActiveRecord scripts against a deck via remote console: environment bootstrap, `script/card runner`, quoting, Windows and Linux stdin workflows, troubleshooting. The more directly reusable of the two. |
| [`EMAIL_SETUP.md`](EMAIL_SETUP.md) | SMTP configuration for a Decko deck: provider options, environment variables, verification. Referenced from [`../ROLES-AND-PERMISSIONS.md`](../ROLES-AND-PERMISSIONS.md) §1f when account-verification email is failing. |

A third template, an EC2 and RDS deployment walkthrough, was **retired to
[`../archive/AWS-DEPLOYMENT.md`](../archive/AWS-DEPLOYMENT.md)**. It described standing up a
new deployment from scratch on a platform this wiki is already running on, and nothing in
the documentation depended on it. It is kept as a historical record, not as guidance.

## What is missing, and it is deliberate

[`../OPERATIONS.md`](../OPERATIONS.md) exists but is a skeleton: it records the facts already
confirmed in this repository and marks everything needing server access as open. Deciding
what happens to these two templates — rewrite each for this deck, fold them into that
runbook, or retire them — is tracked per document in
[`../DOCUMENTATION-MAP.md`](../DOCUMENTATION-MAP.md) → Follow-up tasks.

**Until a document has been updated and verified, its template banner stays.** Removing the
label is the last step, not the first.

## What an operator actually needs first

- [`../ROLE-BASED-ONBOARDING.md`](../ROLE-BASED-ONBOARDING.md) → *Operator / SNET technical
  owner*, for the first week and the code-before-cards ordering rule.
- [`../../README.md`](../../README.md), for environment setup, tests, and the Decko gotchas
  table.
- [`../ROLES-AND-PERMISSIONS.md`](../ROLES-AND-PERMISSIONS.md), for account and role
  administration.
- [`../INGESTION-WORKFLOWS.md`](../INGESTION-WORKFLOWS.md), before running any ingestion.
- [`../atomspace/ATOMSPACE-MIRROR-DEPLOYMENT.md`](../atomspace/ATOMSPACE-MIRROR-DEPLOYMENT.md),
  if the AtomSpace mirror is in scope — it is the one runbook here written for this system.

Server access and Decko administrator access are **two separate handoffs**; holding one does
not imply the other.
