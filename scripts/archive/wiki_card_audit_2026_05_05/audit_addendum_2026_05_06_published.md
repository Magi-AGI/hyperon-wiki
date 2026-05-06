# Audit Addendum — Published-card scan (2026-05-06)

**Trigger:** Discovery during Non-clustered HAA cluster pilot Source 1 (AIRIS) close that `Hyperon AI Algorithms+AIRIS` already existed as a Published card with `+content` shell — yesterday's audit had verdict `MISSING-CARD` for it. The original audit's CQL query filtered on `type: Draft` and `type: Markdown` only; Published cards (43 total) were never queried.

**Scope:** Re-ran `run_query {"type": "Published"}` against `wiki.hyperon.dev` 2026-05-06 17:14 UTC. Found 43 Published cards. This addendum reconciles those 43 against the original `audit_report.md` and corrects the load-bearing `MISSING-CARD` verdicts in §2.9 / §4.3.

**Headline corrections:**
- §4.3 missing-card list: **all 4 listed missing cards exist as Published parents.** AIRIS, NACE, AI-DSL, MOSES are NOT missing; the audit misidentified them due to the query bug.
- §2.9 (Non-clustered HAA cluster table): rows for these 4 should change from `MISSING-CARD` → `AUDITED-PARTIAL` (Published parent with `+content` shell present; cluster-pilot work is to audit/refine the `+content`, not create from scratch).
- 8 additional Published HAA-related cards missed entirely by the original audit, including the next-pilot anchor `Hyperon AI Algorithms+MetaMo` (Source 2).
- ~22 additional Published cards across MeTTa runtime / Cognitive Architectures / About Hyperon / ASI Chain Runtime Environment / Knowledge Representations namespaces — affects MeTTa runtime, PRIMUS, and Cross-org clusters' card counts.

---

## §1 Full Published-card inventory (43 cards)

### 1.1 Test / scaffolding (out of scope, but listed for completeness)

| Card | ID-via-name | Status |
|---|---|---|
| Test Card 6 | — | OUT-OF-SCOPE (test) |
| Test Card 7 | — | OUT-OF-SCOPE (test) |
| Test Card 9 | — | OUT-OF-SCOPE (test) |
| Test Card 10 | — | OUT-OF-SCOPE (test) |
| Test Card 11 | — | OUT-OF-SCOPE (test) |
| Human Authored Test Card | — | OUT-OF-SCOPE (test) |

### 1.2 Top-level navigation / TOC (Published parents)

These are the canonical top-level Published anchors; their actual content lives in `+content` shells. Already light-touch out-of-scope per audit_report §1, but missed-as-Published in the original query.

| Card | Cluster context |
|---|---|
| Hyperon AI Algorithms | Top-level TOC for HAA |
| About Hyperon | Top-level — already noted in audit_report §2.10 as Draft, BUT it is actually Published |
| Cognitive Architectures | Top-level — was queried as Draft only |
| Knowledge Representations | Top-level — was queried as Draft only |
| MeTTa Programming Language | Top-level — was queried as Draft only |
| ASI Chain Runtime Environment | Top-level cross-org — was queried as Draft only |

**Note:** the original audit had several of these listed as Draft because the wiki has parallel `+Foo Full` Draft subcards alongside Published parents. The original query found only the Drafts. Pattern: Published parent + Draft `+Foo Full` technical-depth subcard + Published `+content` shell.

### 1.3 HAA Published cards (relevant to Non-clustered HAA cluster pilot)

| Card | Audit verdict (CORRECTED) | Notes |
|---|---|---|
| Hyperon AI Algorithms+ECAN | PILOT-EDITED (via subcards 7096/7100/7098) | Published parent, ECAN cluster pilot edited the Full subcards. Was not visible in original Draft+Markdown query. |
| Hyperon AI Algorithms+PLN (Probabilistic Logic Networks) | PILOT-EDITED (via subcards 4184 etc.) | Published parent, PLN cluster pilot edited Full subcards + +AI proposal. |
| Hyperon AI Algorithms+AIRIS | PILOT-EDITED (today, 2026-05-06; +AIRIS Full 7495 + +AI 7497) | Today's S1 close. Was `MISSING-CARD` in audit_report §2.9 / §4.3 — INCORRECT. Now corrected. |
| Hyperon AI Algorithms+MetaMo | AUDITED-PARTIAL → next pilot S2 target | Published parent with `+content` shell. Has Draft `+MetaMo Full` subcard. The cluster-pilot S2 will audit `+content` and create +AI proposal child if needed. |
| Hyperon AI Algorithms+MOSES | AUDITED-PARTIAL → S5 target | Published parent + `+MOSES Full` Published subcard. Was `MISSING-CARD` in §4.3 — INCORRECT. The S5 cluster pilot will audit existing content, not create new. |
| Hyperon AI Algorithms+MOSES+MOSES Full | AUDITED-PARTIAL → S5 target | Published Full subcard (rare — most Full subcards are Draft). |
| Hyperon AI Algorithms+MeTTa-NARS | AUDITED-PARTIAL → S5 target | Published parent. Was implied missing in original audit table for non-clustered HAA. |
| Hyperon AI Algorithms+NACE | AUDITED-PARTIAL → S5 target | Published parent. Was `MISSING-CARD` in §4.3 — INCORRECT. |
| Hyperon AI Algorithms+AI-DSL | AUDITED-PARTIAL → S5 target | Published parent. Was `MISSING-CARD` in §4.3 — INCORRECT. |
| Hyperon AI Algorithms+Semantic Parsing | AUDITED-PARTIAL → S4 target | Published parent + Draft `+Semantic Parsing Full` subcard. |
| Hyperon AI Algorithms+MeTTa-Motto | AUDITED-PARTIAL — NEW DISCOVERY | Published. NOT in original audit at all. LLM agent integration library (`zarqa-ai/metta-motto` — already in Reference+GitHub Repositories). Belongs to non-clustered HAA cluster (or possibly MeTTa runtime/cross-cluster). |

**HAA-cluster impact:** of the 4 reviewer-promoted missing-card cluster outputs (AIRIS / NACE / AI-DSL / MOSES), all exist as Published parents. The non-clustered HAA cluster pilot's role is **audit + refine + +AI propose** the existing Published `+content` shells, NOT create cards from scratch. MetaMo (S2 next pilot) follows the same pattern.

### 1.4 Cognitive Architectures Published cards (relevant to PRIMUS cluster)

| Card | Audit verdict (CORRECTED) | Notes |
|---|---|---|
| Cognitive Architectures+PRIMUS | NOT-AUDITED → PRIMUS cluster | Published parent of the 5 +PRIMUS Full + sectioning subcards already in audit_report §2.8. |
| Cognitive Architectures+PRIMUS+Weakness Theory | NOT-AUDITED → PRIMUS cluster — NEW | Published subcard not in original audit. Likely PRIMUS subcomponent paper. |
| Cognitive Architectures+HyperClaw | NOT-AUDITED → PRIMUS or its own micro-cluster — NEW | Published. Not in original audit. "Claw" suggests Anthropic-Claude-related agent? Needs investigation in PRIMUS cluster pilot. |
| Cognitive Architectures+MeTTaClaw | NOT-AUDITED → PRIMUS or its own micro-cluster — NEW | Published. Same family as HyperClaw. |

**PRIMUS-cluster impact:** +1 Published parent + 3 new Published cards (Weakness Theory, HyperClaw, MeTTaClaw). Total PRIMUS cards now 24 (was 20 in audit_report §2.8).

### 1.5 About Hyperon Published cards

| Card | Audit verdict (CORRECTED) | Notes |
|---|---|---|
| About Hyperon+AtomSpace | PILOT-EDITED (via Full subcard 7115 etc.) | Published parent of the AtomSpace Full Draft I edited 2026-05-05. |
| About Hyperon+Self-Modification and Safety | NOT-AUDITED → non-clustered HAA boundary | Published parent of the Full Draft. |
| About Hyperon+Neural-Symbolic Integration | PILOT-EDITED (via SynerGAN edits) | Published parent. |
| About Hyperon+Cognitive Synergy | NOT-AUDITED — NEW | Published. Not in original audit. Foundational concept; likely PRIMUS/About-Hyperon cluster boundary. |
| About Hyperon+OpenCog Legacy | NOT-AUDITED — NEW | Published parent of OpenCog Legacy Full. Historical context; likely AtomSpace cluster spillover. |
| About Hyperon+OpenCog Legacy+OpenCog Legacy Full | NOT-AUDITED — NEW | Published Full subcard. |

### 1.6 Knowledge Representations Published cards

| Card | Audit verdict (CORRECTED) | Notes |
|---|---|---|
| Knowledge Representations+DAS | PILOT-EDITED (via DAS Full Draft 4200) | Published parent of DAS Full. |
| Knowledge Representations+MORK (MeTTa Optimized Reduction Kernel) | PILOT-EDITED (via MORK Full Draft 4194 + 7153/7155) | Published parent with the full long-form name. The `+MORK Full` Draft uses the short name `MORK` — explains the dual-name observation in the audit. |

### 1.7 MeTTa Programming Language Published cards (MeTTa runtime cluster)

| Card | Audit verdict (CORRECTED) | Notes |
|---|---|---|
| MeTTa Programming Language+Hyperon Experimental | NOT-AUDITED → MeTTa cluster — NEW | Published. Concrete trueagi-io/hyperon-experimental impl card. |
| MeTTa Programming Language+MeTTa-Morph | NOT-AUDITED → MeTTa cluster — NEW | Published. trueagi-io/metta-morph impl card. |
| MeTTa Programming Language+MeTTaLog (Legacy) | NOT-AUDITED → MeTTa cluster — NEW | Published. trueagi-io/metta-wam impl card. |
| MeTTa Programming Language+JeTTa | NOT-AUDITED → MeTTa cluster — NEW | Published. trueagi-io/jetta impl card. |
| MeTTa Programming Language+PeTTa | NOT-AUDITED → MeTTa cluster — NEW | Published. patham9/PeTTa impl card. (Note: PeTTa is referenced from many existing wiki cards but the dedicated card was NOT in original audit.) |
| MeTTa Programming Language+MeTTaTron | NOT-AUDITED → MeTTa cluster — NEW | Published. F1R3FLY-io/MeTTa-Compiler impl card. |

**MeTTa-cluster impact:** +1 Published parent + 6 new Published impl cards. Total MeTTa cards now 25 (was 18 in audit_report §2.6).

### 1.8 ASI Chain Runtime Environment Published cards (Cross-org cluster, asi-alliance subcluster)

| Card | Audit verdict (CORRECTED) | Notes |
|---|---|---|
| ASI Chain Runtime Environment | PILOT-EDITED (via Full Draft) | Published parent. |
| ASI Chain Runtime Environment+MeTTa-IL | NOT-AUDITED — NEW | Published. F1R3FLY-io/MeTTaIL impl card; bridges Cross-org (c) infrastructure to MeTTa cluster. |
| ASI Chain Runtime Environment+F1R3FLY | NOT-AUDITED — NEW | Published. F1R3FLY-io ecosystem; bridges Cross-org (c) to MeTTa cluster. |
| ASI Chain Runtime Environment+MeTTaCycle | NOT-AUDITED — NEW | Published. Not currently in Reference+GitHub Repositories. |

**Cross-org-cluster impact:** +3 new Published cards under ASI Chain. Total Cross-org cluster cards now 30 (was 26 in audit_report §2.7). The cross-org subcluster splits per Codex 2026-05-06 framing should now reflect these as Cross-org (c) infrastructure.

---

## §2 Audit-report verdict corrections

### §4.3 Missing wiki cards — REVISED

The original §4.3 list claimed 4 missing-card cluster outputs (AIRIS, NACE, AI-DSL, MOSES) plus HERMES candidate. **All 4 are now confirmed as existing Published parents.** Revised:

- ~~AIRIS — Cluster output for non-clustered HAA cluster~~ — EXISTS as Published parent (ID 801) with `+content` shell. PILOT-EDITED 2026-05-06 via +AIRIS Full Draft (7495) + +AI proposal child (7497). Cluster-pilot work was audit/refine, NOT create.
- ~~NACE~~ — EXISTS as Published parent. To be audited in S5.
- ~~AI-DSL~~ — EXISTS as Published parent. To be audited in S5.
- ~~MOSES~~ — EXISTS as Published parent + Published +MOSES Full subcard. To be audited in S5.
- HERMES — STILL MISSING from `wiki.hyperon.dev` (only on Magi Archive as card 741 `Hypergraph-RFP-Lakes`). Candidate for Cross-org (f) Magi or PRIMUS cluster output. Status unchanged.

**Replacement guidance for cluster outputs:** all 4 promoted "missing-card outputs" are actually `AUDITED-PARTIAL` Published parents whose `+content` shells need cluster-pilot review. The cluster-pilot's role for each is:
1. Audit the existing `+content` against extraction findings.
2. Create a `+Foo Full` Draft technical-depth subcard if not already present (AIRIS pattern).
3. Create a `+AI` Draft proposal child for any corrections to the `+content` (AIRIS pattern).
4. Update the +AI tag with `ai_generated`.

### §2.9 Non-clustered HAA cluster table — REVISED

Original §2.9 listed 5 existing cards + 4 explicit missing-card outputs. Revised count:

- 5 existing Draft cards (Concept Blending, Pattern Mining, MetaMo Full, Semantic Parsing Full, Self-Modification and Safety Full).
- 8 existing Published parents (AIRIS [PILOT-EDITED today], MetaMo, MOSES, MOSES Full, MeTTa-NARS, NACE, AI-DSL, Semantic Parsing) + MeTTa-Motto (newly discovered Published, possibly non-clustered HAA or MeTTa runtime boundary).
- 1 still-missing card (HERMES).

**Total non-clustered HAA cluster cards: 13 existing + 1 missing**, NOT "5 existing + 4 missing" as audit_report §2.9 claimed.

### §6.4 Summary numbers — REVISED

Original audit said: "PILOT-EDITED: 23 wiki cards directly edited by closed pilots."
Add 4 from today's AIRIS S1 close (+AIRIS Full, +AIRIS Full+tag, +AIRIS+AI, +AIRIS+AI+tag) + 1 corrective edit (Reference+GitHub Repositories) = **28 PILOT-EDITED**.

Original AUDITED-PARTIAL count was ~50; needs upward revision to ~60+ to include the 8 Published HAA parents + ~10 newly-discovered Published cards in PRIMUS / About Hyperon / MeTTa / ASI Chain namespaces.

NOT-AUDITED count goes UP slightly (newly-discovered Published cards in not-started clusters) but the structural change is:
- MISSING-CARD count goes from 4 → 1 (HERMES only).
- Total substantive wiki cards audited goes from ~150 → ~190+ (adding the 30+ Published cards not previously visible).

---

## §3 Methodology fix — query coverage

**Bug:** original audit query was `run_query {"type": "Draft"}` + `run_query {"type": "Markdown"}`. Published cards (which use `+content` shell pattern with the actual content in a separate RichText subcard) were entirely absent from the inventory.

**Fix:** all future audits MUST query all relevant cardtypes. For wiki.hyperon.dev:
- Draft (substantive content, AI-author authority)
- Published (canonical / human-reviewed; content lives in +content RichText subcard)
- Markdown (legacy stubs + Publications)
- RichText (content shells + sectioning subcards under Full pattern)

The RichText query was deferred in the original audit because the volume was 3,012 (mostly Decko system scaffolding) — a full RichText query is impractical. Better practice: query type:Published first to identify Published parents, then enumerate their +content children individually (each is a known small set of subcards via list_children).

**Carry-forward to future audits:** add this methodology fix as a memory file or feedback rule.

---

## §4 Implications for Source 2 (MetaMo) brief

Per Gemini's framing 2026-05-06: this audit re-run was a prerequisite for finalizing the S2 scope.

**MetaMo state:**
- Published parent `Hyperon AI Algorithms+MetaMo` exists with `+content` shell.
- Draft `Hyperon AI Algorithms+MetaMo+MetaMo Full` exists (from previous wiki authoring).
- The Source 2 cluster-close pattern will mirror AIRIS S1: audit existing `+content` against extraction findings, refine `+MetaMo Full` Draft if needed, create `+AI` Draft proposal child for `+content` corrections.

**This is the same pattern the wiki's HAA Published-parent + Draft-Full-subcard convention requires for ALL non-clustered HAA sources** (S2 MetaMo, S3 Pattern Mining residual, S4 Concept Blending + Semantic Parsing, S5 NACE + AI-DSL + MOSES + MeTTa-NARS).

The S2 brief should explicitly use this pattern from the start — no more "missing-card creation" framing.

---

## §5 Sign-off

This addendum supersedes audit_report.md §4.3 missing-card list and §2.9 row counts. Other audit_report sections remain valid. Recommend: add a one-line forward-pointer at the top of audit_report.md to this addendum so future readers see both.

Closed: 2026-05-06.
