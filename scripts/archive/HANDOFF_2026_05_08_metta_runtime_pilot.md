# Session Handoff — MeTTa runtime cluster pilot (next-up after HAA close)

**Written:** 2026-05-08 by orchestrator-Claude, end-of-session before MeTTa runtime cluster pilot kickoff.
**For:** the next Claude orchestrator session that will dispatch the MeTTa runtime cluster pilot.
**You will be:** an Opus 4.7 (1M context) Claude Code instance in this same project working directory.

---

## §0. Where things stand at handoff

The Non-clustered Hyperon AI Algorithms cluster pilot was fully closed 2026-05-07 in commit `815194a` ("Close Non-clustered HAA cluster pilot Sources 4 + 5 — full cluster complete"). That brings the total to **seven cluster pilots closed** in the current iteration:

| Cluster | Closed | Sources |
|---|---|---|
| PLN | 2026-04-25 | 11 |
| ECAN / Attention | 2026-04-26 | 4 |
| OpenPsi / Motivation | 2026-04-28 | 4 |
| AtomSpace Backend Integration | 2026-04-29 | 4 |
| Perception / Neural-Symbolic | 2026-05-01 | 5 |
| AtomSpace Integration Phase 4 | 2026-05-05 | 7 (research-track) |
| Non-clustered HAA | 2026-05-07 | 5 (S1+S2+S3+S4+S5) |

**Your task**: dispatch the **MeTTa runtime cluster pilot** — next-in-line per Option A (backlog burn-down) ordering authorized by user 2026-05-05. After MeTTa, the remaining pilots are Cross-org sweeps (likely subcluster splits) and a Phase 5+/6+ design pass.

---

## §1. Critical methodology change you MUST internalize before dispatching

A new standing protocol was promoted at HAA cluster pilot close 2026-05-07. **Read this memory file before your first reviewer dispatch**:

```
C:\Users\Lake\.claude\projects\E--GitHub-Magi-AGI-hyperon-wiki\memory\feedback_gemini_pre_verification_protocol.md
```

**Summary**: cumulative Gemini drift across the seven cluster pilots reached ~65% by HAA S5 close, crossing the 60% escalation threshold flagged at HAA S3. User chose option (ii) over option (i) (Codex-only-primary): keep Gemini in the trilateral methodology BUT shift cite-verification work entirely to the orchestrator at extraction-return time, not reconciliation time.

**What you (the orchestrator) must do** when `findings_gemini.txt` arrives, BEFORE composing `findings_reconciled_crossmodel.txt`:

Run a verification pass over every Gemini cite. Four cite classes:

1. **File-path cites** — confirm existence at the cited HEAD via `git ls-tree HEAD --name-only` or `git show HEAD:<path>`. Reject confabulations immediately. (HAA S5 examples of confabulation: `NACE/src/main.cpp` and `ai-dsl/src/Composition.idr` — neither directory exists.)
2. **Line-number cites** — `git show HEAD:<file> | sed -n '<n>p'` for every `file:line` cite. Off-by-±5 = soft confabulation (flag in dissent table); larger mismatches = rejection.
3. **Numerical cites** (fork-divergence counts, line counts, byte counts, commit counts) — re-run the cited command in a fresh shell. For fork divergence: `cd <repo> && git fetch <upstream-url> <branch> && git rev-list --left-right --count HEAD...FETCH_HEAD`. Compare verbatim. Any mismatch >1 cosmetic = load-bearing rejection.
4. **"Implemented via X" / "X reduces to Y" / "consolidated into Z" interpretation cites** — independent grep run by orchestrator; reject if zero hits in claimed location. (HAA S5 example of confabulation: Paraconsistent_Interference_Blending "implemented via the interference logic in `a_categorytheoretic_approach/`" — `git grep -i 'paraconsistent|interference'` returned 0 hits across the directory; REJECTED.)

**Output**: a "Gemini cite-verification log" appended to each reconciliation document. Per-cite pass/reject status. Makes the discipline auditable rather than ambient.

**What stays Gemini-valued and is NOT subject to cite verification**: high-level synthesis claims that don't depend on file:line evidence — trilateral framing, cross-cluster boundary articulation, narrative-guard formulation, paradigm disambiguation. These are where Gemini contributes uniquely; cite-verification doesn't apply because there's no cite to verify.

**Re-evaluation gate**: if cumulative Gemini drift crosses **75%** by MeTTa runtime cluster pilot's Source 2 close, methodology escalates to Codex's option (i) — Codex-only primary, Gemini relegated to high-level conceptual mapping or counter-dissent only, not as an equal citation source. 65% is the warning; 75% would mean (ii) isn't arresting the trend.

Both reviewers signed off on (ii) at HAA close (2026-05-07):
- **Codex** committed to citation-grade evidence (file paths, file:line, raw numerical command output, no inference disguised as source fact). Status: composed and ready.
- **Gemini** committed to the four-class verification discipline operationally (using ls/git ls-tree before every citation; sed/restricted read_file ranges for line numbers; raw shell output for counts; specific grep evidence for "implemented via" claims). Status: at 65% drift but committed; MeTTa pilot is the test.

---

## §2. Standing protocols carry-forward (all in force)

Read these memory files before extraction begins (not all need fresh re-reading every cluster, but be aware they apply):

- `feedback_published_card_edits.md` — Draft cards editable directly; Published cards need +AI Draft proposal children for substantive edits.
- `feedback_attribution_verify_against_git.md` — cross-model verification rule.
- `feedback_parallel_extraction.md` — three-way triangulation pattern (Codex + Gemini + orchestrator-Claude).
- `feedback_pickaxe_for_dead_code.md` — `git log --all -S '<token>'` before any "never used" / "dead code" claim.
- `feedback_bidirectional_fork_divergence.md` — bidirectional `git rev-list --left-right --count` before labeling fork as divergent tradition.
- `feedback_sandra_spec_port_recheck_before_batch.md` — when parallel session has Sandra-spec ported a Published parent between cluster-pilot reconciliation lock-in and orchestrator's wiki-write window, HALT and re-read all targets fresh. Path-prefix shifts to renamed parent. Discovered HAA S2 close 2026-05-06; further reinforced HAA S5 close 2026-05-07 where the parallel agent was actively Sandra-spec-porting MOSES + NACE + MeTTa-NARS Published parents during the orchestrator's edit window.
- `feedback_webfetch_verify_external_urls.md` — wiki edits referencing external URLs MUST include fresh WebFetch verification immediately before the edit.
- `feedback_query_all_cardtypes_in_audits.md` — wiki audits must query Draft + Markdown + Published (not just Draft+Markdown).
- `feedback_research_vs_implementation_workstreams.md` — research and implementation are separate parallel workstreams; do not collapse one into the other without owner authorization.
- `feedback_parallel_claude_handoff.md` — Two Claude sessions in same project share memory + compaction framing → identical drift. Session start: ask if another Claude is on this project; get explicit scope split BEFORE tool calls.
- `feedback_gemini_has_wiki_mcp_write_access.md` — Gemini interpretation of "go" as authorization to write has happened before; be explicit "review only — DO NOT write" when relaying.
- `feedback_gemini_file_identity_verification.md` — CF5.6 cluster-pilot default; verify Gemini source-location claims via direct filesystem before reconciliation. **Now strengthened by `feedback_gemini_pre_verification_protocol.md` to apply systematically to ALL Gemini cites, not just suspicious ones.**

Plus the wiki-edit semantics protocols documented in `CLAUDE.md` § "Wiki-edit semantics (this repo's protocols)":
- One writer only (orchestrator executes wiki writes; advisory models do not).
- Sequential calls, no parallel batches for wiki writes.
- Verify after every write via `get_card`.
- RawData fidelity (don't modify raw source text to "fix" what the source paper says).
- Author attribution conventions (zariuq = Zarathustra Goertzel; "Oruži" = AI-collaboration; "Zarko Zaremba" = pseudonymous self-citation, not a wiki error).

---

## §3. MeTTa runtime cluster pilot — scoping notes

This section is **scoping suggestion, not locked brief** — you (the next-session orchestrator) should refine in dialogue with the user before committing to source structure.

**In scope**:
- `trueagi-io/hyperon-experimental` — official Rust reference implementation (v0.2.10 stable, multi-crate workspace + Python/C bindings). Core MeTTa runtime.
- `patham9/PeTTa` — High-performance Prolog-based compiler with Smart Dispatch.
- `F1R3FLY-io/MeTTa-Compiler` (MeTTaTron) — Pure Rust evaluator with MORK/PathMap integration and Rholang linking.
- `F1R3FLY-io/MeTTaIL` — Scala 3 + BNFC + Haskell intermediate language interpreter.
- `trueagi-io/metta-wam` (MeTTaLog) — Warren Abstract Machine interpreter/transpiler.
- `trueagi-io/jetta` — JVM/Kotlin compiler.
- `trueagi-io/metta-morph` — Macro-based MeTTa-to-Chicken-Scheme translator.
- `trueagi-io/FormalMeTTa` — Literal Scala spec implementation.
- `opencog/atomspace-metta` — C++ ForeignAST bridge from MeTTa to AtomSpace.
- Hyperon 0.2.x runtime quirks (already in memory at `reference_hyperon_0210_quirks.md`).
- MORK production deployment topology (residual scope NOT covered by AtomSpace Backend Integration cluster pilot 2026-04-29 or AtomSpace Integration Phase 4 cluster pilot 2026-05-05; check what's left after those pilots).

**Out of scope (covered by closed pilots)**:
- MORK + AtomSpace + DAS substrate work — covered by AtomSpace Backend Integration cluster pilot 2026-04-29 + AtomSpace Integration Phase 4 cluster pilot 2026-05-05. Cross-link, don't re-extract.
- PLN, ECAN, OpenPsi, AtomSpace, Perception, AIRIS, MetaMo, Pattern Mining, Concept Blending, Semantic Parsing, NACE, AI-DSL, MOSES, MeTTa-NARS — all covered by closed cluster pilots (PLN through HAA). Cross-link, don't re-extract.
- MeTTa-Motto — deferred to cross-org sweeps cluster per HAA S2 reconciliation 2026-05-06 + HAA S5 V5-14 narrative-guard 2026-05-07. Cross-link, don't re-extract.
- SGNN — deferred to cross-org sweeps per HAA S4 V4-X 2026-05-07.
- Hanson Robotics repos — substantively covered by OpenPsi cluster pilot Source 4 (2026-04-28) and residual Hanson-era post-2019 perception utilities by Perception cluster pilot Source 5 (2026-05-01).

**Suggested source breakdown** (likely 4-6 sources; refine with user):
- S1: hyperon-experimental — Rust core runtime, multi-crate workspace, Python/C bindings, v0.2.x semantic specifics.
- S2: PeTTa + MeTTaTron + MeTTaLog (or split if too large).
- S3: MeTTa-IL + FormalMeTTa + jetta + metta-morph (compilation/translation paths; possibly split S3.A compilation vs S3.B formal-spec).
- S4: opencog/atomspace-metta (C++ ForeignAST bridge) + MORK production deployment residuals.
- S5 (if needed): MeTTa quirks + cross-runtime semantics gaps + Hyperon 0.2.x bug catalog (already partly in `reference_hyperon_0210_quirks.md`).

User authorized Option A (backlog burn-down) ordering: MeTTa runtime → Cross-org sweeps. **DO NOT start Cross-org sweeps until MeTTa runtime closes.**

---

## §4. Reviewer state at handoff

Both reviewers are **standing by for the MeTTa runtime cluster pilot brief**. Both signed off on the option (ii) methodology change at HAA close 2026-05-07. Final messages from each:

**Codex** (final):
> Acknowledged. I accept option (ii) as the locked protocol. For the MeTTa runtime pilot, I'll continue treating my findings as citation-grade: exact file paths, file:line evidence, raw numerical command output where relevant, and no inference disguised as source fact. Gemini remains in the trilateral flow, with Claude's pre-verification layer carrying the added skepticism around Gemini's cited evidence and adjacent framing. The 75% gate is clear.

**Gemini** (final):
> I acknowledge the new Option (ii) Standing Protocol... I have internalized the four claim classes for orchestrator pre-verification: 1. File-path integrity: ls or git ls-tree before every citation. 2. Line-number precision: git show with sed or restricted read_file ranges to ensure ±5 accuracy. 3. Numerical verbatimness: copy-paste raw shell output for all counts. 4. Interpretation grounding: specific grep/file evidence for every "implemented via" claim. I accept that the MeTTa runtime cluster pilot is the test of this methodology. Standing by for the brief.

When you (next-session orchestrator) draft the MeTTa runtime brief, dispatch normally. The pre-verification work happens AT EXTRACTION RETURN, not at dispatch — Gemini doesn't need different instructions in the brief itself, since the brief already references the standing P12 + V4-11 protocols. The CHANGE is on the orchestrator's side: when `findings_gemini.txt` arrives, run the four-class verification pass and append the cite-verification log to the reconciliation.

---

## §5. Pending tasks at handoff

The current task list (from prior session):
- **#67 [pending]**: Audit correctness — spot-check cards in already-closed clusters against extraction archives. This has been pending since the start of HAA pilot (2026-05-05). May be deprioritized indefinitely OR worth a short pass before MeTTa runtime brief drafting. User's call.
- **#92-#97 [completed]**: HAA Sources 4 + 5 + close (the just-finished work).

You (next-session orchestrator) will create the MeTTa runtime pilot tasks (brief drafting → reviewer dispatch → reviewer extraction return → reconciliation → cluster-close edit batch — mirror the HAA Source 5 task pattern, just for each MeTTa runtime source).

---

## §6. Critical pointers

- **CLAUDE.md** at repo root — top-level orientation; cluster-pilot status table + wiki-edit audit subsections per pilot + Phase 4 architecture lock-in + Phase 3 architecture lock-in + extraction archive map + standing protocols + Claude-specific references.
- **HYPERON_CLUSTER_FINDINGS.md** at `E:\GitHub\hyperon reference\` — substantive source-code findings (cross-model-readable; Codex and Gemini can read this too). Authoritative source-code-side counterpart to CLAUDE.md.
- **SERVER-BUGS.md** at `E:\GitHub\Magi-AGI\hyperon-wiki-mcp\` — wiki MCP operational quirks (`create_card` spurious-error, `restore_card` `+tag` quirk, Draft-vs-Published edit semantics, one-writer-only protocol).
- **Closed pilot reconciliations** under `scripts/archive/{pln,ecan,openpsi,atomspace,perception}_pilot/`, `scripts/archive/atomspace_integration_phase4/`, and `scripts/archive/non_clustered_haa_pilot/`. Each has `source*/findings_reconciled_crossmodel.txt` as the canonical synthesis.
- **CLUSTER_PILOT_HANDOFF.md** at `scripts/archive/CLUSTER_PILOT_HANDOFF.md` — standing template for spawning reviewer agents (read it; refine if needed; do NOT clobber it with this MeTTa-specific handoff).
- **Memory index** at `C:\Users\Lake\.claude\projects\E--GitHub-Magi-AGI-hyperon-wiki\memory\MEMORY.md` — auto-loaded into every Claude session; ~50+ entries spanning project state, feedback rules, references, identity facts.

---

## §7. Suggested first-actions for the next session

When you (next-session orchestrator) start, the user's first message will likely be terse ("MeTTa runtime brief", "let's start", or similar). Before any tool calls:

1. **Acknowledge handoff**: confirm you've read this handoff doc + `feedback_gemini_pre_verification_protocol.md` + the standing-protocols list in §2.
2. **Confirm parallel-Claude awareness**: per `feedback_parallel_claude_handoff.md`, ask if another Claude is currently on this project (Sandra-spec porting work has been active and may still be — at HAA S5 close it was actively touching MOSES + NACE + MeTTa-NARS Published parent siblings during the orchestrator's edit window). Get scope split BEFORE tool calls.
3. **Check git state**: `git status` + `git log -3` to see where the repo stands and whether any new commits landed since this handoff.
4. **Start the MeTTa runtime brief**: scope dialogue with user → repo inventory + HEAD SHA verification → §3.A/B/C population → P12 + V4-11 protocol citation → Q-list → §6 standing-protocols block (carry forward + the new option (ii) protocol).

Do NOT auto-dispatch reviewers without user authorization. The dispatch trigger has historically been user-relayed reviewer messages ("From Codex: ...", "From Gemini: ..."), not autonomous orchestrator action.

---

**End of handoff.**

If you (next session) find this doc unclear, incomplete, or stale, ask the user before improvising. The cluster-pilot methodology has matured over seven pilots; deviations are expensive.
