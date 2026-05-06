# Hyperon Wiki Card Audit — 2026-05-05

> ⚠ **2026-05-06 ADDENDUM SUPERSEDES PARTS OF THIS REPORT.** A query-coverage bug was discovered during the AIRIS S1 cluster-close on 2026-05-06: this audit's CQL query filtered on `type: Draft` and `type: Markdown` only, missing 43 Published cards entirely. Of the 4 cards listed in §4.3 as missing-card cluster outputs (AIRIS / NACE / AI-DSL / MOSES), **all 4 exist as Published parents with `+content` shells**. See [audit_addendum_2026_05_06_published.md](audit_addendum_2026_05_06_published.md) for the corrected verdicts and the 30+ newly-discovered Published cards across HAA / PRIMUS / About Hyperon / MeTTa runtime / ASI Chain namespaces. The methodology fix (always query Published in addition to Draft+Markdown) is documented in §3 of the addendum.

**Scope:** Forward audit of every substantive Draft and Published card on `wiki.hyperon.dev` against the cluster-pilot framework. Two questions:

1. Are the cards technically correct according to our sources?
2. Have we read and ingested every source?

**Methodology:** Per-card cluster assignment + per-card correctness verdict + per-source/cluster coverage verdict. Orphan cards get tentative best-fit. Applications section (per-card) excluded from the correctness pass per user direction (retention undecided). This is **not the final pass**; tentative assignments will be revisited.

**Reviewer sign-off (2026-05-05):** Codex + Gemini reviewed and signed off. Methodology refinements applied: label rename `AUDITED-CLOSED-CLUSTER` → `PILOT-EDITED` (Codex); explicit fidelity-vs-coverage note in legend; missing-card list promoted to explicit cluster outputs (Gemini concurred); Cross-org-may-need-subclusters caveat (Codex); pilot-order optimization criterion stated explicitly (Codex).

**Reading order:**
- §1 Cluster framework — the 9-cluster pillar structure used for assignment
- §2 Per-card verdicts — every audited card with cluster + correctness + coverage status
- §3 Per-cluster (per-source) verdicts — what's read/reconciled and what's missing per cluster
- §4 Coverage gaps — the punch list of unread sources
- §5 Correctness gaps — the punch list of cards needing re-edit even within closed clusters
- §6 Recommendations and next-pass plan

---

## §1 Cluster framework

This audit groups the wiki's substantive cards into 9 clusters. The first 5 are **closed** cluster-pilots (multi-source extractions reconciled across Codex+Gemini+Claude); the latter 4 are **not started**.

| # | Cluster | Status | Closed | Sources extracted | Carry-forwards |
|---|---|---|---|---|---|
| 1 | PLN | CLOSED | 2026-04-25 | 11 sources | V0-1..V0-4 + No-Go theorem |
| 2 | ECAN / Attention | CLOSED | 2026-04-26 | 4 sources | V0-1 (URE STI hook) + 3 protocols |
| 3 | OpenPsi / Motivation | CLOSED | 2026-04-28 | 4 sources | V4-1 (9-event lifecycle); V4-2 (bidirectional fork) |
| 4 | AtomSpace Backend Integration | CLOSED | 2026-04-29 | 4 sources | Four-layer taxonomy; Phase 3 READONLY-ATOMSPACE-BRIDGE |
| 5 | Perception / Neural-Symbolic | CLOSED | 2026-05-01 | 5 sources | Trilateral framing; AtomSpace-Scheme vs MeTTa-runtime; CF5.6 |
| 6 | MeTTa runtime | NOT STARTED | — | 0 of ~5-7 needed | — |
| 7 | Cross-org sweeps | NOT STARTED | — | 0 of ~6 needed (likely subclusters) | — |
| 8 | PRIMUS / Cognitive Architectures | NOT STARTED | — | 0 of ~5-7 needed | — |
| 9 | Non-clustered Hyperon AI Algorithms | NOT STARTED | — | 0 of ~4-5 needed | — |

**Out of cluster scope:**
- Top-level navigation / TOC / framework cards (Hyperon Index, About Hyperon, Reference, Implementation Families, Ecosystem, Cognitive Architectures, Publications root, Publication Maps root) — light-touch correctness only; no cluster assignment because they're framework scaffolding.
- Administrator cards (Dashboard, Content Attribution Guide, etc.) — operational, out of scope.
- Applications section (Applications, +Social Robotics, +Bioinformatics, +Mathematics, +Game AI) — per user 2026-05-04: ignore; retention undecided.

**Verdict legend:**

> **Important:** *Card fidelity* (correctness) and *source coverage* are independent dimensions. A card can be `SOURCES-READ-COMPLETE` (the cluster's source set is fully extracted) while still requiring a card-level fidelity check — `SOURCES-READ-COMPLETE` is NOT a claim that the card is correct, only that the inputs needed to judge it have been read. The reverse also holds: a `PILOT-EDITED` card is fidelity-checked at the time of edit but its cluster may still have residual source gaps.

Correctness (card fidelity):
- `PILOT-EDITED` — pilot closed AND card edited by pilot AND audit table records the edit (i.e., pilot already produced a corrected version of this card). Renamed from `AUDITED-CLOSED-CLUSTER` per Codex review 2026-05-05: the prior label could read as "fully audited" when it really means "edited by a closed pilot."
- `AUDITED-PARTIAL` — pilot closed AND card relevant BUT not edited by pilot (potential gap; needs spot-check against extraction archive)
- `NOT-AUDITED` — primary cluster not yet started
- `NEEDS-RE-EDIT` — pilot edited an earlier version, but a new finding (V-N-X carry-forward, or Source N+1 reconciliation update) supersedes the current state
- `OUT-OF-SCOPE` — Applications, Administrator, scaffolding

Coverage (source ingestion):
- `SOURCES-READ-COMPLETE` — all sources for this cluster reconciled; no known external gap to find. Does NOT imply card-level correctness.
- `SOURCES-PARTIAL` — closed cluster but specific source for this card area is incomplete (e.g., 2013 FISHGRAM was a known gap retrieved 2026-04-30)
- `CLUSTER-NOT-STARTED` — sources not yet enumerated in a brief
- `N/A` — out of scope

---

## §2 Per-card verdicts

Total substantive audit anchors: **~150 cards** (93 Drafts + 43 substantive Markdown Publications + ~14 named RichText subcards under Full parents that received pilot edits).

Subcard convention: a parent `+Foo Full` card and its sectioning subcards (Core Mechanisms, Status and Resources, Implementations, etc.) inherit the parent's cluster. Sectioning subcards are listed once per parent group; named subcards that received explicit pilot edits are called out individually.

### 2.1 PLN cluster

| Card | Type | Pilot edits | Correctness | Coverage | Notes |
|---|---|---|---|---|---|
| Hyperon AI Algorithms+PLN (Probabilistic Logic Networks)+PLN Full | Draft | 4184 (PLN cluster phase 4a) | PILOT-EDITED | SOURCES-READ-COMPLETE | Five-tradition map + two-paradigm framing + No-Go citation already landed |
| ↳ +PLN Full+Execution on MORK | RichText | 7106 (PLN phase 4b) | PILOT-EDITED | SOURCES-READ-COMPLETE | FactorGraph paper-only correction landed |
| ↳ +PLN Full+Mathematical Foundations | RichText | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Spot-check vs Source 11 reconciliation; verify No-Go theorem framing aligned |
| ↳ +PLN Full+Core Mechanisms and Inference | RichText | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Spot-check vs xiPLN/Wm Calculus sources |
| ↳ +PLN Full+Design History and Implementation | RichText | not edited | AUDITED-PARTIAL | SOURCES-PARTIAL | `lib_pln_xi.metta` not located in any clone — known source-text gap |
| ↳ +PLN Full+Status and Resources | RichText | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Spot-check current PLN repo SHAs |
| Hyperon AI Algorithms+PLN (Probabilistic Logic Networks)+AI | Draft | 7415 (PLN phase 5) | PILOT-EDITED | SOURCES-READ-COMPLETE | +AI proposal child for Published parent; tag 7416 carries `ai_generated` |
| Publications+Probabilistic Logic Networks | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Foundational PLN book — verify metadata + curated-excerpt status |
| Publications+Real World Reasoning | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Foundational; verify excerpts |
| Publications+Probabilistic Quantifier Logic | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Verify excerpts |
| Publications+Uncertain Interval Algebra | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Verify excerpts |
| Publications+Uncertain Spatiotemporal Logic | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Verify excerpts; cross with FISHGRAM disambiguation |
| Publications+Intensional Inheritance Between Concepts | Draft | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | PLN concept primitive — spot-check |
| Publications+PLN and NARS Under Uncertain Term Probabilities | Draft | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | PLN/NARS bridge; also relevant to non-clustered HAA (NARS) |
| Publications+Patterns of Quantum Cognition I | Draft | not edited | AUDITED-PARTIAL | SOURCES-PARTIAL | Quantum-PLN extension; less core; likely PRIMUS-cluster relevance too |
| RawData+Publications+xiPLN | RichText (Magi Archive) | 7403 (PLN phase 2) | PILOT-EDITED | SOURCES-READ-COMPLETE | Magi Archive only — included for completeness |
| RawData+Publications+World-Model Calculus | RichText (Magi Archive) | 7405 (PLN phase 2) | PILOT-EDITED | SOURCES-READ-COMPLETE | Magi Archive only |
| RawData+Publications+Markov-de Finetti Formalization | RichText (Magi Archive) | 7409 (PLN phase 2) | PILOT-EDITED | SOURCES-READ-COMPLETE | Magi Archive only |

**PLN-cluster cards:** 16 wiki cards (excluding Magi-Archive-only RawData parents). 5 directly edited; 11 partial-audit (relevant cluster + closed pilot, not edited).

### 2.2 ECAN / Attention cluster

| Card | Type | Pilot edits | Correctness | Coverage | Notes |
|---|---|---|---|---|---|
| Hyperon AI Algorithms+ECAN+ECAN Full | Draft | parent-only | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Edits landed on subcards; parent draft itself not directly modified |
| ↳ +ECAN Full+System Interfaces and Implementation | RichText | 7096 (ECAN phase 1) | PILOT-EDITED | SOURCES-READ-COMPLETE | PLN bullet refined, 0/4 strict-literal note, OpenPsi V4-1 expansion |
| ↳ +ECAN Full+Development and Historical Context | RichText | 7100 (ECAN phase 1 + OpenPsi V4-1 + Perception V5 addendum) | PILOT-EDITED | SOURCES-READ-COMPLETE | Three-pilot accumulated edits; most-touched ECAN subcard |
| ↳ +ECAN Full+Status and Resources | RichText | 7098 (ECAN phase 1) | PILOT-EDITED | SOURCES-READ-COMPLETE | Stochastic naming + 2 new Open Problems + archive ref |
| ↳ +ECAN Full+Core Mechanisms and Foundations | RichText | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Spot-check vs Source 4 V0-1 reconciliation |
| Hyperon AI Algorithms+ECAN+AI | Draft | 7419 (ECAN phase 4 + V4-1 supplement) | PILOT-EDITED | SOURCES-READ-COMPLETE | +AI proposal child carrying both ECAN findings + V4-1 supplement |
| Implementation Families+Attention and Motivation | Draft | 4751 (ECAN phase 3 + OpenPsi update + AtomSpace AttentionBroker + Perception Vepstas portfolio) | PILOT-EDITED | SOURCES-READ-COMPLETE | Four-pilot accumulated edits |
| Publications+Economic Attention Networks | Markdown | 3063 (PLN phase 3 + ECAN phase 2) | PILOT-EDITED | SOURCES-READ-COMPLETE | Refined PLN-control framing + Source 3 V0-1 timeline |
| Publications+Guiding PLN with Attention Allocation | Markdown | 3057 (ECAN phase 2 + OpenPsi 2016-05/2016-11 lifecycle) | PILOT-EDITED | SOURCES-READ-COMPLETE | Cosmo Harrigan identity, executable-realization timeline, Hanson runtime branch |
| Publications+Nonlinear Dynamical Attention via Information Geometry | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Spot-check ECAN-adjacent; possibly more PRIMUS (info-geom)-relevant |
| Publications+Lifelong Forgetting | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Spot-check; ECAN forgetting-cycle context |

**ECAN-cluster cards:** 11. 6 directly edited; 5 partial-audit.

### 2.3 OpenPsi / Motivation cluster

| Card | Type | Pilot edits | Correctness | Coverage | Notes |
|---|---|---|---|---|---|
| Publications+OpenPsi A Novel Computational Affective Model | Markdown | 7426 (OpenPsi new) | PILOT-EDITED | SOURCES-READ-COMPLETE | New 2013 EAAI paper card with equation index; tag 7427 |
| Publications+OpenPsi Cognitive Model | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Existing OpenPsi paper card; spot-check vs OpenPsi reconciliation |
| Publications+PSI Affective Dynamics | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Spot-check |
| Publications+MetaMo Robust Motivational Framework | Draft | not edited | AUDITED-PARTIAL | SOURCES-PARTIAL | Hybrid OpenPsi/non-clustered HAA (MetaMo); MetaMo design-context not deeply extracted |
| Publications+MetaMo to Open-Ended OpenPsi | Draft | not edited | AUDITED-PARTIAL | SOURCES-PARTIAL | Same boundary; needs MetaMo extraction in non-clustered-HAA cluster |
| Hyperon AI Algorithms+MetaMo+MetaMo Full | Draft | not edited | NOT-AUDITED | CLUSTER-NOT-STARTED | Primary cluster: non-clustered HAA. OpenPsi pilot only touched lifecycle, not MetaMo |
| RawData+Publications+Openpsi Zhenhua | Magi Archive | 3827 (OpenPsi) | PILOT-EDITED | SOURCES-READ-COMPLETE | Magi-side editorial-metadata block |

**OpenPsi-cluster cards (wiki):** 5 substantive + MetaMo Full (boundary). Edits landed primarily on Magi-Archive RawData and ECAN-cluster cards carrying V4-1; only one direct OpenPsi-side wiki creation (7426/7427).

### 2.4 AtomSpace Backend Integration cluster

| Card | Type | Pilot edits | Correctness | Coverage | Notes |
|---|---|---|---|---|---|
| About Hyperon+AtomSpace+AtomSpace Full | Draft | parent not directly edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Most edits on subcards |
| ↳ +AtomSpace Full+Implementations | RichText | 7115 (AtomSpace phase 1) | PILOT-EDITED | SOURCES-READ-COMPLETE | Four-layer taxonomy lock-in section; DAS first-class note |
| ↳ +AtomSpace Full+Core Concept and Data Model | RichText | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Verify Atom/Value distinction holds against Source 4 |
| ↳ +AtomSpace Full+Values and Space API | RichText | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Verify Space-API surface vs hyperon-experimental |
| ↳ +AtomSpace Full+Design Evolution and Performance | RichText | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Verify 400M not 500M; classical vs Hyperon split |
| ↳ +AtomSpace Full+Status and Resources | RichText | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Verify SHAs current |
| Knowledge Representations+DAS+DAS Full | Draft | 4200 (AtomSpace phase 1) | PILOT-EDITED | SOURCES-READ-COMPLETE | Cluster-Pilot Lock-In section: split implementation, AttentionBroker surrogate, MorkDB caveats |
| Knowledge Representations+MORK+MORK Full | Draft | parent not directly edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Most edits on subcards |
| ↳ +MORK Full+Architecture and Ecosystem | RichText | 7153 (AtomSpace phase 1) | PILOT-EDITED | SOURCES-READ-COMPLETE | 8-crate workspace correction; PathMap-as-sibling; PLN paper-only |
| ↳ +MORK Full+Status and Resources | RichText | 7155 (AtomSpace phase 1) | PILOT-EDITED | SOURCES-READ-COMPLETE | Server-branch-versioning, CountSink reframing, 400M, MorkDB delete-blocking |
| ↳ +MORK Full+Formal Foundations and Indexing | RichText | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Spot-check trie/PathMap/MM2 framing |
| ↳ +MORK Full+Core Mechanisms | RichText | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Spot-check vs current MORK SHAs |
| Knowledge Representations+PathMap | Draft | 7429 (AtomSpace new) | PILOT-EDITED | SOURCES-READ-COMPLETE | Luke Peterson author; sibling-repo; pathmap-book; tag 7430 |
| Implementation Families+AtomSpace Backend Integration | Draft | 7432 (AtomSpace new) | PILOT-EDITED | SOURCES-READ-COMPLETE | Synthesis card: four-layer taxonomy + Phase 3 lock-in + 7 narratives + blockers; tag 7433 |
| Implementation Families+Knowledge Substrates | Draft | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Boundary card: AtomSpace + MORK + PathMap + DAS substrates |
| Publications+Graphs Metagraphs RAM CPU | Draft | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Engineering-dimension paper; spot-check |
| Publication Maps+Mork theory | Draft | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | MORK-theory map; verify against PathMap+MM2 reconciliation |
| Publications+OpenCog Software Framework | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Foundational OpenCog framework; AtomSpace-relevant |

**AtomSpace-cluster cards:** 18. 5 directly edited; 13 partial-audit. Largest spot-check backlog.

### 2.5 Perception / Neural-Symbolic cluster

| Card | Type | Pilot edits | Correctness | Coverage | Notes |
|---|---|---|---|---|---|
| Publications+Deep Learning Perception with PLN | Markdown | 3081 (Perception) | PILOT-EDITED | SOURCES-READ-COMPLETE | 2013 FISHGRAM paper retrieval; full DOI/citation/Yu 4th author |
| Knowledge Representations+Sensory | Draft | 7439 (Perception new) | PILOT-EDITED | SOURCES-READ-COMPLETE | opencog/sensory synthesis; 7 wired types; OllamaNode dual char.; tag 7440 |
| Implementation Families+Neural Pattern Mining | Draft | 7442 (Perception new) | PILOT-EDITED | SOURCES-READ-COMPLETE | rejuve-bio/neural-subgraph-matcher-miner synthesis; tag 7443 |
| About Hyperon+Vision | Draft | 7445 (Perception new) | PILOT-EDITED | SOURCES-READ-COMPLETE | opencog/vision scaffolding; 6 wired types; SCAFFOLDING-NOT-PIPELINE; tag 7446 |
| About Hyperon+Neural-Symbolic Integration+SynerGAN | Draft | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Spot-check SynerGAN vs Perception findings |
| Implementation Families+Neural-Symbolic and LLM Integration | Draft | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Boundary card; OllamaNode + LLM-mediated-perception relevant |
| Publications+FISHGRAM Pattern Mining | Markdown | not edited | NEEDS-RE-EDIT | SOURCES-READ-COMPLETE | Perception pilot verified paper does not use "FISHGRAM" term — wiki card should reflect |
| Publications+OpenCog NS Hybrid Neural-Symbolic | Markdown | 3120 (PLN phase 3) | PILOT-EDITED | SOURCES-READ-COMPLETE | Stub upgrade; refined neural-symbolic framing |
| Publications+Compositional Spatiotemporal Deep Learning | Markdown | 3108 (PLN phase 3) | PILOT-EDITED | SOURCES-READ-COMPLETE | Includes ≠ FISHGRAM disambiguation |
| Publications+Perception Processing for AGI | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Spot-check |
| Publications+Sentence Generation for AI | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | NLP/perception adjacent; spot-check |
| Publications+NLP Architecture for Embodied AGI | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Embodied/perception adjacent |
| Publications+Pragmatic Path to Linguistic AGI | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | NLP / language perception |
| Publications+Syntax-Semantic Mapping | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | NLP boundary |
| Publications+Inferential Dynamics for Virtual Animals | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Embodied / virtual-agent |
| Publications+Cognitive Synergy in Animated Agents | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Animated agents / boundary with cross-org |
| Publications+Teaching Embodied Non-Linguistic Agents | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Embodied learning; spot-check |
| Publications+Integrative AGI in Minecraft | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Embodied AGI experimental; cross with cross-org/Magi |
| Publications+OpenCogBot Virtual Agent Control | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Virtual-agent control; cross-org boundary |
| Publications+Humanoid Robotics Architecture | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | Hanson-side robotics; cross-org boundary |
| Publications+Grounding Possible Worlds Semantics | Markdown | not edited | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | NLP grounding; spot-check |
| About Hyperon+table of contents | RichText | 4022 (Perception edit; added Vision) | PILOT-EDITED | N/A | Scaffolding edit |

**Perception-cluster cards:** 22. 5 directly edited (3 new + 2 PLN-phase carry-overs that landed perception-relevant content); 1 needs re-edit (FISHGRAM); 16 partial-audit. Largest cluster after AtomSpace.

### 2.6 MeTTa runtime cluster (NOT STARTED)

| Card | Type | Primary cluster | Correctness | Coverage | Notes |
|---|---|---|---|---|---|
| MeTTa Programming Language+MeTTa Programming Language Full | Draft | MeTTa | NOT-AUDITED | CLUSTER-NOT-STARTED | Core MeTTa runtime / language |
| ↳ +MPL Full+Core Mechanisms and Type System | RichText | MeTTa | NOT-AUDITED | CLUSTER-NOT-STARTED | Type system / unification |
| ↳ +MPL Full+Language Stack and Implementations | RichText | MeTTa | NOT-AUDITED | CLUSTER-NOT-STARTED | hyperon-experimental + MeTTa-IL + PeTTa |
| ↳ +MPL Full+Formal Foundations and Operational Semantics | RichText | MeTTa | NOT-AUDITED | CLUSTER-NOT-STARTED | MeTTa-IL semantics |
| ↳ +MPL Full+Status and Resources | RichText | MeTTa | NOT-AUDITED | CLUSTER-NOT-STARTED | Verify against Aug-2025 docs.metta-lang.dev |
| MeTTa Programming Language+Learning Resources | Draft | MeTTa | NOT-AUDITED | CLUSTER-NOT-STARTED | Tutorials / examples |
| Implementation Families+MeTTa Implementations | Draft | MeTTa | NOT-AUDITED | CLUSTER-NOT-STARTED | Implementation family overview |
| Implementation Families+Infrastructure and Developer Surfaces | Draft | MeTTa (boundary cross-org) | NOT-AUDITED | CLUSTER-NOT-STARTED | dev tooling / IDE / package mgmt |
| Implementation Families+Reasoning and Search | Draft | MeTTa (boundary PLN) | NOT-AUDITED | CLUSTER-NOT-STARTED | MeTTa-runtime reasoning surface; cross with PLN |
| Implementation Families+NARS Ecosystem | Draft | MeTTa (boundary non-clustered HAA) | NOT-AUDITED | CLUSTER-NOT-STARTED | MeTTa-NARS family of impls |
| Publications+Meta-MeTTa | Draft | MeTTa | NOT-AUDITED | CLUSTER-NOT-STARTED | Meta-MeTTa paper |
| Publication Maps+Meta-MeTTa Paper | Draft | MeTTa | NOT-AUDITED | CLUSTER-NOT-STARTED | Map for Meta-MeTTa |
| Publications+OpenCog Hyperon Framework | Draft | MeTTa (boundary AtomSpace) | NOT-AUDITED | CLUSTER-NOT-STARTED | Hyperon overview paper; foundational |
| Publication Maps+Hyperon Whitepaper 2025 | Draft | MeTTa (boundary cross-cluster) | NOT-AUDITED | CLUSTER-NOT-STARTED | 2025 whitepaper map |
| Publications+Practical Path to Beneficial AGI and ASI | Draft | MeTTa (boundary cross-cluster) | NOT-AUDITED | CLUSTER-NOT-STARTED | Strategic / overview |
| Publications+Formal Verification in AGI Architecture | Draft | MeTTa (boundary PRIMUS) | NOT-AUDITED | CLUSTER-NOT-STARTED | Formal verification on MeTTa |
| Ecosystem+Magi+Magi Full+MAGUS Framework+Hyperon 0.2.1 Dispatch Patterns | Draft | MeTTa (Magi/cross-org-adjacent) | NOT-AUDITED | CLUSTER-NOT-STARTED | Concrete MeTTa runtime quirks; user has direct knowledge per memory |
| Hyperon Wiki Extensions | Draft | MeTTa (boundary infra) | AUDITED-PARTIAL | N/A | Largely scaffolding; MeTTa runtime + extensions; light spot-check needed |

**MeTTa-cluster cards:** 18. **Zero edited.** All NOT-AUDITED awaiting cluster pilot.

### 2.7 Cross-org sweeps cluster (NOT STARTED)

Hanson Robotics post-2019 perception was covered by Perception Source 5; OpenPsi era Hanson by OpenPsi Source 4. Residual cross-org sweep covers asi-alliance, fetchai, F1R3FLY-io, Rejuve, Xcceleran-do, gitlab.com/nunet, plus the various Ecosystem+ partner cards.

**Codex caveat (2026-05-05):** Cross-org may need to be split into subclusters once org cards, repo families, and ecosystem narratives are separated. A single cross-org pilot may have too wide a source surface to triangulate cleanly. Candidate splits: (a) ASI-Alliance member orgs (SingularityNET / Fetch.ai / Ocean Protocol / CUDOS), (b) SingularityNET partner ventures (TrueAGI / Mind Children / EARTHwise / SophiaVerse / Singularity Finance), (c) infrastructure / distributed compute (NuNet / F1R3FLY / ASI Chain), (d) bio / longevity (Rejuve broader scope), (e) iCog Labs research portfolio + residual Hanson, (f) Magi (user-owned, design-intent already in user's head).

| Card | Type | Primary cluster | Correctness | Coverage | Notes |
|---|---|---|---|---|---|
| Ecosystem | Draft | Cross-org | OUT-OF-SCOPE (TOC) | N/A | Top-level TOC card |
| Ecosystem+SingularityNET | Draft | Cross-org (a) | NOT-AUDITED | CLUSTER-NOT-STARTED | Foundation org |
| Ecosystem+ASI Alliance | Draft | Cross-org (a) | NOT-AUDITED | CLUSTER-NOT-STARTED | asi-alliance |
| ASI Chain Runtime Environment+ASI Chain Runtime Environment Full | Draft | Cross-org (c) | NOT-AUDITED | CLUSTER-NOT-STARTED | Runtime sibling org |
| Ecosystem+TrueAGI | Draft | Cross-org (b) | NOT-AUDITED | CLUSTER-NOT-STARTED | TrueAGI |
| Ecosystem+Mind Children | Draft | Cross-org (b) | NOT-AUDITED | CLUSTER-NOT-STARTED | Mind Children |
| Ecosystem+EARTHwise | Draft | Cross-org (b) | NOT-AUDITED | CLUSTER-NOT-STARTED | EARTHwise |
| Ecosystem+EARTHwise+Elowyn | Draft | Cross-org (b) | NOT-AUDITED | CLUSTER-NOT-STARTED | Elowyn agent |
| Ecosystem+SophiaVerse | Draft | Cross-org (b) | NOT-AUDITED | CLUSTER-NOT-STARTED | SophiaVerse |
| Ecosystem+Rejuve | Draft | Cross-org (d) | AUDITED-PARTIAL | SOURCES-PARTIAL | Rejuve-bio/neural-subgraph-matcher-miner cited in Perception pilot; Rejuve-as-org broader scope NOT covered |
| Ecosystem+Magi | Draft | Cross-org (f) | AUDITED-PARTIAL | SOURCES-PARTIAL | User is owner; MAGUS framework draft; design-intent owned by user |
| Ecosystem+Magi+Magi Full | Draft | Cross-org (f) | AUDITED-PARTIAL | SOURCES-PARTIAL | User-owned; partial subcard coverage |
| ↳ +Magi Full+Tools and Assistants | RichText | Cross-org (f) | NOT-AUDITED | CLUSTER-NOT-STARTED | — |
| ↳ +Magi Full+Status and Resources | RichText | Cross-org (f) | NOT-AUDITED | CLUSTER-NOT-STARTED | — |
| ↳ +Magi Full+Partnerships and Applications | RichText | Cross-org (f) | NOT-AUDITED | CLUSTER-NOT-STARTED | — |
| ↳ +Magi Full+MAGUS Framework | RichText | Cross-org (f) / MeTTa | NOT-AUDITED | CLUSTER-NOT-STARTED | MAGUS — see also `project_magus_atomspace_plan_2026_03_11.md` memory |
| Ecosystem+Hanson Robotics | Draft | Cross-org (e) | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | OpenPsi Source 4 + Perception Source 5 covered; verify post-2019 Hanson identity |
| Ecosystem+NuNet | Draft | Cross-org (c) | NOT-AUDITED | CLUSTER-NOT-STARTED | gitlab.com/nunet |
| Ecosystem+Singularity Finance | Draft | Cross-org (b) | NOT-AUDITED | CLUSTER-NOT-STARTED | SingularityFinance |
| Ecosystem+iCog Labs | Draft | Cross-org (e) | NOT-AUDITED | CLUSTER-NOT-STARTED | iCog Labs |
| Ecosystem+Fetch.ai | Draft | Cross-org (a) | NOT-AUDITED | CLUSTER-NOT-STARTED | fetchai (asi-alliance member) |
| Ecosystem+Ocean Protocol | Draft | Cross-org (a) | NOT-AUDITED | CLUSTER-NOT-STARTED | Ocean Protocol (asi-alliance member) |
| Ecosystem+F1R3FLY | Draft | Cross-org (c) | NOT-AUDITED | CLUSTER-NOT-STARTED | F1R3FLY-io |
| Implementation Families+Game Worlds and Simulated Environments | Draft | Cross-org (boundary Magi) | NOT-AUDITED | CLUSTER-NOT-STARTED | Game / simulation impls |
| Implementation Families+Robotics and Embodiment | Draft | Cross-org (boundary Hanson) | AUDITED-PARTIAL | SOURCES-READ-COMPLETE | OpenPsi Hanson + Perception Vepstas portfolio cover parts |
| Implementation Families+Bio-AI and Cheminformatics | Draft | Cross-org (boundary Rejuve) | AUDITED-PARTIAL | SOURCES-PARTIAL | Rejuve-bio touched via Perception; not a full bio-AI sweep |

**Cross-org cluster cards:** 26. 4 partial (Hanson, Rejuve, Robotics, Magi); 22 not-audited.

### 2.8 PRIMUS / Cognitive Architectures cluster (NOT STARTED)

| Card | Type | Primary cluster | Correctness | Coverage | Notes |
|---|---|---|---|---|---|
| Cognitive Architectures+Cross-Stack Research Directions | Draft | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | Cross-stack overview |
| Cognitive Architectures+PRIMUS+PRIMUS Full | Draft | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | PRIMUS root |
| ↳ +PRIMUS Full+Architecture and Core Dynamics | RichText | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | — |
| ↳ +PRIMUS Full+Cognitive Synergy | RichText | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | — |
| ↳ +PRIMUS Full+Components and Integration | RichText | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | — |
| ↳ +PRIMUS Full+Status and Resources | RichText | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | — |
| Cognitive Architectures+PRIMUS+QuantiMork | Draft | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | Quantum-MORK extension |
| Cognitive Architectures+PRIMUS+Algorithmic Chemistry | Draft | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | ActPC-Chem related |
| Cognitive Architectures+PRIMUS+Schrödinger Bridge Learning | Draft | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | Modularization-via-OT related |
| Cognitive Architectures+PRIMUS+TransWeave | Draft | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | TransWeave |
| Cognitive Architectures+PRIMUS+TransWeave+TransWeave Full | Draft | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | TransWeave Full |
| Cognitive Architectures+PRIMUS+WILLIAM | Draft | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | WILLIAM |
| Cognitive Architectures+PRIMUS+WILLIAM+WILLIAM Full | Draft | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | WILLIAM Full |
| Cognitive Architectures+PRIMUS+Geodesic Inference | Draft | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | Geodesic / ActPC-Geom |
| Cognitive Architectures+PRIMUS+SubRep | Draft | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | Sub-symbolic representations |
| Publications+ActPC-Geom | Draft | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | — |
| Publications+ActPC Chem | Draft | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | — |
| Publications+Selectivity Theorem and Hierarchical Corollary | Draft | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | — |
| Publications+Modularization via Optimal Transport | Draft | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | — |
| Publication Maps+Building Better Minds | Draft | PRIMUS | NOT-AUDITED | CLUSTER-NOT-STARTED | Goertzel "Building Better Minds" mapping |

**PRIMUS-cluster cards:** 20. **Zero edited.** All NOT-AUDITED.

### 2.9 Non-clustered Hyperon AI Algorithms cluster (NOT STARTED)

This cluster covers HAA cards not assigned to PLN/ECAN: Concept Blending, Pattern Mining (non-FISHGRAM/non-NPM), MetaMo (cluster anchor itself), Semantic Parsing, MeTTa-NARS. **Promoted to explicit cluster outputs** (per Codex+Gemini review 2026-05-05) — not just audit notes — are the missing wiki cards: AIRIS, NACE, AI-DSL, MOSES.

| Card | Type | Primary cluster | Correctness | Coverage | Notes |
|---|---|---|---|---|---|
| Hyperon AI Algorithms+Concept Blending | Draft | Non-clustered HAA | NOT-AUDITED | CLUSTER-NOT-STARTED | — |
| Hyperon AI Algorithms+Pattern Mining | Draft | Non-clustered HAA | NOT-AUDITED | CLUSTER-NOT-STARTED | Generic pattern mining (non-FISHGRAM scope) |
| Hyperon AI Algorithms+MetaMo+MetaMo Full | Draft | Non-clustered HAA | NOT-AUDITED | CLUSTER-NOT-STARTED | MetaMo full; OpenPsi pilot only touched lifecycle adjacency |
| Hyperon AI Algorithms+Semantic Parsing+Semantic Parsing Full | Draft | Non-clustered HAA (boundary Perception NLP) | NOT-AUDITED | CLUSTER-NOT-STARTED | NLP front-end |
| About Hyperon+Self-Modification and Safety+Self-Modification and Safety Full | Draft | Non-clustered HAA (boundary PRIMUS) | NOT-AUDITED | CLUSTER-NOT-STARTED | Self-modification; possibly own micro-cluster (AIRIS) |
| **(missing) Hyperon AI Algorithms+AIRIS** | — | Non-clustered HAA | MISSING-CARD | CLUSTER-NOT-STARTED | Cook & Hammer 2024 paper exists; cluster pilot must create card |
| **(missing) Hyperon AI Algorithms+NACE** | — | Non-clustered HAA | MISSING-CARD | CLUSTER-NOT-STARTED | Non-Axiomatic Causal Engine; cluster pilot must create card |
| **(missing) Hyperon AI Algorithms+AI-DSL** | — | Non-clustered HAA | MISSING-CARD | CLUSTER-NOT-STARTED | Ring/SingularityNET AI-DSL; cluster pilot must create card |
| **(missing) Hyperon AI Algorithms+MOSES** | — | Non-clustered HAA | MISSING-CARD | CLUSTER-NOT-STARTED | Meta-Optimizing Semantic Evolutionary Search; cluster pilot must create card |

**Non-clustered HAA cards:** 5 existing + **4 explicit missing-card cluster outputs** (AIRIS / NACE / AI-DSL / MOSES). Zero edited; all NOT-AUDITED.

### 2.10 Top-level scaffolding (light-touch, no cluster)

| Card | Type | Verdict | Notes |
|---|---|---|---|
| Hyperon Index | Draft | OUT-OF-SCOPE (TOC) | Top-level index |
| About Hyperon | Draft | OUT-OF-SCOPE (TOC) | Section anchor |
| Reference | Draft | OUT-OF-SCOPE (TOC) | Section anchor |
| Reference+GitHub Repositories | Draft | NEEDS-VERIFY | Repo list — should match HYPERON_CLUSTER_FINDINGS.md per-cluster archive pointers |
| Implementation Families | Draft | OUT-OF-SCOPE (TOC) | Section anchor |
| Publications | Draft | OUT-OF-SCOPE (TOC) | Section anchor |
| Publication Maps | Draft | OUT-OF-SCOPE (TOC) | Section anchor |
| Technical Companions | Draft | OUT-OF-SCOPE (TOC) | Section anchor |

### 2.11 Out of scope per user direction (Applications)

| Card | Type | Verdict |
|---|---|---|
| Applications | Draft | OUT-OF-SCOPE |
| Applications+Social Robotics | Draft | OUT-OF-SCOPE |
| Applications+Bioinformatics | Draft | OUT-OF-SCOPE |
| Applications+Mathematics | Draft | OUT-OF-SCOPE |
| Applications+Game AI | Draft | OUT-OF-SCOPE |

### 2.12 Out of scope (Administrator / system Markdown)

| Card | Type | Verdict |
|---|---|---|
| *all+*guide | Markdown | OUT-OF-SCOPE (system) |
| Cardtype+*type+*guide | Markdown | OUT-OF-SCOPE (system) |
| *structure+*right+*guide | Markdown | OUT-OF-SCOPE (system) |
| Administrator+Dashboard | Markdown | OUT-OF-SCOPE (admin) |
| Administrator+Content Attribution Guide | Markdown | OUT-OF-SCOPE (admin) |
| Administrator+Background Publications Ingestion Plan | Markdown | OUT-OF-SCOPE (admin) |
| Administrator+Wiki Drafting Session Handoff 2026 04 08 | Markdown | OUT-OF-SCOPE (admin) |
| Administrator+TOC Integration Proposal | Markdown | OUT-OF-SCOPE (admin) |

---

## §3 Per-cluster (per-source) verdicts

### 3.1 PLN cluster — CLOSED 2026-04-25

- **Sources read:** 11/11 (Sources 1–11 all reconciled across Codex+Gemini+Claude). Canonical synthesis: `scripts/archive/pln_pilot/source11_*/findings_reconciled_crossmodel.txt`.
- **Cards mapped:** 16 wiki cards + 4 RawData (Magi Archive).
- **Cards directly edited:** 5 of 16 wiki cards (PLN Full parent + Execution-on-MORK subcard + +AI proposal + ECAN Pubs Markdown + Compositional Spatiotemporal Markdown via PLN phase 3).
- **Cards partial-audit (relevant cluster, not edited):** 11 — mostly RichText sectioning subcards under PLN Full + several Markdown publications.
- **Carry-forwards:** V0-1..V0-4 + No-Go theorem; "Zarko Zaremba" pseudonym; pickaxe-before-dead-code protocol established here.
- **Source-text gaps remaining:** `lib_pln_xi.metta` not located in any clone (xiPLN.tex citation; either uncommitted, in undisclosed `zariuq/PeTTa`, or never written).
- **Coverage verdict:** SOURCES-READ-COMPLETE-WITH-ONE-MINOR-GAP. The xiPLN module gap is logged; no new source-extraction needed on top of the 11.

### 3.2 ECAN / Attention cluster — CLOSED 2026-04-26

- **Sources read:** 4/4 (Sources 1–4 reconciled). Canonical synthesis: Source 4 V0-1 (broader-OpenCog ECAN consumer disambiguator) + Source 3 V0-1 (URE STI source-selection lifecycle).
- **Cards mapped:** 11 wiki cards.
- **Cards directly edited:** 6 of 11 (ECAN Full subcards 7096/7100/7098, +AI 7419, Pubs Economic Attention Networks 3063, Guiding PLN with Attention Allocation 3057, Implementation Families+Attention and Motivation 4751).
- **Cards partial-audit:** 5 — Core Mechanisms subcard + 3 Markdown pubs (Nonlinear Dynamical Attention via Information Geometry, Lifelong Forgetting, etc.) + ECAN Full parent itself.
- **Carry-forwards:** V0-1 (URE STI hook wired 2016-2018), V3-PROTOCOL-1/2/3, audit-token-list protocol (BOTH C++ and Scheme/MeTTa API layers).
- **Coverage verdict:** SOURCES-READ-COMPLETE.

### 3.3 OpenPsi / Motivation cluster — CLOSED 2026-04-28

- **Sources read:** 4/4. Canonical synthesis: Source 4 V4-1 (caller-analysis time-indexing — OpenPsi default-selector STI 2016-05/2016-11 lifecycle) + Source 3 (HYBRID/PAPER-LEANING equation tally).
- **Cards mapped:** 5 wiki + 1 Magi-Archive RawData. **Note:** most OpenPsi findings landed on **ECAN-cluster cards** (V4-1 addendum on ECAN subcards 7100/7096 + Pubs Guiding PLN 3057 + Impl Fam Attention and Motivation 4751). Direct OpenPsi-side wiki creations: 7426 (OpenPsi 2013 EAAI paper) + 7427 (tag).
- **Cards directly edited:** 1 wiki + 1 Magi.
- **Cards partial-audit:** 4 — OpenPsi Cognitive Model, PSI Affective Dynamics, MetaMo Robust Motivational Framework, MetaMo to Open-Ended OpenPsi.
- **Boundary with non-clustered HAA:** MetaMo Full not extracted; only lifecycle-adjacency from OpenPsi side.
- **Carry-forwards:** V4-1 9-event executable-coupling lifecycle, V4-2 bidirectional fork-divergence + staleness, Hanson runtime branch (Loving AI Ghost).
- **Coverage verdict:** SOURCES-READ-COMPLETE for OpenPsi proper; MetaMo design-context only PARTIAL (gap inherited by non-clustered-HAA cluster).

### 3.4 AtomSpace Backend Integration cluster — CLOSED 2026-04-29

- **Sources read:** 4/4. Canonical synthesis: Source 4 reconciliation Sections A–M + Bottom Line (R4.B4).
- **Cards mapped:** 18 wiki cards.
- **Cards directly edited:** 5 (AtomSpace Implementations subcard 7115; MORK Architecture+Status subcards 7153/7155; DAS Full 4200; Impl Families+Atomspace Backend Integration 7432 + tag 7433; Knowledge Repr+PathMap 7429 + tag 7430; +Attention and Motivation 4751 carry-over).
- **Cards partial-audit:** 13 — Five sectioning subcards under AtomSpace Full + four under MORK Full + Knowledge Substrates + 2 Pubs (Graphs Metagraphs RAM CPU, Mork theory map) + OpenCog Software Framework Markdown.
- **Subsequent Phase 4 program:** A separate AtomSpace Integration Phase 4 cluster pilot (closed 2026-05-05; 7 sources; rollup card 17124) extended this work but is RESEARCH for the wiki-mirror substrate, NOT additional audit input on these cards' correctness.
- **Carry-forwards:** Four-layer taxonomy (Classical/Hyperon Space/DAS/MORK); Phase 3 READONLY-ATOMSPACE-BRIDGE lock-in; MorkDB delete-blocking; MORK 8-crate + 400M not 500M; `from hyperon import MCP` apocryphal.
- **Coverage verdict:** SOURCES-READ-COMPLETE.

### 3.5 Perception / Neural-Symbolic cluster — CLOSED 2026-05-01

- **Sources read:** 5/5. Canonical synthesis: Source 5 reconciliation (trilateral framing + AtomSpace-Scheme vs MeTTa-runtime + Vepstas portfolio).
- **Cards mapped:** 22 wiki cards.
- **Cards directly edited:** 5 (Sensory 7439, Neural Pattern Mining 7442, Vision 7445 + tag subcards; +Deep Learning Perception with PLN 3081; +Attention and Motivation 4751 carry-over; +ECAN Dev Historical 7100 carry-over; About Hyperon+TOC 4022).
- **Cards needs-re-edit:** 1 (FISHGRAM Pattern Mining Markdown — paper does not actually use "FISHGRAM" term; needs editorial-terminology note).
- **Cards partial-audit:** 16 — broad NLP/embodied/perception Markdown publication backlog; SynerGAN; Neural-Symbolic and LLM Integration.
- **Carry-forwards:** Trilateral framing; AtomSpace-Scheme vs MeTTa-runtime two-stack; Vepstas 5-repo Hyperon-era portfolio; OllamaNode dual characterization; CF5.6 (Gemini file-existence verification).
- **Source-text gaps remaining:** None (2013 FISHGRAM paper retrieved 2026-04-30).
- **Coverage verdict:** SOURCES-READ-COMPLETE.

### 3.6 MeTTa runtime cluster — NOT STARTED

- **Sources to read (estimated):** ~5–7. Candidate source list:
  - `trueagi-io/hyperon-experimental` — main MeTTa runtime (Rust/Python)
  - `trueagi-io/MeTTa-IL` — intermediate language semantics
  - `zariuq/PeTTa` (if found) — Zarathustra's PeTTa runtime (related to PLN xiPLN gap)
  - `trueagi-io/MeTTaMoRPH` and other Meta-MeTTa/macro implementations
  - `metta-lang.dev` documentation site
  - hyperon docs (`docs/`) on hyperon-experimental
  - `MeTTaLog` (Logtalk-based MeTTa) — Douglas Miles
- **Cards mapped:** 18.
- **Cards edited:** 0.
- **Estimated carry-forwards:** type-system reconciliation (gradual? non-deterministic?); MeTTa-IL semantics; Hyperon 0.2.x quirks (per memory: `bind!+new-space` doesn't clear, `cond` non-reducing, catchalls duplicate); Magi-side MAGUS dispatch patterns (user-owned).
- **Coverage verdict:** CLUSTER-NOT-STARTED.

### 3.7 Cross-org sweeps cluster — NOT STARTED

- **Codex caveat (2026-05-05):** May need to be split into subclusters; one pilot may have too wide a source surface. Candidate splits enumerated in §2.7.
- **Sources to read (estimated):** ~6 cross-org sweeps in aggregate; if subclustered, each subcluster is ~3–5 sources:
  - **(a) ASI-Alliance member orgs:** SingularityNET + Fetch.ai + Ocean Protocol + CUDOS — multi-org meta-source
  - **(b) SingularityNET partner ventures:** TrueAGI / Mind Children / EARTHwise / SophiaVerse / Singularity Finance
  - **(c) Infrastructure / distributed compute:** F1R3FLY-io + NuNet + ASI Chain Runtime
  - **(d) Bio / longevity:** Rejuve broader scope (beyond Perception's rejuve-bio)
  - **(e) iCog Labs research portfolio + residual non-OpenPsi non-Perception Hanson**
  - **(f) Magi (user-owned)** — design-intent already in user's head; may not need full multi-source extraction
- **Cards mapped:** 26.
- **Cards edited:** 4 partial (Hanson, Rejuve, Robotics and Embodiment, Magi).
- **Estimated carry-forwards:** ASI Alliance organizational structure; cross-org repo inventory; Magi-internal user-owned design intent.
- **Coverage verdict:** CLUSTER-NOT-STARTED.

### 3.8 PRIMUS / Cognitive Architectures cluster — NOT STARTED

- **Sources to read (estimated):** ~5–7:
  - **PRIMUS source paper(s)** — Goertzel et al. "Building Better Minds" / PRIMUS architecture papers (Publication Maps+Building Better Minds points to it)
  - **ActPC-Geom paper + reference implementation** (if any)
  - **ActPC-Chem paper + reference implementation** (Algorithmic Chemistry sibling)
  - **Schrödinger-Bridge / Modularization-via-OT paper(s)**
  - **Selectivity Theorem & Hierarchical Corollary paper**
  - **TransWeave** — TBD
  - **WILLIAM** — TBD
  - **QuantiMork** — quantum-MORK
  - **Geodesic Inference** — Goertzel info-geom papers
  - **SubRep** — sub-symbolic representation work
  - **Patterns of Quantum Cognition I** — already a card (Pubs)
- **Cards mapped:** 20.
- **Cards edited:** 0.
- **Estimated carry-forwards:** Cognitive-architecture-stack lock-in (PRIMUS as PLN+ECAN+OpenPsi+MORK+MeTTa unifier); paper-vs-implementation status across PRIMUS components; relationship to Magus 2026-03-11 plan (memory: `project_magus_atomspace_plan_2026_03_11.md` — HERMES = card 741 in Magi Archive).
- **Coverage verdict:** CLUSTER-NOT-STARTED.

### 3.9 Non-clustered Hyperon AI Algorithms cluster — NOT STARTED

- **Sources to read (estimated):** ~4–5:
  - **Concept Blending** — Goertzel/Eskridge paper(s) + any reference implementation (likely under singnet/opencog or similar)
  - **Pattern Mining (broad)** — pattern-miner C++ codebase + scheme miner; not the FISHGRAM 2013 paper (that's Perception) and not rejuve-bio neural mining (Perception)
  - **MetaMo paper + implementation** (MetaMo Robust Motivational Framework + MetaMo to Open-Ended OpenPsi pubs) — bridges to OpenPsi but not extracted in OpenPsi pilot
  - **Semantic Parsing** — RelEx + Link Grammar + MeTTa-front-end-NL
  - **MeTTa-NARS** — TruthValue ports + NARS Ecosystem cards
  - **AIRIS** — Cook & Hammer 2024 paper (per memory: `reference_airis_citations.md`); Cook is creator
  - **NACE** — Non-Axiomatic Causal Engine; relates to NARS family
  - **AI-DSL** — Ring/SingularityNET AI-DSL
  - **MOSES** — Meta-Optimizing Semantic Evolutionary Search
  - **Self-Modification and Safety** — relates to AIRIS but also ASI-safety literature
- **Cluster outputs (explicit):** Audit existing 5 cards + **create 4 missing wiki cards (AIRIS, NACE, AI-DSL, MOSES)**. Promoted from audit-note to explicit cluster output per Codex+Gemini review 2026-05-05.
- **Cards mapped:** 5 existing + 4 missing.
- **Cards edited:** 0.
- **Coverage verdict:** CLUSTER-NOT-STARTED.

---

## §4 Coverage gaps (sources to read)

### 4.1 Within closed clusters
- **PLN:** `lib_pln_xi.metta` — single file, may be in unscanned `zariuq/PeTTa` repo or never committed. Low priority unless xiPLN-runtime work resumes.

### 4.2 Cluster pilots not started
1. **MeTTa runtime cluster** — 0/~5–7 sources. Affects 18 cards.
2. **Cross-org sweeps cluster** — 0/~6 cross-org sweeps; **likely 3–6 subclusters** (per Codex caveat). Affects 22+ cards (4 partially covered via Hanson/Rejuve/Magi).
3. **PRIMUS / Cognitive Architectures cluster** — 0/~5–7 sources. Affects 20 cards.
4. **Non-clustered Hyperon AI Algorithms cluster** — 0/~4–5 sources. Affects 5 cards + must produce 4 new cards (AIRIS/NACE/AI-DSL/MOSES) as explicit cluster outputs.

### 4.3 Missing wiki cards (explicit cluster outputs)
Promoted from audit-note status to explicit cluster outputs per Codex+Gemini review 2026-05-05:
- **AIRIS** — referenced in `HYPERON_CLUSTER_FINDINGS.md` and `reference_airis_citations.md` (Cook & Hammer 2024). Non-clustered HAA cluster output.
- **NACE** — Non-Axiomatic Causal Engine. Non-clustered HAA cluster output.
- **AI-DSL** — Ring/SingularityNET. Non-clustered HAA cluster output.
- **MOSES** — Meta-Optimizing Semantic Evolutionary Search; legacy OpenCog program-evolution. Non-clustered HAA cluster output.
- **HERMES** — Magi Archive card 741 (`Hypergraph-RFP-Lakes`); referenced in MAGUS Phase 4 plan. Likely Cross-org (f) Magi or PRIMUS cluster output, TBD.

---

## §5 Correctness gaps (cards needing re-edit even within closed clusters)

| Card | Cluster | Issue | Fix source |
|---|---|---|---|
| Publications+FISHGRAM Pattern Mining | Perception | Paper does not actually use "FISHGRAM" term — wiki name and content should reflect editorial-terminology disambiguation | Perception Source 1 reconciliation; PLN phase 3 already added the disambiguation to Compositional Spatiotemporal Deep Learning |
| Hyperon AI Algorithms+ECAN+ECAN Full (parent) | ECAN | Parent draft itself not directly edited despite extensive subcard edits; consider light parent overview update reflecting subcard findings | ECAN Source 4 V0-1; V4-1 supplement |
| About Hyperon+AtomSpace+AtomSpace Full (parent) | AtomSpace | Parent draft itself not edited; subcard 7115 carries the four-layer taxonomy lock-in but parent's overview text predates it | AtomSpace Source 4 reconciliation |
| Knowledge Representations+MORK+MORK Full (parent) | AtomSpace | Same pattern — subcards edited; parent overview not | AtomSpace Source 4 |
| Reference+GitHub Repositories | scaffolding | Should reflect cluster-pilot archive pointers from HYPERON_CLUSTER_FINDINGS.md; verify SHAs and additions for new repos surfaced in pilots (atomspace-rocks Phase 5+ candidate, rejuve-bio neural-subgraph-matcher-miner, etc.) | All 5 closed pilots' archive sections |

(All other cards in closed clusters are either PILOT-EDITED or AUDITED-PARTIAL-needs-spot-check; no firm "needs re-edit" verdict for them yet — that requires the spot-check pass.)

---

## §6 Recommendations and next-pass plan

### 6.1 Immediate priorities (correctness within closed clusters)

1. **Spot-check the ~50 partial-audit cards** in PLN/ECAN/OpenPsi/AtomSpace/Perception against their cluster's reconciliation files. Highest density: AtomSpace (13) and Perception (16).
2. **Re-edit FISHGRAM Pattern Mining** Markdown card with editorial-terminology note.
3. **Reconcile parent Full-card overviews** with subcard pilot edits (PLN/ECAN/AtomSpace/MORK Full parents currently lag their own subcards).
4. **Audit Reference+GitHub Repositories** against HYPERON_CLUSTER_FINDINGS.md archive map. Add atomspace-rocks Phase 5+ candidate and rejuve-bio neural miner per Gemini.

### 6.2 Coverage gaps (new cluster pilots) — pilot-order options

**Optimization criterion under each option must be stated explicitly** (per Codex review 2026-05-05). Two candidate orderings:

**Option A — Backlog burn-down (current report recommendation, Gemini concurs):**
1. Non-clustered HAA (smallest, ~4–5 sources). Resolves 5 cards + creates 4 missing cards (AIRIS/NACE/AI-DSL/MOSES). Bridges to OpenPsi/ECAN via MetaMo.
2. MeTTa runtime (~5–7 sources). Affects 18 cards; foundational for all other Hyperon work.
3. PRIMUS / Cognitive Architectures (~5–7 sources). Affects 20 cards.
4. Cross-org sweeps (~6 sources, likely subclustered). Affects 22+ cards.

> Optimization: minimize per-card backlog as fast as possible (ship-the-most-cards-soonest); easy first cluster reduces unknowns; PRIMUS/Cross-org last because they have the largest source surface and most external dependencies.

**Option B — Architectural dependency (Codex alternative):**
1. **MeTTa runtime** (~5–7 sources). Affects 18 cards; foundational layer.
2. Non-clustered HAA (~4–5 sources). Creates AIRIS/NACE/AI-DSL/MOSES; depends on MeTTa-runtime context.
3. PRIMUS / Cognitive Architectures (~5–7 sources). Builds on MeTTa + non-clustered HAA components.
4. Cross-org sweeps (~6 sources, likely subclustered).

> Optimization: each later cluster benefits from the earlier cluster's stack-distinction findings; e.g., MeTTa runtime's type-system + IL semantics inform what "AIRIS impl on MeTTa" or "MOSES port to MeTTa" means in practice. Carries some risk that MeTTa-cluster takes longer than HAA-cluster, delaying first close.

**Decision needed:** which optimization criterion should drive the next pilot's selection? Pending user direction; both reviewers are aligned on the *content* of the next cluster (whichever it is, the pilot pattern remains brief.txt → findings_codex + findings_gemini → reconciliation → close).

Each pilot pattern: brief.txt → findings_codex.txt + findings_gemini.txt → findings_reconciled_crossmodel.txt → cluster-close batch.

### 6.3 Caveats

- **Tentative cluster assignments** in this audit are best-fit; orphan cards (e.g., Implementation Families+Reasoning and Search straddles PLN/MeTTa) may be re-mapped at next pass.
- **Per-cluster source counts** (5–7) are rough estimates; PRIMUS could be larger if every named PRIMUS subcomponent has its own source paper.
- **Cross-org subcluster split** is recommended (Codex 2026-05-05); a single cross-org pilot likely has too wide a source surface to triangulate cleanly.
- **Parent-vs-subcard edit pattern:** This audit reveals a systematic gap — pilots heavily edit Full+sectioning subcards but rarely the parent Full card's overview text. The next pass should consider whether parent overviews need a light "see subcards for current findings" pass or a fuller harmonization. This is not just "closed-pilot source gaps"; it is a closed-pilot **edit-coverage** gap (Codex 2026-05-05 framing).
- **Magi-side Magi Archive cards** (xiPLN, World-Model Calculus, OpenPsi Zhenhua RawData, etc.) are listed but the audit anchor here is `wiki.hyperon.dev` only. Magi Archive has its own audit surface.

### 6.4 Summary numbers

- **Total substantive wiki cards audited:** ~150 (93 Drafts + 43 substantive Markdown Pubs + ~14 named RichText subcards). Excludes Applications (5), Administrator (5), system Markdown guides (3), top-level TOC scaffolding (8).
- **PILOT-EDITED:** 23 wiki cards directly edited by closed pilots. (Plus 4 Magi-Archive RawData cards.)
- **AUDITED-PARTIAL (spot-check needed):** ~50 wiki cards in closed clusters but not edited by their pilot.
- **NOT-AUDITED (cluster not started):** ~64 wiki cards across MeTTa/Cross-org/PRIMUS/Non-clustered HAA. Plus 4 explicit missing-card cluster outputs (AIRIS/NACE/AI-DSL/MOSES) and 1 candidate (HERMES).
- **NEEDS-RE-EDIT:** 1 confirmed (FISHGRAM Markdown), 4 likely (parent Full cards lagging subcards; Reference+GitHub Repositories).
- **OUT-OF-SCOPE:** 18 (Applications 5 + Administrator 5 + system 3 + top-level TOC 5).
