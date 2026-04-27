# CLAUDE.md — Hyperon Wiki Orchestration Anchor

This file is the **top-level orientation doc** for the Hyperon Wiki repository (Magi Archive infrastructure + cluster-pilot extraction artifacts). For Decko / Rails / PostgreSQL infrastructure guidance, see `docs/CLAUDE.md`. For coding-style conventions, see `AGENTS.md`.

This document captures the PLN cluster pilot findings (2026-04-08 through 2026-04-25) and the ECAN/Attention cluster pilot findings (2026-04-26) so future agents do not have to re-derive them from the per-cluster extraction archives.

---

## PLN Cluster Pilot — what it is

A multi-source content pass over the Hyperon-PLN cluster of repositories and papers. Cross-model triangulation (for this content pass, the user intends review by Claude + Codex + Gemini, with reconciliation across all three). 11 sources extracted; wiki edits applied in Phases 2-5.

Reconciliation files (one per source) live at `scripts/archive/pln_pilot/source*/findings_reconciled_crossmodel.txt`. Each captures cross-model consensus + dissent + source-of-truth checks. **PLN cluster pilot extraction is closed for this iteration; editorial/orientation cleanup remains.**

---

## Five-tradition cluster map

The PLN cluster is **not a single coherent codebase** — it has five distinct traditions that future agents must distinguish:

1. **Production Local-Rule PLN** — `PLN/`, `PLN3` (trueagi-io). Runnable / current reference implementation. pln0.9 rule surface (~14 rules) under a confidence-priority forward-chaining queue. Multiplicative-confidence pivot since Peter Isaev's commit `7ffce05` in `PLN/`.

2. **Historical OpenCog / URE / ECAN control** — URE Bayesian Thompson + MixtureModel inference control (now legacy); ECAN attention-currency. **Did not migrate** into production MeTTa PLN. Only ~5 of 16 URE control features survive in `chaining/` at toy scale. Future agents reading these older repos should expect richer historical control architectures that were lost in the OpenCog-to-Hyperon transition.
   - **iCog-Labs-Dev MeTTa ECAN sub-branch (Tradition 2 extension)**: `iCog-Labs-Dev/metta-attention` is the active MeTTa port of OpenCog Classic ECAN (`iCog-Labs-Dev/attention` C++). The 2026-04-26 ECAN cluster pilot established this is a sub-branch *extension* of Tradition 2 rather than a sixth tradition: the MeTTa port faithfully replicates the same pragmatic engineered surrogates (target-funds rent, fund-buffer wage, normalized-STI Hebbian, deterministic decay) that Classic C++ used in place of the 2009 paper's literal equations. Both score **0/4 strict-literal** compliance against the paper. Lead: Birhane Gulilat (iCog-Labs-Dev). Original C++ architects: Cosmo Harrigan (diffusion subsystem, 2014), Linas Vepstas (Classic ECAN lead).

3. **Adjacent ai-agents Python + Lean** — `zariuq/ai-agents` workspace, led by **Zarathustra Goertzel** (GitHub `zariuq`; user-confirmed identity). Contains:
   - `ai-agents/atps/scripts/` — Python premise selectors for theorem proving
   - `ai-agents/lean-projects/mettapedia/` — Lean 4 formalizations (xiPLN, World-Model Calculus, MORK-PathMap, Markov-de Finetti, PLN Review)

   This is the active formalization + benchmark workspace.

4. **CeTTa runtime-support / experimental implementation line** — `zariuq/CeTTa`. Contains `lib_pln.metta` (production-style mirror), `lib_wmpln*` (World-Model variants), and biomedical regression tests in `tests/support/bio_wmpln_*`. Runtime/implementation line; deployment status unverified.
   - **Important caveat**: `lib_wmpln.metta` is **not** verified identical to the cited `lib_pln_xi.metta`. Runtime equivalence remains open per xiPLN.tex's own §9 status note.

5. **MORK substrate + formalization** — Rust `MORK/` (Vandervorst/Clarke/Peterson) plus the adjacent Lean formalization in `mork-mm2-pathmap-formalization.tex` (Zar + Oruži). The Lean ZAM (Zipper Abstract Machine) soundness theorems exist alongside Rust MORK but are **not** wired into Rust production. **FactorGraph PLN over MORK remains paper / proposal / benchmark-only** — substrate is implementable, but the message-passing engine that would actually use MORK as a FactorGraph runtime is not built.

---

## Two-paradigm framing

The PLN cluster has **two coexisting paradigms**:

**Paradigm 1: Local-Rule PLN (production)** — runnable / current reference implementation, formally known to be incomplete. Tradition 1 in the map above.

**Paradigm 2: World-Model PLN (Lean-formal)** — theorem-level, runtime closure pending. Traditions 3 + 4 jointly. Articulated in xiPLN (architectural manifesto) and World-Model Calculus (systematic theory paper).

The architectural justification for Paradigm 2 is the **No-Go theorem** (xiPLN §5; Lean-proven in `Mettapedia/Logic/PLNJointEvidenceNoGo.lean`):

```
Theorem (No local complete deduction rule):
  There is no function f : Evidence^5 -> Evidence
  that, for all joint evidence states E, computes the
  exact link evidence for A => C from only the local
  premises Evidence(A), Evidence(B), Evidence(C),
  Evidence(A => B), Evidence(B => C).
```

This is the cluster's deepest formal result — local-rule PLN cannot be globally complete without joint-state information. Future agents working on PLN inference control should cite this when justifying world-model approaches.

---

## Wiki-edit audit (PLN cluster pilot, 2026-04-25)

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

## ECAN / Attention Cluster Pilot — what it is

A four-source content pass over the ECAN/Attention cluster (2026-04-26), executed under the same cross-model triangulation protocol established by the PLN pilot (Claude orchestrator + Codex + Gemini reviewers, with reconciliation across all three). Per-source briefs, per-model findings, and cross-model reconciliations live at `scripts/archive/ecan_pilot/source*/`. **ECAN cluster pilot extraction is closed for this iteration; editorial/orientation cleanup remains.**

### Cluster-narrative-deciding findings

1. **0/4 strict-literal compliance against the 2009 ECAN paper, in BOTH Classic C++ and MeTTa port.** Rent, wages, Hebbian update, and stochastic-diffusion equations are all replaced by pragmatic engineered surrogates (target-funds rent, fund-buffer wage, normalized-STI fuzzy-conjunction Hebbian, deterministic elapsed-time decay in place of the literal `tanh` sigmoid). The MeTTa port faithfully ports those surrogates from C++ — it did not regress paper equations; Classic C++ had already moved away from them.

2. **Executable PLN-attention coupling existed historically and was deliberately removed in late OpenCog Classic.** The 2014 Harrigan et al. paper "Guiding Probabilistic Logical Inference with Nonlinear Dynamical Attention Allocation" described ECAN as a control layer for PLN. The only realized executable hook in OpenCog history was a narrow URE forward-chainer STI source-selection mechanism: wired by Misgana Bayetta in commit `0a0b09912` (2016-03-09), unwired by Nil Geisweiller in commit `0b744dbab` (2018-10-23) with the comment "An attentionbank is needed in order to get the STI...", finalized in `5a5b7785d`. **This is a late-OpenCog Classic deliberate decoupling, not a Hyperon-era regression.** Current MeTTa-PLN has no attention-layer integration.

3. **Broader-OpenCog ECAN consumers existed at the pre-split monorepo snapshot but none survived as functioning ECAN integrations.** Verified consumers at `b31c7e3b9beab7a458c84117f3b654a03ca9ffe2` (the last commit before the 2019-09-06 AttentionBank removal `318c0b4cb`): OpenPsi action-selection via Scheme `cog-av-sti` rule weighting (`action-selector.scm:63`); Ghost dialogue using STI/AttentionalFocus in matcher and schemas; NLP fuzzy matching gated AF-only via `bank->atom_is_in_AF`; Python web API surfacing AttentionValue. None preserved as functioning integrations across the AttentionBank removal; no documented MeTTa equivalents in the current Hyperon ecosystem.

### Wiki-edit audit (ECAN cluster pilot, 2026-04-26)

| Phase | Card | ID | Action |
|---|---|---|---|
| 1 | Hyperon AI Algorithms+ECAN+ECAN Full+Development and Historical Context | 7100 | RichText subcard — appended Cluster-Pilot Findings section |
| 1 | Hyperon AI Algorithms+ECAN+ECAN Full+System Interfaces and Implementation | 7096 | RichText subcard — refined PLN bullet (3 SHAs) + metta-attention 0/4 strict-literal note + stochastic naming clarification |
| 1 | Hyperon AI Algorithms+ECAN+ECAN Full+Status and Resources | 7098 | RichText subcard — stochastic naming, 2 new Open Problems, cluster-pilot archive reference |
| 2 | Publications+Economic Attention Networks | 3063 | Markdown stub — refined PLN-control framing with Source 3 V0-1 timeline + 3 SHAs + 0/4 strict-literal note |
| 2 | Publications+Guiding PLN with Attention Allocation | 3057 | Markdown stub upgrade — Cosmo Harrigan cross-source identity, executable-realization timeline with 3 SHAs + verbatim 2018 unwiring comment, Hyperon 2026 status |
| 3 | Implementation Families+Attention and Motivation | 4751 | Draft — Attention-lineage 0/4 strict-literal note + 4 new Gaps and Consolidation Opportunities (incl. Hardcoding-vs-Dormancy split per Gemini's distinction) |
| 4 | Hyperon AI Algorithms+ECAN+AI | 7419 | Draft `+AI` proposal child for Published parent (cluster-pilot consolidated findings) |
| 4 | Hyperon AI Algorithms+ECAN+AI+tag | 7420 | Pointer (`ai_generated`) |

Total: 8 cards touched. All verified post-write via `get_card`.

## File-system audit (extraction archive)

### PLN cluster pilot

`scripts/archive/pln_pilot/` contains the per-source brief + per-model findings + cross-model reconciliation for sources 1-11. Each source corresponds to a major code/paper artifact in the cluster:

- Source 1: PLN book (Goertzel et al., Springer)
- Source 2: PLN3 modular MeTTa fork
- Source 3: PLN/ production code
- Source 4: pln-experimental2
- Source 5: hyperon-pln (lineage of leungmanhin's 2023 0.2 MP hack)
- Source 6: URE C++ legacy
- Source 7: chaining (URE successor)
- Source 8: MORK Rust
- Source 9: 13-paper bundle (FactorGraph MORK series + confidence/control papers)
- Source 10: ai-agents + CeTTa adjacent-tree reality check
- Source 11: full-text upgrades + late-breaking formalizations (xiPLN, WM Calculus, MORK-PathMap, Markov-de Finetti)

Source 11 reconciliation is the canonical synthesis. Sources 1-10 reconciliations are referenced from there.

### ECAN cluster pilot

`scripts/archive/ecan_pilot/` contains the per-source brief + per-model findings + cross-model reconciliation for sources 1-4:

- Source 1: `iCog-Labs-Dev/metta-attention` @ `67cd525` (current MeTTa ECAN port)
- Source 2: `iCog-Labs-Dev/attention` @ `e8162a5` (canonical OpenCog Classic ECAN C++)
- Source 3: `opencog/ure` @ `cec5509` + `opencog/pln` @ `a0983ad` (legacy URE + legacy C++ PLN paired audit)
- Source 4: `singnet/opencog` fork of pre-split monorepo @ `b31c7e3` (last commit before 2019-09-06 AttentionBank removal)

Source 4 V0-1 reconciliation (OpenPsi coupling) is the canonical disambiguator for whether broader-OpenCog ECAN consumers existed; Source 3 V0-1 reconciliation (URE STI source-selection lifecycle) is the canonical disambiguator for the historical-vs-Hyperon-era framing of executable PLN-attention coupling.

## Source-text gaps remaining

- **2013 FISHGRAM paper** (Goertzel et al., "Integrating Deep Learning Based Perception with Probabilistic Logic via Frequent Pattern Mining") — full text not yet retrieved. `Publications+Deep Learning Perception with PLN` Markdown stub still needs upgrade from a separate source.
- **`hyperon/PeTTa/lib/lib_pln_xi.metta`** — cited by xiPLN.tex but not located in any local clone. Either uncommitted local work, in a separate `zariuq/PeTTa` repo we haven't found, or never written.

---

## Standing protocols (operational rules)

These rules emerged during the cluster pilot and apply to subsequent wiki/code edit sessions:

### Cross-model triangulation
- For this content pass, the user intends cross-model review by Claude + Codex + Gemini, with reconciliation across all three.
- Apply standing rule: any "Verified" claim from any model (attribution, identity-between-artifacts, theorem existence) must be cross-checked against the source. Gemini in particular drifts on V-N-X identity assertions.

### Wiki edit protocol
- **One writer only**: the orchestrating model executes `create_card` / `update_card` / `delete_card`. Advisory models do not write wiki state.
- **Sequential calls, no parallel batches** for wiki writes.
- **Verify after every write**: `get_card` immediately after `create_card` / `update_card` to confirm the change landed.
- **Maintain an audit trail**: name, cardtype, returned result, verified ID, timestamp for each write.
- **Treat "already exists" as real** initially — verify with `get_card` and `get_card_history` before deciding next action. (See the post-create spurious-error pattern noted below.)

### RawData fidelity
- RawData wiki cards preserve raw source text; do not modify to "fix" what the source paper says.
- Editorial annotations (e.g., pseudonym clarifications) go in synthesis-layer cards or editorial-metadata blocks — not in the raw source body.
- See V0-4 in `scripts/archive/pln_pilot/source10_atps_cetta/findings_reconciled_crossmodel.txt` for the "Zarko Zaremba" pseudonym case study.

### Author attribution
- `zariuq` = **Zarathustra Goertzel** (Zar). User-verified identity.
- "Oruži" denotes AI-assisted collaboration (Claude Code / Codex / ChatGPT, varies by paper). Not a person.
- "Zarko Zaremba" appears as a pseudonymous self-citation in the Pln Review bibliography only; this is in the source PDF itself, not a wiki extraction error.
- Wm Pln Book V3 = Zarathustra Goertzel + Oruži.

### Published vs Draft card edits
- Draft cardtype: edit directly via `update_card`.
- Published cardtype: requires `+AI` Draft child for proposed diffs.
- Tag subcards use canonical `<parent>+tag` (Pointer cardtype, plain text content like `ai_generated`). Trailing-s plurals are aliased by the wiki — `+tag` and `+tags` resolve to the same card.
- Draft parents auto-generate empty `+tag` subcards; use `update_card` to populate, not `create_card`.

### Wiki MCP operational quirks
- `create_card` can return a spurious "already exists" validation error after a successful create. Always verify with `get_card`.
- `restore_card` does not find `+tag` Pointer subcards in trash even when `list_trash` shows them. Workaround: use `create_card` (which succeeds despite the spurious error). Both bugs filed via `submit_feedback` 2026-04-25.

### Pickaxe before "dead code" or "never implemented" claims
- A token absent from current HEAD does not mean it was never implemented. Always run `git log --all -S '<token>'` (the pickaxe) before classifying code as "dead enum" or "architected but never wired".
- Source 3 V0-1 case study: Gemini classified URE `source_selection_mode::STI` as "never implemented" via current-HEAD-only grep. Codex's pickaxe found wire-up at `0a0b09912` (2016-03-09) and deliberate unwire at `0b744dbab` (2018-10-23). Orchestrator `git show` on the three commits verified the integration was real and was deliberately removed. The dissent flipped the cluster narrative from "Hyperon regression" to "late-OpenCog Classic deliberate decoupling".

### OpenCog audits must cover BOTH C++ and Scheme/MeTTa API layers
- A token list of just C++ symbols (`AttentionBank | AttentionValue | get_sti | get_lti`) misses Scheme-side consumers. Always include the Scheme/MeTTa equivalents (`cog-av-sti`, `cog-av-lti`, `cog-stimulate`, `cog-confidence`, `cog-mean`, etc.) when grepping legacy OpenCog for API consumption.
- Source 4 V0-1 case study: Gemini classified OpenPsi as NO-COUPLING via C++-only grep at `b31c7e3`. Codex found `(* (cog-confidence RULE) (cog-mean RULE) (cog-av-sti RULE))` at `action-selector.scm:63` — a real STI consumer. Verified directly. The C++/Scheme dual-layer rule is mandatory for any legacy-OpenCog audit.

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
- `reference_wiki_mcp_quirks.md` — wiki MCP operational quirks
- `project_repo_orientation_docs.md` — orientation-doc workflow
- `project_wiki_quality_bar.md` — Ben Goertzel approval bar

For multi-model continuity, the canonical record lives in this repo at `scripts/archive/pln_pilot/` and `scripts/archive/ecan_pilot/` (extraction archives) and in the wiki itself (cards listed in the audit tables above).

---

## What's next (post-pilot work)

The PLN cluster pilot extraction is closed; editorial cleanup is in progress. The ECAN/Attention cluster pilot extraction is also closed (2026-04-26). Other clusters remain (each its own multi-source pilot):

- Perception / Neural-Symbolic (incl. 2013 FISHGRAM retrieval)
- MeTTa runtime (`hyperon-experimental`, `MeTTa-IL`, `PeTTa`, MORK production angle)
- Hyperon DAS / atomspace
- OpenPsi / motivation (note: ECAN pilot Source 4 already established that pre-2019 OpenPsi consumed `cog-av-sti`; the OpenPsi cluster will need its own Tradition-2-extension treatment)
- Cross-org sweeps (asi-alliance, fetchai, F1R3FLY-io, Rejuve, hansonrobotics, Xcceleran-do, gitlab.com/nunet)
