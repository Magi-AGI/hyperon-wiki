# Operations — verified supporting procedures

> **These two documents have been checked against the Hyperon Wiki's actual deployment**,
> via a read-only production evidence check on 2026-09-15, and are no longer generic
> unreviewed templates. They originated as procedures carried over from a sibling deck. What
> that check actually covered: the environment bootstrap (rbenv PATH shape,
> `.env.production` presence), the stdin form of the remote-console runner
> (`ruby script/card runner -`), SMTP configuration inspection, and sign-up/account card
> lookups — all read-only, over a direct SSH session. It did **not** cover email delivery,
> UI-based account recovery, backups, restarts, deploys, or the platform-specific
> (PowerShell/Linux) example scripts in `DECKO-DATABASE-ACCESS.md` as written; see each
> document for exactly what's confirmed versus inferred.
>
> Concrete values — hosts, keys, endpoints, database names, paths, credentials — remain
> **not in this repository and must not be added to it**. They come from the server-access
> handoff, which is a separate process. What changed is that several deployment-specific
> facts (SMTP provider, `script/card` executability, the rbenv-prepend requirement) are now
> confirmed rather than assumed, within the scope above.

**Start at [`../OPERATIONS.md`](../OPERATIONS.md)**, which records what is actually confirmed
about operating this wiki and marks the rest as open. These two are supporting procedures
behind it.

| Document | What it covers |
|---|---|
| [`DECKO-DATABASE-ACCESS.md`](DECKO-DATABASE-ACCESS.md) | Running Decko/ActiveRecord scripts against a deck via remote console: environment bootstrap, `ruby script/card runner`, quoting, Windows and Linux stdin workflows, troubleshooting. Verified 2026-09-15 — `script/card` is not executable on this deployment; use the `ruby script/card runner` form. |
| [`EMAIL_SETUP.md`](EMAIL_SETUP.md) | SMTP configuration for the Hyperon Wiki: confirmed provider (Gmail via `smtp.gmail.com`), confirmed sign-up/verification card existence, and an administrator recovery path for when email is failing that the document marks as **unverified** beyond that card existence. Referenced from [`../ROLES-AND-PERMISSIONS.md`](../ROLES-AND-PERMISSIONS.md) §1f. |

A third template, an EC2 and RDS deployment walkthrough, was **retired to
[`../archive/AWS-DEPLOYMENT.md`](../archive/AWS-DEPLOYMENT.md)**. It described standing up a
new deployment from scratch on a platform this wiki is already running on, and nothing in
the documentation depended on it. It is kept as a historical record, not as guidance.

## What is still placeholdered, deliberately

[`../OPERATIONS.md`](../OPERATIONS.md) exists as the this-wiki runbook these two feed into;
it now carries the SMTP provider and remote-console procedure as confirmed facts, with the
remaining server-access items (restart/deploy procedure, backups, monitoring, credential
rotation, escalation contacts) still open. Access values themselves — hosts, keys, endpoints
— stay in the server-access handoff regardless of how verified a procedure is. Status is
tracked per document in [`../DOCUMENTATION-MAP.md`](../DOCUMENTATION-MAP.md) → Follow-up
tasks (items 1a and 1b, both now closed).

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
