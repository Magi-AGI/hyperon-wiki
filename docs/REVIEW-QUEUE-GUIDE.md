# Review Queue Guide

**A reviewer's task guide: working the queue, reading the workbench, and recovering when the
parent moved under you.**

[`ROLE-BASED-ONBOARDING.md`](ROLE-BASED-ONBOARDING.md) → Editor / reviewer covers your first
week. [`EDITORIAL-WORKFLOW.md`](EDITORIAL-WORKFLOW.md) covers the lifecycle and card names.
This page is what to do when you have an item open in front of you.

> **Status:** current, drawn from the WS6 phase specifications in
> [`merge-editor/`](merge-editor/) and from `mod/review_queue_ui/`. UI details described here
> come from those specifications; if the running wiki differs, the wiki is right and this
> page needs correcting.

---

## The queue

`Review Queue` is a saved search card, not a separate application. It lists two things,
oldest first:

- `Draft` cards, and
- cards carrying a `+proposal` child that has **no** `+merge audit` child — that is,
  proposals not yet merged.

```json
{"or":{"type":"draft","right_plus":["proposal",{"not":{"right_plus":"merge audit"}}]},
 "sort":"create","dir":"asc"}
```

The `not right_plus merge audit` clause makes the queue self-clearing: applying a merge
writes the audit, and the item drops out.

**Clicking a row opens the card in a new tab** rather than loading it in place, so you can
queue several up before starting. Modifier keys and the dropdown items inside a row behave
normally.

**The queue is a listing surface, not a task manager.** There is no assignment, no claiming,
and no status beyond what the cards themselves carry — two reviewers can pick up the same
item without the queue noticing. Coordinate out of band if that matters.

---

## Reviewing a Draft

The common case, and the simpler one.

1. Read it, and check it against the sources it cites.
2. Edit it directly if it needs work. Drafts are ordinary editable cards; there is no
   ceremony.
3. Use **Approve & Publish**.
4. **Verify:** reload the card and confirm `human approved` is present, `needs review` is
   gone, the approval banner renders, and `<Card>+approved by` and `+approved at` are
   populated. If you expected the cardtype to change, confirm that too.

---

## Reviewing a proposal

Usually agent-authored. Open it in the merge workbench.

### The three panes

| Pane | What it is |
|---|---|
| **Base** | The version of the parent the proposal was written against |
| **Current** | The live parent, which may have moved since |
| **Proposal** | What is being suggested |

### The confidence banner — read it first

The workbench tells you how much to trust the three-way view, and the tiers are not cosmetic.

| Tier | What it means | What you get |
|---|---|---|
| **Verified** | The base stamp is present and its hash still matches | Full three-way merge, no warning |
| **Estimated** | The base was inferred, typically via the legacy `+AI` bridge | Yellow caveat banner; treat the third pane as a guess |
| **Stale** | A base was stamped but its hash no longer matches | **Hard stop on three-way.** Base content is withheld deliberately and the workbench falls back to two-way |
| **Unreliable** | No usable base | Two-way |

A stale base is the system refusing to silently three-way-merge against content that has
changed. It is not a bug, and there is no override to reach for.

### Reading the hunks

Each difference is a hunk, classified and colour-banded:

| Type | Meaning | Default selection |
|---|---|---|
| `stable` | Unchanged | — |
| `both_same` | Both sides made the same change | Current |
| `ai_only` | Only the proposal changed it | Current |
| `human_only` | Only the live card changed it | Current |
| `conflict` | Both changed it differently | **None — you must choose** |

**Conflicts have no default on purpose.** Assembly refuses to run while any conflict is
unresolved, and the UI blocks until every one has a selection. The client-side rendering is
preview-only and non-authoritative; the merged text that matters is derived server-side from
your recorded selections when you assemble.

### The sequence, and the two Assemble actions

Select hunks → **assemble** → optionally polish → **Apply**.

The two assemble affordances are not the same thing, and the difference matters:

| Action | What it does |
|---|---|
| **Assemble Merge Draft** | **Preview only.** Shows you the merged result. Nothing is persisted |
| **Assemble & Polish** | **Persists** the merge draft as a card and opens it for editing |

Only the second creates the `<Card>+proposal+merge draft` that Apply later verifies and
writes. If you assembled for preview and then navigated away, there is nothing to apply.

The merge draft is a separate card from the proposal, so the original proposal and its
provenance stay immutable no matter how much you polish.

### Re-assembling when a draft already exists

Once a merge draft is persisted, assembling again is not silent — the workbench offers
**Discard Edits & Re-assemble**.

**It does what it says: your polishing is lost.** The draft is re-derived from hunk
selections, and any hand-editing you did in the polish pane goes with it. If the polish
contained work you care about, copy it out before re-assembling.

---

## When apply refuses

The gate runs several checks inside one transaction, and a failure rolls everything back —
the parent is never partially written. Each refusal means something specific.

| Message | What happened | What to do |
|---|---|---|
| **Not mergeable** | The proposal's `+proposal+mode` is not `full-replacement`. Re-read at apply time, so a mode that changed after you assembled will stop you here | Deliberate fail-closed behaviour, not a fault. The notice explains why and offers no merge controls |
| **No merge-draft audit found** | There is no audit record to verify the draft against | The draft was not produced by the normal assembly path. If a draft already exists, the workbench offers **Discard Edits & Re-assemble** rather than Assemble & Polish — use it, and note that it permanently discards any polishing. **Assemble & Polish** appears only when no draft exists yet |
| **Already merged (409)** | A `+merge audit` already exists on the proposal | Someone else applied it. Open the parent and confirm the content is what you expected |
| Permission | You may not update the parent card | Ask an Administrator; do not work around it |
| **Parent changed since review began** | The optimistic lock fired — the parent's latest act no longer matches the one recorded when you assembled | See recovery below |
| **Draft changed since last saved** | The draft's content no longer hashes to the recorded `polished_hash` | Reload the merge draft and re-apply |

### Recovering when the parent moved mid-review

Someone published a change to the parent while you had the workbench open. The optimistic
lock stopped you rather than overwriting their work.

**What has and has not changed.** The **current** pane is out of date — your selections were
made against a version of the parent that is no longer live, and your assembled draft was
derived from it. The **base** is unaffected: it is reconstructed from the historical revision
recorded in the proposal's provenance, and an ordinary forward edit adds new revisions
without altering that one. So the confidence tier normally stays **verified** and you keep a
true three-way view. What you are recovering from is a moved *current*, not a broken base.

1. **Do not reload and re-apply blindly.** Applying would write a draft built against content
   that has since changed.
2. Open the parent and read what actually changed. Often it is a small edit your merge would
   have silently reverted — that is the thing the lock exists to catch.
3. Reload the workbench. It re-reads the live parent, so *current* now reflects the new
   content while *base* and *proposal* are as before.
4. Re-select against the new current. Where the other change and the proposal touch the same
   region, that region is now a conflict and you have to judge both. Then re-assemble — and
   if a polished draft already exists, **Discard Edits & Re-assemble** will lose the
   polishing, so copy anything you want to keep before confirming.
5. If the proposal has been overtaken entirely, say so on the proposal rather than merging a
   suggestion that no longer fits. The proposal is a record; it does not have to be applied.

**When the tier does change to `stale`, it means something different** — the stamped base
revision could not be found, or the content reconstructed from it no longer hashes to what
was recorded. That is a history-level problem, not the result of an ordinary edit, and the
workbench deliberately withholds the base and falls back to two-way rather than merging
against a base it cannot trust.

---

## Verifying afterwards — check the action you took

Applying a merge and approving a card are different actions with different evidence. Do not
check for one and assume the other.

**After applying a merge:** reload the parent, confirm its content matches the merge draft
you assembled, and confirm `<Card>+proposal+merge audit` now exists naming who applied it.
The merge does **not** change the cardtype, stamp `human approved`, or clear `needs review`.
Confirm the proposal now shows as merged — the workbench should render its locked view rather
than the diff.

**After Approve & Publish:** reload and confirm the tag change, the banner, and the approval
subcards, as in the Draft flow above.

---

## What you do not do

- **Do not apply `expert approved`.** That marker belongs to the `Expert` role. Approving and
  publishing is your job; endorsing domain accuracy is theirs.
- **Do not "fix" a `RawData` card** to match what you think a source should have said.
- **Do not treat an empty queue as a finished backlog** — proposals drop out once merged, and
  Drafts only appear once created.

## Where to go next

| Question | Document |
|---|---|
| What are all the cards this workflow writes? | [`EDITORIAL-WORKFLOW.md`](EDITORIAL-WORKFLOW.md) |
| Why is the merge model shaped this way? | [`merge-editor/ws6-merge-editor-design.md`](merge-editor/ws6-merge-editor-design.md) |
| The exact workbench payload and hunk shape | [`merge-editor/ws6-merge-editor-phase4-ui-contract.md`](merge-editor/ws6-merge-editor-phase4-ui-contract.md) |
| The apply gate in full | [`merge-editor/ws6-merge-editor-phase6-apply-gate.md`](merge-editor/ws6-merge-editor-phase6-apply-gate.md) |
| I need to undo something | [`HISTORY-AND-ROLLBACK.md`](HISTORY-AND-ROLLBACK.md) |
