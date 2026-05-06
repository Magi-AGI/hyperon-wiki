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
| AtomSpace Integration Phase 4 | 2026-05-05 | 2 (1 new rollup card under `Neoterics+Magus+...` parent + 1 tag subcard) — research-track cluster pilot, not a content pilot | `scripts/archive/atomspace_integration_phase4/source1` … `source7` |
| Non-clustered Hyperon AI Algorithms (Sources 1+2+3 closed — partial cluster, S4..S5 pending) | S1 AIRIS + S2 MetaMo + S3 Pattern Mining residual all closed 2026-05-06 | S1: 5 (4 new +AIRIS Full subtree + Reference URL correction); S2: 6 (3 +MetaMo Full sectioning subcards refined + 1 new +AI proposal Draft + 1 +AI tag + 1 Reference repo additions); S3: 2 (4087 trilateral framing refine + 7268 opencog/miner & pattern-index additions) | `scripts/archive/non_clustered_haa_pilot/source1_airis_paper`, `source2_metamo_paper`, `source3_pattern_mining_residual` |

All six closed clusters above are closed for this iteration; the Non-clustered HAA cluster has Sources 1+2+3 closed and remains in progress (S4 Concept Blending + Semantic Parsing, S5 NACE + AI-DSL + MOSES + MeTTa-NARS still to extract). Substantive findings live in `HYPERON_CLUSTER_FINDINGS.md` (see header). The AtomSpace Integration Phase 4 pilot is a *research-track* cluster pilot: its primary deliverables are the on-disk Source-1-through-7 reconciliations (locked PATCH set, V7-X carry-forwards, phase-numbering crosswalk) plus a single human-facing rollup card in the Magi Archive `Neoterics+Magus` subtree. It did NOT touch the Hyperon-content cards. The wiki-edit audit tables below record which cards in *this* wiki were modified by the content-track cluster pilots; the Phase 4 pilot has its own short audit row added below.

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

### AtomSpace Integration Phase 4 cluster pilot (2026-05-05)

This is a **research-track** cluster pilot — a 7-source triangulated extraction that produces the design spec for the Phase 4 implementation track (which runs as a separate parallel workstream consuming this pilot's reconciliations). Unlike PLN/ECAN/OpenPsi/AtomSpace/Perception, this pilot's deliverable is the on-disk reconciliation set, not wiki content updates. The single wiki write below is a human-facing rollup card placed in the Magi Archive `Neoterics+Magus` subtree (where the contractually-rooted 4-phase plan lives).

| Card | ID | Action |
|---|---|---|
| Neoterics+Magus+Atomspace Layer - Wiki Integration Plan+Cluster Pilot Findings Summary | 17124 | New RichText card — 7-source rollup, V7-1..V7-5 carry-forwards, locked PATCH set, phase-numbering crosswalk, on-disk archive map |
| Neoterics+Magus+Atomspace Layer - Wiki Integration Plan+Cluster Pilot Findings Summary+tag | 17125 | Pointer (`ai_generated`) — wiki normalized to `+tags` trailing-s alias on read |

Total: 1 substantive card + 1 tag subcard. Both verified post-write via `get_card`.

**Why a single rollup card and no content-card edits**: this pilot's findings are implementation-facing (mod skeletons, encoders, MCP tools, upstream patches), not wiki-content updates. Per `feedback_research_vs_implementation_workstreams.md`, the cluster-pilot research workstream and the Phase 4 implementation workstream run in parallel. The +AI Draft proposals on Magus cards 11446 + 11448 (V7-3 cognitive-stack reframing + Phase numbering crosswalk) and the direct edits on Workstream-B-authored sibling spec cards 17117 + 17120 (V7-1 auth-on-read promotion, V7-2 subscribe-wording fix, V7-4 stale-pointer fix, R7.Q14 operational gaps) are relayed to the implementation-track session for authoring under user editorial direction; they are NOT in the research-track cluster pilot's edit batch.

**Sources covered**:
- Source 1 (atomspace-bridge): READ-ONLY-BY-DESIGN, ruled out as Phase 4 substrate.
- Source 2 (hyperon-space): Phase 4 substrate locked in. PATCH-1 (pybind11 binding for `space_register_observer` at `c/src/space.rs:464-468`) + PATCH-2 (MeTTa replace-atom!) specified.
- Source 3 (atomspace-linas / cpp-mcp): atomspace-rocks = Phase 5+ primary durability candidate; cpp-mcp ruled out (19 commits behind upstream hkr04/cpp-mcp; transport-layer drift).
- Source 4 (mork/pathmap/das/rocks): STAY-HYPERON-SPACE-PHASE-4 confirmed; ROCKS-PATH primary / MORK-PATH secondary (delete blocker) / DAS-PATH Phase 6+ for Phase 5+ durability.
- Source 5 (decko-semantics): PATCH-3 (mirror mod) + PATCH-4 (encoder) specified; D3-1 16-field envelope finalized; integrate_with_delay event hook + Ruby outbox + Python sidecar architecture chosen. V5-PROTOCOL-1..5 promoted (TRACKED_FIELDS ≠ Card::Dirty; codename omission; delayed_jobs not IPC; dual-actor; POLICY-B trash).
- Source 6 (agent-facing MCP surface): [RUBY-EXTEND-PRIMARY-PHASE-4] + [POLLING-FIRST] + 8-tool PATCH-5 read surface (`query_atoms`, `get_card_atom`, `get_card_provenance`, `list_references`, `list_atoms_by_type`, `atom_types`, `atom_count_by_type`, `space_stats`); 20-field D3-1 (Source 5 16 + agent_session_id, agent_kind, origin_system, origin_request_id); PATCH-6 deferred Phase 5+. V6-PROTOCOL-1 (launcher-aware tool inventory) + V6-PROTOCOL-2 (request-path propagation) promoted; CF5.6.E [CONSTANT-CITED-FOR-IMPLEMENTATION-READINESS] promoted from ≥2-instance criterion.
- Source 7 (Magus 4-phase plan reconciliation): phase-numbering crosswalk locked (Magus Phase 2 splits into cluster Phase 3 + Phase 4); five V7-X carry-forwards (V7-1 [AUTH-ON-READ-MIRROR] load-bearing pre-implementation gate; V7-2 [CARD-C-PATCH5-SUBSCRIBE-WORDING]; V7-3 [MAGUS-PHASE4-FULL-COGNITIVE-STACK-ASPIRATIONAL]; V7-4 [CARD-D-STALE-MEMORY-POINTER]; V7-5 [D3-1-COUNT-CONVENTION]). [EXTRACTION-COMPLETE].

### Documentation-file edits (this repo, AtomSpace Integration Phase 4 cluster pilot)

- `CLAUDE.md` (this file) — status table extended with AtomSpace Integration Phase 4 row; new audit subsection above; new "Phase 4 architecture lock-in" engineering-roadmap section below; Claude-specific references extended; "What's next" updated.
- `scripts/archive/atomspace_integration_phase4/source1..7/` — 7 source directories with brief.txt + findings_codex.txt + findings_gemini.txt + findings_reconciled_crossmodel.txt each. The Source 5 reconciliation has v1 + v2 addendum structure. All committed as part of cluster close.

### Non-clustered Hyperon AI Algorithms cluster pilot — Source 1 (AIRIS) close (2026-05-06)

This is a **partial-cluster** entry — only Source 1 (AIRIS) of the Non-clustered HAA cluster is closed. The cluster continues with S2 (MetaMo), S3 (Pattern Mining residual / cross-cluster verification scope), S4 (Concept Blending + Semantic Parsing), S5 (NACE + AI-DSL + MOSES + MeTTa-NARS) still pending. The cluster pilot was authorized 2026-05-05 with Option A (backlog burn-down) pilot ordering: Non-clustered HAA → MeTTa runtime → PRIMUS → Cross-org sweeps.

| Card | ID | Action |
|---|---|---|
| Hyperon AI Algorithms+AIRIS+AIRIS Full | 7495 (new) | Draft technical-depth card — Cook & Hammer 2024 source spec, IMPLEMENTATION-BACKED-CORE verdict, Core Concepts (Causal Rules + State Graph + State Confidence/Curiosity + Self-modification scope + Comparisons), 3-repo Implementations table with full HEAD SHAs, Empirical Results, Limitations, Boundaries (vs ECAN/PLN/AtomSpace/Self-Mod-Safety/SubRep), cluster-pilot extraction archive pointer. |
| Hyperon AI Algorithms+AIRIS+AIRIS Full+tag | 7496 (new) | Pointer (`ai_generated`). |
| Hyperon AI Algorithms+AIRIS+AI | 7497 (new) | Draft +AI proposal child for Published parent (ID 801) — proposes V1-5 caveat note (AtomSpace integration is forward-looking, not current implementation), stale `singnet/AIRIS-scripts` URL fix (HTTP 404), pointer to +AIRIS Full. Apply or reject at human reviewer's discretion. |
| Hyperon AI Algorithms+AIRIS+AI+tag | 7498 (new) | Pointer (`ai_generated`). |
| Reference+GitHub Repositories | 7268 | URL correction: `singnet/AIRIS_Public` → `berickcook/AIRIS_Public` (paper-cited canonical; `singnet/AIRIS_Public` returns HTTP 404). New entry added: `singnet/AIRIS-general` (active Cook-side rewrite, MIT). |

Total: 4 new cards (2 substantive + 2 tag subcards) + 1 corrective edit. All verified post-write via `get_card`.

**Sources covered**:
- Source 1 (Cook & Hammer 2024 AIRIS paper + reference impl): paper retrieved 2026-05-06 to `publication_texts/2024_Cook_Hammer_AIRIS.pdf` (KTH/DiVA diva2:1890142, 654854 bytes, MD5 KH1mZXyDhfKdUI2QU6DrqA==). [IMPLEMENTATION-BACKED-CORE] verdict locked. Five V-N-X carry-forwards: V1-1 [AIRIS-REPO-MISATTRIBUTION] (load-bearing); V1-2 [SUBREP-AIRIS-EXTENSION-NOT-SOURCE-SPEC] (narrative guard against the Goertzel 2025-09 SubRep paper's six-tuple/tripartite-state/MC-rollout extensions being treated as Cook & Hammer source); V1-3 [AIRIS-CURIOSITY-NOT-ECAN]; V1-4 [AIRIS-CONFIDENCE-NOT-PLN-TV]; V1-5 [AIRIS-STATE-GRAPH-NOT-ATOMSPACE]. [EXTRACTION-COMPLETE].

**CF5.6.E criterion-met → standing protocol promoted**: Two instances of "wiki edit referencing external URL without WebFetch verification" landed within this cluster pilot's window — (1) the 2026-05-05 audit-correction batch left `singnet/AIRIS_Public` in `Reference+GitHub Repositories` without verifying it (V1-1); and (2) a separate stale `singnet/AIRIS-scripts` URL was found in the existing AIRIS Published parent's `+content` subcard. Both URLs return HTTP 404. Per CF5.6.E ≥2-instance promotion criterion (originally locked at AtomSpace Integration Phase 4 close 2026-05-05), the standing protocol "wiki edits referencing external URLs must include fresh WebFetch verification immediately before the edit; cite the verification (HTTP status + redirect path) in the edit's commit message or notes" is **promoted from candidate to live**. Saved to memory as `feedback_webfetch_verify_external_urls.md`.

**Drift findings against Gemini extraction (cumulative count update)**:
- D1 (off-by-one AIRIS-general airis.py L23 → actual L24/L30 for s_input/u_input).
- D2 (line count off-by-5: airis_stable.py "1,876" → actual 1881).
- D3 (LOAD-BEARING REJECTED): Gemini's V1-3 carry-forward asserted `lib_spaces.metta` as "phantom-file citation for HAA (confirmed in Source 1-7)." Cross-archive grep returned 0 hits for `lib_spaces` (only Gemini's just-written findings) vs 55 hits across 12 files for `lib_pln_xi`. Gemini conflated the PLN-cluster phantom file with a different (nonexistent) "spaces" filename. Codex's V1-3 (AIRIS-CURIOSITY-NOT-ECAN) adopted as canonical V1-3.

Cumulative Gemini source-location/file-identity drift across closed pilots: previously 8/25 dissents = 32% across 5 prior pilots (per `feedback_gemini_file_identity_verification.md`). This S1 reconciliation adds 3 more drift findings (D1+D2+D3) to the cumulative count. CF5.6 protocol continues to apply.

### Documentation-file edits (this repo, Non-clustered HAA Source 1 close)

- `CLAUDE.md` (this file) — cluster-pilot status table extended with partial-cluster row; new audit subsection above; CF5.6.E protocol-promotion note; "What's next" updated.
- `publication_texts/2024_Cook_Hammer_AIRIS.pdf` + `publication_texts/2024_Cook_Hammer_AIRIS.provenance.txt` — paper retrieved + provenance.
- `scripts/archive/non_clustered_haa_pilot/source1_airis_paper_brief.txt` (710 lines, 16 P-claims, 12 S1.Q questions, 4 Codex pre-extraction refinements applied, §3.A pre-resolved by orchestrator).
- `scripts/archive/non_clustered_haa_pilot/source1_airis_paper/findings_codex.txt` + `findings_gemini.txt` + `findings_reconciled_crossmodel.txt` — three-way reviewer extraction + reconciliation. Three-way sign-off (Codex 2026-05-06, Gemini 2026-05-06, orchestrator Claude 2026-05-06).

### Non-clustered Hyperon AI Algorithms cluster pilot — Source 2 (MetaMo) close (2026-05-06)

This is the second-source close of the partial-cluster Non-clustered HAA pilot. Source 2 (MetaMo) extracted both AGI 2025 papers (Goertzel & Lian) plus three reference implementations against the existing wiki MetaMo subtree.

| Card | ID | Action |
|---|---|---|
| Hyperon AI Algorithms+MetaMo (Motivational Framework)+MetaMo Full+Core Mechanisms and Formalism | 7135 | Refine — Implementation Backing section appended with 11-construct file:line cite table; [IMPLEMENTATION-BACKED-CORE] / [FORMAL-LAWS-PAPER-ONLY] split; Principle 2 [SKELETON-IMPLEMENTATION] note. |
| Hyperon AI Algorithms+MetaMo (Motivational Framework)+MetaMo Full+Historical Lineage | 7137 | Refine — new MAGUS section attributing decision-monad component to Mikeda 2024; reframed MetaMo (2025) section to subsumes-not-replaces with hyperon-openpsi-zero-MetaMo-naming finding. |
| Hyperon AI Algorithms+MetaMo (Motivational Framework)+MetaMo Full+Status and Resources | 7139 | Refine — trilateral classification table (formal-reference + heuristic-prototype + predecessor-substrate + Prolog-port variant); Primary Sources updated to Goertzel-first; MAGUS-Mikeda-2024 added. |
| Hyperon AI Algorithms+MetaMo (Motivational Framework)+AI | 7742 (new) | Create — Draft +AI proposal child against the Sandra-spec sibling cards (P-AI-1 authorship reversal for +responsible 7566; P-AI-2 trilateral URL split for +github 7567). |
| Hyperon AI Algorithms+MetaMo (Motivational Framework)+AI+tag | 7743 | Update auto-generated Pointer subcard with `ai_generated`. |
| Reference+GitHub Repositories | 7268 | Refine — hyperon-openpsi framing fixed to [OPENPSI-PREDECESSOR-SUBSTRATE] with zero-MetaMo-naming note; MetaMo-Prototype added; MetaMo-Python annotated with cluster-pilot verdict tags. |

Total: 6 substantive writes (3 refines + 1 create + 1 tag update + 1 cross-card audit refine). All verified post-write via `get_card`. Sandra-spec sibling cards (+responsible, +github, +description, +approval, +deep_dive, +examples, +Motivational dynamics) were preserved unchanged per `feedback_sandra_spec_port_recheck_before_batch.md`; the +AI proposal child carries the substantive corrections targeting the new sibling structure.

**Sources covered**:
- Source 2 (MetaMo paper bundle + 3 reference implementations): both AGI 2025 papers (Goertzel & Lian) read from local Mattermost archive. Verdict locked: **[PAPER-LEANING-HYBRID]** / **[IMPLEMENTATION-BACKED-CORE]** / **[REFERENCE-IMPLEMENTATION-NOT-PRODUCTION]**. Seven V2-X carry-forwards: V2-1 [METAMO-AUTHORSHIP-ORDER-WIKI-DRIFT, load-bearing] (Goertzel-first); V2-2 [METAMO-PYTHON-PRIMARY-REFERENCE]; V2-3 [HYPERON-OPENPSI-PREDECESSOR-NOT-METAMO-IMPL, load-bearing] (zero MetaMo/MAGUS naming at HEAD `3b356c5`); V2-4 [METAMO-PROTOTYPE-HEURISTIC-PARALLEL-PROTOTYPE]; V2-5 [SUBREP-METAMO-FAITHFUL-AIRIS-EXTENSION-GUARD, narrative-guard] (do NOT generalize AIRIS S1.V1-2 extension drift to MetaMo); V2-6 [METAMO-TWO-DUPLICATE-NOT-BYTE-IDENTICAL, non-blocking diagnostic] (`MetaMo_Two.json` 30,585 bytes vs `MetaMo_Two__1_.json` 30,762 bytes); V2-7 [MAGUS-BOUNDARY-EXTERNAL-COMPONENT, load-bearing] (Mikeda 2024 attribution).

**Drift findings against Gemini extraction (cumulative count update)**:
- D1..D2 (cosmetic line offsets): bimonad.py:42 vs Gemini L43; bimonad.py:62 vs Gemini L68; openpsi/appraisal.py:17 vs Gemini L18.
- D3 (meaningful body-line drift): stability.py `apply_homeostatic_damping` at L84; Gemini cited L65 (inside a different function — `check_contractive_update_law`), off by 19.
- D4 (PHANTOM LINE): Gemini cited stability.py L100 for "contractive update check"; the file ends at L99.
- D5 (cosmetic, but illustrative): wiki inventory completeness — Codex 6 cards (incl. RichText virtual parents 4086/3089/7441), Gemini 3 cards.
- **D6 (LOAD-BEARING, REJECTED)**: Gemini's S2.Q6 Principle 2 verdict `[PAPER-ONLY]` "not found in MetaMo-Python" — REJECTED via direct read. `class TranslationFunctor` exists at `category/functors.py:57` with `simulate_peer` method invoked at `applications/research_assistant.py:88`. Reconciled to `[IMPLEMENTATION-BACKED]` (skeleton — demo uses identity translation matrix, but the class runs and is exercised).

Cumulative Gemini drift through HAA S2: **17/34 ≈ 50%** (8/25 prior + 3 S1 + 6 S2 — D1..D6).

### Non-clustered Hyperon AI Algorithms cluster pilot — Source 3 (Pattern Mining residual) close (2026-05-06)

This is the third-source close of the partial-cluster Non-clustered HAA pilot. Source 3 was scoped narrowly as **residual cross-cluster verification only** — three opencog/miner forks + singnet/pattern-index paradigm classification + cross-cluster HAA wiki alignment vs the closed Perception cluster pilot 2026-05-01 (whose S2/S3/S4 reconciliations are authoritative for opencog/miner + hyperon-miner trio + rejuve-bio/neural-subgraph-matcher-miner; reviewers explicitly forbidden from re-extracting those).

| Card | ID | Action |
|---|---|---|
| Hyperon AI Algorithms+Pattern Mining | 4087 | Refine — trilateral tradition map (symbolic + neural + perception); [PARTIAL-FRAGMENTED-REVIVAL] for 2013 DeSTIN-FISHGRAM-PLN; "What This Card Is Not" disambiguation block; pattern-index adjacent-legacy paragraph; cross-links to ID 7442 / 7439 / 3090; roadmap qualifiers on MORK/TransWeave/WILLIAM/Symbolic-Heads. |
| Reference+GitHub Repositories | 7268 | Refine — opencog/miner added under Cognitive Logic & Reasoning (legacy symbolic baseline + paper-faithful Chi/Xia/Yang/Muntz 2005 + fork-staleness summary); singnet/pattern-index added under Infrastructure & Storage as [PATTERN-INDEX-SEPARATE-PARADIGM-ADJACENT]. |

Total: 2 substantive writes. C2 (cosmetic 3090 wording pass) and C3 (separate Knowledge Representations+Pattern Index card) skipped per Codex's reconciliation default to lighter-touch in-paragraph mention. C5 NOOP confirmed (no AIRIS cleanup needed; S1 corrections already shipped 2026-05-06). All verified post-write via `get_card`.

**Sources covered**:
- Source 3 (Pattern Mining residual): NO new tradition; trilateral framing already locked at Perception. Seven V3-X carry-forwards: V3-1 [HAA-PATTERN-MINING-CARD-STALE, load-bearing] (card 4087 last update 2026-04-10 predates Perception close 2026-05-01); V3-2 [LEUNGMANHIN-MINER-STRICT-FORK-STALE]; V3-3 [SINGNET-MINER-STRICT-FORK-STALE-MERGED-UPSTREAM]; **V3-4 [NGEISWEI-MINER-MAINTAINER-FORK-MERGED-BEHIND, load-bearing]** (corrects Gemini's direction-reversed claim; see drift findings below); V3-5 [PATTERN-INDEX-SEPARATE-PARADIGM-ADJACENT]; V3-6 [SGNN-NOT-PATTERN-MINING, narrative-guard for S4]; V3-7 [REFERENCE-REPO-CARD-PATTERN-MINING-GAPS].

**Fork-divergence verdicts (orchestrator CF5.6-verified via `git rev-list --left-right --count`)**:
- `leungmanhin/miner` HEAD `9b3e7cf` — **0 ahead / 44 behind** opencog/master (Gemini claimed 0/245).
- `singnet/miner` HEAD `6797171` — **5 ahead / 58 behind** with all 5 ahead-commits being merge/sync metadata (Gemini claimed 0/250).
- `ngeiswei/miner` HEAD `339cc49` — **0 ahead / 8 behind** opencog/master, with the 8 opencog-ahead commits being API/CMake/cogutil work that ngeiswei has not picked up. The historically-staged ngeiswei work (#67 misc-fix + #68 proof comment) has merged into opencog/miner mainline. **Gemini claimed 8 ahead / 0 behind [ACTIVE-MAINTAINER-SCRATCH] — DIRECTION-REVERSED, REJECTED**.
- `singnet/pattern-index` — 1 ahead / 3 behind opencog/pattern-index. Verdict [PATTERN-INDEX-SEPARATE-PARADIGM-ADJACENT].

**Drift findings against Gemini extraction**:
- D1+D2+D3 (numerical fork divergence): Codex 100% accurate on all four numerical claims; Gemini 0% accurate, including one **DIRECTION-REVERSED** verdict tag (D3 ngeiswei) that would have produced wrong wiki text.
- D4 (cosmetic): pattern-index count Gemini did not provide; Codex's 1/3 verified.
- D5 (cosmetic): Wiki card inventory completeness — Codex 6 cards + raw discussion list; Gemini 3 cards.
- Gemini's `[ACTIVE-MAINTAINER-SCRATCH]` tag for ngeiswei REJECTED via CF5.6 D3.
- Gemini's S3.Q12 C3 "Add missing S1 AIRIS corrections" REJECTED — already shipped at S1 close 2026-05-06 commit `65783e2`; including would create duplicate or accidentally revert.

Cumulative Gemini drift through HAA S3: **22/39 ≈ 56%**. The 50% midpoint (S2 close) crossed; the 60% escalation threshold approaching. **First time observed: a load-bearing direction-reversed claim** (D3 ngeiswei) — different in kind from prior off-by-N citation drifts. Recommendation at S4 dispatch: explicitly require Gemini to copy-paste exact `git rev-list --left-right --count` output rather than re-state, removing the most recent confabulation channel. Gemini self-acknowledged this commitment in S3 sign-off.

### Documentation-file edits (this repo, Non-clustered HAA Sources 2 + 3 close)

- `CLAUDE.md` (this file) — cluster-pilot status table updated with S2 + S3 close (sources 1+2+3 closed, S4..S5 pending); two new audit subsections above; "What's next" updated; Claude-specific references extended.
- `scripts/archive/non_clustered_haa_pilot/source2_metamo_paper_brief.txt` — title-line authorship-form drift "Lian & Goertzel" → "Goertzel & Lian" fixed (12 occurrences); checklist updated to READY-FOR-REVIEWER state.
- `scripts/archive/non_clustered_haa_pilot/source2_metamo_paper/findings_codex.txt` + `findings_gemini.txt` + `findings_reconciled_crossmodel.txt` (565 lines) — three-way Codex+Gemini+orchestrator-Claude sign-off recorded.
- `scripts/archive/non_clustered_haa_pilot/source3_pattern_mining_residual_brief.txt` (601 lines, residual scope; frozen prior art = Perception pilot reconciliations; explicit no-re-extract boundaries on opencog/miner + hyperon-miner trio + rejuve-bio/neural-subgraph-matcher-miner).
- `scripts/archive/non_clustered_haa_pilot/source3_pattern_mining_residual/findings_codex.txt` + `findings_gemini.txt` + `findings_reconciled_crossmodel.txt` (623 lines) — three-way sign-off recorded; Gemini's [ACTIVE-MAINTAINER-SCRATCH] direction-reversed verdict rejected per CF5.6.
- New memory files at `C:\Users\Lake\.claude\projects\E--GitHub-Magi-AGI-hyperon-wiki\memory\`: `project_haa_cluster_pilot_source2_2026_05_06.md`, `project_haa_cluster_pilot_source3_2026_05_06.md`, `feedback_sandra_spec_port_recheck_before_batch.md` (process learning from the parallel-session Sandra-spec port detected mid-batch).

---

## Phase 4 architecture lock-in (this repo's engineering roadmap)

The AtomSpace Integration Phase 4 cluster pilot's primary deliverable is the **co-canonical AtomSpace+Postgres write-through** architecture for `mod/atomspace_mirror/` in this repo. Decko/PostgreSQL stays the source of truth; every non-draft Card mutation is mirrored to a Hyperon Space instance via a Decko-callback-driven event hook. This SUPERSEDES the Phase 3 read-only architecture for the write-through track; Phase 3 (read-only mirror via atomspace-bridge style import) is now itself superseded for the write-through track per Card 17117 §1.

**Locked architecture (Phase 4)**:
- **Substrate**: Hyperon Space at HEAD (single-process, in-memory) via existing Hyperon Rust/Python bindings. Persistence + distribution = Phase 5+/6+.
- **Mirror mod**: `mod/atomspace_mirror/` (PATCH-3) — `integrate_with_delay` event subscription on `%i[create update delete]` with `next if action&.draft` filter; outbox ActiveRecord-table backup; recursion guard excludes mirror's own outbox writes.
- **Encoder**: `card_atom_encoder.rb` (PATCH-4) — DeckoCard (14 fields, codename read from `cards.codename` column at mirror time per V5-PROTOCOL-2), DeckoReference (4-code I/L/Q/P), DeckoProvenance (20-field D3-1 envelope incl. dual-actor `auth_current_id` + `auth_as_id` + 4 Source-6 agent-identity fields).
- **IPC contract**: stable JSON over HTTP/Unix-socket (primary) between Ruby outbox-drain worker and Python sidecar; outbox table backup. `delayed_jobs.handler` is NOT the IPC contract (V5-PROTOCOL-3).
- **Idempotency**: keyed by `event_id = "decko:action:<action_id>"`.
- **Trash**: V5-PROTOCOL-5 [POLICY-B-IS-FAITHFUL-MIRROR] — `Replace(old, new_with_Trash_true)`, NOT `Remove`. MeTTa queries default-filter `(Trash False)`.
- **Agent MCP surface (PATCH-5)**: 8 read tools on extended Ruby `hyperon-wiki-mcp`; POLLING-FIRST resource subscriptions (subscribe/server-push deferred to PATCH-5 v2 contingent on upstream Ruby `mcp` gem implementing the no-op stubs at `server.rb:113-117`); shared tool registry across the 4 production launchers per V6-PROTOCOL-1.
- **Agent identity**: D3-1 origin fields threaded end-to-end (JWT `jti` + `session_id`) per V6-PROTOCOL-2.

**Upstream-blocking patches**:
- **PATCH-1** [REQUIRED, UPSTREAM]: pybind11 binding for `space_register_observer` (the C ABI `extern "C"` exists at `hyperon-experimental/c/src/space.rs:464-468`; the Python binding is the gap). Blocks the Python sidecar's observer subscription model.
- **PATCH-2** [RECOMMENDED, UPSTREAM]: MeTTa-side `replace-atom!` grounded operator.

**Pre-implementation gate (V7-1)**: `[AUTH-ON-READ-MIRROR]` — PATCH-5 read tools MUST NOT bypass Decko read-rule enforcement. The AtomSpace mirror contains atoms for every card the integrate hook fired on, including private/restricted cards. Phase 4 default options: (c) public-only mirror by filtering restricted cards out of the integrate hook, OR (d) admin-only mirror with no agent reads in Phase 4. (a) full auth-aware encoding is the long-run answer but blocked on Phase 5+ encoder lift. The PATCH-5 implementation must choose between (c) and (d) before exposing reads to non-admin agents.

**Phase 5+/6+ deferrals**:
- PATCH-6 (agent atom-write surface): Phase 5+; OPTION-C HYBRID (wiki-content writes via Decko; agent-ephemeral atoms direct).
- Substrate migration: ROCKS-PATH primary / MORK-PATH secondary (delete blocker) for Phase 5+ durability; DAS-PATH for Phase 6+ distribution.
- Encoder semantic lift: typed editorial-relation atoms for `+expert_reviewed` / `+ai_draft` / `+review_status` (Phase 4 ships nesting via LeftId/RightId).
- HERMES + AIRIS + MAGUS L2/L3 cognitive-stack architecture: Phase 5+/6+; HERMES proposal text in card 741 (`Neoterics+Metta+drive-docs+Hypergraph-RFP-Lakes`).

The PLN cluster No-Go theorem applies regardless of storage choice — Phase 5+ PLN-over-AtomSpace must be characterized as "semantic queries that PostgreSQL cannot trivially answer," NOT as global PLN inference.

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
- **AtomSpace Integration Phase 4**: Source 5 v1+v2 reconciliation (Decko-side mirror spec; PATCH-3 + PATCH-4 + V5-PROTOCOL-1..5) + Source 6 reconciliation (agent-MCP surface; PATCH-5 + V6-PROTOCOL-1/2 + CF5.6.E) + Source 7 reconciliation (phase numbering crosswalk, V7-1 [AUTH-ON-READ-MIRROR] + V7-2..V7-5; cluster-pilot closure record).

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
- `project_atomspace_phase4_pilot_2026_05_05.md` — AtomSpace Integration Phase 4 cluster pilot summary (research-track 7-source pilot closed); locked PATCH set (PATCH-1..PATCH-6); V7-1..V7-5 carry-forwards (auth-on-read pre-implementation gate; subscribe-wording fix; cognitive-stack reframing; stale-pointer; D3-1 count-convention); phase-numbering crosswalk; rollup card 17124
- `project_haa_cluster_pilot_source1_2026_05_06.md` — Non-clustered HAA cluster pilot Source 1 (AIRIS — Cook & Hammer 2024) close summary; [IMPLEMENTATION-BACKED-CORE] verdict; V1-1..V1-5 carry-forwards (repo misattribution; SubRep extension narrative-guard; curiosity-not-ECAN; confidence-not-PLN; state-graph-not-AtomSpace); 4 new wiki cards (7495 +AIRIS Full + 7496 tag + 7497 +AI + 7498 tag); Reference+GitHub Repositories URL correction; D3 Gemini lib_spaces.metta phantom-file hallucination rejected
- `project_haa_cluster_pilot_source2_2026_05_06.md` — Non-clustered HAA cluster pilot Source 2 (MetaMo — Goertzel & Lian 2025) close summary; [PAPER-LEANING-HYBRID] / [IMPLEMENTATION-BACKED-CORE] / [REFERENCE-IMPLEMENTATION-NOT-PRODUCTION] verdict; trilateral repo classification (MetaMo-Python primary categorical reference / MetaMo-Prototype heuristic LangGraph-LLM / hyperon-openpsi OpenPsi predecessor substrate with zero MetaMo naming at HEAD `3b356c5`); V2-1..V2-7 carry-forwards (Goertzel-first authorship; MetaMo-Python primary; hyperon-openpsi predecessor-not-impl; MetaMo-Prototype heuristic-parallel; SubRep faithful guard; MetaMo_Two duplicate not byte-identical; MAGUS-external-component Mikeda 2024); 6 wiki writes; Gemini Principle-2 [PAPER-ONLY] hallucination rejected via CF5.6 D6 (TranslationFunctor exists at category/functors.py:57 and is exercised at research_assistant.py:88)
- `project_haa_cluster_pilot_source3_2026_05_06.md` — Non-clustered HAA cluster pilot Source 3 (Pattern Mining residual) close summary; residual scope only (Perception 2026-05-01 frozen prior art); no new tradition; fork verdicts CF5.6-verified: leungmanhin 0/44 [STRICT-FORK-STALE], singnet 5/58 [STRICT-FORK-STALE-MERGED-UPSTREAM], **ngeiswei 0/8 [MAINTAINER-FORK-MERGED-BEHIND]** (Gemini's 8/0 [ACTIVE-MAINTAINER-SCRATCH] DIRECTION-REVERSED, rejected); pattern-index [PATTERN-INDEX-SEPARATE-PARADIGM-ADJACENT]; SGNN out-of-scope defer to S4 per V3-6; 2 wiki writes (4087 trilateral framing + 7268 opencog/miner & pattern-index additions); cumulative Gemini drift 22/39 ≈ 56% with first DIRECTION-REVERSED claim observed
- `feedback_sandra_spec_port_recheck_before_batch.md` — process learning: when parallel session has Sandra-spec ported a Published parent (rename + per-field sibling cards) between cluster-pilot reconciliation lock-in and the orchestrator's wiki-write window, HALT and re-read all targets fresh; +AI proposal must retarget from +content (now an inclusion shell) to the new sibling cards (+responsible/+github/etc.); discovered 2026-05-06 during MetaMo S2 close
- `feedback_webfetch_verify_external_urls.md` — standing protocol promoted from CF5.6.E ≥2-instance criterion 2026-05-06: wiki edits referencing external URLs must include fresh WebFetch verification immediately before the edit; cite HTTP status + redirect path in edit notes/commit message
- `feedback_query_all_cardtypes_in_audits.md` — wiki audits must query Draft + Markdown + Published (not just Draft+Markdown); Published cards use the +content shell pattern with actual content in a separate RichText subcard, invisible to Draft+Markdown filter; discovered 2026-05-06 when 8 HAA cards wrongly verdicted as MISSING-CARD turned out to be Published parents (AIRIS, NACE, AI-DSL, MOSES, MetaMo, MeTTa-NARS, Semantic Parsing, MeTTa-Motto)
- `feedback_gemini_file_identity_verification.md` — CF5.6 cluster-pilot default: verify Gemini file-existence claims via ls/Glob before adoption (8/25 dissents = 32% Gemini source-location/file-identity drift across 5 pilots; +3 more in HAA Source 1)
- `feedback_research_vs_implementation_workstreams.md` — research and implementation are separate parallel workstreams; do not collapse one into the other without owner authorization (Phase 4 program 2026-05-04 incident)
- `feedback_parallel_claude_handoff.md` — two Claude sessions in same project share memory + compaction framing → identical drift; ask before tool calls
- `project_user_loving_ai_ghost_history.md` — user has 18 commits in `leungmanhin/loving-ai-ghost`; defer to user recollection on Ghost/OpenPsi/STI design intent
- `reference_wiki_mcp_quirks.md` — wiki MCP operational quirks
- `project_repo_orientation_docs.md` — orientation-doc workflow
- `project_wiki_quality_bar.md` — Ben Goertzel approval bar

For multi-model continuity, the canonical record lives:
- in this repo at `scripts/archive/{pln,ecan,openpsi,atomspace,perception}_pilot/`, `scripts/archive/atomspace_integration_phase4/`, and `scripts/archive/non_clustered_haa_pilot/` (extraction archives) and the wiki itself (cards listed in the audit tables above);
- in `E:\GitHub\hyperon reference\HYPERON_CLUSTER_FINDINGS.md` (substantive source-code findings, cross-model-readable);
- in `E:\GitHub\Magi-AGI\hyperon-wiki-mcp\SERVER-BUGS.md` (MCP bugs and operational conventions).

---

## What's next (post-pilot work)

The PLN, ECAN/Attention, OpenPsi/Motivation, AtomSpace Backend Integration, Perception/Neural-Symbolic, and AtomSpace Integration Phase 4 cluster pilots are closed (2026-04-25, 2026-04-26, 2026-04-28, 2026-04-29, 2026-05-01, 2026-05-05 respectively). The **Non-clustered Hyperon AI Algorithms** cluster pilot is in progress: Sources 1 (AIRIS — Cook & Hammer 2024), 2 (MetaMo — Goertzel & Lian 2025), and 3 (Pattern Mining residual) all closed 2026-05-06; Sources 4 and 5 pending. Other clusters remain (each its own multi-source pilot):

- **Non-clustered HAA cluster — Sources 4..5 (in progress)**:
  - S4: Concept Blending + Semantic Parsing (Goertzel/Eskridge concept-blending paper(s) + singnet/semantic-parsing + RelEx + Link Grammar; pickup of glicerico/SGNN per S3 V3-6 narrative-guard)
  - S5: NACE + AI-DSL + MOSES + MeTTa-NARS (patham9/NACE; singnet/ai-dsl; opencog/moses + iCog-Labs-Dev/metta-moses; patham9/metta-nars; pickup of [MOSES-PROGRAM-LEARNING-NOT-PATTERN-MINING] guard analog of S3 V3-6)
  - Per Option A (backlog burn-down) pilot ordering authorized 2026-05-05.
- **MeTTa runtime** (`hyperon-experimental`, `MeTTa-IL`, `PeTTa`, MORK production angle — note: substantial MORK + AtomSpace + DAS coverage now lives in the AtomSpace Backend Integration cluster pilot 2026-04-29 + AtomSpace Integration Phase 4 cluster pilot 2026-05-05; residual MeTTa-runtime-specific topics include MeTTa-IL semantics, PeTTa runtime closure, and MORK-server deployment topology beyond what the AtomSpace pilots covered).
- **Cross-org sweeps** (asi-alliance, fetchai, F1R3FLY-io, Rejuve, Xcceleran-do, gitlab.com/nunet) — note: `hansonrobotics/*` was substantively covered by the OpenPsi cluster pilot Source 4 (2026-04-28) and residual Hanson-era post-2019 perception utilities by the Perception cluster pilot Source 5 (2026-05-01); residual non-OpenPsi-non-perception Hanson repos may still need a separate sweep. Per Codex caveat 2026-05-05, this cluster likely needs subcluster splits (asi-alliance vs partner-ventures vs distributed-compute vs bio/longevity vs iCog-Labs vs Magi).
- **Phase 4 implementation track** — engineering work consuming the AtomSpace Integration Phase 4 cluster pilot's reconciliations as the locked spec. Runs as a SEPARATE parallel workstream per `feedback_research_vs_implementation_workstreams.md`. Deliverables: `mod/atomspace_mirror/` (PATCH-3 + PATCH-4), Ruby outbox-drain worker, Python sidecar, agent-MCP atom surface (PATCH-5), upstream PATCH-1 + PATCH-2. PATCH-1 is upstream-blocking. V7-1 [AUTH-ON-READ-MIRROR] is the load-bearing pre-implementation gate before exposing PATCH-5 reads to non-admin agents.
- **Phase 3 READONLY-ATOMSPACE-BRIDGE prototype build** — engineering work, not an extraction pilot; benchmarks decide between `atomspace-bridge` import and `mork_ffi` + `mork_loader.py` mechanism under the read-only umbrella. Note: superseded for the write-through track by the Phase 4 architecture above; Phase 3 may still be relevant as an interim read-only delivery if the Phase 4 implementation track is delayed.
- **Phase 5+/6+ design pass** — substrate migration to atomspace-rocks (primary) / MORK (secondary, delete blocker) / DAS (Phase 6+); HERMES + AIRIS + MAGUS L2/L3 cognitive-stack architecture. Future cluster pilot or design pass; out of scope for the current iteration.
