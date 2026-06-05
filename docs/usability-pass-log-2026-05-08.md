# Hyperon Wiki Usability Pass — Audit Log (started 2026-05-13)

Per `docs/usability-pass-checklist-2026-05-08.md`. One entry per card walked. Edit mechanism noted (direct vs `+AI` Draft proposal). Batches passed to Anna noted at the bottom.

---

## Batch 1 — ECAN Full (pilot)

Started 2026-05-13. Junction: `Hyperon AI Algorithms+ECAN (Economic Attention Networks)+ECAN Full` (ID 4282, Draft, virtual junction with 4 RichText subcards).

### Card 7100 — `+Development and Historical Context` (RichText, child of 4282)

- **Walked**: 2026-05-13
- **Mechanism**: direct `update_card` (RichText child of Draft junction)
- **Storage cleanup**: 17 nested-anchor wrappings around filename pseudo-URLs (e.g. `http://nace.py:34`) unwrapped via local regex script `scripts/clean_autolinker_artifacts.py`. Content verified preserved (27003 chars echo-matched).
- **Bracket-leak rewrites** (4 patches):
  - `[PARTIAL-FRAGMENTED-REVIVAL]/[REVIVED]/[ABANDONED]` → "in a partial, fragmented revival — not fully revived but not abandoned either"
  - `[FISHGRAM-CLEAN-BREAK]` → "The clean break from FISHGRAM holds across the entire cluster"
  - `[LLM-MEDIATED-PERCEPTION]` and `[LLM-AS-KNOWLEDGE-SOURCE]/[LLM-AS-MEMORY-SUBSTRATE]` → reframed as readable prose
  - `CF5.2 [LEGACY-AUTHOR-BRIDGE]/[HYPERON-ERA-PARALLEL-RESEARCH-PORTFOLIO]` → "The cluster pilot reframes Vepstas's role: he is not just a legacy-era author bridging into Hyperon, but actively maintains a parallel Hyperon-era research portfolio."
- **Verified**: post-update find_in_card on `[PARTIAL-FRAGMENTED-REVIVAL]` returned 0 matches; `partial, fragmented revival` returned 1; nested-anchor pattern returned 0.

### Card 4282 — `ECAN Full` (Draft, junction parent)

- **Walked**: 2026-05-13
- **Mechanism**: direct `update_card` (Draft cardtype)
- **Changes**: replaced "Cluster-pilot context" paragraph with "Implementation note" plain-English version (drops V0-1/V4-1/V5 carry-forward IDs and Source-N citations; keeps the substantive 0-of-4-strict-literal finding and the URE STI hook timeline); added "On this page" manual TOC (4 H3-level entries with one-line descriptors); added `id="ecan-..."` attributes to the 4 H3 section headers so the TOC anchors are clickable.
- **Verified**: post-update find_in_card on `On this page` returned 1 match; no V0-1/V4-1/V5 leakage in the content.

### Card 7094 — `+Core Mechanisms and Foundations` (RichText, child of 4282)

- **Walked**: 2026-05-13
- **Mechanism**: no edit needed
- **Notes**: zero bracket leaks, zero RawData links, zero external URLs. HJB / AF / WA expanded inline within the card. Diagram opportunity flagged in inventory but diagram-build is out of scope (requires rendering-mechanism decision).

### Card 7096 — `+System Interfaces and Implementation` (RichText, child of 4282)

- **Walked**: 2026-05-13
- **Mechanism**: direct `update_card` (RichText child of Draft junction)
- **Changes**: reworded `(cluster Sources 1+2)` → "confirmed by direct code inspection of both repos" / "neither implementation reproduces the 2009 ECAN paper math literally (a strict-literal score of 0/4 across the four core formal mechanisms)". Reworded `OpenPsi cluster pilot Source 4 V4-1 addendum (2026-04-28)` → "the OpenPsi action-selector path documented during the OpenPsi cluster pilot (2026-04-28)". The cross-link to Development and Historical Context kept.
- **Verified**: post-update find_in_card on `cluster Source` returned 0 matches.

### Card 7098 — `+Status and Resources` (RichText, child of 4282)

- **Walked**: 2026-05-13
- **Mechanism**: direct `update_card` (RichText child of Draft junction) + `create_card` for the new PlainText sibling
- **Changes**: reworded `(cluster Sources 1+2)` → "confirmed by direct code inspection of both repos"; `(cluster Source 3)` removed (cross-link to Dev/Historical retained); `(cluster Source 4)` and `OpenPsi cluster pilot Source 1 V1-1` reworded to "all confirmed at the pre-removal monorepo snapshot during the ECAN cluster pilot" / "OpenPsi (action-selector seam plus an uncalled `rule-sca-weight` STI helper — an enabler rather than a default consumer)". Created `Hyperon AI Algorithms+ECAN (Economic Attention Networks)+ECAN Full+Status and Resources+last_verified` (PlainText, ID 7842, content `2026-05-13`), included via `{{+last_verified|core}}` at top of Status content.
- **Verified**: post-update find_in_card on `cluster Source` returned 0 matches; rendered get_card shows "Last verified: 2026-05-13" inline at top. Decko-side cosmetic note: the wrapper class `text-muted small` was stripped from the surrounding `<p>`; treated as acceptable for now (low cost vs. Decko-CSS-allowlist investigation).
- **Convention note**: `+last_verified` placed as a child of the Status subcard (not as a sibling under `+Full`). Tied to the Status section's verification specifically; if Anna prefers the simpler one-per-junction convention, easy to relocate.

---

## Batch 2 — PLN Full

Started 2026-06-01. Junction: `Hyperon AI Algorithms+PLN (Probabilistic Logic Networks)+PLN Full` (ID 4184, Draft, virtual junction with 5 RichText subcards). Much lighter than ECAN — zero bracket leaks across all subcards per inventory; the real work was a buried TL;DR, dead RawData links, and one auto-linker artifact.

### Card 4184 — `PLN Full` (Draft, junction parent)

- **Walked**: 2026-06-01
- **Mechanism**: direct `update_card` (Draft cardtype)
- **Changes**:
  - **TL;DR lifted to top**: the plain-English "PLN is Hyperon's primary framework for uncertain reasoning…" definition was buried *below* the dense two-paradigm + five-tradition-map material (a newcomer hit the No-Go theorem and "Σ-guarded compiled tactics" before learning what PLN is). Moved a reworded one-paragraph TL;DR to immediately after the breadcrumb, with a one-sentence pointer to the two-paradigm split.
  - **"On this page" manual TOC** added (5 H3-level entries with one-line descriptors); `id="pln-..."` anchors added to all 5 H3 section headers.
  - **De-linked dead RawData citations**: 9 `{{RawData+Publications+…|view:link}}` inclusions (xiPLN ×3, World-Model Calculus ×2, MORK MM2 PathMap Formalization ×2, Wm Pln Book V3, Markov-de Finetti Formalization, Pln Review) converted to plain-text italic citations. **Verified these return HTTP 403 for anonymous readers** (curl), and **no reader-visible `Publications+…` equivalents exist** (all 404) — so they only exist as raw-source-archive cards. Added a parenthetical noting the six 2026 drafts "are not yet reader-facing publication cards."
- **Verified**: post-update find_in_card on `RawData+Publications` returned 0 matches.

### Card 7102 — `+Core Mechanisms and Inference` (RichText, child of 4184)

- **Walked**: 2026-06-01
- **Mechanism**: no edit needed
- **Notes**: zero bracket leaks, zero RawData, zero external-link artifacts (verified find_in_card `external-link` = 0). Diagram opportunity flagged in inventory (inference-rules table + chaining flow) but diagram-build is out of scope.

### Card 7104 — `+Mathematical Foundations` (RichText, child of 4184)

- **Walked**: 2026-06-01
- **Mechanism**: no edit needed
- **Notes**: zero bracket leaks, zero RawData, zero external-link artifacts (verified). Quantale/quantaloid diagram opportunity flagged; out of scope.

### Card 7106 — `+Execution on MORK` (RichText, child of 4184)

- **Walked**: 2026-06-01
- **Mechanism**: direct `update_card`
- **Changes**: de-linked 2 inline RawData citations (`MORK MM2 PathMap Formalization`, `xiPLN`) to plain-text italics. Reworded internal-process phrasing for a newcomer: "the cluster-pilot review (2026)" → "A 2026 source-code review"; "during cluster review" → "during that review"; "The cluster-pilot MORK review found" → "A direct review of the MORK Rust source found"; "(cluster-pilot finding)" → "(per the same source review)". Substance unchanged.

### Card 7108 — `+Design History and Implementation` (RichText, child of 4184)

- **Walked**: 2026-06-01
- **Mechanism**: `find_and_replace` (targeted)
- **Changes**: collapsed a 4-deep nested-anchor auto-linker artifact wrapping `wiki.opencog.org` (provenance citation) into a single clean anchor, upgraded `http://` → `https://` (the OpenCog wiki **301-redirects http→https and resolves 200** — verified curl, so the link is valid and kept, not dropped). Content dropped 9969→9721 chars. The 8 github repo links flagged in inventory are valid and untouched.

### Card 7109 — `+Status and Resources` (RichText, child of 4184)

- **Walked**: 2026-06-01
- **Mechanism**: `find_and_replace` (prepend) + `create_card` for the PlainText sibling
- **Changes**: created `…+Status and Resources+last_verified` (PlainText, ID 7879, content `2026-06-01`), inlined via `{{+last_verified|core}}` at top of Status content. No bracket leaks, no RawData, no jargon; all Publications+ links reader-visible; github example links valid. Diagram skipped (concise status section).
- **Verified**: rendered get_card shows "Last verified: 2026-06-01" inline.

---

## Batch 3 — MORK Full

Started 2026-06-01. Junction: `Knowledge Representations+MORK (MeTTa Optimized Reduction Kernel)+MORK Full` (ID 4194, Draft, virtual junction with 4 RichText subcards). Two clean subcards; the work was the same auto-linker artifacts (this time nested 7-deep on source-file refs), dead RawData citations, internal cluster-pilot prose, and a buried TL;DR.

### Card 4194 — `MORK Full` (Draft, junction parent)

- **Walked**: 2026-06-01
- **Mechanism**: direct `update_card` (Draft cardtype)
- **Changes**: lifted the plain-English TL;DR ("MORK is Hyperon's high-performance hypergraph engine…") to immediately after the breadcrumb; added "On this page" TOC (4 entries) with `id="mork-..."` anchors on all 4 H3s; reworded the "Cluster-pilot context" paragraph → "Where MORK sits" (drops "AtomSpace Backend Integration cluster pilot … locked in a four-layer taxonomy … per-corner reconciled findings … strict-literal ECAN port"); reworded the Status parenthetical "(per AtomSpace cluster pilot 2026-04-29 reconciliation; earlier 500M figure was wiki drift)" → "(400M is the reconciled figure; an earlier 500M figure on the wiki was inaccurate)". The reader-visible `Publication Maps+Mork theory` link (verified HTTP 200) kept.
- **Verified**: find_in_card `On this page` = 1; `cluster pilot` = 0.

### Card 7149 — `+Core Mechanisms` (RichText, child of 4194)

- **Walked**: 2026-06-01 · **Mechanism**: no edit needed.
- **Notes**: zero bracket leaks / RawData / external-link artifacts (verified `external-link` = 0). PathMap/ZAM/MM2 3-tier diagram opportunity flagged; out of scope.

### Card 7151 — `+Formal Foundations and Indexing` (RichText, child of 4194)

- **Walked**: 2026-06-01 · **Mechanism**: no edit needed.
- **Notes**: zero artifacts (verified `external-link` = 0). Selectivity-Theorem worked-example diagram opportunity flagged; out of scope.

### Card 7153 — `+Architecture and Ecosystem` (RichText, child of 4194)

- **Walked**: 2026-06-01
- **Mechanism**: sub-agent storage cleanup (auto-linker) + `find_and_replace` (jargon)
- **Changes**: cleanup script unwrapped 2 filename pseudo-URLs nested **7-deep** (`morkspaces.pl:7-32`, `MorkDB.cc:268-270`) → plain `<code>` text; 7 real github links preserved (verified `external-link` 14→0, `github.com` 7→7). Reworded inline "PLN cluster pilot Sources 8/11 and AtomSpace cluster pilot Source 3 confirm…" → "2026 source-code reviews of PLN and of the MORK backend both confirm…".
- **Verified**: `external-link` = 0; `cluster pilot` = 0; `morkspaces.pl:7-32` renders as plain code.

### Card 7155 — `+Status and Resources` (RichText, child of 4194)

- **Walked**: 2026-06-01
- **Mechanism**: sub-agent storage cleanup (auto-linker) + `find_and_replace` (RawData de-link, jargon) + `create_card` (PlainText sibling)
- **Changes**: cleanup script collapsed a 4-deep `MorkDB.cc:268-270` pseudo-URL → plain text (arxiv link preserved). De-linked 3 RawData citations (`Mork theory`, `MORK Tensor Networks`, `MORK slots` — all 403 for readers, and uselessly titled "RawData"); the paper titles already appear in the citation prose, so removal is lossless. Reworded 2 inline cluster-pilot refs ("per AtomSpace cluster pilot Source 3", "(AtomSpace cluster pilot Source 3 R3.G2)") and the Primary-Sources provenance line into reader-facing "source-code review archive" language; kept the reader-visible `Publication Maps+Mork theory` link. Created `…+last_verified` (PlainText, ID 7880, `2026-06-01`), inlined via `{{+last_verified|core}}`.
- **Verified**: `RawData+Publications` = 0; `cluster pilot Source` = 0; `external-link` = 0; rendered shows "Last verified: 2026-06-01".

---

## Batch 4 — DAS Full

Started 2026-06-01. Card: `Knowledge Representations+DAS (Distributed AtomSpace)+DAS Full` (ID 4200, Draft, **single card — not a virtual junction**, so no subcards). This was the worst auto-linker offender in the whole inventory and matched Anna's `atomdbsingleton.cc` example by name.

### Card 4200 — `DAS Full` (Draft, single card)

- **Walked**: 2026-06-01
- **Mechanism**: two passes — (1) sub-agent storage cleanup (auto-linker), (2) direct `update_card` editorial rewrite + `create_card` for the PlainText sibling.
- **Pass 1 (auto-linker)**: cleanup script unwrapped **36 nested-matching anchors + 9 filename pseudo-URL anchors** (8 distinct source-file refs nested up to **9-deep**: `MorkDB.cc`, `MorkDB.cc:268`, `MorkDB.cc:197`, `MorkDB.cc:150`, `AtomDBSingleton.cc`, `HebbianNetworkUpdater.cc:57`, `StimulusSpreader.cc:54`, `CLAUDE.md`). `external-link` 81→0; 6 real github links preserved; content 24,740→18,782 bytes. All file refs now plain `<code>`.
- **Pass 2 (editorial)**:
  - **Breadcrumb**: replaced the non-standard `← Back to DAS` line with the standard `{{Home}} / {{Knowledge Representations}} / {{DAS}} / DAS Full` breadcrumb.
  - **TL;DR lifted to top** (immediately after breadcrumb); **"On this page" TOC** added (10 entries) with `id="das-..."` anchors on all 10 H3s.
  - **Reframed the dense lead section**: heading `AtomSpace Cluster-Pilot Lock-In (2026-04-29)` → `How DAS Relates to MORK and ECAN`. Dropped "R4.L1 finding is the canonical technical wording"; unwrapped the verbatim-quote `<blockquote>` (which read as an internal cluster-pilot citation) into plain numbered prose ("1. The MORK backend is real but not a drop-in mutable store" / "2. The Attention Broker approximates ECAN…"); removed the `[SPLIT IMPLEMENTATION]` all-caps styling. **Removed the "see ECAN cluster pilot finding #1 in the top-level CLAUDE.md" reference** (a repo-internal pointer that had become a fake `CLAUDE.md` URL) — folded its substance ("all three score 0/4 on strict-literal compliance") into prose.
  - **Fixed all "see cluster-pilot lock-in above" cross-refs** (Core Mechanisms Attention Broker, Storage Backends MORK bullet, System Interfaces MORK bullet, Status line) → "see the &ldquo;How DAS Relates to MORK and ECAN&rdquo; section above".
  - **Renamed trailing `Status and Resources` → `Primary Sources`** (the card already has a separate `Current Status` section; having both was confusing). Reworded its provenance line from "AtomSpace Backend Integration Cluster Pilot … Source 4 reconciliation R4.L1 is the canonical record" → reader-facing "Source-code review archive (2026-04-29)".
  - **`+last_verified`**: created `…+DAS Full+last_verified` (PlainText, ID 7881, `2026-06-01`) as a direct child of the Full card (no Status subcard exists), inlined via `{{+last_verified|core}}` under the Current Status heading.
- **Verified**: `external-link` = 0; `cluster pilot` = 0; `R4.L1` = 0; `CLAUDE.md` = 0; `github.com` = 6 (preserved); breadcrumb renders (Home / Knowledge Representations / DAS / DAS Full); Draft banner + working "Approve & Publish" button render.
- **Note**: did NOT reorder sections (kept "How DAS Relates…" as the first H3 so the "above" cross-refs stay valid); the section is now reader-facing rather than an internal-citation block. Heavy diagram opportunities (4-layer taxonomy, query-tree, Lambda topology) flagged in inventory remain out of scope pending the rendering-mechanism decision.

---

## Batch 5 — AtomSpace Full

Started 2026-06-01. Junction: `About Hyperon+AtomSpace+AtomSpace Full` (ID 4403, **Published** — virtual junction with 5 RichText subcards). First Published parent in the walk, so the parent edit went through a `+AI` Draft proposal (Anna merges) while the RichText subcards were edited directly.

### Card 4403 — `AtomSpace Full` (Published, junction parent)

- **Walked**: 2026-06-01
- **Mechanism**: `+AI` Draft proposal child (Published card — not edited directly)
- **Created**: `About Hyperon+AtomSpace+AtomSpace Full+AI` (Draft, ID 7883) + `+AI+tag` (Pointer, ID 7884, `ai_generated`).
- **Proposed changes** (in the +AI child): lifted the TL;DR to the top (with an added "AtomSpace is not a single piece of software but a concept across four layers" pointer); added "On this page" TOC (5 entries) with `id="as-..."` anchors on all 5 H3s; reworded the Status paragraph to drop "(locked in by the AtomSpace Backend Integration cluster pilot, closed 2026-04-29)" and "the cluster-pilot lock-in section with per-layer reconciled findings" → "the per-layer detail". Parent breadcrumb/intro were already good.
- **Verified**: parent rendered view now shows the working "Review AI Draft → / Merge AI Draft → Parent" banner (alongside the existing "Approved by Ursula Addison 2026-05-07" seal) — confirms the merge-banner fix works on Published parents. Anna reviews + merges per `feedback_anna_review_workflow.md`.

### Card 7111 — `+Core Concept and Data Model` (RichText, child of 4403)

- **Walked**: 2026-06-01 · **Mechanism**: `find_and_replace`
- **Changes**: single `wiki.opencog.org` provenance link upgraded `http://` → `https://` (link is live — verified 200 earlier). Not nested (inventory's "double-nested" had already collapsed to one). Otherwise clean.

### Card 7113 — `+Values and Space API` (RichText, child of 4403)

- **Walked**: 2026-06-01 · **Mechanism**: no edit needed (clean — no leaks, RawData, or external-link artifacts).

### Card 7115 — `+Implementations` (RichText, child of 4403)

- **Walked**: 2026-06-01 · **Mechanism**: `find_and_replace` ×3
- **Changes**: table heading "Four-Layer AtomSpace Taxonomy (Cluster-Pilot Lock-In, 2026-04-29)" → "Four-Layer AtomSpace Taxonomy"; reworded the odd "Future agents reading 'AtomSpace'…" → "Readers who encounter 'AtomSpace'…"; source line "AtomSpace Backend Integration Cluster Pilot (2026-04-29) — R4.J1 lock-in across Sources 1-4" → "a 2026-04-29 source-code review across the four layers". 15 github links preserved.
- **Verified**: `Cluster-Pilot` = 0, `R4.J1` = 0.

### Card 7117 — `+Design Evolution and Performance` (RichText, child of 4403)

- **Walked**: 2026-06-01 · **Mechanism**: `find_and_replace` (occurrence: all)
- **Changes**: collapsed 4 double-nested `wiki.opencog.org` provenance anchors into single clean `https://` anchors (link is live; kept, not de-linked). Decko normalized the saved anchor to `<a href="…" target="_blank">` form (drops the manual `external-link` class — re-applied at render time).
- **Verified**: `external-link` = 0; single clean anchors confirmed via get_card.

### Card 7118 — `+Status and Resources` (RichText, child of 4403)

- **Walked**: 2026-06-01 · **Mechanism**: `find_and_replace` (prepend) + `create_card`
- **Changes**: created `…+Status and Resources+last_verified` (PlainText, ID 7882, `2026-06-01`), inlined via `{{+last_verified|core}}`. No jargon/RawData; arxiv + github links valid.

---

## Batch 6 — Hyperon Experimental Full

Started 2026-06-01. Card: `MeTTa Programming Language+Hyperon Experimental+Hyperon Experimental Full` (ID 7814, **single card**). Highest bracket-leak concentration in the whole inventory (~25 tags). **Cardtype changed since inventory**: it was Draft on 2026-05-12; it has since been approved to **Published** (Ursula Addison, 2026-05-14), so the edit went through a `+AI` Draft proposal, not a direct edit.

### Card 7814 — `Hyperon Experimental Full` (Published, single card)

- **Walked**: 2026-06-01
- **Mechanism**: `+AI` Draft proposal (Published card) + `create_card` for the PlainText sibling
- **Created**: `…+Hyperon Experimental Full+AI` (Draft, ID 7885) + `+AI+tag` (Pointer, ID 7886, `ai_generated`) + `…+Hyperon Experimental Full+last_verified` (PlainText, ID 7887, `2026-06-01`).
- **Auto-linker**: none needed — the inventory's filename pseudo-URLs (`base.py:205`, `runner.py:24`, etc.) were a *render-time* artifact; stored content was already clean `<code>` (verified `external-link` = 0). The render-time mod fix from earlier this session covers the display side.
- **Proposed changes** (in the +AI child):
  - **Removed all ~25 bracket-label tags.** The 9 standalone `<code>[TAG]</code>` lines under the Architecture H4s (`[SMALL-STEP-INTERPRETER]`, `[DYNAMIC-CHECKED]`, `[HYBRID-RUST-PLUS-METTA-STDLIB]`, `[BUILTIN-FULLY-WIRED]`, `[MODULE-SYSTEM-PARTIAL]`, `[IN-MEMORY-ATOMTRIE-INDEX]` `[NO-BENCHMARK-CLAIMS]`, `[PY-PARTIAL-WITH-GAPS]`, `[C-CORE-ONLY]`, `[TEST-COVERAGE-ADEQUATE]`) deleted as pure noise — the prose under each already explains the concept. Quirk tags (`[QUIRK-CONFIRMED-AT-HEAD]` ×2, `[QUIRK-FIXED-SINCE-V0-2-1]`) reworded inline to "confirmed at HEAD" / "fixed since v0.2.1 (by removal)". Sandbox-table Verdict column (`[SANDBOX-PROTOTYPE]` ×5, `[SANDBOX-EXAMPLE-ONLY]`) → plain "Prototype" / "Example only" / "Unclassified".
  - **TL;DR reworded** to lead with the plain definition (was opening on a HEAD SHA). **"On this page" TOC** added (4 H3 entries) with `id="he-..."` anchors.
  - **Internal jargon reworded**: dropped the `reference_hyperon_0210_quirks.md` memory-file reference and "MAGUS pin"; "Path II / Path IV" → "a Rust-only bridge service (the Phase 4 implementation plan), or contributing the binding upstream via PR"; "during cluster-pilot extraction" → "(static inventory; tests catalogued, not executed)"; "S2-S6 must treat these as precedent…" → "These sandbox modules are precedent and examples, not packaged interfaces."
  - **Removed the "Cross-Source Forwards (S2 to S6)" section entirely** — it was reviewer scaffolding (audit instructions for later cluster-pilot sources), not reader content. Its substance is preserved in the cluster-pilot archive linked from the reframed "Provenance" section. **Flag for Anna**: if she wants that audit-guidance kept somewhere, it should live in the archive/handoff, not the reader card.
  - **"Cluster-Pilot Provenance" → "Provenance"**, reworded to a reader-facing footnote with the two archive pointers.
  - `+last_verified` inlined near the top (tied to the pinned HEAD): "Last verified: 2026-06-01 (at HEAD 3f76dc46 / v0.2.10)".
- **Verified**: +AI proposal has 0 `[SANDBOX` / `[QUIRK` / `[SMALL-STEP` bracket leaks; parent renders the "Review AI Draft → / Merge AI Draft → Parent" banner (next to "Approved by Ursula Addison 2026-05-14" seal). All file:line technical detail preserved.

---

## Batch 7 — OpenCog Legacy Full

Started 2026-06-04. Junction: `About Hyperon+OpenCog Legacy+OpenCog Legacy Full` (ID 4409, **Published** — virtual junction with 4 RichText subcards). The lightest junction so far — these cards predate the cluster-pilot-heavy authoring, so no bracket leaks, no RawData, no cluster jargon. All 4 subcards verified `external-link` = 0 (the inventory's "OpenCog Legacy Status" auto-linker flag was render-time only; stored content clean).

### Card 4409 — `OpenCog Legacy Full` (Published, junction parent)

- **Walked**: 2026-06-04 · **Mechanism**: `+AI` Draft proposal
- **Created**: `…+OpenCog Legacy Full+AI` (Draft, ID 7889) + `+AI+tag` (Pointer, ID 7890, `ai_generated`).
- **Proposed changes**: lifted the TL;DR to the top (plain "OpenCog was the open-source AGI framework (2008–2021) that preceded Hyperon… documents history, not a living system"); added "On this page" TOC (4 entries) with `id="ocl-..."` anchors on the 4 H3s. Note: this parent uses Decko `[[...]]` link syntax (valid, renders fine) rather than the `{{...|view:link}}` form — **preserved as-is** to avoid churn.
- **Self-corrected a copy error during authoring**: an intermediate version had collapsed the three maintained-repo github links (cogutil/cogserver/link-grammar) into one mislabeled internal link; restored the three external links via find_and_replace before finalizing.
- **Verified**: parent renders "Review AI Draft → / Merge AI Draft → Parent" banner (next to "Approved by Ursula Addison 2026-05-05" seal).

### Cards 7141 / 7143 / 7145 — Timeline / Why-Replaced / Maturity (RichText, children of 4409)

- **Walked**: 2026-06-04 · **Mechanism**: no edit needed.
- **Notes**: all three clean — 0 bracket leaks, 0 RawData, 0 external-link artifacts (verified). Diagram opportunities flagged in inventory (1995→2025 timeline, lessons-learned table) remain out of scope.

### Card 7147 — `+Status and Resources` (RichText, child of 4409)

- **Walked**: 2026-06-04 · **Mechanism**: `find_and_replace` (prepend) + `create_card`
- **Changes**: created `…+Status and Resources+last_verified` (PlainText, ID 7888, `2026-06-04`), inlined via `{{+last_verified|core}}`. No jargon/RawData; github + arxiv links valid; `[[Publication Maps+...]]` links are reader-visible.

---

## Batch 8 — MeTTa Programming Language Full

Started 2026-06-04. Junction: `MeTTa Programming Language+MeTTa Programming Language Full` (ID 4288, **Published** — virtual junction with 4 RichText subcards). Two clean subcards; the work was 2 dead RawData citations, one inline cluster-pilot ref (from the earlier MeTTaTron edit), a non-standard breadcrumb, and the missing TOC.

### Card 4288 — `MeTTa Programming Language Full` (Published, junction parent)

- **Walked**: 2026-06-04 · **Mechanism**: `+AI` Draft proposal
- **Created**: `…+MeTTa Programming Language Full+AI` (Draft, ID 7892) + `+AI+tag` (Pointer, ID 7893, `ai_generated`).
- **Proposed changes**: replaced the non-standard `← Back to` line with the standard `{{Home}} / {{MeTTa Programming Language}} / MeTTa Programming Language Full` breadcrumb; lifted the TL;DR to the top; added "On this page" TOC (4 entries) with `id="mtl-..."` anchors on the 4 H3s. Kept the existing per-section one-line descriptors and the full-path `{{...|content}}` inclusions.
- **Verified**: parent renders "Review AI Draft → / Merge AI Draft → Parent" banner (next to "Approved by Ursula Addison 2026-05-07" seal).

### Cards 7157 / 7159 — Core Mechanisms / Formal Foundations (RichText, children of 4288)

- **Walked**: 2026-06-04 · **Mechanism**: no edit needed (verified `external-link` = 0; no leaks/RawData).

### Card 7161 — `+Language Stack and Implementations` (RichText, child of 4288)

- **Walked**: 2026-06-04 · **Mechanism**: `find_and_replace`
- **Changes**: reworded the one inline cluster-pilot provenance note "(MeTTa runtime cluster pilot Source 3, closed 2026-05-13.)" → "(per a 2026-05-13 source-code review.)" — left over from the MeTTaTron paragraph added during that review. 7 github links intact (verified `external-link` = 0).

### Card 7162 — `+Status and Resources` (RichText, child of 4288)

- **Walked**: 2026-06-04 · **Mechanism**: `find_and_replace` ×3 + `create_card`
- **Changes**: de-linked 2 dead RawData citations (`MeTTa Specification`, `Meta-MeTTa: an operational semantics for MeTTa` — both 403; titled uselessly "RawData"; lossless since the Meta-MeTTa arxiv link and citation text remain). Created `…+Status and Resources+last_verified` (PlainText, ID 7891, `2026-06-04`), inlined. The inventory's `http://crates.io` pseudo-URL was render-time only — stored content has "crates.io" as plain text ("analogous to PyPI/crates.io"), nothing to fix. `Publication Maps+Meta-MeTTa Paper` link is reader-visible, kept.
- **Verified**: `RawData+Publications` = 0.

---

## Batch 9 — HAA bracket-leak trio (NACE / AI-DSL / MeTTa-NARS Full)

Started 2026-06-04. Three single cards from the Non-clustered HAA cluster — the highest bracket-leak concentration in the inventory after Hyperon Experimental. All three were Draft at inventory but are now **Published** (Ursula Addison approved them ~2026-05-14), so each went through a `+AI` Draft proposal. In all three the inventory's filename pseudo-URLs were render-time only — stored content already had plain `<code>` file refs (verified `external-link`-free in passing). The shared problem profile: each opened cold on a `<h3>Source Verdict</h3>` block full of `[ALL-CAPS]` tags, with "HAA cluster pilot Source N / V5-x" process jargon woven throughout, no breadcrumb, no TL;DR, no TOC.

### Card 7765 — `NACE Full` (Published, single card)

- **Walked**: 2026-06-04 · **Mechanism**: `+AI` proposal (7896) + `+AI+tag` (7897, ai_generated) + `+last_verified` (7898, 2026-06-04)
- **Changes**: added standard breadcrumb + plain TL;DR (NACE = a pure-Python AIRIS-extending causal-learning agent by Patrick Hammer); dropped the "Source Verdict" tag block, folding the four verdicts (`[IMPLEMENTATION-BACKED-CORE]` / `[AIRIS-DERIVED-NAL-ADJACENT]` / `[NACE-NOT-AIRIS]` / `[PARTIALLY-INTEGRATED-VIA-METTA-BRIDGE]`) into prose; reworded the V1-3/V1-4/V1-5 carry-forward tags and "Per HAA cluster pilot Source 5 close" / "rejected at S5 close (V5-1)" process jargon to reader-facing language; added "On this page" TOC + `id` anchors; reworded the provenance footer. All `nace.py:NN` file-line evidence preserved.
- **Verified**: +AI has 0 `[IMPLEMENTATION-BACKED` / 0 `S5 close`; parent shows merge banner.

### Card 7768 — `AI-DSL Full` (Published, single card)

- **Walked**: 2026-06-04 · **Mechanism**: `+AI` proposal (7899) + `+AI+tag` (7900, ai_generated) + `+last_verified` (7901, 2026-06-04)
- **Changes**: breadcrumb + TL;DR (AI-DSL = a SingularityNET service-composition DSL, dual Idris + MeTTa tracks, marketplace tooling not a core cognitive algorithm); dropped `[ACTIVE-IDRIS-DSL]` / `[AI-DSL-DUAL-CITIZEN]` tags into prose; cleaned heading collision (two "Implementation Surface" → "Implementation: Two Tracks" + "Repository"); reworded the "(V5-rejected pre-cluster-pilot reviewer cite)" note on the `src/Composition.idr` correction and the provenance footer; TOC + anchors. Idris/MeTTa file inventories + cross-grep evidence preserved.
- **Verified**: +AI has 0 `[AI-DSL-DUAL`; parent shows merge banner ("Approved by Ursula Addison 2026-05-14").

### Card 7771 — `MeTTa-NARS Full` (Published, single card)

- **Walked**: 2026-06-04 · **Mechanism**: `+AI` proposal (7902) + `+AI+tag` (7903, ai_generated) + `+last_verified` (7904, 2026-06-04)
- **Changes**: breadcrumb + TL;DR (MeTTa-NARS = Hammer's MeTTa port of NARS/ONA, NAL-1..5, paradigm-distinct from PLN); dropped `[IMPLEMENTATION-BACKED-NAL1-5]` / `[METTA-NARS-NOT-PLN]` / `[MOTTO-POC-INTEROP]` / `[PAPER-NOT-IMPLEMENTED-IN-METTA-NARS]` tags into prose; reworded "Mirror of S1 V1-4 [AIRIS-CONFIDENCE-NOT-PLN-TV]", "per closed S2 reconciliation", "(V5-14 narrative-guard at S5 close)" jargon; kept the important GPT-o1-hallucination-warning caveat on the Goertzel PLN-vs-NARS Mattermost paper (reworded to reader-facing). TOC + anchors. Renamed "Cluster-Narrative Position — Paradigm Boundaries" → "How MeTTa-NARS Relates to Its Neighbors".
- **Verified**: +AI has 0 `[METTA-NARS` / 0 `S5 close`; parent (checked via sibling pattern) carries merge banner.

---

## Batch 10 — MOSES Full

Started 2026-06-05. Junction: `Hyperon AI Algorithms+MOSES (Meta-Optimizing Semantic Evolutionary Search)+MOSES Full` (ID 4399, **Published** — virtual junction with 4 RichText subcards). Heavy fork-divergence bracket-tag load (~22 tags across 2 subcards), plus raw `git rev-list` output (`0\t107`, `7\t165`) that's opaque to non-developers.

### Card 4399 — `MOSES Full` (Published, junction parent)

- **Walked**: 2026-06-05 · **Mechanism**: `+AI` proposal (7934) + `+AI+tag` (7935, ai_generated)
- **Changes**: lifted the TL;DR to the top; added "On this page" TOC (4 entries) with `id="moses-..."` anchors on the 4 H3s. Breadcrumb/intro/status already good.

### Card 7128 — `+Core Mechanisms and Scoring` (RichText, child of 4399)

- **Walked**: 2026-06-05 · **Mechanism**: no edit needed (verified `external-link` = 0; no bracket leaks).

### Card 7130 — `+Mathematical Foundations and MORK` (RichText, child of 4399)

- **Walked**: 2026-06-05 · **Mechanism**: direct `update_card`
- **Changes**: dropped the `[MORK-MOSES-PARTIAL-SCAFFOLD-OPEN-RESEARCH-LINE]` tag + "Per HAA cluster pilot Source 5 close" line into prose ("aspirational architecture, not current implementation — a partial scaffold and open research line"); softened the raw `git ls-tree`/`grep -ri` commands into reader-facing descriptions of the same evidence; reworded the V5-10 provenance footer. All proposal-vs-implemented framing preserved.

### Card 7132 — `+Implementation Eras and Design History` (RichText, child of 4399)

- **Walked**: 2026-06-05 · **Mechanism**: direct `update_card`
- **Changes**: the heaviest card — converted ~12 fork-verdict bracket tags (`[ACTIVE-METTA-PRIMARY]`, `[VEPSTAS-MIRROR-SAME-SHA]`, `[STRICT-FORK-STALE]`, `[STRICT-FORK-STALE-MERGED-UPSTREAM]`, `[STRICT-FORK-DIVERGED-LEGACY-FIXES]`, `[STANDALONE-EXPERIMENT-NOT-FORK]`, `[ACTIVE-CPP-ATOMSPACE-BASELINE]`, `[SUPERSEDED-BY-METTA-MOSES]`, `[ARCHIVAL-PARADIGM-PREDECESSOR]`, `[MORK-MOSES-PARTIAL-SCAFFOLD-OPEN-RESEARCH-LINE]`) into plain prose; converted the raw `git rev-list --left-right --count` output (`0\t0`, `0\t107`, `7\t165`, `19\t23`) into readable "N ahead / M behind" phrasing; dropped "Per HAA Source 5 / P12 verbatim / same pattern as S3 singnet-miner" process jargon. All repo URLs, file-line evidence (`deme/*.metta`, `scoring/*.metta`), mailing-list citations, and HEAD SHAs preserved.
- **Verified**: `[STRICT-FORK` = 0.

### Card 7133 — `+Status and Resources` (RichText, child of 4399)

- **Walked**: 2026-06-05 · **Mechanism**: direct `update_card` ×2 + `create_card`
- **Changes**: converted ~10 status bracket tags to prose; dropped "(V5-9 lump)" and "P12-verified" jargon; reworded the provenance footer. Created `…+Status and Resources+last_verified` (PlainText, ID 7933, `2026-06-05`), inlined. (Fixed a dead `#` placeholder anchor I briefly introduced → plain-text cross-reference.)
- **Verified**: `[ACTIVE-METTA` = 0.

---

## Batch 11 — MetaMo Full

Started 2026-06-05. Junction: `Hyperon AI Algorithms+MetaMo (Motivational Framework)+MetaMo Full` (ID 4278, **Published** — virtual junction with 3 RichText subcards; was Draft at inventory, since approved). The last of the moderate bracket-leak cards (~9 across 2 subcards). RawData (2) confirmed 403; the inventory's filename pseudo-URLs were render-time only (stored content clean — verified `external-link` = 0 on the lineage subcard).

### Card 4278 — `MetaMo Full` (Published, junction parent)

- **Walked**: 2026-06-05 · **Mechanism**: `+AI` proposal (7937) + `+AI+tag` (7938, ai_generated)
- **Changes**: lifted TL;DR to the top; added "On this page" TOC (3 entries) with `id="metamo-..."` anchors. Breadcrumb/intro/status already good.

### Card 7135 — `+Core Mechanisms and Formalism` (RichText, child of 4278)

- **Walked**: 2026-06-05 · **Mechanism**: `find_and_replace` ×5
- **Changes**: the formalism sections (motivational state, pseudo-bimonad, stability, five principles) were already clean. Reworded the "Implementation Backing" block: dropped `[PAPER-LEANING-HYBRID]` / `[IMPLEMENTATION-BACKED-CORE]` / `[REFERENCE-IMPLEMENTATION-NOT-PRODUCTION]` / `[FORMAL-LAWS-PAPER-ONLY]` / `[SKELETON-IMPLEMENTATION]` tags into prose; reworded "Non-clustered HAA cluster pilot Source 2 ... extracted a verdict" → "A 2026-05-06 source-code review ... assessed"; reworded the provenance footer. All `core/*.py:NN` / `category/*.py:NN` file-line citations preserved.
- **Verified**: `[IMPLEMENTATION-BACKED` = 0.

### Card 7137 — `+Historical Lineage` (RichText, child of 4278)

- **Walked**: 2026-06-05 · **Mechanism**: no edit needed (verified `external-link` = 0; no bracket leaks per inventory).

### Card 7139 — `+Status and Resources` (RichText, child of 4278)

- **Walked**: 2026-06-05 · **Mechanism**: direct `update_card` + `create_card`
- **Changes**: reworded the "Implementation Anchors (cluster-pilot trilateral classification, Source 2 close)" heading + intro to plain "three distinct roles"; dropped `[IMPLEMENTATION-BACKED-CORE]` / `[FORMAL-LAWS-PAPER-ONLY]` / `[HEURISTIC-PROTOTYPE]` / `[OPENPSI-PREDECESSOR-SUBSTRATE]` tags into prose; de-linked 2 dead RawData citations (AGI 25 METAMO One, OpenPsi Cognitive Model — both 403; the AGI-2025 + OpenPsi-2011 citation text remains); dropped "V2-1..V2-7 carry-forwards" footer; created `…+Status and Resources+last_verified` (PlainText, ID 7936, `2026-06-05`), inlined.
- **Verified**: `RawData+Publications` = 0.

---

## Batch 12 — PRIMUS Full

Started 2026-06-05. Junction: `Cognitive Architectures+PRIMUS (formerly CogPrime)+PRIMUS Full` (ID 4192, **Draft** — virtual junction with 4 RichText subcards). First fully leak-free cluster in the tail: all 4 subcards have zero bracket leaks / RawData / cluster jargon (verified `external-link` = 0 on all). Parent is **Draft**, so edited directly (live), unlike the recent Published parents.

### Card 4192 — `PRIMUS Full` (Draft, junction parent — edited directly)

- **Walked**: 2026-06-05 · **Mechanism**: direct `update_card`
- **Changes**: replaced the non-standard `← Back to` line with the standard `{{Home}} / {{Cognitive Architectures}} / {{PRIMUS}} / PRIMUS Full` breadcrumb; lifted the TL;DR to the top; added "On this page" TOC (4 entries) with `id="primus-..."` anchors on the 4 H3s. Kept the existing per-section descriptors and full-path inclusions.

### Cards 7164 / 7166 / 7167 — Architecture / Components / Cognitive Synergy (RichText, children of 4192)

- **Walked**: 2026-06-05 · **Mechanism**: no edit needed (all verified `external-link` = 0; no bracket leaks per inventory).

### Card 7169 — `+Status and Resources` (RichText, child of 4192)

- **Walked**: 2026-06-05 · **Mechanism**: `find_and_replace` ×2 + `create_card`
- **Changes**: upgraded the `wiki.opencog.org` provenance link `http://` → `https://` (single anchor in storage — the inventory's "double-nested" was render-time; link is live). Created `…+Status and Resources+last_verified` (PlainText, ID 7994, `2026-06-05`), inlined under the first heading. github + arxiv links valid.

---

## Batch 13 — Semantic Parsing Full

Started 2026-06-05. Junction: `Hyperon AI Algorithms+Semantic Parsing (LLM/NLP)+Semantic Parsing Full` (ID 4419, **Published** — virtual junction with 4 RichText subcards). Fully leak-free per inventory (all 4 subcards verified `external-link` = 0; no RawData, no jargon). Pure structural pass.

- **4419 (Published parent)** — `+AI` proposal (7995) + `+AI+tag` (7996): lifted TL;DR + "On this page" TOC (4 entries) with `id="sp-..."` anchors. Breadcrumb/intro/status already good.
- **7120 / 7122 / 7124** (Legacy Pipeline / Hyperon-Era Approaches / Symbolic Heads) — no edit needed (verified clean).
- **7126 (Status)** — `+last_verified` (PlainText, ID 7997, `2026-06-05`) created + inlined.

---

## Batch 14 — Magi Full

Started 2026-06-05. Junction: `Ecosystem+Magi+Magi Full` (ID 7180, **Published** — virtual junction with 4 RichText subcards). Leak-free; the work was bare-http `magi-agi.org` host references + one RawData link.

- **7180 (Published parent)** — `+AI` proposal (7999) + `+AI+tag` (8000): standard breadcrumb (replacing `← Back to`), lifted TL;DR, "On this page" TOC (4 entries) with `id="magi-..."` anchors.
- **7182 / 7186** (MAGUS Framework / Partnerships and Applications) — no edit needed (clean).
- **7184 (Tools and Assistants)** — converted plain-text `wiki.magi-agi.org` to an explicit `https://` anchor (host 301s http→https; was render-time auto-linked to bare http).
- **7187 (Status)** — converted `wiki.magi-agi.org` + `mcp.magi-agi.org` plain-text mentions to explicit `https://` anchors; de-linked the `{{RawData|view:link}}` pointer (reader-inaccessible) to plain text ("held in the Hyperon Wiki raw-source archive"); created `…+Status and Resources+last_verified` (PlainText, ID 7998, `2026-06-05`), inlined.

---

## Batch 15 — Final single cards (AIRIS / ASI Chain / TransWeave / WILLIAM / Self-Modification and Safety)

Started 2026-06-05. The last five inventory slots, all **single cards** (no subcards), all now **Published** (several were Draft at inventory; since approved). `+last_verified` attaches directly to each Full card. All five via `+AI` proposals.

### Card 7495 — `AIRIS Full` (Published, single card)
- `+AI` (8001) + `+AI+tag` (8002) + `+last_verified` (8003, 2026-06-05). The one substantive card: dropped `[IMPLEMENTATION-BACKED-CORE]` tags and the V1-1..V1-5 carry-forward refs into prose; fixed genuine stored auto-linker artifacts (`airis_<a href="http://stable.py">stable.py</a>` → plain `airis_stable.py`; same for `airis.py`); removed the internal "Wiki attribution corrections (V1-1)" / CF5.6.E bookkeeping paragraph (kept a one-line reader-useful note on the canonical repo); lifted TL;DR; added TOC + anchors. All paper-cite + file-line + empirical content preserved. Verified `[IMPLEMENTATION-BACKED` = 0, `http://stable.py` = 0.

### Card 4292 — `ASI Chain Runtime Environment Full` (Published, single card)
- `+AI` (8004) + `+AI+tag` (8005) + `+last_verified` (8006, 2026-06-05). Collapsed a **9-deep** `docs.asichain.io` nested anchor → single clean https; standard breadcrumb (replacing `← Back to`); lifted TL;DR; TOC + anchors; de-linked the dead RawData Meta-MeTTa citation (arxiv link retained); renamed trailing "Status and Resources" → "Primary Sources" (a separate "Current Status" section already existed). Verified `http://docs.asichain.io` = 0, `RawData+Publications` = 0.

### Card 6295 — `TransWeave Full` (Published, single card)
- `+AI` (8007) + `+AI+tag` (8008) + `+last_verified` (8009, 2026-06-05). Clean content; structural only — standard breadcrumb, lifted TL;DR, TOC + anchors. Body verbatim.

### Card 6298 — `WILLIAM Full` (Published, single card)
- `+AI` (8010) + `+AI+tag` (8011) + `+last_verified` (8012, 2026-06-05). Clean; structural only — breadcrumb, TL;DR, TOC + anchors. Body verbatim.

### Card 6301 — `Self-Modification and Safety Full` (Published, single card)
- `+AI` (8013) + `+AI+tag` (8014) + `+last_verified` (8015, 2026-06-05). Clean; structural only — breadcrumb, TL;DR, TOC + anchors. Body verbatim.

---

## Hand-off batches

### Batch 15 — Final single cards (ready for Anna review)

- 5 Published single cards: AIRIS (7495→+AI 8001), ASI Chain (4292→+AI 8004), TransWeave (6295→+AI 8007), WILLIAM (6298→+AI 8010), Self-Mod (6301→+AI 8013), each with a new `+last_verified`.
- All five need Anna's merge (the `+AI` Drafts carry breadcrumb + TL;DR + TOC; AIRIS + ASI Chain also carry the de-bracketing / nested-anchor / RawData cleanups). The `+last_verified` siblings are live.
- URLs: AIRIS, ASI Chain Runtime Environment, TransWeave, WILLIAM, Self-Modification and Safety — all under their respective Full paths on wiki.hyperon.dev.

---

## ✅ Card-walk complete — all 21 inventory junctions done (2026-06-05)

All 21 "Foo Full" junctions from `docs/usability-inventory-2026-05-08.md` have been walked across Batches 1–15:

ECAN · PLN · MORK · DAS · AtomSpace · Hyperon Experimental · OpenCog Legacy · MeTTa Programming Language · NACE · AI-DSL · MeTTa-NARS · MOSES · MetaMo · PRIMUS · Semantic Parsing · Magi · AIRIS · ASI Chain Runtime · TransWeave · WILLIAM · Self-Modification and Safety.

**Totals:** ~64 substantive cards walked; 21 `+last_verified` siblings created; 16 `+AI` Draft proposals raised on Published/approved parents; the rest direct edits on Draft cards/subcards.

**Consistent treatment applied to every card:** breadcrumb normalized (standard `Home / … / Foo Full` form, replacing `← Back to` where present); plain-English TL;DR lifted to the top; per-card "On this page" TOC with intra-page `id` anchors; cluster-pilot `[ALL-CAPS]` bracket tags + `V-N-X` / `HAA Source N` / `R4.x` process jargon reworded into prose; auto-linker nested-anchor / filename-pseudo-URL artifacts cleaned (stored-content ones fixed; render-time ones covered by the deployed mod); dead `RawData+Publications` citations de-linked (403 for readers; verified, no reader-visible equivalents); live `wiki.opencog.org` / `docs.asichain.io` / `magi-agi.org` links collapsed/upgraded to single https anchors; `+last_verified` Status dates added.

**Open follow-ups (NOT done in this pass — flagged for editors / future work):**
1. **Anna's merges** — 16 `+AI` proposals on Published parents await human review + merge.
2. **RawData reader-visibility policy** — many cards cite World-Model-line / MORK-theory / MeTTa-spec drafts that exist *only* as RawData (403 for readers). De-linked per checklist; a standing decision is needed on whether to synthesize reader-facing `Publications+…` cards or relax the read-rule.
3. **Diagrams** — the inventory flagged ~33 high-value diagram opportunities (taxonomies, lineages, pipelines, state machines). Out of scope here pending a rendering-mechanism decision (Mermaid vs SVG vs uploaded image).
4. **Two AIRIS / Hyperon-Experimental judgment calls** (removed reviewer-scaffolding sections; tag deletions) — reversible from the `+AI` diffs if editors disagree.

### Batch 14 — Magi Full (ready for Anna review)

- 5 cards walked: 7180 (Published parent — via `+AI` 7999/8000), 7182, 7184, 7186, 7187 + new sibling 7998. 2 subcards needed no edit.
- Parent needs Anna's merge (breadcrumb + TL;DR + TOC); the 7184/7187 link edits are live.
- URL: https://wiki.hyperon.dev/Ecosystem+Magi+Magi_Full
- Note: the magi-agi.org hosts (the separate Magi Archive wiki + its MCP) are intentional external references; upgraded to https, kept as links.

### Batch 13 — Semantic Parsing Full (ready for Anna review)

- 4 cards walked: 4419 (Published parent — via `+AI` 7995/7996), 7120, 7122, 7124, 7126 + new sibling 7997. 3 subcards needed no edit.
- Parent needs Anna's merge (TOC + TL;DR); 7126 last_verified is live.
- URL: https://wiki.hyperon.dev/Hyperon_AI_Algorithms+Semantic_Parsing_(LLM/NLP)+Semantic_Parsing_Full

### Batch 12 — PRIMUS Full (ready for Anna review)

- 5 cards walked: 4192 (Draft parent — edited directly, live), 7164, 7166, 7167, 7169 plus new sibling 7994 (`+last_verified`). 3 subcards needed no edit.
- **No `+AI` proposal** — Draft parent, so the breadcrumb + TL;DR + TOC are already live. Only the wiki.opencog.org https upgrade + last_verified touched a subcard.
- URL to review: https://wiki.hyperon.dev/Cognitive_Architectures+PRIMUS_(formerly_CogPrime)+PRIMUS_Full

### Batch 11 — MetaMo Full (ready for Anna review)

- 4 cards walked: 4278 (Published parent — via `+AI` proposal 7937/7938), 7135, 7137, 7139 plus new sibling 7936 (`+last_verified`). 1 subcard needed no edit.
- **Parent requires Anna's merge** (the `+AI` Draft 7937 carries the TL;DR + TOC). The 2 subcard rewrites (7135, 7139) are already live.
- URL to review: https://wiki.hyperon.dev/Hyperon_AI_Algorithms+MetaMo_(Motivational_Framework)+MetaMo_Full

### Batch 10 — MOSES Full (ready for Anna review)

- 5 cards walked: 4399 (Published parent — via `+AI` proposal 7934/7935), 7128, 7130, 7132, 7133 plus new sibling 7933 (`+last_verified`). 1 subcard needed no edit.
- **Parent requires Anna's merge** (the `+AI` Draft 7934 carries the TL;DR + TOC). The 3 subcard rewrites (7130, 7132, 7133) are already live.
- URL to review: https://wiki.hyperon.dev/Hyperon_AI_Algorithms+MOSES_(Meta-Optimizing_Semantic_Evolutionary_Search)+MOSES_Full
- Notable: 7132 is the best example so far of converting raw git-divergence output + verdict tags into readable prose; worth showing editors as a pattern for the remaining fork-heavy cards (e.g. Pattern Mining, Concept Blending).

### Batch 9 — HAA bracket-leak trio (ready for Anna review)

- 3 Published single cards: NACE (7765 → +AI 7896), AI-DSL (7768 → +AI 7899), MeTTa-NARS (7771 → +AI 7902), each with a new `+last_verified` (7898 / 7901 / 7904).
- **All three require Anna's merge** (the `+AI` Drafts carry the de-bracketed + reworded + breadcrumb/TOC content). Nothing is live yet on these three parents except the new `+last_verified` siblings.
- URLs to review:
  - https://wiki.hyperon.dev/Hyperon_AI_Algorithms+NACE_(Non-Axiomatic_Causal_Explorer)+NACE_Full
  - https://wiki.hyperon.dev/Hyperon_AI_Algorithms+AI-DSL+AI-DSL_Full
  - https://wiki.hyperon.dev/Hyperon_AI_Algorithms+MeTTa-NARS_(Non-Axiomatic_Reasoning_System)+MeTTa-NARS_Full
- These were the cards most directly matching Anna's bracket-label complaint; good high-visibility wins once merged.

### Batch 8 — MeTTa Programming Language Full (ready for Anna review)

- 4 cards walked: 4288 (Published parent — via `+AI` proposal 7892/7893), 7157, 7159, 7161, 7162 plus new sibling 7891 (`+last_verified`). 2 subcards needed no edit.
- **Parent requires Anna's merge** (the `+AI` Draft 7892 carries the breadcrumb + TL;DR + TOC). Subcard edits (7161, 7162) are already live.
- URL to review: https://wiki.hyperon.dev/MeTTa_Programming_Language+MeTTa_Programming_Language_Full

### Batch 7 — OpenCog Legacy Full (ready for Anna review)

- 4 cards walked: 4409 (Published parent — via `+AI` proposal 7889/7890), 7141, 7143, 7145, 7147 plus new sibling 7888 (`+last_verified`). 3 subcards needed no edit.
- **Parent requires Anna's merge** (the `+AI` Draft 7889 carries the TOC + lifted TL;DR). Subcard 7147 edit is already live.
- URL to review: https://wiki.hyperon.dev/About_Hyperon+OpenCog_Legacy+OpenCog_Legacy_Full
- Lightest batch — mostly a TOC + `+last_verified` addition; the content was already in good shape.

### Batch 6 — Hyperon Experimental Full (ready for Anna review)

- 1 card walked (single card, Published): 7814 — via `+AI` proposal 7885/7886, plus new sibling 7887 (`+last_verified`).
- **Parent requires Anna's merge**: the `+AI` Draft (7885) carries the full de-bracketed + reworded + TOC'd content; review via the "Review AI Draft → Merge" banner.
- URL to review: https://wiki.hyperon.dev/MeTTa_Programming_Language+Hyperon_Experimental+Hyperon_Experimental_Full
- **Two judgment calls to confirm with Anna**: (1) removal of the "Cross-Source Forwards (S2 to S6)" reviewer-scaffolding section; (2) deletion (rather than rewording) of the 9 standalone architecture bracket-tags. Both are reversible from the +AI diff if she disagrees.

### Batch 5 — AtomSpace Full (ready for Anna review)

- 6 cards walked: 4403 (Published parent — via `+AI` proposal 7883/7884), 7111, 7113, 7115, 7117, 7118 plus new sibling 7882 (`+last_verified`). 1 subcard needed no edit.
- **Parent requires Anna's merge**: the `+AI` Draft (7883) carries the TOC + de-jargon proposal; she reviews via the "Review AI Draft → Merge" banner now showing on the parent. Subcard edits are already live (direct RichText edits).
- URL to review: https://wiki.hyperon.dev/About_Hyperon+AtomSpace+AtomSpace_Full
- **Process note (first Published parent in the walk)**: confirmed the Published-parent path works end-to-end — `+AI` Draft proposal + populated `+AI+tag` + the merge banner renders. Future Published junctions (e.g. MeTTa Programming Language Full) follow this same pattern; the RichText subcards under them stay direct-edit.

### Batch 4 — DAS Full (ready for Anna review)

- 1 card walked (single-card junction): 4200 plus new sibling 7881 (`+last_verified`).
- All edits direct (Draft + PlainText child); no `+AI` proposal needed.
- URL to review: https://wiki.hyperon.dev/Knowledge_Representations+DAS_(Distributed_AtomSpace)+DAS_Full
- This was the worst auto-linker card in the inventory (81 nested anchors); now fully clean. Good candidate to show Anna as the "before/after" proof that the `atomdbsingleton.cc`-style breakage is resolved.

### Batch 3 — MORK Full (ready for Anna review)

- 6 cards walked: 4194 (parent), 7149 (Core Mechanisms), 7151 (Formal Foundations), 7153 (Architecture), 7155 (Status) plus new sibling 7880 (`+last_verified`). 2 subcards needed no edit.
- All edits direct (Draft + RichText/PlainText children); no `+AI` proposals needed.
- URL to review: https://wiki.hyperon.dev/Knowledge_Representations+MORK_(MeTTa_Optimized_Reduction_Kernel)+MORK_Full
- Same RawData-403 policy flag as Batch 2 applies: 3 MORK-theory drafts (`Mork theory`, `MORK Tensor Networks`, `MORK slots`) exist only as RawData cards. De-linked per checklist; flagged for the standing reader-visibility decision.

### Batch 2 — PLN Full (ready for Anna review)

- 6 cards walked: 4184 (parent), 7102 (Core Mechanisms), 7104 (Math Foundations), 7106 (Execution on MORK), 7108 (Design History), 7109 (Status) plus new sibling 7879 (`+last_verified`). 2 subcards needed no edit.
- All edits direct (Draft + RichText/PlainText children); no `+AI` proposals needed.
- URL to review: https://wiki.hyperon.dev/Hyperon_AI_Algorithms+PLN_(Probabilistic_Logic_Networks)+PLN_Full
- **Policy flag for Lake/Anna**: the PLN Full parent cited 9 World-Model-line drafts (xiPLN, World-Model Calculus, etc.) that exist *only* as RawData cards (403 for readers). I de-linked them to plain-text citations per the checklist. If these drafts should be reader-visible, the fix is to synthesize reader-facing `Publications+…` cards (or relax the RawData read-rule for these specific papers) — bigger policy call, deferred. Same RawData-403 pattern will recur on other cluster-pilot-heavy cards; worth a standing decision.

### Batch 1 — ECAN Full (ready for Anna review)

- 5 cards walked: 4282 (parent), 7094 (Core), 7096 (System Interfaces), 7098 (Status), 7100 (Dev/Historical) plus new sibling 7842 (`+last_verified`).
- All edits are direct (Draft cardtype + RichText/PlainText children); no `+AI` Draft proposals needed.
- URL to review: https://wiki.hyperon.dev/Hyperon_AI_Algorithms+ECAN_(Economic_Attention_Networks)+ECAN_Full
- Carry-over flagged for follow-on (NOT in this batch): diagram-rendering mechanism decision (Mermaid vs SVG vs uploaded image) before building the urgent ECAN diagram opportunities (9-event executable-coupling lifecycle, trilateral perception/symbolic/neural mining, AtomSpace-Scheme vs MeTTa-runtime two-stack split). Tracked in inventory not in this checklist.
