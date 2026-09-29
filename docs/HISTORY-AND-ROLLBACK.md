# History and Rollback

**How card history works, how to undo a bad edit, and what history means for content that
should never have been visible.**

> **Status:** current for the mechanism, which is base Decko behaviour and is used
> operationally — card history is read through the MCP surface routinely. **Specific UI
> affordances are not verified against the running wiki in this pass.** Where this document
> describes a button or a menu item, confirm it on the wiki before relying on it; where it
> describes what history *is*, that is safe.

---

## The mechanism

Decko versions every card edit. Each card carries a history of who changed it, when, and
which fields moved. Because everything is a card, this applies as much to layouts, saved
searches, and permission rules as to articles.

Two consequences follow, and they pull in opposite directions:

- **Almost nothing is truly lost.** A bad edit, an accidental overwrite, a deletion — all are
  recoverable in the ordinary case.
- **Almost nothing is truly gone.** Removing text from a card's current body does not remove
  it from that card's history.

## Reading a card's history

Every card has a history view reachable from its card menu, showing revisions in order with
the actor and timestamp for each. Agents read the same data through the MCP surface, which
is how the editorial documentation was able to confirm, for example, when index cards were
created and later retyped.

**When to reach for it:**

- Working out what a change actually did, rather than what its author said it did.
- Confirming a write landed. For agents this is the standing rule — read the card back rather
  than trusting the response.
- Recovering content after a bad edit or a deletion.
- Auditing who changed a permission rule, which is a card like any other.

## Reverting a bad edit

Decko supports rolling a card back to a previous revision. The practical sequence:

1. **Open the card's history and identify the revision you want.** Read it before restoring —
   the revision that looks right by timestamp is not always the one you want.
2. **Restore it.** This creates a *new* revision recording the restore; it does not erase the
   intervening ones. The history stays a complete record of what happened, including the
   mistake.
3. **Verify.** Reload the card and confirm the content is what you expected.

**Restoring content is not the same as restoring state.** A rollback returns the body. It
does not re-run the workflow events that stamp approval metadata or tags, so if you roll back
across a publication boundary, check `<Card>+tag`, `<Card>+approved by`, and the cardtype
separately rather than assuming they followed.

## Deletion and the trash

**Deleting a card moves it to trash rather than destroying it.** Who may delete is governed
by the `*delete` rules — currently Administrator for the editorial cardtypes.

Recovering a deleted card is a two-part job: the card and its content are recovered through
history, and the name must match exactly. Compound names fold case, space against hyphen, and
singular against plural, so a near-miss creates a *different* card rather than restoring the
one you wanted. Confirm the exact name before recreating.

**Hyperon-specific:** this deck's MCP surface exposes an administrator-only trash listing,
which is often the quickest way to confirm something is in trash and get its exact name when
the UI path is not obvious. [`ROLE-BASED-ONBOARDING.md`](ROLE-BASED-ONBOARDING.md) →
Administrator carries the operational walkthrough.

**Escalate rather than improvise** if the deleted card was a rule card, a layout, or anything
with children. Restoring an article is routine; restoring a structural card into the wrong
shape is how a working wiki starts rendering strangely.

## What history means for sensitive content

This is the part that catches people, and it is worth stating bluntly.

**If something should never have been visible, deleting it later is not equivalent to never
having added it.** The current body changes; the revision history retains what was there.
Anyone who can read the card can, in the ordinary case, read its history.

Two practical consequences:

- **A Draft is not a safe place to stage sensitive material.** Beyond the visibility caveat —
  production currently permits Draft reads by anyone, including guests — anything placed
  there enters that card's permanent history. Check `Draft+*type+*read` on the production
  wiki before placing restricted or source-derived material in a Draft, and consider whether
  it belongs in a card at all.
- **"Clean it up afterwards" is not a plan.** This is precisely why the proposed born-clean
  architecture in the handoff record specified *rebuilding* a public wiki rather than cleaning
  one in place: history is a property of the instance, and a content purge does not change it.

If material has already entered history and that is a problem, it is an administrator
decision with real trade-offs, not a routine edit. Raise it rather than attempting a fix.

## Not verified in this pass

The following are base Decko features whose presence on this wiki was **not confirmed**:

- **Recent changes** — a site-wide feed of recent edits.
- **Watch / follow** — subscribing to notifications for a card.

Check the wiki UI directly before documenting either as available. Do not infer their
presence from generic Decko documentation.

## Where to go next

| Question | Document |
|---|---|
| What is a card, and what metadata does it carry? | [`CONTENT-MODEL.md`](CONTENT-MODEL.md) |
| Who may delete, and how do I recover a card? | [`ROLE-BASED-ONBOARDING.md`](ROLE-BASED-ONBOARDING.md) → Administrator |
| What are the permission rules on each type? | [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §4 |
| How does the merge audit trail relate to history? | [`EDITORIAL-WORKFLOW.md`](EDITORIAL-WORKFLOW.md) |
| What else surprises people about Decko? | [`DECKO-GOTCHAS.md`](DECKO-GOTCHAS.md) |
