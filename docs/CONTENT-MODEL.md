# Content Model

**The complete reference for cardtypes, naming, index conventions, and the tag vocabulary.**

[`../ONBOARDING.md`](../ONBOARDING.md) §3 introduces this in five minutes and
[`FEATURE-PRIMERS.md`](FEATURE-PRIMERS.md) §1–§3 teaches it one idea at a time. This page is
the reference the two of them point at: the full list, with the exact card names.

> **Status:** current, drawn from repository evidence — `mod/editorial_review/data/real.yml`
> for the seeded vocabulary, and mod source for behaviour. Where the live wiki and this
> document could differ, the live wiki is authoritative and the difference is flagged.

---

## 1. Everything is a card

Pages, users, tags, layouts, saved searches, and permission rules are all cards. A card has
a **name**, a **type**, and **content**, and every change to it is versioned.

There is no separate user table, no separate settings file, and no separate permissions
store. Once that lands, most of the system stops being surprising.

## 2. Names compose with `+`

A name joined with `+` expresses "this thing, belonging to that thing." The part before the
`+` is the **left**; the part after is the **right**.

```
PLN (Probabilistic Logic Networks)                    a topic card
PLN (Probabilistic Logic Networks)+PLN Primer         an article beneath it
PLN (Probabilistic Logic Networks)+tag                that card's tags
```

This one convention carries both **hierarchy** (a child article under a topic) and
**metadata** (a card's tags, authors, approval stamps). Names nest further where needed:
`<Card>+proposal+provenance` is the provenance record of the proposal on that card.

**Naming behaviour worth knowing before you rename anything:** name keys fold case, and they
fold space against hyphen and singular against plural. Two names that look different can
resolve to the same card, and a rename can silently collide with an existing one. See
[`DECKO-GOTCHAS.md`](DECKO-GOTCHAS.md) before renaming a compound card.

## 3. Cardtypes

The type carries editorial state, not just category.

| Cardtype | What it holds | Visibility |
|---|---|---|
| **Draft** | Unpublished content pending review. The normal working state for new or in-progress articles | Production currently permits read by anyone including guests; the seed says signed-in only. See the caveat below |
| **Published** | Human-approved content | Everyone |
| **RawData** | Source material — transcripts, chat logs, meeting notes, publication text. Preserved verbatim | Read: Raw Data Analyst and Administrator. Create, update, delete: Administrator |
| **IndexSection** | A curated top-level section landing page in the wiki's index | Everyone |
| **IndexSubtopic** | A curated subtopic page beneath a section | Everyone |
| **Contributor** | A person who authored, contributed to, or edited content; referenced from `+author`, `+contributor`, `+editor` pointers | Everyone |

**Seed provenance differs across these.** `Draft`, `Published`, and `RawData` are declared in
`mod/editorial_review/data/real.yml`. `IndexSection`, `IndexSubtopic`, and `Contributor` are
in live use and referenced by mod code — `PUBLISHED_TYPE_NAMES` treats the two index types as
publication targets — but no seed file in this repository declares them. Where they are
defined is *(to be confirmed)* against the running wiki. Absence from the seed is not
evidence of absence on the wiki.

### The Draft-visibility caveat

Production reports `Draft+*type+*read = Anyone`; the repository seed says
`Anyone Signed In`. The live setting was an intentional change and reverting it has been
discussed but not done. **A Draft is therefore not a private workspace.** Before putting
restricted or source-derived material in one, check `Draft+*type+*read` on the production
wiki yourself. The full matrix and the seed-versus-production table are in
[`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §4.

## 4. Index conventions

`IndexSection` and `IndexSubtopic` are **curated navigation**, not a general container. They
share the review and approval behaviour of `Published` cards — publication stamps apply to
all three — and the index structure is deliberately managed.

The convention for substantial new write-ups is to place them in a neutral namespace and
cross-link, rather than inventing new index scaffolding. The live left sidebar is driven by
a `*sidebar` card in the database, not by a template in the code.

Structured multi-section articles follow the pattern in
[`DECKO-SECTION-PATTERN.md`](DECKO-SECTION-PATTERN.md).

## 5. Metadata subcards

Written by the workflow, not by hand.

| Card name | Type | Written when |
|---|---|---|
| `<Card>+tag` | Pointer | Draft creation, publication, expert endorsement |
| `<Card>+approved by` | Phrase | On transition to a published type |
| `<Card>+approved at` | Date | On transition to a published type |
| `<Card>+expert approved by` | — | On the Expert Approve action |
| `<Card>+expert approved at` | — | On the Expert Approve action |
| `<Card>+ai reviewed by`, `+ai reviewed at` | — | On an AI review pass |
| `<Card>+author`, `+contributor`, `+editor` | Pointer | Attribution, referencing `Contributor` cards |

The proposal and merge subcards — `+proposal`, `+proposal+base`, `+proposal+provenance`,
`+proposal+mode`, `+proposal+merge draft`, `+proposal+merge audit` — are documented in
[`EDITORIAL-WORKFLOW.md`](EDITORIAL-WORKFLOW.md) §3, where the lifecycle explains them.

**Tag names fold trailing-s plurals**, so `<Card>+tag` and `<Card>+tags` resolve to the same
card. Tag content is plain newline-separated values in a Pointer card.

## 6. The tag vocabulary

Seven markers, declared in `mod/editorial_review/data/real.yml`. They render as pills at the
top of a card and some drive banners.

| Marker | Means | Applied by |
|---|---|---|
| `needs review` | Nobody has approved this | Automatically, on Draft creation |
| `ai generated` | Produced by an AI agent. Provenance, not a verdict | The author |
| `human authored` | Written by a person | The author |
| `transcript derived` | Derived from source material such as a meeting transcript | The author |
| `ai reviewed` | An AI pass reviewed it. **Not** approval | An AI review pass |
| `human approved` | A human approved and published it | Automatically on publication; `needs review` is removed at the same time |
| `expert approved` | A domain expert endorsed it. The strongest marker here | A person holding the `Expert` role, through the Expert Approve action |

**`human approved` and `expert approved` are never applied by an AI agent**, regardless of
how confident an assessment is. They exist to mean that a person judged the content;
applying them any other way empties them of meaning.

Banner behaviour — the amber Draft notice, the green approval banner for the first week
settling into a grey line, the amber expert seal, and the not-mergeable notice — is described
in [`../ONBOARDING.md`](../ONBOARDING.md) §5.

## 7. Roles

Not covered here. [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) is the reference for
roles, accounts, and the permission matrix.

## Where to go next

| Question | Document |
|---|---|
| How does content move between these states? | [`EDITORIAL-WORKFLOW.md`](EDITORIAL-WORKFLOW.md) |
| What does a reviewer actually do? | [`REVIEW-QUEUE-GUIDE.md`](REVIEW-QUEUE-GUIDE.md) |
| Who can read or change each type? | [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) |
| What breaks when I rename a card? | [`DECKO-GOTCHAS.md`](DECKO-GOTCHAS.md) |
| Where does this live in the code? | [`ARCHITECTURE.md`](ARCHITECTURE.md) |
