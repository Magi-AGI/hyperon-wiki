# CLAUDE.md — Hyperon Wiki Orchestration Anchor

This file is the **top-level orientation doc** for the Hyperon Wiki repository (Magi Archive infrastructure + cluster-pilot extraction artifacts in `scripts/archive/`).

For sibling guidance:
- **Decko / Rails / PostgreSQL infrastructure** → `docs/CLAUDE.md`.
- **Coding-style conventions** → `AGENTS.md`.
- **Substantive findings about the source repos audited by the cluster pilots** (PLN five-tradition map, ECAN/OpenPsi/AtomSpace findings, source-investigation protocols like pickaxe-before-dead-code) → `E:\GitHub\hyperon reference\HYPERON_CLUSTER_FINDINGS.md`. That document is the authoritative source-code-side counterpart to this orchestration doc; do not duplicate findings here.
- **Wiki-MCP server bugs and operational conventions** (`create_card` spurious-error, `restore_card` `+tag` quirk, Draft-vs-Published edit semantics, one-writer-only protocol) → `E:\GitHub\Magi-AGI\hyperon-wiki-mcp\SERVER-BUGS.md`. That document is the authoritative MCP-side reference; cite a one-liner here when needed.

The role of this file is the **wiki-edit audit trail and engineering-roadmap anchor for `wiki.magi-agi.org`**: which cards in this wiki were touched by which cluster pilot, where the per-source extraction archives live in this repo, the Phase 3 prototype scope, and the wiki-edit semantics protocols. Findings about MeTTa/Hyperon source code are not reproduced here; check the cluster-findings doc.

---

## Cluster-pilot status

| Cluster | Closed | Cards touched | Extraction archive |
|---|---|---|---|
| PLN | 2026-04-25 | 15 | `scripts/archive/pln_pilot/source1` … `source11` |
| ECAN / Attention | 2026-04-26 | 8 | `scripts/archive/ecan_pilot/source1` … `source4` |
| OpenPsi / Motivation | 2026-04-28 | 8 (5 ECAN-cluster carrying V4-1 addendum + 3 new/annotated) | `scripts/archive/openpsi_pilot/source1` … `source4` |
| AtomSpace Backend Integration | 2026-04-29 | 9 (5 existing + 4 new) | `scripts/archive/atomspace_pilot/source1` … `source4` |
| Perception / Neural-Symbolic | 2026-05-01 | 6 (3 existing annotated + 3 new); wiki-edit pass closed 2026-05-01 | `scripts/archive/perception_pilot/source1` … `source5` |

All five are closed for this iteration. Substantive findings live in `HYPERON_CLUSTER_FINDINGS.md` (see header). The wiki-edit audit tables below record which cards in *this* wiki were modified.

---

## Wiki-edit audit tables

These tables are this-repo-specific: they document which cards in `wiki.magi-agi.org` were created or modified during each cluster pilot, with card IDs and intent. Use them to back-trace wiki state changes; pair them with `get_card_history` for full revision detail.

### PLN cluster pilot (2026-04-25)

| Phase | Card | ID | Action |
|---|---|---|---|
| 2 | RawData+Publications+xiPLN | 7403 | RawData parent (curated excerpt) |
| 2 | RawData+Publications+World-Model Calculus | 7405 | RawData parent (curated excerpt) |
| 2 | RawData+Publications+MORK MM2 PathMap Formalization | 7407 | RawData parent (curated excerpt) |
| 2 | RawData+Publications+Markov-de Finetti Formalization | 7409 | RawData parent (curated excerpt) |
| 2 | (4 corresponding +tag Pointer subcards) | 7410-7413 | `ai_generated` |
| 3 | Publications+Economic Attention Networks | 3063 | Markdown stub upgrade (appended Curated Excerpts) |
| 3 | Publications+OpenCog NS Hybrid Neural-Symbolic | 3120 | Markdown stub upgrade |
| 3 | Publications+Compositional Spatiotemporal Deep Learning | 3108 | Markdown stub upgrade (incl. ≠ FISHGRAM disambiguation) |
| 4a | Hyperon AI Algorithms+PLN+PLN Full | 4184 | Draft container update — five-tradition map + two-paradigm framing + No-Go citation |
| 4b | Hyperon AI Algorithms+PLN+PLN Full+Execution on MORK | 7106 | RichText subcard — FactorGraph paper-only correction |
| 5 | Hyperon AI Algorithms+PLN+AI | 7415 | Draft +AI proposal child for Published parent |
| 5 | Hyperon AI Algorithms+PLN+AI+tag | 7416 | Pointer (`ai_generated`) |

Total: 15 cards touched. All verified post-write via `get_card`.

### ECAN cluster pilot (2026-04-26)

| Phase | Card | ID | Action |
|---|---|---|---|
| 1 | Hyperon AI Algorithms+ECAN+ECAN Full+Development and Historical Context | 7100 | RichText subcard — appended Cluster-Pilot Findings section |
| 1 | Hyperon AI Algorithms+ECAN+ECAN Full+System Interfaces and Implementation | 7096 | RichText subcard — refined PLN bullet (3 SHAs) + metta-attention 0/4 strict-literal note + stochastic naming clarification |
| 1 | Hyperon AI Algorithms+ECAN+ECAN Full+Status and Resources | 7098 | RichText subcard — stochastic naming, 2 new Open Problems, cluster-pilot archive reference |
| 2 | Publications+Economic Attention Networks | 3063 | Markdown stub — refined PLN-control framing with Source 3 V0-1 timeline + 3 SHAs + 0/4 strict-literal note |
| 2 | Publications+Guiding PLN with Attention Allocation | 3057 | Markdown stub upgrade — Cosmo Harrigan cross-source identity, executable-realization timeline with 3 SHAs + verbatim 2018 unwiring comment, Hyperon 2026 status |
| 3 | Implementation Families+Attention and Motivation | 4751 | Draft — Attention-lineage 0/4 strict-literal note + 4 new Gaps and Consolidation Opportunities |
| 4 | Hyperon AI Algorithms+ECAN+AI | 7419 | Draft `+AI` proposal child for Published parent (cluster-pilot consolidated findings) |
| 4 | Hyperon AI Algorithms+ECAN+AI+tag | 7420 | Pointer (`ai_generated`) |

Total: 8 cards touched. All verified post-write via `get_card`.

### OpenPsi cluster pilot (2026-04-28)

| Card | ID | Intent |
|---|---|---|
| Hyperon AI Algorithms+ECAN+ECAN Full+Development and Historical Context | 7100 | V4-1 addendum: 9-event executable-coupling lifecycle reconstruction |
| Hyperon AI Algorithms+ECAN+ECAN Full+System Interfaces and Implementation | 7096 | PLN bullet expanded to two narrow executable hooks + Loving AI Ghost reference |
| Publications+Guiding PLN with Attention Allocation | 3057 | New H3 section: OpenPsi 2016-05/2016-11 lifecycle + Hanson runtime branch |
| Implementation Families+Attention and Motivation | 4751 | Hanson runtime branch under Motivation lineage; Lost-coupling Gap expanded to 9-event lifecycle |
| Hyperon AI Algorithms+ECAN+AI | 7419 | V4-1 supplementary appended to finding #2 |
| RawData+Publications+Openpsi Zhenhua | 3827 | Editorial-metadata block prepended (canonical citation, no rename) |
| Publications+OpenPsi A Novel Computational Affective Model | 7426 (new) | Markdown stub for 2013 EAAI paper; equation index + cluster-pilot Curated Excerpts |
| Publications+OpenPsi A Novel Computational Affective Model+tag | 7427 (new) | Pointer (`ai_generated`) |

Total: 8 cards touched (5 ECAN-cluster carrying the V4-1 addendum + 3 new/annotated OpenPsi-specific). All verified post-write via `get_card`.

### AtomSpace cluster pilot (2026-04-29)

| Card | ID | Action |
|---|---|---|
| About Hyperon+AtomSpace+AtomSpace Full+Implementations | 7115 | Prepended four-layer taxonomy lock-in section; cross-links to Layer 3 (DAS Full) and Layer 4 (MORK Full); added DAS first-class feature note |
| Knowledge Representations+MORK+MORK Full+Architecture and Ecosystem | 7153 | 8-crate workspace correction; PathMap as sibling-repo dependency; server-branch separation; 400M-not-500M correction; PLN paper-only framing; weighted-atom-sweep reframed as adjacent experimental analogy |
| Knowledge Representations+MORK+MORK Full+Status and Resources | 7155 | Server-branch-versioning Known Limitation; CountSink reframing as MM2 query primitive; RAM scaling 400M correction; MorkDB link-delete blocking note; cluster-pilot archive reference |
| Knowledge Representations+DAS+DAS Full | 4200 | Cluster-Pilot Lock-In section with R4.L1 wording (split implementation; AttentionBroker engineering surrogate; new-das! bridge; server-branch drift); MORK / MorkDB Storage Backends entry rewritten with delete-incomplete + Docker pin caveats |
| Implementation Families+Attention and Motivation | 4751 | DAS AttentionBroker added to ECAN repos table + as third member of ECAN-engineering-surrogate lineage; weighted-atom-sweep reframed as analogy not bridge; new Gap on three-implementations-no-strict-literal-track |
| Knowledge Representations+PathMap | 7429 (new) | Draft card — Luke Peterson author, foundational MORK trie substrate, sibling-repo classification, pathmap-book status, Lean/ZAM caveat |
| Knowledge Representations+PathMap+tag | 7430 (new) | Pointer (`ai_generated`) |
| Implementation Families+AtomSpace Backend Integration | 7432 (new) | Draft synthesis card — four-layer taxonomy, Phase 3 lock-in, 7 cluster-narrative findings, Phase 4+ blockers, source archive map |
| Implementation Families+AtomSpace Backend Integration+tag | 7433 (new) | Pointer (`ai_generated`) |

Total: 9 cards touched (5 existing + 4 new). All verified post-write via `get_card`.

### Documentation-file edits (this repo, AtomSpace cluster pilot)

- `docs/ATOMSPACE-INTEGRATION.md` — Cluster-Pilot Reframing block at top (status reframed to "Conceptual Sketch"; bottom-line corrections enumerated); Conceptual-Sketch banner on the MCP Adapter Python (apocryphal API flagged); MORK section corrected from "distributed backend" to "single-process triemap substrate"; sanitization-helper lossiness noted; footer cluster-pilot pointer.
- `docs/ROADMAP.md` — Phase 3 reframing block (READONLY-ATOMSPACE-BRIDGE; <500ms fetch / 5+ semantic insights gate; PLN No-Go caveat); Phase 4 reframed as blocked until cluster-pilot blockers clear; Decision Point updated to read-only-mirror-as-durable-feature framing.

### Perception cluster pilot (2026-05-01)

The Perception cluster pilot extraction phase closed 2026-05-01; the wiki-edit pass executed in a separately-gated session later the same day (per Codex's recommendation for clean review-after-write cycles). **Total: 6 cards touched** (3 existing annotated + 3 new) plus tag subcards.

| Card | ID | Action |
|---|---|---|
| Publications+Deep Learning Perception with PLN (2013 FISHGRAM) | 3081 | Markdown reframe — added Gino Yu as 4th co-author; full DOI/citation; `[PARTIAL-FRAGMENTED-REVIVAL]` cross-link; editorial-terminology note (paper does not use "FISHGRAM"); provenance pointer to retrieved PDF. |
| Hyperon AI Algorithms+ECAN+ECAN Full+Development and Historical Context | 7100 | RichText subcard — appended "Source 5 Perception cluster pilot addendum (2026-05-01)" section: trilateral framing; bidirectional cross-grep zero-references; pickaxe `[FISHGRAM-CLEAN-BREAK]`; AtomSpace-Scheme vs MeTTa-runtime two-stack finding; OllamaNode dual characterization; Vepstas role upgrade; ECAN/AttentionBank revival implications. |
| Implementation Families+Attention and Motivation | 4751 | Draft — inserted "Linas Vepstas Hyperon-era research portfolio" paragraph after the Hanson runtime branch with full 5-repo SHA inventory and two-stack framing; added new gap-bullet on AtomSpace-Scheme perception-portfolio non-coupling to attention. |
| Knowledge Representations+Sensory (NEW) | 7439 | Draft — opencog/sensory synthesis card: 7 wired sensory atom types (table), OllamaNode dual characterization (`[LLM-MEDIATED-PERCEPTION]` vs `[LLM-AS-KNOWLEDGE-SOURCE]`/`[LLM-AS-MEMORY-SUBSTRATE]`), sister-portfolio table (agents/motor/evidence/atomese-simd + co-authored miner/vision), AtomSpace-Scheme stack identity, `[PARTIAL-FRAGMENTED-REVIVAL]` architecture status, trilateral framing. |
| Knowledge Representations+Sensory+tag | 7440 | Pointer (`ai_generated`). |
| Implementation Families+Neural Pattern Mining (NEW) | 7442 | Draft — rejuve-bio/neural-subgraph-matcher-miner synthesis card: `[SPMiner-LINEAGE]` / `[GNN-NEURAL-MINING]` / `[PARADIGM-DISTINCT-NEURAL]` / `[STRICTLY-EMPIRICAL]`; verified code-structure (search/ subdirectory not stale README's `search_agents.py`); team authorship breakdown; trilateral tradition map; `[PARALLEL-NON-INTEGRATED]` cross-grep finding. |
| Implementation Families+Neural Pattern Mining+tag | 7443 | Pointer (`ai_generated`). |
| About Hyperon+Vision (NEW) | 7445 | Draft — opencog/vision scaffolding card: 6 wired types (2 support `ImageNode`/`ImageValue` + 4 ImageLink operation: blur/write/filter2d/halfsize); 1 `[STUB-NOT-WIRED]` (`ImageRectangleLink`); `[UNIMPLEMENTED]` README ideas; `[SCAFFOLDING-NOT-PIPELINE]` verdict; "What It Is NOT" disambiguation; bridge-to-sensory open question. |
| About Hyperon+Vision+tag | 7446 | Pointer (`ai_generated`). |
| About Hyperon+table of contents | 4022 | RichText TOC — added Vision entry between Neural-Symbolic Integration and Self-Modification and Safety. (Knowledge Representations TOC follows a Published-only convention per the PathMap precedent and was not modified for Sensory; Implementation Families has no TOC card.) |

Total: 6 substantive cards + 3 tag subcards + 1 TOC = 10 wiki writes. All verified post-write via `get_card`. Each new card linked back to the cluster-pilot extraction archive at `scripts/archive/perception_pilot/source*/`.

**Tradition-map root cards: deferred (optional).** Trilateral framing is now anchored in 5 cards (Sensory § "Trilateral Tradition Map"; Neural Pattern Mining § "Trilateral Tradition Map"; Vision § "Cluster-Narrative Position"; ECAN Dev/Historical § "Source 5 addendum"; Attention/Motivation § "Linas Vepstas portfolio"). No existing Tradition-map parent infrastructure in the wiki; creating standalone root cards would invent scaffolding for a single use case. Defer to a future session if cross-cutting tradition-map navigation is needed.

### Documentation-file edits (this repo, Perception cluster pilot)

- `scripts/archive/CLUSTER_PILOT_HANDOFF.md` — "Last refined" line updated to 2026-05-01; Gemini-specific drift guards extended with CF5.6 file-existence verification rule (8/25 dissents = 32% of cluster-pilot V-N-X drift was Gemini source-location/file-identity drift).
- `E:\GitHub\hyperon reference\HYPERON_CLUSTER_FINDINGS.md` — new "Perception / Neural-Symbolic cluster (closed 2026-05-01)" section with 8 cluster-narrative findings (trilateral framing, AtomSpace-Scheme vs MeTTa-runtime stack distinction, Vepstas portfolio mapping, OllamaNode dual characterization, [PARTIAL-FRAGMENTED-REVIVAL] verdict, sandbox-tier nuance, Surface D vocabulary, methodology lock); pointers to extraction archives updated; "Source-text gaps still open" 2013 FISHGRAM entry removed (paper retrieved); "What's next" updated.
- `CLAUDE.md` (this file) — cluster-pilot status table extended with Perception row (6 cards touched); wiki-edit-audit table populated with 9 actual writes (6 substantive + 3 tag subcards); "Source-text gaps remaining" 2013 FISHGRAM entry removed (paper retrieved at `publication_texts/2013_Goertzel_Sanders_ONeill_Yu_DeSTIN_PLN.pdf`); "What's next" Perception entry removed; Claude-specific references extended.

---

## Phase 3 architecture lock-in (this repo's engineering roadmap)

The AtomSpace Backend Integration cluster pilot's secondary purpose was to scope Phase 3 (Jan-Apr 2026) Decko/Rails/PostgreSQL → AtomSpace integration prototype work in *this* repo.

**Architecture: READONLY-ATOMSPACE-BRIDGE.** Decko/Rails/PostgreSQL stays the source of truth. AtomSpace serves a **read-only semantic mirror**. Decko MCP is the extraction API. **NO write-through to DAS or MORK in Phase 3.**

**Implementation mechanism (open question for prototype benchmark):**
- (a) `atomspace-bridge` style import / small custom exporter (lower complexity).
- (b) `mork_ffi` for low-latency queries + `mork_loader.py` for periodic hydration (higher engineering effort but directly meets latency).

**Decision criterion**: <500ms fetch gate + simplest Decko-mirror semantics.

**Phase 4+ blockers (preserved for write-through promotion)**: MorkDB link delete, MORK server-branch reconciliation, Decko-semantics-as-AtomSpace-types definitions (history, RichText, files, permissions, sections/TOC, rename/aliases, rollback). The PLN cluster No-Go theorem applies regardless of storage choice — Phase 5 PLN-over-AtomSpace must be characterized as "semantic queries that PostgreSQL cannot trivially answer," not as global PLN inference. (No-Go theorem detail: see `HYPERON_CLUSTER_FINDINGS.md` PLN section.)

---

## Extraction archive (in this repo)

Each cluster pilot's per-source brief + per-model findings + cross-model reconciliation lives under `scripts/archive/{cluster}_pilot/source*/`. The canonical synthesis files per cluster:

- **PLN**: Source 11 reconciliation (`scripts/archive/pln_pilot/source11_*/findings_reconciled_crossmodel.txt`).
- **ECAN**: Source 4 V0-1 reconciliation (broader-OpenCog ECAN consumer disambiguator) + Source 3 V0-1 reconciliation (URE STI source-selection lifecycle).
- **OpenPsi**: Source 4 V4-1 reconciliation (caller-analysis time-indexing — OpenPsi default-selector STI 2016-05/2016-11 lifecycle) + Source 3 reconciliation (HYBRID/PAPER-LEANING equation tally).
- **AtomSpace**: Source 4 reconciliation Sections A–M plus Bottom Line (canonical integration design memo, R4.B4).

The full source-by-source breakdown (which clones, which commit SHAs) is documented in `HYPERON_CLUSTER_FINDINGS.md` "Pointers to extraction archives" section.

---

## Source-text gaps remaining

- **`hyperon/PeTTa/lib/lib_pln_xi.metta`** — cited by xiPLN.tex but not located in any local clone. Either uncommitted local work, in a separate `zariuq/PeTTa` repo we haven't found, or never written.

(2013 FISHGRAM paper retrieved 2026-04-30 at `publication_texts/2013_Goertzel_Sanders_ONeill_Yu_DeSTIN_PLN.pdf` with provenance file alongside; Perception cluster pilot Source 1 used it as canonical input. Wiki card 3081 reframe deferred to gated edit pass.)

---

## Wiki-edit semantics (this repo's protocols)

These rules are **wiki-edit-specific** — they govern how Claude/Codex/Gemini sessions modify cards in `wiki.magi-agi.org`. For *source-code-investigation* protocols (pickaxe-before-dead-code, OpenCog dual-API audit, caller-analysis time-indexing, bidirectional fork-divergence), see `HYPERON_CLUSTER_FINDINGS.md` "Standing protocols" section. For MCP server bugs and operational conventions, see `hyperon-wiki-mcp/SERVER-BUGS.md`.

### Cross-model triangulation

For cluster-pilot content passes, the user runs review by Claude + Codex + Gemini, with reconciliation across all three. Any "Verified" claim from any model (attribution, identity-between-artifacts, theorem existence) must be cross-checked against the source. Gemini in particular drifts on V-N-X identity assertions.

### Wiki edit protocol

- **One writer only**: the orchestrating model executes `create_card` / `update_card` / `delete_card`. Advisory models do not write wiki state.
- **Sequential calls, no parallel batches** for wiki writes.
- **Verify after every write**: `get_card` immediately after `create_card` / `update_card` to confirm the change landed.
- **Maintain an audit trail**: name, cardtype, returned result, verified ID, timestamp for each write.
- **Treat "already exists" as real** initially — verify with `get_card` and `get_card_history` before deciding next action. (See MCP Bug #4 in `hyperon-wiki-mcp/SERVER-BUGS.md` for the spurious-error pattern.)

### RawData fidelity

- RawData wiki cards preserve raw source text; do not modify to "fix" what the source paper says.
- Editorial annotations (e.g., pseudonym clarifications) go in synthesis-layer cards or editorial-metadata blocks — not in the raw source body.
- See V0-4 in `scripts/archive/pln_pilot/source10_atps_cetta/findings_reconciled_crossmodel.txt` for the "Zarko Zaremba" pseudonym case study.

### Author attribution (wiki-side handling)

- `zariuq` = **Zarathustra Goertzel** (Zar). User-verified identity. (See `HYPERON_CLUSTER_FINDINGS.md` for full author-identity context.)
- "Oruži" denotes AI-assisted collaboration. Not a person.
- "Zarko Zaremba" is a pseudonymous self-citation in the source PDF, not a wiki extraction error — preserve in RawData; clarify in synthesis cards.

### Published vs Draft card edits

- Draft cardtype: edit directly via `update_card`.
- Published cardtype: requires `+AI` Draft child for proposed diffs.
- Tag subcards use canonical `<parent>+tag` (Pointer cardtype, plain text content like `ai_generated`). Trailing-s plurals are aliased by the wiki — `+tag` and `+tags` resolve to the same card.
- Draft parents auto-generate empty `+tag` subcards; use `update_card` to populate, not `create_card`.

### Wiki MCP operational quirks (one-line summary)

- `create_card` may return spurious "already exists" after success — verify with `get_card`. (Bug #4 in `hyperon-wiki-mcp/SERVER-BUGS.md`.)
- `restore_card` doesn't find `+tag` Pointer subcards in trash — workaround is `create_card`. (Bug #5 in `hyperon-wiki-mcp/SERVER-BUGS.md`.)

---

## Claude-specific references

The following memory paths are part of Claude Code's persistent-memory system and apply to **Claude sessions only** in this directory. Codex and Gemini have their own memory layers and cannot read these files; do not assume cross-model availability.

Claude memory at `C:\Users\Lake\.claude\projects\E--GitHub-Magi-AGI-hyperon-wiki\memory\`:
- `MEMORY.md` — index loaded into every Claude session
- `project_zar_goertzel_cluster_contributor.md` — Zarathustra Goertzel identity + pseudonym note
- `feedback_attribution_verify_against_git.md` — cross-model verification rule
- `feedback_parallel_extraction.md` — cross-model triangulation pattern
- `feedback_published_card_edits.md` — Draft vs Published edit protocol
- `feedback_pickaxe_for_dead_code.md` — git pickaxe before "dead code" / "never implemented" claims (ECAN Source 3 V0-1)
- `feedback_ecan_audit_token_list.md` — OpenCog audits must cover both C++ and Scheme/MeTTa API layers (ECAN Source 4 V0-1)
- `feedback_bidirectional_fork_divergence.md` — bidirectional fork-divergence + codebase-staleness corollary (OpenPsi Source 2 V2-1, generalized at Source 4 V4-2)
- `project_openpsi_cluster_pilot_2026_04_28.md` — OpenPsi cluster pilot summary + key SHAs + archive paths
- `project_atomspace_cluster_pilot_2026_04_29.md` — AtomSpace Backend Integration cluster pilot summary; four-layer taxonomy; Phase 3 READONLY-ATOMSPACE-BRIDGE lock-in; key SHAs; archive paths
- `project_perception_pilot_2026_05_01.md` — Perception/Neural-Symbolic cluster pilot summary; trilateral framing; AtomSpace-Scheme vs MeTTa-runtime stack distinction; Linas Vepstas Hyperon-era portfolio mapping; key SHAs; archive paths
- `feedback_gemini_file_identity_verification.md` — CF5.6 cluster-pilot default: verify Gemini file-existence claims via ls/Glob before adoption (8/25 dissents = 32% Gemini source-location/file-identity drift across 5 pilots)
- `project_user_loving_ai_ghost_history.md` — user has 18 commits in `leungmanhin/loving-ai-ghost`; defer to user recollection on Ghost/OpenPsi/STI design intent
- `reference_wiki_mcp_quirks.md` — wiki MCP operational quirks
- `project_repo_orientation_docs.md` — orientation-doc workflow
- `project_wiki_quality_bar.md` — Ben Goertzel approval bar

For multi-model continuity, the canonical record lives:
- in this repo at `scripts/archive/{pln,ecan,openpsi,atomspace,perception}_pilot/` (extraction archives) and the wiki itself (cards listed in the audit tables above);
- in `E:\GitHub\hyperon reference\HYPERON_CLUSTER_FINDINGS.md` (substantive source-code findings, cross-model-readable);
- in `E:\GitHub\Magi-AGI\hyperon-wiki-mcp\SERVER-BUGS.md` (MCP bugs and operational conventions).

---

## What's next (post-pilot work)

The PLN, ECAN/Attention, OpenPsi/Motivation, AtomSpace Backend Integration, and Perception/Neural-Symbolic cluster pilots are closed (2026-04-25, 2026-04-26, 2026-04-28, 2026-04-29, 2026-05-01 respectively). Other clusters remain (each its own multi-source pilot):

- **MeTTa runtime** (`hyperon-experimental`, `MeTTa-IL`, `PeTTa`, MORK production angle — note: substantial MORK + AtomSpace + DAS coverage now lives in the AtomSpace Backend Integration cluster pilot 2026-04-29; residual MeTTa-runtime-specific topics include MeTTa-IL semantics, PeTTa runtime closure, and MORK-server deployment topology beyond what the AtomSpace pilot covered).
- **Cross-org sweeps** (asi-alliance, fetchai, F1R3FLY-io, Rejuve, Xcceleran-do, gitlab.com/nunet) — note: `hansonrobotics/*` was substantively covered by the OpenPsi cluster pilot Source 4 (2026-04-28) and residual Hanson-era post-2019 perception utilities by the Perception cluster pilot Source 5 (2026-05-01); residual non-OpenPsi-non-perception Hanson repos may still need a separate sweep.
- **Phase 3 READONLY-ATOMSPACE-BRIDGE prototype build** — engineering work, not an extraction pilot; benchmarks decide between `atomspace-bridge` import and `mork_ffi` + `mork_loader.py` mechanism under the read-only umbrella.
