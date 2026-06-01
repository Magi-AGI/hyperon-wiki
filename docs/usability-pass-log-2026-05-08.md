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

## Hand-off batches

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
