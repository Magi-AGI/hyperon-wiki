# Hyperon Wiki Usability Pass — Per-Card Checklist (2026-05-08)

Holistic per-card readability + usability walk on every Full card (and Published parents that need it). Triggered by Anna Mikeda's 2026-05-08 Mattermost feedback batch. The companion read-only inventory at `docs/usability-inventory-2026-05-08.md` lists concrete bracket-leak / RawData-link / external-URL / diagram-opportunity / undefined-term findings per card; this checklist is what the editor applies on top of those findings to make the card actually *good*.

**Audience**: a non-snet-community newcomer who has heard of Hyperon but doesn't know ECAN / PLN / MetaMo / AttentionBank. They should be able to land on any Full card and form an accurate picture of what the thing is, why it exists, and where it sits in the larger system, without giving up in the first paragraph.

**Edit mechanism**: Draft cardtype → edit directly via `update_card`. Published / IndexPublished / IndexSection cardtype → propose via `+AI` Draft child for Anna's review per `feedback_anna_review_workflow.md` and `feedback_published_card_edits.md`.

---

## Per-card checklist

For each Full card (and the Published parent if it carries body content), confirm or add:

### Top of card

- [ ] **Breadcrumb** on first line. Convention per `reference_full_subcard_convention.md`: `<p> {{Home|...}} / {{section|...}} / {{subtopic|...}} / Foo Full </p>`. Verify each segment links to the right parent and renders correctly.
- [ ] **Intro paragraph (TL;DR)** placed immediately after the breadcrumb. 2-4 sentences in plain English, audience = newcomer. Says what the thing IS, why it exists, and where it sits relative to neighbors. Does NOT open with implementation details, file:line citations, version SHAs, or cluster-pilot vocabulary.
- [ ] **Per-card manual TOC** near the top of the body (per Lake 2026-05-08; replaces the removed auto-TOCs from task #6). Data-driven (curated by the editor), not programmatic. List the H2/H3 sections in order with intra-card anchors.

### Body — readability

- [ ] **No bracket-label leaks**. The cluster-pilot `[ALL-CAPS-WITH-DASHES]` vocabulary (`[IMPLEMENTATION-BACKED-CORE]`, `[FORMAL-LAWS-PAPER-ONLY]`, `[PARTIAL-FRAGMENTED-REVIVAL]`, etc.) reworded into plain prose or removed. Carry-forward IDs like `(V1-3)` that aren't introduced are also removed.
- [ ] **Define abbreviations / technical terms on first use**, with a hyperlink to the Glossary card or the term's own card if one exists. Universal terms (Hyperon, MeTTa, AGI, GitHub) don't need this; snet/AGI jargon (ECAN, PLN, AttentionBank, STI, OpenPsi, MOSES, NAL, NARS, etc.) does.
- [ ] **Heading hierarchy is consistent** (H2 / H3 / H4 in order, no level-skipping). Section titles describe the section's content in newcomer terms, not in cluster-pilot framing.
- [ ] **Paragraphs flow** — no orphan one-line paragraphs or wall-of-text blocks; aim for 2-5 sentence paragraphs.
- [ ] **Code blocks render correctly** (proper fencing, language hint where useful). MeTTa snippets should syntax-highlight if the highlighter is wired up.
- [ ] **Tables aren't broken** (escaped pipes, no rendering artifacts, alignment legible).
- [ ] **Terminology is consistent within the card** (e.g., don't switch between "AttentionBank" and "AB" mid-card unless the abbreviation is defined and intentional).

### Body — links

- [ ] **Internal links work**. Every `{{Card Name|view:...}}` inclusion and `<a href="/...">` link resolves to a real card. Run `get_card` on questionable ones.
- [ ] **No outbound RawData+ links** from the card body (RawData+ is hidden from non-Raw-Data-Analyst readers; produces 404). Either drop the link or move the citation to a non-RawData reference.
- [ ] **External URLs verified**. Every `http(s)://` URL in the card returns 200 (or a sensible redirect chain). Hallucinated URLs (`http://atomdbsingleton.cc/`, auto-linked filename pseudo-URLs like `http://airis.py`) removed or replaced. Per `feedback_webfetch_verify_external_urls.md`, cite the WebFetch verification in the edit notes.
- [ ] **Cross-references to sibling Full cards** present where the card discusses a related subject (e.g., MetaMo Full referencing OpenPsi Full and ECAN Full where it discusses motivation/attention coupling).

### Visuals

- [ ] **Diagrams added where the inventory flagged an opportunity** — taxonomies, lineages, comparison tables, multi-component architectures, process flows. See `docs/usability-inventory-2026-05-08.md` per-card diagram-opportunity flags. Rendering mechanism per task #3 is open (Mermaid if Decko renders it; inline SVG; uploaded image). Pick once and stay consistent.

### Status section

- [ ] **`+last_verified` PlainText sibling** added to Status subcards (per Anna 2026-05-08 — semantically stronger than `updated_at` because it doesn't tick on typo fixes). Today's date in ISO form `YYYY-MM-DD`.
- [ ] **Status content reflects current upstream reality** (HEAD SHA, version string, recent activity vs. dormant). Cross-check against the linked GitHub repo's actual state.

### Sandra-spec siblings (for IndexPublished / IndexSection parents that have them)

- [ ] **`+description`** is short, plain-English, newcomer-friendly. Not a technical summary.
- [ ] **`+responsible`** lists actual contributors (no curator-as-contributor leak per `feedback_publication_curator_not_contributor.md`).
- [ ] **`+github`** points to the canonical repo (no HTTP 404; trilateral repo set documented if relevant).
- [ ] **`+roadmap`** items are still real / current (not abandoned plans).
- [ ] **`+examples`** code is correct and runs; comments explain what the example demonstrates.

---

## Output protocol

- **Draft cards**: edit directly via `update_card`.
- **Published / IndexPublished / IndexSection cards**: create or update an `+AI` Draft child with the proposed diff. Anna reviews per `feedback_anna_review_workflow.md` and approves the parent only once the `+AI` is merged or rejected.
- **Per-write verification**: `get_card` after every `update_card` / `create_card` to confirm the change landed (`reference_wiki_mcp_quirks.md` MCP Bug #4).
- **One writer**: the orchestrating session does the writes; advisory models do not.
- **Audit trail**: append a short note per card-walk to `docs/usability-pass-log-2026-05-08.md` (create when the first card is walked) — card name, ID, what changed, how it was reviewed (`+AI` Draft ID or direct edit), date.

## Hand-off to Anna

When a batch of cards is ready for re-review:
1. Note the batch in the audit log with the cards' URLs.
2. Ping Anna in Mattermost with the URL list.
3. Anna re-reviews per the loop in `feedback_anna_review_workflow.md`. Approve button bug per `project_wiki_ui_bugs_inventory.md` is a current step-4 blocker — track separately.
4. Iterate on cards Anna re-flags.
5. Mark the batch complete in the audit log when Anna approves.

## What this pass is NOT

- Not a content rewrite from scratch — preserve technically-correct material; transform the framing only.
- Not a Sandra-spec migration (the per-field IndexPublished/IndexSection sibling structure is separate; tracked under the existing port work).
- Not a Magi/MAGUS separation pass (still deferred per Lake's earlier prioritization).
- Not the auto-glossary tooltip build (separate seed at `project_glossary_tooltip_design.md`).
- Not the upstream-commit watcher build (separate seed at `project_upstream_commit_watcher_design.md`).
