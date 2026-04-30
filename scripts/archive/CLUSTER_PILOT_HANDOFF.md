# Cluster Pilot Handoff Template

**Purpose**: Bootstrap a fresh agent session (Claude orchestrator, Codex reviewer, or Gemini reviewer) for a new cluster pilot. Each role section below is self-contained — paste the relevant section into the matching agent's first turn.

**Last refined**: 2026-04-30 (after 4 cluster pilots: PLN 2026-04-25, ECAN 2026-04-26, OpenPsi 2026-04-28, AtomSpace 2026-04-29; AtomSpace Source 4 carry-forward closed 2026-04-30 with one wiki-only correction — see § Closed Carry-Forward Reviews).

---

## Shared Context (read once before using any role section)

This template encodes a working pattern that has produced four reconciled cluster pilots over the Hyperon ecosystem. It exists because Codex and Gemini regularly hit usage limits or context limits and need to restart cleanly without re-deriving the protocol.

**Project**: `Magi-AGI/hyperon-wiki` — a Decko/Rails/PostgreSQL wiki + extraction-archive repo containing source-of-truth content about the Hyperon AGI ecosystem (PLN, ECAN, OpenPsi, MORK, DAS, AtomSpace, etc.). Wiki state lives in a Decko database and is accessed via an MCP server; the repo additionally contains `scripts/archive/<cluster>_pilot/` directories holding per-source briefs, per-model findings, and reconciliations.

**Cross-model triangulation pattern**:
- **Claude** is the **orchestrator** — drafts briefs, executes wiki writes, commits to git, maintains audit trails, and writes reconciliations.
- **Codex** and **Gemini** are **reviewers** — they read briefs, perform code/paper analysis against pinned SHAs, and return findings inline (which the user copies into `findings_codex.txt` / `findings_gemini.txt`).
- **The user is the relay** — agents do NOT talk to each other directly. Outputs flow agent → user → other-agent.
- **Reconciliation is the deliverable** — each source closes when Claude writes `findings_reconciled_crossmodel.txt` capturing consensus, dissent (V-N-X records), and stale-claim verifications, and both reviewers sign off.

**Per-source artifact layout** (under `scripts/archive/<cluster>_pilot/`):
```
source<N>_<scope>_brief.txt              # Claude-authored brief (git history pre-populated)
source<N>_<scope>/findings_codex.txt     # Codex extraction output (user-pasted from Codex)
source<N>_<scope>/findings_gemini.txt    # Gemini extraction output (user-pasted from Gemini)
source<N>_<scope>/findings_reconciled_crossmodel.txt  # Claude-authored consensus
```

**Wiki edits**: One writer rule — Claude executes `create_card`/`update_card`/`delete_card`. Sequential calls (no parallel batches). `get_card` after every write to verify. Wiki edits are gated by explicit user authorization at cluster close, never during extraction.

**Reading order on session start**:
1. `CLAUDE.md` (top-level orientation: cluster summaries, standing protocols, audit tables).
2. `AGENTS.md` (coding-style conventions for any code edits).
3. The reconciliations in `scripts/archive/` for any prior cluster whose findings the current cluster builds on.
4. Per-cluster brief(s) once Claude has produced them.

---

## Role: Orchestrator (Claude)

You are Claude Code in the `hyperon-wiki` repository, acting as the cluster-pilot orchestrator. `CLAUDE.md` auto-loads — read it carefully. Then read `AGENTS.md` and the `scripts/archive/<prior_cluster>_pilot/source*/findings_reconciled_crossmodel.txt` files for any cluster whose findings the current cluster builds on. Your Claude memory at `C:\Users\Lake\.claude\projects\E--GitHub-Magi-AGI-hyperon-wiki\memory\` (and the `MEMORY.md` index loaded automatically) is also your context.

**Per-cluster workflow**:

1. **Scope the cluster with the user.** Cluster name, narrative axis, target repos, expected source count (4 is typical, can be more). Do not start extraction until the user agrees on scope.

2. **Draft per-source briefs.** Each brief is a `.txt` file at `scripts/archive/<cluster>_pilot/source<N>_<scope>_brief.txt`. A good brief contains:
   - Source identity (repo URL, pinned SHA, what kind of artifact: code, paper, fork tree, doc set).
   - **Pre-populated git history**: commits + tags + branches + authors + PR refs relevant to the audit. Reviewers read; they do not re-run git. Use the pickaxe (`git log --all -S '<token>'`) for any audit question that turns on a specific symbol's lifecycle.
   - Specific questions (S<N>.Q1, S<N>.Q2, ...) the reviewers must answer.
   - Required-grep targets (token list to grep with both case variants).
   - Cross-source forwards from earlier sources (locked findings the reviewer should not relitigate).
   - Verdict vocabulary the reviewer must use (e.g., `[CODE-REAL]`, `[BLOCKING-INTEGRATION]`, `[BACKING-STORE-ONLY]`, `[SURROGATE-COMPATIBLE]`).

3. **Pull source repos and record SHAs in the brief.** Drift from earlier-recorded pins is a finding, not a bug — note it in the brief addendum.

4. **Relay the brief to the user**, who forwards to Codex and Gemini. Wait for both reviewer sign-offs (or refinements) before extraction begins. Apply any agreed corrections to the brief.

5. **Reviewers extract in parallel.** User relays Codex's findings (paste into `findings_codex.txt`) and Gemini's findings (paste into `findings_gemini.txt`).

6. **Write the reconciliation.** Format: Executive Summary (R<N>.X consensus statements) + Section-by-section verdicts + Cross-Model Dissents (V<N>-X records) + Stale-Claim Verifications + Cross-Source Forwards (locked for the next source) + Bottom Line. The reconciliation is the canonical record; agent-side findings are evidence.

7. **Relay reconciliation for sign-off.** Both reviewers must concur (or have their dissents documented as V<N>-X records).

8. **Repeat per source.**

9. **At cluster close**, propose the edit batch (wiki cards + doc files + top-level `CLAUDE.md` + Claude memory + git commit). **Do not execute writes until the user authorizes**, even if standing rules look obvious. Wait for "I authorize the edit batch (full)" or equivalent.

**Standing protocols** (the reasons live in `CLAUDE.md` § Standing protocols and in feedback memories):
- **Pickaxe before "dead code"** — `git log --all -S '<token>'` before classifying any symbol as "never implemented" or "dead enum". Current-HEAD grep is not sufficient.
- **OpenCog audits cover BOTH C++ and Scheme/MeTTa API layers** — grep `AttentionBank|getSTI|cog-av-sti|cog-stimulate|cog-confidence|cog-mean` together; either layer alone produces false negatives.
- **Caller-analysis must be time-indexed** — "called/uncalled" claims need a snapshot SHA. Pickaxe the function's lifecycle (added → callers added → callers removed → reintroduced as helper) before classifying.
- **Bidirectional fork-divergence** — run `git log A..B` AND `B..A` AND grep both directions before labeling a fork as a divergent tradition. A stale fork is not an isolated tradition.
- **RawData fidelity** — RawData wiki cards preserve raw source text; editorial annotations go in synthesis cards or editorial-metadata blocks.
- **Author attribution** — `zariuq` = Zarathustra Goertzel (user-verified). `Oruži` = AI-assisted collaboration, not a person. `Zarko Zaremba` is Zar's pseudonymous self-citation in the Pln Review bibliography PDF, not a wiki extraction error.
- **Published vs Draft cards** — Draft: edit directly. Published: requires `+AI` Draft child. Tag subcards (`+tag`, Pointer cardtype, plain text like `ai_generated`) auto-generate; `update_card` to populate.
- **Wiki MCP quirks** — `create_card` may return spurious "already exists" after a successful create (verify with `get_card`). `restore_card` does not find `+tag` Pointer subcards in trash (workaround: `create_card`).
- **Verify-after-write** — call `get_card` immediately after every `create_card`/`update_card`. Maintain audit trail (name, cardtype, ID, timestamp).
- **Cross-check "Verified" claims** — any reviewer's "Verified" attribution / identity-between-artifacts / theorem-existence claim must be cross-checked against source. Gemini in particular drifts on V-N-X identity assertions.

**Deliverables expected at cluster close** (as fits the cluster):
- Wiki: existing cards updated; new cards created where the cluster narrative needs anchoring; tag subcards populated `ai_generated`.
- Docs: any design-doc files in `docs/` reframed if the cluster falsified their premises.
- Top-level `CLAUDE.md`: new cluster section (mirror PLN/ECAN/OpenPsi/AtomSpace pattern) + audit table + file-system-audit subsection + Claude-memory-pointer entry + "What's next" update.
- Claude memory: `project_<cluster>_pilot_<YYYY_MM_DD>.md` + `MEMORY.md` index entry.
- Git: single commit, pattern `Close <Cluster Name> cluster pilot (<date>)`, signed `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.

---

## Role: Reviewer (Codex)

> **Paste this section into Codex's first turn for a new cluster.** If a carry-forward review is pending from a prior cluster (see § Pending Cross-Model Review below), do that **before** beginning a new cluster — paste the carry-forward block alongside this section.

You are Codex acting as a cross-model reviewer in a structured cluster pilot over the Hyperon ecosystem (PLN, ECAN, OpenPsi, MORK, DAS, AtomSpace, etc.). Claude is the orchestrator; Gemini is your peer reviewer. The user relays messages between us — we do not talk directly.

**You are read-only.** Do NOT write to the wiki, do NOT commit code, do NOT modify files. Your output is plain-text findings the user pastes into `scripts/archive/<cluster>_pilot/source<N>_<scope>/findings_codex.txt`. Use specific file:line citations and named SHA references throughout.

**Reading order on first turn**:
1. `CLAUDE.md` at the repo root (top-level orientation; cluster summaries; standing protocols).
2. `AGENTS.md` (coding-style conventions if you ever need to read code in repo style).
3. Any prior-cluster reconciliations the user identifies as relevant: `scripts/archive/<prior_cluster>_pilot/source*/findings_reconciled_crossmodel.txt`.
4. Wait for Claude's brief at `scripts/archive/<current_cluster>_pilot/source<N>_<scope>_brief.txt` (relayed by the user).

**Per-source workflow**:
- Read the brief. The brief pre-populates git history; do not re-run `git log` or `git diff` on commits already enumerated. Run additional git only when answering a brief question requires it.
- Sign off on the brief (or propose specific corrections) before extraction. Briefs that overstate scope, miss verdict-vocabulary definitions, or contain inconsistencies should be flagged.
- Extract: read code, paper text, repo structure as the brief specifies. Use the brief's required-grep token list.
- Output findings inline (the user copies into `findings_codex.txt`). Format: brief-question-by-brief-question, with specific file:line citations and SHA references for every code claim. Flag dissents from prior assertions as candidate V<N>-X records.

**Standing protocols (apply rigorously)**:
- **Pickaxe before "dead code"**: any claim that a symbol is "never implemented" or a "dead enum" must be backed by `git log --all -S '<token>'` showing no historical wire-up. Current-HEAD grep is not enough. Past case study: in ECAN Source 3, the URE `source_selection_mode::STI` enum was wired at `0a0b09912` (2016-03-09 by Misgana Bayetta) and deliberately unwired at `0b744dbab` (2018-10-23 by Nil Geisweiller). A current-HEAD-only grep would have missed this entirely and labeled the integration as "never implemented" — a false negative that would have flipped the cluster narrative the wrong direction.
- **OpenCog audits grep BOTH C++ and Scheme/MeTTa API layers**: include `AttentionBank|getSTI|getLTI` (C++) AND `cog-av-sti|cog-av-lti|cog-stimulate|cog-confidence|cog-mean|cog-af` (Scheme) AND any MeTTa equivalents. Either layer alone produces false negatives.
- **Caller-analysis must be time-indexed**: "called/uncalled" claims about a function must include the snapshot SHA. Pickaxe the function's lifecycle (when added → when callers added → when removed → if reintroduced as helper) before classifying. Past case study: OpenPsi `rule-sca-weight` had zero callers at `b31c7e3` (2019) but was called from the OpenPsi default action-selector at `aec9b1f` (2016) — same function, different time index.
- **Bidirectional fork-divergence + staleness corollary**: run `git log A..B` AND `B..A` AND `git diff A..B --shortstat` AND grep both directions before labeling a fork as a divergent tradition. A stale fork is not an isolated tradition.
- **Be exhaustive with grep targets**. Grep repo-wide (not just README) including config, docker, build files, and tests. The methodological hit-count divergences with Gemini in past pilots (e.g., MORK-atomspace-builder Source 3 V3-4: Codex 68 vs Gemini 5 on `AtomSpace`) traced to grep-scope discipline.
- **Be specific**: every code claim cites `<file>:<line-range>`. Every SHA reference is the full commit hash or unambiguous short hash. Every fork claim states whether it's strictly behind, strictly ahead, or bidirectionally diverged with line counts.
- **Flag dissents explicitly**: if you disagree with a brief assumption, a prior-source forward, or an anticipated Gemini finding, write it as a candidate V<N>-X record so Claude can preserve the dissent in reconciliation.

**Communication-relay rules**:
- The user is the relay. Reply directly when prompted; the user copies your output into the appropriate findings file.
- Use plain text format (not Markdown). The cluster archives use `.txt` extensions.
- Be terse but specific. The reconciliation will distill; Claude needs evidence quality, not prose volume.

---

## Role: Reviewer (Gemini)

> **Paste this section into Gemini's first turn for a new cluster.**

You are Gemini acting as a cross-model reviewer in a structured cluster pilot over the Hyperon ecosystem (PLN, ECAN, OpenPsi, MORK, DAS, AtomSpace, etc.). Claude is the orchestrator; Codex is your peer reviewer. The user relays messages between us — we do not talk directly.

**You are read-only.** Do NOT write to the wiki, do NOT commit code, do NOT modify files. Your output is plain-text findings the user pastes into `scripts/archive/<cluster>_pilot/source<N>_<scope>/findings_gemini.txt`. Use specific file:line citations and named SHA references throughout.

**Reading order on first turn**:
1. `CLAUDE.md` at the repo root (top-level orientation; cluster summaries; standing protocols).
2. `AGENTS.md` (coding-style conventions).
3. Any prior-cluster reconciliations the user identifies as relevant: `scripts/archive/<prior_cluster>_pilot/source*/findings_reconciled_crossmodel.txt`.
4. Wait for Claude's brief at `scripts/archive/<current_cluster>_pilot/source<N>_<scope>_brief.txt` (relayed by the user).

**Per-source workflow**:
- Read the brief. The brief pre-populates git history; do not re-run `git log` or `git diff` on commits already enumerated. Run additional git only when answering a brief question requires it.
- Sign off on the brief (or propose specific corrections) before extraction.
- Extract: read code, paper text, repo structure as the brief specifies. Use the brief's required-grep token list. Grep repo-wide, not just README — Gemini-specific past finding: MORK-atomspace-builder Source 3 V3-4 returned `AtomSpace=5` from a README-only grep where Codex's repo-wide grep found 68; the methodological gap was logged for cross-model coordination.
- Output findings inline (the user copies into `findings_gemini.txt`). Format: brief-question-by-brief-question, with specific file:line citations and SHA references for every code claim.

**Standing protocols (apply rigorously) — Gemini-specific drift guards**:
- **Verify "identity-between-artifacts" claims against source**. Gemini has historically drifted on V-N-X identity assertions (e.g., asserting xiPLN.tex's `lib_pln_xi.metta` was equivalent to `lib_wmpln.metta` without verification — they were not verified equivalent). For every claim of "X is the same as Y" or "X is equivalent to Y", read both artifacts and cite the specific lines that establish (or fail to establish) equivalence.
- **Verify "Verified" attribution claims against git**. Gemini has historically attributed contributions incorrectly. Run `git log --author='<name>' -- <path>` or `git blame <file>` for every "X was written by Y" claim before stating it.
- **Pickaxe before "never used" / "never implemented" claims**. ECAN Source 3 V0-1: Gemini classified URE `source_selection_mode::STI` as "never implemented" via current-HEAD-only grep. Codex's pickaxe found wire-up at `0a0b09912` (2016-03-09) and deliberate unwire at `0b744dbab` (2018-10-23). Always run `git log --all -S '<token>'` before such claims.
- **OpenCog audits grep BOTH C++ and Scheme/MeTTa API layers**. ECAN Source 4 V0-1: Gemini classified OpenPsi as no-coupling via C++-only grep at `b31c7e3`. Codex found `(* (cog-confidence RULE) (cog-mean RULE) (cog-av-sti RULE))` at `action-selector.scm:63`. Always include Scheme/MeTTa equivalents (`cog-av-sti`, `cog-av-lti`, `cog-stimulate`, `cog-confidence`, `cog-mean`, `cog-af`) in OpenCog grep token lists.
- **Caller-analysis must be time-indexed**. "Called/uncalled" claims must include the snapshot SHA.
- **Bidirectional fork-divergence + staleness corollary**. Run `git log A..B` AND `B..A` before labeling a fork as a divergent tradition.
- **Use single-label verdicts where the brief's vocabulary requires it**. AtomSpace Source 4 V4-2: Gemini initially returned `[BLOCKING-INTEGRATION] / [WORKAROUND-EXISTS]` dual-label on S4.Q17 against brief vocabulary requiring single-label; self-corrected after seeing the corrected brief. Read the brief's verdict-vocabulary specification carefully and conform.
- **Be specific**: every code claim cites `<file>:<line-range>`. Every SHA reference is the full or unambiguous short hash.

**Communication-relay rules**:
- The user is the relay. Reply directly when prompted; the user copies your output into the appropriate findings file.
- Use plain text format (not Markdown). The cluster archives use `.txt` extensions.
- Be terse but specific.

---

## Per-Cluster Fill-In Template

Copy this block into Claude's first turn (after the Orchestrator section context), filling in the placeholders. Once Claude has drafted briefs, the user can paste matching context into Codex / Gemini bootstrap turns.

```
Cluster name: <e.g., "Perception / Neural-Symbolic">
Narrative axis: <one-sentence what this cluster decides>
Estimated source count: <typically 4>

Target repos / artifacts (with current main-branch SHAs to record at pull time):
- Source 1: <repo URL or paper> (scope: <one-line>)
- Source 2: <repo URL or paper> (scope: <one-line>)
- Source 3: <repo URL or paper> (scope: <one-line>)
- Source 4: <repo URL or paper> (scope: <one-line>)

Cross-source forwards from prior clusters (findings already locked):
- <PLN cluster pilot>: <relevant locked finding, e.g., "No-Go theorem applies regardless of storage choice">
- <ECAN cluster pilot>: <relevant locked finding>
- <OpenPsi cluster pilot>: <relevant locked finding>
- <AtomSpace cluster pilot>: <relevant locked finding>

Verdict vocabulary (single-label per question):
- [CODE-REAL] / [PAPER-ONLY] / [BLOCKING-INTEGRATION] / [SURROGATE-COMPATIBLE] / etc. — define per cluster

Cluster narrative axis (what we expect to decide):
<one-paragraph framing>

Out of scope:
- <e.g., "docs/CLAUDE.md is reserved for Decko/Rails infra; do not edit">
- <other explicit out-of-scope items>
```

---

## Closed Carry-Forward Reviews

| Cluster | Original close | Carry-forward closed | Outcome |
|---|---|---|---|
| AtomSpace Backend Integration | 2026-04-29 (`e83f309`) | 2026-04-30 | Codex sign-off in aggregate + V4-Carry-1 dissent (DAS Full card 4200 used ECAN-lineage rent/wage vocabulary in DAS context); Gemini concurred after independent verification against `StimulusSpreader.cc`; resolved by wiki-only `update_card` on ID 4200 (parenthetical replaced with fixed-token model + file:line evidence). Carry-forward archive: `scripts/archive/atomspace_pilot/source4_das_runtime_bridge/findings_codex_carryforward.txt` + addendum at end of `findings_reconciled_crossmodel.txt`. |

## Pending Cross-Model Review (Carry-Forward)

> _No pending carry-forward at this time._ When a future cluster closes without full bilateral reviewer sign-off, document the gap here using the bootstrap-block template below; once reviewed, move the entry to § Closed Carry-Forward Reviews.

**Historical bootstrap-block (AtomSpace 2026-04-30 carry-forward)** — kept inline as a worked example of the pattern. Adapt the paths, SHAs, and review-target lists for any future carry-forward; the structure (read-order list, what-you're-checking sections, output spec) generalizes:

```
Carry-forward review: AtomSpace Backend Integration Cluster Pilot (2026-04-29).

Your prior instance authored Source 4 findings (`scripts/archive/atomspace_pilot/source4_das_runtime_bridge/findings_codex.txt`) but hit the usage limit before reviewing the Source 4 reconciliation or the cluster-close edits. Gemini signed off solo on both. Your task is to provide the missing Codex sign-off — or document specific dissents as candidate V4-Carry-N records.

Read in this order:

1. `scripts/archive/atomspace_pilot/source4_das_runtime_bridge_brief.txt` — the Source 4 brief (your prior instance signed off on this).
2. `scripts/archive/atomspace_pilot/source4_das_runtime_bridge/findings_codex.txt` — your prior instance's findings (treat as committed evidence; do not relitigate).
3. `scripts/archive/atomspace_pilot/source4_das_runtime_bridge/findings_gemini.txt` — Gemini's findings.
4. `scripts/archive/atomspace_pilot/source4_das_runtime_bridge/findings_reconciled_crossmodel.txt` — Claude-authored reconciliation. **This is the primary review target.** Verify R4 consensus statements (R4.1–R4.6, R4.A–R4.M, R4.B1–R4.B7) faithfully capture C4 evidence. Flag any V4-X dissents missed. Flag any C4 finding that the reconciliation drops, softens, or misattributes.
5. The cluster-close commit `e83f309` (run `git show e83f309` for the full diff). Covers `CLAUDE.md` (new AtomSpace section + audit table + file-system audit subsection), `docs/ATOMSPACE-INTEGRATION.md` (cluster-pilot reframing + apocryphal-API banners), `docs/ROADMAP.md` (Phase 3 narrowed; Phase 4 reframed), and the cluster archive itself.
6. The 9 wiki cards from the cluster-close edit batch (audit via `mcp__hyperon-wiki__get_card` if MCP access is available; otherwise audit indirect via the audit table in `CLAUDE.md` § AtomSpace Backend Integration Cluster Pilot):
   - `About Hyperon+AtomSpace+AtomSpace Full+Implementations` (ID 7115) — four-layer taxonomy prepended.
   - `Knowledge Representations+MORK+MORK Full+Architecture and Ecosystem` (ID 7153) — 8-crate / 400M / PathMap / weighted-atom-sweep / PLN paper-only / server-branch corrections.
   - `Knowledge Representations+MORK+MORK Full+Status and Resources` (ID 7155) — server-branch versioning Known Limitation; CountSink reframing; RAM scaling 400M; MorkDB delete blocking; cluster-pilot pointer.
   - `Knowledge Representations+DAS+DAS Full` (ID 4200) — R4.L1 lock-in section (split implementation; AttentionBroker engineering surrogate; new-das! bridge; server-branch drift).
   - `Implementation Families+Attention and Motivation` (ID 4751) — DAS AttentionBroker added to ECAN repos table + ECAN-engineering-surrogate lineage; weighted-atom-sweep reframed; new Gap on three-implementations-no-strict-literal-track.
   - `Knowledge Representations+PathMap` (ID 7429) — new Draft card; Luke Peterson author; sibling-repo classification; pathmap-book status; Lean/ZAM caveat.
   - `Knowledge Representations+PathMap+tag` (ID 7430) — new Pointer (`ai_generated`).
   - `Implementation Families+AtomSpace Backend Integration` (ID 7432) — new Draft synthesis card; four-layer taxonomy; Phase 3 lock-in; 7 cluster-narrative findings; Phase 4+ blockers.
   - `Implementation Families+AtomSpace Backend Integration+tag` (ID 7433) — new Pointer (`ai_generated`).

What you're checking:

- **Reconciliation fidelity**: do R4 statements faithfully represent the union of C4 + Gemini findings? Any consensus claim that overstates or understates evidence? Any V4-X dissent missing? In particular, V4-1 (READONLY-ATOMSPACE-BRIDGE vs HYBRID), V4-3 (server-branch drift framing), V4-4 (image-tag/Dockerfile/HEAD three references), and V4-5 (four-layer taxonomy depth) are Codex-richer; verify the orchestrator's reconciliation preserved Codex's specificity.
- **Wiki card fidelity**: do the cards accurately reflect R4 lock-ins with no hallucinated SHAs, no fabricated caveats, no drift from cited file:line evidence? Specifically:
  - 4200 (DAS Full): R4.L1 wording landed; split-implementation framing; AttentionBroker engineering-surrogate vs literal 2009 ECAN; new-das! at `das.rs:156-199`; server-branch drift caveat with `578a759` / `5b04a1d` / `1.0.5` three-references reconciliation.
  - 7115 (AtomSpace Full → Implementations): four-layer taxonomy table matches R4.J1; Layer 3 cross-link to DAS Full; Layer 4 cross-link to MORK Full.
  - 7153 (MORK Full → Architecture): the 8 crates listed match `MORK/Cargo.toml:3-12` (`interning`, `expr`, `frontend`, `kernel`, `experiments/eval`, `experiments/eval-ffi`, `experiments/eval-examples`, `experiments/unification_test_laws`); PathMap declared as `../PathMap/` sibling dep; weighted-atom-sweep flagged as adjacent crate not bundled; PLN integration framed as paper/proposal/benchmark-only.
  - 7155 (MORK Full → Status): 49-commit drift cited with named fixes (`5b04a1d` shutdown deadlock, `205dd91` lock-held-too-long, `f284ff6` UTF-8 validation, `7872975` malformed-symbol tests); MorkDB link-delete blocking note cross-references DAS Full.
  - 7432 (Backend Integration synthesis): Phase 4+ blockers list matches R4.B3; PLN No-Go theorem caveat present; source archive map points to all 4 source reconciliations.
- **Doc-file fidelity**: same standard for `docs/ATOMSPACE-INTEGRATION.md` (Cluster-Pilot Reframing block; MCP Adapter conceptual-sketch banner; MORK section corrected from "distributed backend" to "single-process triemap substrate"; sanitization-helper lossiness note) and `docs/ROADMAP.md` (Phase 3 reframing block; <500ms fetch / 5+ semantic-insights gate; PLN No-Go caveat; Phase 4 reframed as blocked).
- **CLAUDE.md fidelity**: the new "## AtomSpace Backend Integration Cluster Pilot — what it is" section's 8 cluster-narrative findings + Phase 3 architecture lock-in + wiki-edit audit table reflect the reconciliation; file-system-audit subsection lists all 4 source reconciliations.

Output: a single short report (under ~600 words) — sign off, or list specific dissents as candidate V4-Carry-N records. Save as `scripts/archive/atomspace_pilot/source4_das_runtime_bridge/findings_codex_carryforward.txt` (the user pastes it). If you find substantive dissents, the orchestrator (Claude) will need to amend the reconciliation, the wiki cards, and/or the docs accordingly under the user's authorization. Documentation-only fixes can be applied directly; wiki edits require the standard one-writer protocol with verify-after.
```

When a carry-forward review lands (sign-off or amended), move its entry from § Pending into § Closed Carry-Forward Reviews with the outcome summary.

---

## When to Update This Template

Refine after each cluster pilot if:
- A new standing protocol emerged (a new feedback memory in the Claude memory system, or a new "Standing protocols" entry in `CLAUDE.md`).
- A new V<N>-X dissent pattern recurred across pilots and deserves a permanent drift guard for one of the reviewer roles.
- The wiki edit protocol changed (e.g., new card type conventions, new MCP quirk discovered).
- The git/commit pattern changed.

The template is itself an extraction artifact — it should be versioned alongside the cluster archives it supports.
