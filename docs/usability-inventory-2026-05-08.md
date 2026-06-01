# Hyperon Wiki Usability Inventory — 2026-05-08

Read-only inventory feeding the usability pass on Lake's behalf, in response to Anna Mikeda's 2026-05-08 feedback batch (TL;DR / bracket-labels / dead URLs / RawData links / diagrams / define-on-first-use / `+last_verified` Status dates).

**Scope**: all "Foo Full" cards on `wiki.hyperon.dev` — 21 leaf-name junctions plus their RichText subcards.

**What this is NOT**: not editorial commentary, not the usability pass itself, not URL verification (that's a follow-on phase). Just inventory.

**Per-card outputs**: bracket-label leaks (cluster-pilot vocabulary that shouldn't have shipped) / outbound RawData+ links / external URL list (status verification deferred) / diagram-opportunity flag / undefined-on-first-use terms.

---

## Summary

- Total junctions attempted: 21
- Junctions with parent path discovered: 21 (100%)
- Total substantive content cards walked: 54 (RichText subcards + single-card non-virtual junctions). 7 single-card junctions: AIRIS / NACE / AI-DSL / MeTTa-NARS / ASI Chain Runtime / DAS / TransWeave / WILLIAM / Self-Modification and Safety / Hyperon Experimental. 11 virtual junctions with multi-subcard fan-out: MOSES (4) / AtomSpace (4) / OpenCog Legacy (4) / Semantic Parsing (4) / PLN (5) / PRIMUS (4) / MORK (4) / MetaMo (3) / ECAN (4) / MeTTa Programming Language (4) / Magi (4).
- Bracket-label leaks: ~120 occurrences across ~10 cards. Top concentrations: Hyperon Experimental Full (~25), NACE Full (16+), MOSES subcards (~33 across 3 subs), ECAN Development and Historical Context (10+), MeTTa-NARS Full (10), MetaMo subcards (9), AIRIS Full (8), AI-DSL Full (5), DAS Full (~3 in quoted block). Many cards (TransWeave, WILLIAM, Self-Modification and Safety, Magi, MeTTa Programming Language, AtomSpace subcards, OpenCog Legacy, Semantic Parsing, PLN, PRIMUS, MORK) have ZERO bracket leaks — the leak pattern is concentrated in cards authored or refined directly from cluster-pilot extraction findings (HAA pilot 2026-05-06/07 and ECAN/MeTTa-runtime closes), not the broader content-card population.
- RawData+ outbound links: ~10 occurrences across 7 cards. Anna's "404 for non-Raw-Data-Analyst readers" concern applies. Cards: ASI Chain Runtime (1), MORK Status (4), PLN Execution-on-MORK (2), MeTTa Status (2), MetaMo Status (2), Magi Status (1).
- External URLs collected: ~156 across all cards (verification deferred). Of these: roughly 100 are legitimate `github.com/...` repository links; ~56 are ⚠️ SUSPICIOUS auto-linker artifacts where Python/C++/Markdown filenames (e.g. `airis_stable.py`, `MorkDB.cc:268`, `wiki.opencog.org`, `setup.sh`, `bridge.py`) were rendered as `http://...` external links by the wiki renderer, often nested 3-10 levels deep. The DAS Full card and ECAN Development-and-Historical-Context card are the worst offenders (DAS has 6+ pseudo-URLs wrapped in 10-deep `<a>` tags; ECAN has ~9 separate filename:line pseudo-URLs). This is a Decko/Markdown-renderer or content-import bug, not a content authoring problem; it exactly matches Anna's "atomdbsingleton.cc" example and is much broader than initially reported.
- Diagram-opportunity flags: ~33 cards. Highest-priority candidates (cluster the most existing complex content): AtomSpace Implementations (4-layer taxonomy table → diagram), MOSES Implementation Eras (6-implementation lineage tree), OpenCog Legacy Timeline and Bridge Map (1995→2025 timeline + 11-row before-vs-after architecture comparison), ECAN Development-and-Historical-Context (9-event executable-coupling lifecycle + trilateral perception/symbolic/neural mining), Self-Modification and Safety (5-stage pipeline + Worked Example swimlane), Hyperon Experimental (7-crate workspace + Stdlib split), DAS (4-layer Lambda Architecture + Query-Tree).
- Undefined-on-first-use flags: ~52 cards (every substantive card had at least 3-5 jargon terms introduced cold). Most universally-recurring undefined terms: ECAN, PLN, STI/LTI, AttentionBank, MORK, DAS, AtomSpace, MeTTa-IL, MOSES, hyperpose, URE, CRDT, TransWeave, SubRep. These appear unexpanded in many cards even when the cluster-narrative tags they wear (e.g. `[METTA-NARS-NOT-PLN]`) implicitly require the reader to already know the term.
- Cards with no findings: 0 (every card had at least one observation across the 5 categories).
- Cards/junctions where the parent path could not be discovered: 0.

**Cross-cutting findings worth flagging beyond the inventory categories**:
1. **Auto-linker `<a>`-nesting bug** (worst on DAS Full / ECAN Dev-Historical / Atomspace Design Evolution / OpenCog Legacy Status / Hyperon Experimental Full / PLN Design History): the renderer auto-wraps any string matching `\b[a-z]+\.(cc|py|md|sh|pl|py:N+|cc:N+|org)` as an `<a href="http://...">` and then re-applies the same wrapper on subsequent renders, producing 5-to-10-deep nested anchors that break click behavior. This is a single root-cause problem, fixable at the Decko renderer level, that would silently clean up dozens of "broken URLs" that match Anna's complaint.
2. **Cluster-pilot bracket-label vocabulary leakage is ~80% confined to ~10 cards** authored or refined during the HAA / MeTTa-runtime / ECAN cluster-pilot wiki-edit windows. Editorial pass focused on those 10 cards (NACE, AI-DSL, MeTTa-NARS, AIRIS, MOSES Implementation-Eras + Status + MORK-Foundations, MetaMo Core-Mechanisms + Status, ECAN Dev-Historical, DAS Full, Hyperon Experimental Full) would resolve most of Anna's bracket-label complaint without touching the broader ~44 leak-free cards.
3. **No `+last_verified` field exists on any card** — Anna's "Status sections need a 'last updated' date" point is real; the wiki shows `Updated: 2026-05-12T09:18:28Z` in card metadata but this reflects most-recent-edit, not last source-verification. None of the 4 "Status and Resources" subcards (MOSES / MORK / MetaMo / ECAN / MeTTa Lang / DAS / Magi / PRIMUS / OpenCog Legacy) carry an explicit verification date — they all read like timeless statements when most claims are 2026-04-XX or earlier.

---

<!-- INVENTORY-SLOT: AIRIS Full -->
## AIRIS Full

**Junction path**: `Hyperon AI Algorithms+AIRIS (Autonomous Intelligent Reinforcement Inferred Symbolism)+AIRIS Full` (ID 7495, Published — single-card not virtual; Human Approved by Ursula Addison 2026-05-07; updated 2026-05-12)

### Card: AIRIS Full (ID 7495)

**Bracket leaks** (8): `[IMPLEMENTATION-BACKED-CORE]` in "**Status:** ... per Non-clustered HAA cluster pilot"; `(V1-2 below)` (paper boundary); `(V1-3)`, `(V1-4)`, `(V1-5)` in Boundaries section; `(V1-1)` in attribution corrections; `[Still & Precup 2012]` (citation form — OK); references to "V1-2", "V1-3", "V1-4", "V1-5" carry-forward IDs sprinkled in prose without explanation.
**RawData links**: none.
**External URLs** (8): `github.com/berickcook/AIRIS_Public` (paper-cited canonical); `mailto:berick.cook@singularitynet.io`; `github.com/singnet/AIRIS-general`; `github.com/singnet/AIRIS-client`; three malformed `http://stable.py` and one `http://airis.py` rendered as external-link auto-detections from Python filenames `airis_stable.py`/`airis.py` — ⚠️ SUSPICIOUS — verify (these are NOT URLs; auto-linker artifact; cosmetic but visibly broken).
**Diagram opportunity**: Rule Base + State Graph + Pre-/Post-Action Observation loop, plus the 3-implementation comparison table (berickcook reference / singnet generalized / singnet client wrapper), would benefit from architecture and lineage diagrams.
**Undefined-on-first-use** (5): ECAN, PLN, STI/LTI, AtomSpace, NARS (mentioned via cross-link but not defined here); SubRep, PDDL, DQN appear without expansion.

---

<!-- INVENTORY-SLOT: NACE Full -->
## NACE Full

**Junction path**: `Hyperon AI Algorithms+NACE (Non-Axiomatic Causal Explorer)+NACE Full` (ID 7765, Draft — single-card not virtual; updated 2026-05-12)

### Card: NACE Full (ID 7765)

**Bracket leaks** (16+): `[IMPLEMENTATION-BACKED-CORE]`, `[AIRIS-DERIVED-NAL-ADJACENT]`, `[NACE-NOT-AIRIS]`, `[PARTIALLY-INTEGRATED-VIA-METTA-BRIDGE]` in Source Verdict; `[AIRIS-CONFIDENCE-NOT-PLN-TV]` in NAL bullet; carry-forwards `(V1-3 [AIRIS-CURIOSITY-NOT-ECAN], V1-4 [AIRIS-CONFIDENCE-NOT-PLN-TV], V1-5 [AIRIS-STATE-GRAPH-NOT-ATOMSPACE])` in narrative; `(V5-1)` in "Not C++"; `[NACE-IMPLEMENTATION-BACKED-CORE-PURE-PYTHON]`, `[NACE-AIRIS-DERIVED-NAL-ADJACENT]`, `[NACE-BRIDGES-METTA-NARS-NOT-SAME]`, `[PATHAM9-HAA-PORTFOLIO]` in archive footer.
**RawData links**: none.
**External URLs** (12): `github.com/patham9/NACE` (HEAD repo, OK); plus 11 auto-linked filename pseudo-URLs ⚠️ SUSPICIOUS — verify: `http://gui.py`, `http://nace.py` (multiple `:LINE` variants), `http://README.md:5`, `http://bridge.py` — all are file paths the renderer mistook for URLs and wrapped in `external-link` anchors. Cosmetic but they all look like dead links to a reader.
**Diagram opportunity**: A side-by-side AIRIS / NACE / MeTTa-NARS comparison table (paradigm dimensions, truth-value semantics, planning loop) plus a NACE-to-MeTTa-NARS bridge diagram would clarify the "extends but is not" framing.
**Undefined-on-first-use** (5): NAL, ONA (OpenNARS for Applications — expanded once but in passing), STI/LTI, MeTTa runtime architecture, PLN s/c (strength/count) vs NAL f/c.

---

<!-- INVENTORY-SLOT: AI-DSL Full -->
## AI-DSL Full

**Junction path**: `Hyperon AI Algorithms+AI-DSL+AI-DSL Full` (ID 7768, Draft — single-card not virtual; updated 2026-05-12)

### Card: AI-DSL Full (ID 7768)

**Bracket leaks** (5): `[ACTIVE-IDRIS-DSL]` and `[AI-DSL-DUAL-CITIZEN]` (twice each — Source Verdict + Implementation Surface table); `[AI-DSL-DUAL-CITIZEN]` carry-forward referenced as "V5-4" in archive footer; "(V5-rejected pre-cluster-pilot reviewer cite.)" annotation in "Not located in src/Composition.idr" bullet.
**RawData links**: none.
**External URLs** (4): `github.com/singnet/ai-dsl` (HEAD repo, OK — appears twice); plus 1 auto-linked filename pseudo-URL ⚠️ SUSPICIOUS — verify: `http://ai-dsl-project-close-report-2022-oct.md` (a docs-tree file path mistaken for a URL).
**Diagram opportunity**: A two-track diagram (Idris typed-composition layer vs MeTTa combinator/ontology layer) would clarify the "dual citizen" framing better than the prose+bullets.
**Undefined-on-first-use** (4): Idris (dependent-types language not introduced), MeTTa-Motto, ngeiswei (a person — unfamiliar to outside readers), SingularityNET marketplace context.

---

<!-- INVENTORY-SLOT: MeTTa-NARS Full -->
## MeTTa-NARS Full

**Junction path**: `Hyperon AI Algorithms+MeTTa-NARS (Non-Axiomatic Reasoning System)+MeTTa-NARS Full` (ID 7771, Draft — single-card not virtual; updated 2026-05-12)

### Card: MeTTa-NARS Full (ID 7771)

**Bracket leaks** (10): `[IMPLEMENTATION-BACKED-NAL1-5]`, `[METTA-NARS-NOT-PLN]`, `[MOTTO-POC-INTEROP]` in Source Verdict; `[IMPLEMENTATION-BACKED-NAL1-5]` in Implementation Surface table; `[PAPER-NOT-IMPLEMENTED-IN-METTA-NARS]` in vs PLN; `[AIRIS-CONFIDENCE-NOT-PLN-TV]` carry-forward; "(V5-14 narrative-guard at S5 close.)"; `[METTA-NARS-IMPLEMENTATION-BACKED-NAL1-5]`, `[METTA-NARS-NOT-PLN]`, `[PATHAM9-HAA-PORTFOLIO]`, `[METTA-MOTTO-OUT-OF-S5]` in archive footer.
**RawData links**: none.
**External URLs** (3): `github.com/patham9/metta-nars` (twice — OK); plus 1 ⚠️ SUSPICIOUS — verify: `http://bridge.py` (auto-link of Python filename).
**Diagram opportunity**: Side-by-side NAL vs PLN truth-value semantics box (f/c vs s/c) and the patham9 portfolio web (NACE / MeTTa-NARS / AIRIS co-author lineage) would help readers grasp paradigm boundaries.
**Undefined-on-first-use** (5): NAL (used heavily; expanded only as "Non-Axiomatic Logic" in passing), AIKR ("Assumption of Insufficient Knowledge and Resources" expanded once but jargon), ONA (OpenNARS for Applications — expanded once), POC, Mattermost (where "the Goertzel mattermost paper" lives — assumed insider knowledge).

---

<!-- INVENTORY-SLOT: ASI Chain Runtime Environment Full -->
## ASI Chain Runtime Environment Full

**Junction path**: `ASI:Chain Runtime Environment+ASI Chain Runtime Environment Full` (ID 4292, Published — single-card not virtual; Human Approved by Ursula Addison 2026-05-08; updated 2026-05-12). Children are metadata only (`+approved by`, `+approved at`, `+tag`).

### Card: ASI Chain Runtime Environment Full (ID 4292)

**Bracket leaks**: none in cluster-pilot vocab sense.
**RawData links** (1): inline link to `RawData+Publications+Meta_MeTTa_an_operational_semantics_for_MeTTa` in Status and Resources Meta-MeTTa bullet.
**External URLs** (6 distinct, plus rendering bug): `arxiv.org/abs/2305.17218` (Meta-MeTTa, twice); `github.com/asi-alliance/asi-chain` (twice); `github.com/F1R3FLY-io` (org); `github.com/F1R3FLY-io/MeTTaIL` (twice); `github.com/F1R3FLY-io/MeTTa-Compiler` (twice); `https://docs.asichain.io/` (twice). NOTE: the `docs.asichain.io` link is rendered with **9-deep nested `<a>` tags** wrapping each other — ⚠️ STRUCTURAL BUG — verify (looks like a renderer or markdown-to-HTML round-trip mishap; produces visibly broken UI).
**Diagram opportunity**: yes — Dual-Engine architecture (F1R3FLY + MeTTaCycle), MeTTa-IL routing flow (local→MORK / distributed→Rholang), and the four-register → five-register state machine extension all beg for diagrams. Three diagrams could replace ~40% of the text.
**Undefined-on-first-use** (5): Rholang (defined eventually but used before), BlockDAG, RSpaces (defined late, used early), CRDT (used in body before "CRDT Join-Semilattices"), CIDs (Content IDs — never expanded), Ocaps (expanded once parenthetically), GSLT, BNFC.

---

<!-- INVENTORY-SLOT: MOSES Full -->
## MOSES Full

**Junction path**: `Hyperon AI Algorithms+MOSES (Meta-Optimizing Semantic Evolutionary Search)+MOSES Full` (ID 4399, Published — virtual junction; 4 RichText subcards)

### Subcard: Implementation Eras and Design History (ID 7132)

**Bracket leaks** (12+): `[ACTIVE-METTA-PRIMARY]` (twice), `[VEPSTAS-MIRROR-SAME-SHA]` (twice), `[STRICT-FORK-STALE]`, `[STRICT-FORK-STALE-MERGED-UPSTREAM]`, `[STRICT-FORK-DIVERGED-LEGACY-FIXES]`, `[STANDALONE-EXPERIMENT-NOT-FORK]` (twice), `[ACTIVE-CPP-ATOMSPACE-BASELINE]`, `[SUPERSEDED-BY-METTA-MOSES]`, `[ARCHIVAL-PARADIGM-PREDECESSOR]`, `[MORK-MOSES-PARTIAL-SCAFFOLD-OPEN-RESEARCH-LINE]`. Inline `git rev-list --left-right --count` raw output `0\t0`, `0\t107`, `7\t165`, `19\t23` is also visually confusing for non-Git readers.
**RawData links**: none.
**External URLs** (15): `github.com/opencog/moses`, `github.com/opencog/asmoses` (×3), `github.com/trueagi-io/hyperon-moses` (×2), `github.com/iCog-Labs-Dev/metta-moses` (×3), `github.com/linas/as-moses` (×2), `github.com/leungmanhin/asmoses`, `github.com/singnet/asmoses`, `github.com/singnet/moses`, `github.com/iCog-Labs-Dev/moses-optimization-algorithms` (×2), `github.com/iCog-Labs-Dev/elegant-normal-forms-python`; plus 1 ⚠️ SUSPICIOUS — verify: `http://setup.sh` (auto-link of shell-script filename).
**Diagram opportunity**: yes — a 6-implementation lineage tree (legacy moses → asmoses → linas/as-moses mirror; trueagi-io/hyperon-moses; iCog-Labs-Dev/metta-moses primary; standalone moses-optimization-algorithms) showing fork relationships and verdict tags.
**Undefined-on-first-use** (5): MPI, ENF (Elegant Normal Form — defined later in sibling subcard), PathMap, P12, Reduct (used as proper noun without expansion).

### Subcard: Status and Resources (ID 7133)

**Bracket leaks** (10): `[ACTIVE-METTA-PRIMARY]`, `[ACTIVE-CPP-ATOMSPACE-BASELINE]`, `[VEPSTAS-MIRROR-SAME-SHA]`, `[SUPERSEDED-BY-METTA-MOSES]` (twice), `[ARCHIVAL-PARADIGM-PREDECESSOR]`, `[STRICT-FORK-STALE]`, `[STRICT-FORK-STALE-MERGED-UPSTREAM]`, `[STRICT-FORK-DIVERGED-LEGACY-FIXES]`, `[STANDALONE-EXPERIMENT-NOT-FORK]`, `[MORK-MOSES-PARTIAL-SCAFFOLD-OPEN-RESEARCH-LINE]`. Plus inline V5-9, V5-5..V5-10, V5-15 carry-forward refs.
**RawData links**: none.
**External URLs** (9): `github.com/iCog-Labs-Dev/metta-moses`, `github.com/opencog/asmoses`, `github.com/linas/as-moses`, `github.com/trueagi-io/hyperon-moses`, `github.com/ngeiswei/hyperon-moses`, `github.com/opencog/moses`, `github.com/leungmanhin/asmoses`, `github.com/singnet/asmoses`, `github.com/singnet/moses`, `github.com/iCog-Labs-Dev/moses-optimization-algorithms`; plus 1 ⚠️ SUSPICIOUS — verify: `http://setup.sh`.
**Diagram opportunity**: skip; the table format would already work better than the current bullet list, but no diagram needed.
**Undefined-on-first-use** (4): GEO-EVO, Schrödinger bridge, mork_ffi, PathMap.

### Subcard: Core Mechanisms and Scoring (ID 7128)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none.
**Diagram opportunity**: yes — the Two Nested Search Loops + Knob-Based Representation + Deme Structure together form a clean three-tier control loop diagram (outer structural → inner numeric → fitness pipeline) that would replace the bullets.
**Undefined-on-first-use** (5): PGE, SGE, SGGP, SMD, bscore/cscore (defined inline but with abbreviations introduced before expansion).

### Subcard: Mathematical Foundations and MORK (ID 7130)

**Bracket leaks** (1): `[MORK-MOSES-PARTIAL-SCAFFOLD-OPEN-RESEARCH-LINE]`. Plus "(V5-10 carry-forward)" reference. Inline `git ls-tree HEAD -- 'mork_ffi*'` raw command would also confuse non-developers.
**RawData links**: none.
**External URLs** (1): `github.com/iCog-Labs-Dev/metta-moses`; plus 1 ⚠️ SUSPICIOUS — verify: `http://setup.sh`.
**Diagram opportunity**: the GEO-EVO `f·g` selection rule and TransWeave operator interplay diagram (PLN ↔ MOSES ↔ neural value learners) would help illustrate "geodesic search," currently abstract.
**Undefined-on-first-use** (4): TransWeave (cross-link only), Schrödinger bridge, factor-graph priors, commutator gaps.

---

<!-- INVENTORY-SLOT: AtomSpace Full -->
## AtomSpace Full

**Junction path**: `About Hyperon+AtomSpace+AtomSpace Full` (ID 4403, Published — virtual junction; 4 RichText subcards)

### Subcard: Core Concept and Data Model (ID 7111)

**Bracket leaks**: none (uses `\(\mathcal{M}\)` LaTeX notation, not cluster-pilot tags).
**RawData links**: none.
**External URLs** (1 distinct, but rendered with double-nested `<a>` wrappers): `http://wiki.opencog.org` ⚠️ STRUCTURAL — verify (auto-link applied twice, producing nested anchors that break click behavior).
**Diagram opportunity**: yes — the four atom variants (Symbol/Variable/Expression/Grounded) and the metagraph-vs-hypergraph distinction would land faster as a visual.
**Undefined-on-first-use** (5): GIMPLE/GIL/LLVM IR (used as a one-off comparison without expansion), KR (Knowledge Representation, never expanded), Atomese, hash-consing, Zipfian.

### Subcard: Values and Space API (ID 7113)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none (only internal cross-links).
**Diagram opportunity**: yes — the Atom-vs-Value separation ("plumbing vs fluid"), the TruthValue→FloatValue evolution, and the Space-API multi-backend swap-out (MORK/DAS/Neural/Rholang/in-memory) all form a clean architecture diagram.
**Undefined-on-first-use** (4): TruthValue, PLN (cross-linked), DNN (used without expansion), PropertyMap (referenced as historical proposal).

### Subcard: Implementations (ID 7115)

**Bracket leaks** (1): table title "(Cluster-Pilot Lock-In, 2026-04-29)" + inline reference "R4.J1 lock-in across Sources 1-4" + footer cluster-pilot archive pointer. No raw `[TAG]` style leaks though, so cleaner than other Full cards.
**RawData links**: none.
**External URLs** (15): `github.com/opencog/atomspace` (×3), `atomspace-storage` (×2), `atomspace-pgres`, `atomspace-rocks` (×2), `atomspace-cog` (×2), `atomspace-bridge` (×2), `trueagi-io/hyperon-experimental` (×2), `singnet/das`, `trueagi-io/MORK`, `iCog-Labs-Dev/atomspace-viz`, `opencog/atomspace-typescript`. All look legitimate (opencog/trueagi-io/singnet/iCog-Labs-Dev orgs).
**Diagram opportunity**: yes, urgent — a four-layer stack diagram (Classical / Hyperon Space / DAS / MORK) with repos and Decko-relevance per layer would replace the entire intro table, and the Classical→Hyperon→MORK lineage map would help readers grasp "AtomSpace is not one thing."
**Undefined-on-first-use** (6): StorageNode, BackingStore, Kripke semantics, ZAM, ProxyNode, ShardZipper.

### Subcard: Design Evolution and Performance (ID 7117)

**Bracket leaks**: none in cluster-pilot vocab sense.
**RawData links**: none.
**External URLs** (1 distinct, but rendered with **triple-nested `<a>` tags** in 3 places): `http://wiki.opencog.org` ⚠️ STRUCTURAL — verify (auto-linker applied three times in succession on the same string; visible UI issue).
**Diagram opportunity**: yes — the "What was tried and abandoned" timeline (IPFS / OpenDHT / UUID / Postgres / RocksDB / etc.) is begging for a decision-tree or timeline diagram. Threading-scaling per-CPU table would also be cleaner as a small chart.
**Undefined-on-first-use** (5): IPFS, DHT/Kademlia, ZeroMQ/protobuf, MMU, alpha-conversion (assumed lambda-calculus literacy), URE.

### Subcard: Status and Resources (ID 7118)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs** (2): `arxiv.org/abs/2310.18318` (Goertzel 2023 OpenCog Hyperon paper); `github.com/opencog/atomspace` (Vepstas Design Notes ram-cpu.pdf path inside repo).
**Diagram opportunity**: skip; this is the deliberately concise Status section.
**Undefined-on-first-use** (3): JeTTa, MeTTa-4 (referenced as a target without explanation), Neural Spaces (defined upstream but recapped here without recap).

---

<!-- INVENTORY-SLOT: OpenCog Legacy Full -->
## OpenCog Legacy Full

**Junction path**: `About Hyperon+OpenCog Legacy+OpenCog Legacy Full` (ID 4409, Published — virtual junction; 4 RichText subcards)

### Subcard: Why Hyperon Replaced OpenCog (ID 7143)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none (only internal cross-links).
**Diagram opportunity**: skip; the 5-numbered-reasons format reads naturally.
**Undefined-on-first-use** (4): URE, GroundedSchemaNode, RelEx, quantale (used as proper noun).

### Subcard: Maturity and Design Decisions (ID 7145)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none (all inline cites are mailing-list / wiki names without explicit URLs).
**Diagram opportunity**: yes — the "What was tried and why each was rejected" set (CogServer / OpenPsi / OCaml-Haskell / Visualization / Pattern Miner) would land much better as a small lessons-learned table or diagram than a wall of paragraphs.
**Undefined-on-first-use** (5): CogServer, MicroPsi, BindLink, ConceptNet, cog-mine API.

### Subcard: Timeline and Bridge Map (ID 7141)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none.
**Diagram opportunity**: yes — the timeline (1995→2025) is begging to be a horizontal timeline graphic, and the 11-row "Bridge Map" comparison table is good but a side-by-side architecture-then-vs-now diagram would be more memorable.
**Undefined-on-first-use** (5): Webmind, Novamente, CogPrime, GHOST, ChatScript.

### Subcard: Status and Resources (ID 7147)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs** (5): `github.com/opencog/link-grammar`, `github.com/opencog/cogserver`, `github.com/opencog/cogutil`, `github.com/opencog/atomspace`, `github.com/opencog/learn`; plus `arxiv.org/abs/2310.18318`.
**Diagram opportunity**: skip; this is the deliberately concise Status section.
**Undefined-on-first-use** (3): URE, ECAN (linked but not introduced), metta-attention.

---

<!-- INVENTORY-SLOT: Semantic Parsing Full -->
## Semantic Parsing Full

**Junction path**: `Hyperon AI Algorithms+Semantic Parsing (LLM/NLP)+Semantic Parsing Full` (ID 4419, Draft — virtual junction; 4 RichText subcards)

### Subcard: Legacy Pipeline (ID 7120)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none.
**Diagram opportunity**: yes — a clean Legacy NLP-pipeline diagram (input text → Link Grammar → lg-atomese → RelEx → AtomSpace) with each stage's status (operational/legacy/superseded) would land much faster than 6 H4 sections of prose.
**Undefined-on-first-use** (5): CCG, DisCoCat, FrameNet, MST, MSDAG.

### Subcard: Symbolic Heads and Grammar Induction (ID 7124)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none (cites are arxiv:2005.12533 in plain text).
**Diagram opportunity**: yes — the Symbolic-Transformer-Heads training/runtime flow (template memory + contrastive alignment loss + reconstruction loss + retrieval injection) needs a small system diagram; LaTeX equations alone won't communicate to non-ML readers.
**Undefined-on-first-use** (4): WILLIAM (cross-link only), BERT (assumed), residual stream, masked predictions.

### Subcard: Hyperon-Era Approaches (ID 7122)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs** (2): `github.com/rTreutlein/nl2pln_demo`; `github.com/trueagi-io/metta-nl-corpus`.
**Diagram opportunity**: skip; the four H4 subsections (NL-to-MeTTa via LLMs / SENF / Dependent Types / Unified Parsing & Reasoning) are conceptually parallel and a four-quadrant compare table would help, but no critical diagram need.
**Undefined-on-first-use** (5): SNLI, Lojban, Curry-Howard, dependent type theory, Word Grammar (WG).

### Subcard: Status and Resources (ID 7126)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs** (8): `github.com/opencog/link-grammar`, `github.com/opencog/lg-atomese`, `github.com/opencog/learn`, `github.com/opencog/matrix`, `github.com/opencog/generate`, `github.com/rTreutlein/nl2pln_demo`, `github.com/trueagi-io/metta-nl-corpus`, `github.com/iCog-Labs-Dev/bio-semantic-parser`, `github.com/opencog/relex`.
**Diagram opportunity**: skip; the bullet/table format is appropriate for a Status section.
**Undefined-on-first-use** (5): Dagster, SuReal, FST (Finite-State Transducer), SHIQ description logic, Hobbs algorithm.

---

<!-- INVENTORY-SLOT: PLN Full -->
## PLN Full

**Junction path**: `Hyperon AI Algorithms+PLN (Probabilistic Logic Networks)+PLN Full` (ID 4184, Draft — virtual junction; 5 RichText subcards)

### Subcard: Core Mechanisms and Inference (ID 7102)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none.
**Diagram opportunity**: yes — the inference-rules table (Deduction / Induction / Abduction / Modus Ponens / etc. with their truth-value formulas) and the forward/backward/polyward chaining flow could be a clean visual showing the unified TV propagation pipeline.
**Undefined-on-first-use** (5): STV/ETV (defined inline), ImplicationScopeLink, ContextLink, BindLink, stamp-disjoint checking.

### Subcard: Mathematical Foundations (ID 7104)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none.
**Diagram opportunity**: yes — the quantale algebra (carrier + ⊕ accumulation + ⊗ conjunction) plus the Context Quantaloid unification with NARS would benefit from a small commutative-diagram or category-theoretic figure to ground the formalism.
**Undefined-on-first-use** (5): quantale, quantaloid, MLN (Markov Logic Networks — referenced but not expanded), Jaccard similarity, DependencyFactor.

### Subcard: Execution on MORK (ID 7106)

**Bracket leaks**: none.
**RawData links** (2): inline `RawData+Publications+MORK_MM2_PathMap_Formalization` and `RawData+Publications+xiPLN`.
**External URLs** (1): `github.com/trueagi-io/chaining`.
**Diagram opportunity**: yes — the two execution strategies (backward chaining engine vs factor-graph belief propagation) with their atom types/indices/scheduling/caching layers could be a side-by-side architecture comparison; the Implementation status block calls out a real implementation gap that visual highlighting would clarify.
**Undefined-on-first-use** (5): KaHyPar, Magic sets / magic atom (defined inline but heavy term), DTL, Skolemization, NUMA.

### Subcard: Design History and Implementation (ID 7108)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs** (8): `github.com/trueagi-io/PLN`, `github.com/trueagi-io/pln-experimental`, `github.com/trueagi-io/chaining`, `github.com/patham9/PLN`, `github.com/ngeiswei/PLN`, `github.com/trueagi-io/hyperon-pln`, `github.com/opencog/pln`. Plus `wiki.opencog.org` rendered with **5-deep nested `<a>` wrappers** ⚠️ STRUCTURAL — verify (worse instance of the auto-link nesting bug already seen in AtomSpace Full and ASI Chain Runtime Full).
**Diagram opportunity**: yes — the implementation lineage (PLN primary → PLN2 → PLN3 → hyperon-pln → opencog/pln legacy) would be a clean fork-tree diagram, paralleling the MOSES Implementation Eras card.
**Undefined-on-first-use** (5): MLN, Tuffy, ProbLog, AbsentLink, GetLink, Idris2.

### Subcard: Status and Resources (ID 7109)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs** (6): four PLN example links (FlyingRaven.metta, Smokes.metta, toothbrush.metta, Robot.metta) all under `github.com/trueagi-io/PLN/blob/main/examples/`; `github.com/trueagi-io/PLN/wiki`; `github.com/trueagi-io/pln-experimental`.
**Diagram opportunity**: skip; this is the deliberately concise Status section.
**Undefined-on-first-use** (5): OSLF, Yoneda lemma, Grothendieck construction, piPLN, hyperon-miner.

---

<!-- INVENTORY-SLOT: PRIMUS Full -->
## PRIMUS Full

**Junction path**: `Cognitive Architectures+PRIMUS (formerly CogPrime)+PRIMUS Full` (ID 4192, Draft — virtual junction; 4 RichText subcards)

### Subcard: Architecture and Core Dynamics (ID 7164)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none.
**Diagram opportunity**: yes — the "Two Meta-Dynamics" loop (Goal-Directed + Ambient Background) over a shared AtomSpace, with the named flows between MetaMo / PLN / MOSES / SubRep / ECAN / pattern mining / TransWeave, would land much faster as an architecture diagram than the prose.
**Undefined-on-first-use** (5): MetaMo, MOSES/GEO-EVO, SubRep CDS/PDS (defined inline parenthetically), TransWeave, predictive-coding layers.

### Subcard: Components and Integration (ID 7166)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none.
**Diagram opportunity**: yes — the 8-step "How the Advances Work Together" flow (Weakness control → WILLIAM → fluid ECAN → PLN/ActPC-Chem → Schrödinger → MetaMo/SubRep → TransWeave → predictive coding) is begging to be a process flow diagram with feedback loops.
**Undefined-on-first-use** (6): I-surprisingness, HebbianLink, ActPC-Chem (expanded once), QuantiMORK, residuation, pseudo-bimonad.

### Subcard: Cognitive Synergy (ID 7167)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none.
**Diagram opportunity**: yes — the cognitive-schematic equation `Context ∧ Procedure → Goal ⟨p⟩` plus the "Key Synergy Pairs" (PLN↔MOSES, ECAN↔PLN, etc.) would benefit from a synergy-network diagram showing the 6 memory types and their inter-process bridges.
**Undefined-on-first-use** (5): CST (Cognitive Synergy Theory — defined inline), GEO-EVO, deme, indefinite probability truth values, functorial maps.

### Subcard: Status and Resources (ID 7169)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs** (5): `github.com/trueagi-io/hyperon-experimental`, `github.com/patham9/PeTTa`, `github.com/iCog-Labs-Dev/hyperon-openpsi`, `github.com/trueagi-io/PLN`, `github.com/trueagi-io/chaining`, `github.com/trueagi-io/hyperon-miner`; plus `arxiv.org/abs/2310.18318`. Plus `wiki.opencog.org` rendered with **double-nested `<a>`** ⚠️ STRUCTURAL — verify (recurring auto-link bug).
**Diagram opportunity**: skip; this is the deliberately concise Status section.
**Undefined-on-first-use** (4): patternism, glocal memory (defined inline), DeSTIN (expanded once), RSpace.

---

<!-- INVENTORY-SLOT: MORK Full -->
## MORK Full

**Junction path**: `Knowledge Representations+MORK (MeTTa Optimized Reduction Kernel)+MORK Full` (ID 4194, Draft — virtual junction; 4 RichText subcards)

### Subcard: Core Mechanisms (ID 7149)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none.
**Diagram opportunity**: yes — PathMap (triemap with prefix sharing) + ZAM (zipper cursor over posting lists) + MM2 (Gather-Process-Scatter) layered as a 3-tier execution stack diagram would replace pages of prose.
**Undefined-on-first-use** (5): hash-consing, anti-join, MM2 (expanded but jargon-heavy), MORKL (defined inline but introduced cold), Gather-Process-Scatter.

### Subcard: Formal Foundations and Indexing (ID 7151)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none.
**Diagram opportunity**: yes — the Selectivity Theorem + slot-centric break-even rule together would benefit from a worked-example visualization (a small trie, a query with k legs, the resulting posting-list intersection narrowing).
**Undefined-on-first-use** (5): submodular coverage, ε-independence assumption, posting list, hierarchical generative model, AST.

### Subcard: Architecture and Ecosystem (ID 7153)

**Bracket leaks**: none in cluster-pilot vocab sense.
**RawData links**: none.
**External URLs** (5 distinct, plus rendering bugs): `github.com/trueagi-io/MORK`, `github.com/patham9/mork_ffi` (×2), `github.com/patham9/faiss_ffi`, `github.com/Adam-Vandervorst/CZ2`, `github.com/iCog-Labs-Dev/weighted-atom-sweep`, `github.com/ClarkeRemy/MM2_Structuring_Code`. Plus 2 ⚠️ STRUCTURAL — verify pseudo-URLs: `http://morkspaces.pl:7` (a Prolog source filename + line number rendered as URL with port, **wrapped in 8-deep nested `<a>` tags**) and `http://MorkDB.cc:268` (a C++ source filename + line wrapped in 8-deep nested `<a>` tags).
**Diagram opportunity**: yes — the 8-member crate workspace (interning/expr/frontend/kernel/4 experiments) plus the PathMap-vs-server-branch separation, plus the cognitive-algorithm integration column (PLN paper-only / WILLIAM trie / weighted-atom-sweep adjacent / MOSES content-addressed) would land as an architecture diagram much faster than 4 H4 sections.
**Undefined-on-first-use** (6): SWI-Prolog (referenced repeatedly as oracle), FAISS (FAISS vector similarity FFI — expanded inline), ATRIUM, RAPTL, ByteFlow / Tensor Logic / ShardZipper (all defined briefly but introduced cold), AttentionBank.

### Subcard: Status and Resources (ID 7155)

**Bracket leaks**: none.
**RawData links** (4): `RawData+Publications+Mork_theory`, `RawData+Publications+MORK_Tensor_Networks`, `RawData+Publications+MORK_slots`. Plus a Publication-Map link to `Publication_Maps+Mork_theory`.
**External URLs** (1 distinct, plus rendering bug): `arxiv.org/abs/2302.08775` (Peyton Jones et al. Triemaps that Match). Plus 1 ⚠️ STRUCTURAL — verify recurring pseudo-URL: `http://MorkDB.cc:268` rendered with **5-deep nested `<a>`** wrappers.
**Diagram opportunity**: skip; status sections are appropriately list/bullet driven, but the "Server-branch versioning" 3-references reconciliation (das-toolbox CLI tags vs Dockerfile commit vs origin/server HEAD) would clarify as a small versioning timeline.
**Undefined-on-first-use** (5): ATRIUM, ACT (compression metric, "780 GB JSON → 40 GB ACT"), CTL model checking, PDDL, das-toolbox.

---

<!-- INVENTORY-SLOT: DAS Full -->
## DAS Full

**Junction path**: `Knowledge Representations+DAS (Distributed AtomSpace)+DAS Full` (ID 4200, Draft — single-card not virtual; updated 2026-05-12)

### Card: DAS Full (ID 4200)

**Bracket leaks**: none in cluster-pilot vocab sense (tags like `[STRICT-FORK-STALE]` absent), but the prose carries the cluster-pilot lock-in in a quoted `<blockquote>` referring to "R4.L1" and "AtomSpace cluster pilot Source 4 reconciliation" — Anna would still find these labels confusing without context.
**RawData links**: none (only internal cross-links to other wiki cards).
**External URLs** (8 distinct): `github.com/singnet/das`, `github.com/singnet/das-metta-parser`, `github.com/singnet/das-toolbox`, `github.com/opencog/atomspace-storage`, `github.com/opencog/atomspace-rocks`, `github.com/opencog/atomspace-cog`. Plus **EXTREMELY heavy auto-link contamination** ⚠️ STRUCTURAL — verify: pseudo-URLs `http://MorkDB.cc` (10-deep nested anchors), `http://MorkDB.cc:268` (10-deep nested in 2 places, 5-deep elsewhere), `http://MorkDB.cc:197` (10-deep), `http://MorkDB.cc:150` (10-deep), `http://AtomDBSingleton.cc` (10-deep), `http://HebbianNetworkUpdater.cc:57` (10-deep), `http://StimulusSpreader.cc:54` (10-deep), `http://CLAUDE.md` (10-deep). This card is the worst single offender for the auto-linker bug seen across the inventory; ~6-8 separate filename-with-line-numbers wrapped 5-10 layers deep in `<a>` tags. It also matches Anna's flagged "atomdbsingleton.cc" example almost verbatim.
**Diagram opportunity**: yes — the four-layer AtomSpace taxonomy (DAS = Layer 3) plus the Query-Tree Execution model (Sources/Operators/Sinks as asynchronous units) plus the AttentionBroker Hebbian-network engineering-surrogate diagram would all replace heavy prose. The Lambda Architecture deployment topology (DAS components / GRPC vs MQTT vs in-RAM transport / multi-machine spread) is also a natural diagram.
**Undefined-on-first-use** (8): LTI/STI (defined inline but jargon), Hebbian (used heavily), HandleTrie, BOA (Bayesian Optimization Algorithm — expanded once parenthetically), OpenFaaS, GRPC/MQTT, CRDT, ProxyNode.

---

<!-- INVENTORY-SLOT: MetaMo Full -->
## MetaMo Full

**Junction path**: `Hyperon AI Algorithms+MetaMo (Motivational Framework)+MetaMo Full` (ID 4278, Draft — virtual junction; 3 RichText subcards)

### Subcard: Core Mechanisms and Formalism (ID 7135)

**Bracket leaks** (4): `[PAPER-LEANING-HYBRID]`, `[IMPLEMENTATION-BACKED-CORE]`, `[REFERENCE-IMPLEMENTATION-NOT-PRODUCTION]` in Implementation Backing intro; plus `[FORMAL-LAWS-PAPER-ONLY]` and `[SKELETON-IMPLEMENTATION]` (Principle 2 caveat).
**RawData links**: none (only internal cross-link to Status and Resources subcard).
**External URLs** (1 distinct, 11 ⚠️ SUSPICIOUS): `github.com/iCog-Labs-Dev/MetaMo-Python`. Plus 11 auto-linked Python filename pseudo-URLs ⚠️ SUSPICIOUS — verify: `http://state.py`, `http://config.py`, `http://functors.py` (×2), `http://appraisal.py`, `http://decision.py`, `http://bimonad.py` (×3), `http://stability.py` (×3), `http://coherence.py`, `http://assistant.py`, `http://AGENTS.md` — same pattern as NACE Full and AIRIS Full.
**Diagram opportunity**: yes — the pseudo-bimonad coupling (Appraisal comonad Ψ ↔ Decision monad D, joined by lax distributive law λ) and the 5 Design Principles loop would land much faster as a category-theoretic / control-loop diagram than the current LaTeX + bullet mix.
**Undefined-on-first-use** (5): comonad / monad / counit / unit / multiplication (assumed category-theory literacy), lax distributive law, MAGUS (cross-link only), homeostatic damping.

### Subcard: Historical Lineage (ID 7137)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs** (3): `github.com/iCog-Labs-Dev/MetaMo-Python`, `github.com/iCog-Labs-Dev/hyperon-openpsi`. Plus 1 ⚠️ SUSPICIOUS — verify: `http://decision.py` (filename pseudo-URL).
**Diagram opportunity**: yes — the lineage Dörner Psi → MicroPsi (Bach) → OpenPsi (Cai/Goertzel/Geisweiller 2011) → MAGUS (Mikeda 2024) → MetaMo (2025) would be a clean lineage diagram showing how MAGUS and OpenPsi feed into MetaMo's bimonad.
**Undefined-on-first-use** (5): MicroPsi (referenced once, expanded only as proper noun), Hebbian (cross-cutting term), MindAgent, AndLink, PredictiveImplication.

### Subcard: Status and Resources (ID 7139)

**Bracket leaks** (5): `[IMPLEMENTATION-BACKED-CORE]` and `[FORMAL-LAWS-PAPER-ONLY]` in MetaMo-Python row; `[HEURISTIC-PROTOTYPE]`, `[OPENPSI-PREDECESSOR-SUBSTRATE]`. Plus archive footer "V2-1..V2-7 carry-forwards locked."
**RawData links** (2): `RawData+Publications+AGI_25_METAMO_One`, `RawData+Publications+OpenPsi_Cognitive_Model`.
**External URLs** (4 distinct): `github.com/iCog-Labs-Dev/MetaMo-Python` (×2), `github.com/glicerico/MetaMo-Prototype`, `github.com/iCog-Labs-Dev/hyperon-openpsi`, `github.com/iCog-Labs-Dev/PeTTa-OpenPSI`. Plus 3 ⚠️ SUSPICIOUS — verify: `http://engine.py`, `http://assistant.py`, `http://AGENTS.md` (×2). NOTE: there is also a literal `<a class="file-link" href="file:line">file:line</a>` placeholder anchor in the rendered output — clear template/data drift, ⚠️ verify.
**Diagram opportunity**: yes — the trilateral classification (formal-reference / heuristic-prototype / OpenPsi-predecessor + Prolog variant) would benefit from a 4-quadrant comparison table or repo-relationship diagram showing HEAD SHAs and verdict tags.
**Undefined-on-first-use** (5): SubRep, MindAgent, NARS, A* (assumed), Thompson sampling.

---

<!-- INVENTORY-SLOT: ECAN Full -->
## ECAN Full

**Junction path**: `Hyperon AI Algorithms+ECAN (Economic Attention Networks)+ECAN Full` (ID 4282, Draft — virtual junction; 4 RichText subcards + 1 Pointer)

### Subcard: Core Mechanisms and Foundations (ID 7094)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none.
**Diagram opportunity**: yes — the Two-Currencies (STI/LTI) economic model with three diffusion modes (AF / WA / Fringe), plus the proposed fluid-dynamic continuity equation, would form a clean attention-economy + flow-field diagram.
**Undefined-on-first-use** (5): HJB (Hamilton-Jacobi-Bellman — defined inline), AF/WA (Attentional Focus / Whole-AtomSpace — expanded inline), AttentionalFocus, ImplicationLink, ListLink.

### Subcard: Development and Historical Context (ID 7100)

**Bracket leaks** (10+): `[REVIVED]`, `[ABANDONED]`, `[PARTIAL-FRAGMENTED-REVIVAL]` in DeSTIN-FISHGRAM section; `[FISHGRAM-CLEAN-BREAK]`; `[LEGACY-AUTHOR-BRIDGE]` and `[HYPERON-ERA-PARALLEL-RESEARCH-PORTFOLIO]`; `[LLM-MEDIATED-PERCEPTION]`, `[LLM-AS-KNOWLEDGE-SOURCE]`, `[LLM-AS-MEMORY-SUBSTRATE]`. Plus extensive "V4-1", "CF5.2", "Source 5 addendum (2026-05-01)" cluster-pilot references. This is the largest single concentration of bracket-label leaks in the inventory.
**RawData links**: none.
**External URLs** (5): `github.com/iCog-Labs-Dev/metta-attention`. Plus 9 ⚠️ SUSPICIOUS — verify pseudo-URLs from filename + line auto-linking, several with double-nested `<a>`: `http://SourceSet.cc:38` (3-deep), `http://RentCollectionBaseAgent.cc:76`, `http://AttentionBank.cc:142`, `http://HebbianUpdatingAgent.cc:74`, `http://StochasticImportanceDiffusion.cc:115`, `http://WARentCollectionAgent.cc:68`, `http://WAImportanceDiffusionAgent.cc:51`, `http://AFImportanceDiffusionAgent.cc:49`, `http://HebbianCreationAgent.cc:71`, `http://ImportanceIndex.cc:110`, `http://Fuzzy.cc:27` (3-deep), `http://Fuzzy.cc` (3-deep), `http://apiatomcollection.py:97` (3-deep), `http://mappers.py` (3-deep), `http://OllamaNode.cc:629` (3-deep), `http://run.sh` (3-deep), `http://README.md:217` (3-deep). The card is exceptionally heavy on filename:line cites which all became broken pseudo-URLs.
**Diagram opportunity**: yes, urgent — the 9-event "Reconstructed executable ECAN-coupling lifecycle" is begging to be a timeline graphic; the trilateral perception/symbolic/neural mining diagram is also natural; the AtomSpace-Scheme vs MeTTa-runtime two-stack split would help.
**Undefined-on-first-use** (8): URE (Unified Rule Engine — used heavily), AttentionBank, hyperpose, EMA (Exponential Moving Average — referenced via `recentVal.metta`), SPMiner, R-GCN, GNN-geometric, ROCCA.

### Subcard: System Interfaces and Implementation (ID 7096)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs** (2): `github.com/iCog-Labs-Dev/attention`, `github.com/iCog-Labs-Dev/metta-attention`.
**Diagram opportunity**: yes — the System Interfaces map (PLN / MOSES / DAS / MORK / MetaMo / WILLIAM all touching ECAN) plus the executable-coupling lifecycle decoupling story would clarify the "what is and isn't wired" narrative.
**Undefined-on-first-use** (4): URE, AttentionBank, hyperpose, Weighted Atom Sweeps.

### Subcard: Status and Resources (ID 7098)

**Bracket leaks**: none in pure tag form.
**RawData links**: none.
**External URLs** (2): `github.com/iCog-Labs-Dev/attention`, `github.com/iCog-Labs-Dev/metta-attention`.
**Diagram opportunity**: skip; status sections are appropriately list-driven.
**Undefined-on-first-use** (5): IIT Phi (Integrated Information Theory — referenced once in flight), HJB, In-Fluid-Net, AttentionBank, ShardZipper.

---

<!-- INVENTORY-SLOT: MeTTa Programming Language Full -->
## MeTTa Programming Language Full

**Junction path**: `MeTTa Programming Language+MeTTa Programming Language Full` (ID 4288, Published — virtual junction; 4 RichText subcards)

### Subcard: Core Mechanisms and Type System (ID 7157)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none.
**Diagram opportunity**: yes — the gradual-type / arrow-vs-tuple two-rule dispatch + the Pattern-Matching asymmetric-binding rules + the Empty/NotReducible/Error result-atom hierarchy together form a clean evaluator decision tree.
**Undefined-on-first-use** (5): EBNF, currying, dependent types (used as proper noun), homoiconicity (assumed), tokenizer / regex tokenizer pattern.

### Subcard: Formal Foundations and Operational Semantics (ID 7159)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none.
**Diagram opportunity**: yes — the four-register state `<i, k, w, o>` (extended to five-register `<i, k, w, o; eos>` for resource-bounded mode) with its 6 named rewrite rules (Query/Chain/Transform/AddAtom/RemAtom/Output) is begging to be a state-machine diagram. Plus the MeTTa → MeTTa-IL → Rholang compilation pipeline showing bisimulation arrows.
**Undefined-on-first-use** (8): MOPS, ρ-calculus / π-calculus (assumed), barbed bisimulation, GSLT, JAX, EOS / Effort Objects (defined inline), HE (Hyperon Experimental — abbreviated abruptly), `metta_call`.

### Subcard: Language Stack and Implementations (ID 7161)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs** (7): `github.com/trueagi-io/hyperon-experimental`, `github.com/patham9/PeTTa`, `github.com/trueagi-io/jetta`, `github.com/trueagi-io/metta-morph`, `github.com/F1R3FLY-io/MeTTa-Compiler`, `github.com/F1R3FLY-io/MeTTaIL`, `github.com/Adam-Vandervorst/FormalMeTTa`.
**Diagram opportunity**: yes — the 4-layer language stack (MeTTa → MeTTa-IL → MORKL/MM2 → backends), plus the 7-implementation table (HE / PeTTa / JeTTa / MeTTa-Morph / MeTTaTron / MeTTa-IL / FormalMeTTa) with target-runtime + status arrows would be a substantial improvement.
**Undefined-on-first-use** (5): GSLT, F1R3FLY, Tree-Sitter, Tokio, PkgInfo (vs Cargo.toml — explained inline but introduced cold).

### Subcard: Status and Resources (ID 7162)

**Bracket leaks**: none.
**RawData links** (2): `RawData+Publications+MeTTa_Specification`, `RawData+Publications+Meta_MeTTa_an_operational_semantics_for_MeTTa`.
**External URLs** (1 distinct, 1 ⚠️ SUSPICIOUS): `arxiv.org/abs/2305.17218`. Plus `http://crates.io` ⚠️ SUSPICIOUS — verify (likely intended as `https://crates.io/` but auto-linked from inline code; goes to a parked-domain or same as crates.io scheme mismatch).
**Diagram opportunity**: skip; status sections are list-driven.
**Undefined-on-first-use** (4): OSLF (referenced in Open Problems), llama.cpp, qsave_program, shift/reset (Prolog continuation primitives).

---

<!-- INVENTORY-SLOT: TransWeave Full -->
## TransWeave Full

**Junction path**: `Cognitive Architectures+PRIMUS (formerly CogPrime)+TransWeave+TransWeave Full` (ID 6295, Published — single-card not virtual; Human Approved by Ursula Addison 2026-05-08)

### Card: TransWeave Full (ID 6295)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none (only internal cross-links).
**Diagram opportunity**: yes — the Intertwining-Map commutative diagram (`update ∘ map ≈ map ∘ update`), the Yang-Baxter braid composition, and the H-ICA selective-transfer decision tree (transfer / fall-back / mark-for-relearning) are all natural diagrams. Currently expressed in LaTeX + bullets.
**Undefined-on-first-use** (5): H-ICA (defined inline as Hierarchical ICA), Yang-Baxter (introduced cold), commutator (mathematical sense, not Git), Schrödinger bridge (referenced obliquely via Geodesic Control), Merkle-DAG / CID.

---

<!-- INVENTORY-SLOT: WILLIAM Full -->
## WILLIAM Full

**Junction path**: `Cognitive Architectures+PRIMUS (formerly CogPrime)+WILLIAM+WILLIAM Full` (ID 6298, Published — single-card not virtual; Human Approved by Ursula Addison 2026-05-08)

### Card: WILLIAM Full (ID 6298)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none (only internal cross-links).
**Diagram opportunity**: yes — the trie-instrumentation table (occurrence counts / subtree totals / compression-gain sums / top-k rankings) plus the consumer integration table (PLN / Schedulers / ECAN / Pattern mining / Symbolic Heads) plus the 6-step PRIMUS cognitive cycle showing WILLIAM's slot would all benefit from diagrams. Compression-gain formula could also be an annotated picture.
**Undefined-on-first-use** (5): MDL (Minimum Description Length — alluded to but not defined), CoDD (Compositional Description of Data — defined inline), Kolmogorov complexity (assumed), RCU (Read-Copy-Update — defined inline parenthetically), beam search.

---

<!-- INVENTORY-SLOT: Self-Modification and Safety Full -->
## Self-Modification and Safety Full

**Junction path**: `About Hyperon+Self-Modification and Safety+Self-Modification and Safety Full` (ID 6301, Draft — single-card not virtual; updated 2026-05-12)

### Card: Self-Modification and Safety Full (ID 6301)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none (only internal cross-links).
**Diagram opportunity**: yes — the 5-stage pipeline (Proposal → Analysis → Simulation → Certification → Staged Deployment) plus the staged-deployment 3-mode rollout (Shadow → Dual-run → Elevation, with rollback at every stage) are begging to be process-flow + state-machine diagrams. The Worked Example (predictive-coding upgrade walking through all 5 stages) would also benefit from a swimlane diagram.
**Undefined-on-first-use** (8): metamorphism (mathematical sense, not biological), lens laws, supermartingale potentials (defined inline but heavy), Lyapunov function (referenced via "Lyapunov-like"), bisimulation metrics, ShardZipper, FireNode/F1R3FLY, SubRep / TransWeave (cross-link only).

---

<!-- INVENTORY-SLOT: Magi Full -->
## Magi Full

**Junction path**: `Ecosystem+Magi+Magi Full` (ID 7180, Published — virtual junction; 4 RichText subcards)

### Subcard: MAGUS Framework (ID 7182)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none (only internal cross-links).
**Diagram opportunity**: yes — the goal hierarchy (Primary / Subgoals / Metagoals / Anti-goals / Considerations & discouragements) plus the Overgoal feedback loop (measurability + correlation → demote/promote) would benefit from a clear hierarchy + control-loop diagram.
**Undefined-on-first-use** (4): Bach's 6-modulator framework / PAD emotion model (compressed — assumes prior context), MIC (correlation metric, used without expansion), Scoring v2 pipeline, GHOST (referenced as Sophia robot's GHOST system).

### Subcard: Tools and Assistants (ID 7184)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs** (1 ⚠️ SUSPICIOUS): `http://wiki.magi-agi.org` ⚠️ SUSPICIOUS — verify (real domain but auto-link rendered without `https://`; the wiki itself is the Magi Archive — likely fine as an http→https redirect, but the cardinality of the bare-http rendering is worth flagging).
**Diagram opportunity**: yes — the 5-tool MCP architecture (Magi Assistant GM + Discord + Foundry + Smart Glasses + Magi Archive MCP) with their data flows (Discord audio → STT → MCP, Foundry browser → WebSocket → MCP, etc.) is a natural system diagram.
**Undefined-on-first-use** (5): MCP (Model Context Protocol — defined inline parenthetically), Foundry VTT, VITURE Beast XR (specific brand), Tailscale VPN, Soundex / Metaphone (phonetic-matching algorithms).

### Subcard: Partnerships and Applications (ID 7186)

**Bracket leaks**: none.
**RawData links**: none.
**External URLs**: none (only internal cross-links).
**Diagram opportunity**: skip; the H4-section structure is appropriate.
**Undefined-on-first-use** (5): EARTHwise (referenced as joint venture, expanded inline), Elowyn, EAB (EARTHwise Alignment Benchmark — defined inline), Ollama, Neoterics (introduced parenthetically without context).

### Subcard: Status and Resources (ID 7187)

**Bracket leaks**: none.
**RawData links** (1): inline `RawData` link.
**External URLs** (3): `medium.com/singularitynet/neoterics-...`. Plus 2 ⚠️ SUSPICIOUS — verify: `http://wiki.magi-agi.org` and `http://mcp.magi-agi.org` — same bare-http auto-link rendering issue. These are real Magi-side hosts but should be `https://`.
**Diagram opportunity**: yes — the 6-phase 5-year roadmap (SingularityNET Integration → Social Agents → Ownership/Marketplace → AI GM → Distribution Platform → Non-Gaming) is begging for a horizontal timeline diagram. The Four Differentiators (Transparency / Consistency / Plasticity / Corrigibility) would also benefit from a 4-quadrant visual.
**Undefined-on-first-use** (4): MAGUS M2-M4 milestones (referenced without explanation of milestone numbering), STT (Speech-to-Text — assumed), Decko (the wiki platform — used without expansion), schema-first codegen.

---

<!-- INVENTORY-SLOT: Hyperon Experimental Full -->
## Hyperon Experimental Full

**Junction path**: `MeTTa Programming Language+Hyperon Experimental+Hyperon Experimental Full` (ID 7814, Draft — single-card not virtual; updated 2026-05-12)

### Card: Hyperon Experimental Full (ID 7814)

**Bracket leaks** (~25): `[SMALL-STEP-INTERPRETER]`, `[NONDETERMINISTIC-BRANCHING]`, `[DYNAMIC-CHECKED]`, `[HYBRID-RUST-PLUS-METTA-STDLIB]`, `[BUILTIN-FULLY-WIRED]`, `[MODULE-SYSTEM-PARTIAL]`, `[IN-MEMORY-ATOMTRIE-INDEX]`, `[NO-BENCHMARK-CLAIMS]`, `[PY-PARTIAL-WITH-GAPS]`, `[C-CORE-ONLY]`, `[TEST-COVERAGE-ADEQUATE]`, `[QUIRK-CONFIRMED-AT-HEAD]` (×2), `[QUIRK-FIXED-SINCE-V0-2-1]`, `[SANDBOX-PROTOTYPE]` (×5), `[SANDBOX-EXAMPLE-ONLY]`. This is THE highest concentration of bracket-label leaks per-card in the inventory — every architecture H4 section opens with one or more tags.
**RawData links**: none.
**External URLs** (1 distinct, plus 6 ⚠️ SUSPICIOUS): `github.com/trueagi-io/hyperon-experimental` (rendered with double-nested `<a>` ⚠️ STRUCTURAL — verify). Plus 6 auto-linked filename pseudo-URLs ⚠️ SUSPICIOUS — verify: `http://discussion.md`, `http://base.py:205` (×2), `http://base.py:168`, `http://runner.py:24`, `http://base.py:202`, `http://bus.py:6`, `http://numme.py`, `http://torchme.py`, `http://quirks.md`. Same recurring filename-as-URL bug.
**Diagram opportunity**: yes, urgent — the 7-crate Rust workspace structure (hyperon-common / hyperon-atom / hyperon-space / hyperon-macros / lib / c / repl), plus the Stdlib split (Rust-side modules vs MeTTa-side stdlib.metta), plus the Phase 4 PATCH-1 observer-pattern integration gap diagram, plus the Sandbox-Modules verdict table all beg for visualization. The interpreter stack (interpret_step → interpret_stack → eval_impl/query/chain/unify/superpose-bind/native call) would also be a clean state-machine diagram.
**Undefined-on-first-use** (8): cbindgen, pybind11 (used heavily), DynSpace, GroundingSpace, EventAgent / SpaceObserver / SpaceEvent (defined inline but introduced cold), MAGUS pin, "Path II / Path IV" (referenced in PATCH-1 strategy without defining the path enumeration), MeTTaLog (referenced in S5 cross-source forwards without context).
