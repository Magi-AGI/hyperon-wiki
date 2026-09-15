# AtomSpace

Documentation for the Decko → Hyperon AtomSpace track. Two documents with **very different
standing**, and the difference matters more than anything else in this folder.

| Document | What it covers | Standing |
|---|---|---|
| [`ATOMSPACE-MIRROR-DEPLOYMENT.md`](ATOMSPACE-MIRROR-DEPLOYMENT.md) | Phase 5 deployment and operations runbook for the write-through mirror: topology, safety gates, activation sequence, readiness, observability, rollback. | Real runbook for real code. **Nothing in it activates the mirror** — activation is a separate, explicitly approved operation |
| [`ATOMSPACE-INTEGRATION.md`](ATOMSPACE-INTEGRATION.md) | Broader backend integration architecture. | **Conceptual sketch, self-described.** Read its own "Cluster-Pilot Reframing" section first — it lists corrections to the rest of the document, including an import that does not exist in the real Hyperon package |

**Do not cite `ATOMSPACE-INTEGRATION.md`'s diagrams or code blocks as a description of what
runs today.** Its own header warns that code blocks are not necessarily runnable.

## What is actually built

The mirror implementation — mod code, migrations, encoder, outbox writer, read surface —
exists at source level in `mod/atomspace_mirror/`. **It is not activated in production.**
"Code exists in this repository" and "the mirror is running" are different statements, and
this folder is careful about which one it is making.

## Two related files are not here

[`../AGENT-READ-API.md`](../AGENT-READ-API.md) and
[`../AGENT-READ-YOUR-WRITES.md`](../AGENT-READ-YOUR-WRITES.md) describe the mirror's agent
read API and its read-your-writes consistency model. They remain in `docs/` because they are
**pointer stubs only** — their canonical content lives on wiki cards that have not been
published to `wiki.hyperon.dev`, and what to do about them is an open decision rather than a
filing question.

## Where to start

For the primer-level version of what the mirror is and why it exists, read
[`../FEATURE-PRIMERS.md`](../FEATURE-PRIMERS.md) §12 before either document here.
