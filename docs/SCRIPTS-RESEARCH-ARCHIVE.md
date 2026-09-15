# The `scripts/archive/` research corpus

This document describes a directory that is **not** part of this documentation set and is
not covered by it. It lives here, outside that directory, so the explanation is part of the
committed documentation while the corpus itself stays ignored.

Two directories have similar names and are not the same thing.
[`archive/`](archive/) is the documentation archive: completed phase records and shipped-fix
write-ups from this documentation set. `scripts/archive/` at the repository root is
something different — a historical research corpus, and the subject of this document.

## What it is

A record of the source-code and publication investigations that produced much of the
Hyperon Wiki's technical content between April and September 2026. Roughly 300 files:
per-source briefs, per-model findings, and cross-model reconciliations.

Each investigation follows the same shape: a `sourceN_*_brief.txt` defining the question,
then a `sourceN_*/` directory holding one `findings_<model>.txt` per reviewer plus a
`findings_reconciled_crossmodel.txt` recording what was adopted and what was rejected. The
reconciliation file is usually the one worth reading. Loose scripts at the top level are
one-off extraction helpers from the same period.

The pilots cover Probabilistic Logic Networks, Economic Attention Networks and attention
allocation, OpenPsi and motivation, AtomSpace backend integration, perception and
neural-symbolic integration, the AtomSpace mirror design specification, assorted Hyperon AI
algorithms, MeTTa runtimes and compilers, and a point-in-time wiki content audit.

**It is not documentation.** It records what was investigated, what was concluded, and
when. Read anything in it as a snapshot of belief at its stated date, not as a statement
about the system today. Where an archived conclusion and a current document disagree, the
current document wins.

## Why it was kept

It is retained deliberately, as reference for future agents and maintainers. The value is
in the reasoning trail: which repositories were examined at which commits, which claims were
verified against source and which were rejected, and where two models disagreed and why one
was adopted. That trail is expensive to reconstruct and cheap to keep.

## Boundary status — read this before sharing it

A boundary pass was run over working-tree copies of these files, replacing local and private
infrastructure references with placeholders:

| Placeholder | Replaced |
|---|---|
| `<local-workspace>` | A contributor's local checkout root and home directory |
| `<local-agent-memory>` | A contributor's local agent memory or session directory |
| `<remote-home>` | A server home-directory path |
| `<internal-source-wiki>` | An internal wiki hostname |
| `<private-operational-notes>` | Filenames of operational notes kept outside this repository |

That pass did not touch research substance. Repository names, commit SHAs, file-and-line
citations, publication references, technical verdicts, and reconciliation reasoning were left
as originally written, and no conclusion was revised or brought up to date, since doing so
would destroy the thing that makes the archive worth keeping. Two references were left in
place deliberately: `hyperon-wiki-mcp`, a real public sibling repository that the current
documentation cites by URL, and a `postgres://` string quoted from a public upstream README,
which is not a credential.

**Those edits are not part of this commit.** `scripts/archive/` is ignored, and files inside
an ignored directory were deliberately not staged, so the placeholder replacements exist only
in the working tree where they were made. The copies carried in this repository are the
originals.

So treat the corpus as it stands in the repository as **not boundary-reviewed**. That is fine
for its current purpose, which is internal reference, and it is why nothing in the
SNET-facing documentation set points into it.

## Not part of the SNET handoff

The corpus is **not** SNET-facing documentation. Nothing in the onboarding path links into
it, and newcomers have no reason to read it. Current documentation starts at
[`../ONBOARDING.md`](../ONBOARDING.md), with
[`DOCUMENTATION-MAP.md`](DOCUMENTATION-MAP.md) as the index,
[`../README.md`](../README.md) for developer setup, and
[`INGESTION-WORKFLOWS.md`](INGESTION-WORKFLOWS.md) for the ingestion tooling.

## How it is tracked

`scripts/archive/` is listed in `.gitignore`, so newly generated scratch does not accumulate
in version control. Files already tracked there from earlier work remain tracked; a
gitignore rule does not untrack what git is already following.

Two consequences worth knowing:

- Short dated banner files exist inside the corpus in some working trees. They are ignored
  and are not committed, so a fresh clone will not have them. This document is the committed
  explanation; those banners are not.
- Because the previously tracked files travel with the repository, sharing the whole
  repository externally shares them too, regardless of what this document says about scope.

Before any external sharing that would include `scripts/archive/` — a whole-repository handoff,
an export of the corpus, or relocating it out of the ignored path so it can be committed
properly — it needs its own packaging decision and its own boundary pass against whichever
copy is actually being shared. None of that is in scope for the current documentation
package, and none of it is blocked by it.
