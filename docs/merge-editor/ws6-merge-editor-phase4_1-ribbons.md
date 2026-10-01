# WS6 Phase 4.1 — P4Merge Bézier ribbons + resizable bands (design note)

**Status:** PROPOSAL — confirm the layout approach before coding the ribbon layer.
**Scope:** presentation ONLY. Per Codex: no change to the hunk payload, selection
semantics, or `BlockMerge.assemble`. The §3/§4 contract is untouched; this is a rendering
upgrade over the identical data.

## The tension to resolve

The thin cut renders all panes in **one CSS grid** where a hunk's Base/Current/Proposal
cells share a single grid row. That gives perfect alignment + free synced scroll — but it
forces corresponding cells to the **same height and y-position**, so connector ribbons would
be **flat**. The P4Merge look Lake wants — *"resizable highlighted sections bounded in the
middle by bézier curves that animate to fit the different dimensions"* — only exists when the
same block occupies **different vertical extents** across panes. Those differences are real
and common: a proposal block of 3 lines vs a current block of 1 line, an insert (content on
one side, empty on the other), a delete, or a user-resized band.

## Recommended approach — "independent-height hunk slots" (Option B)

- **Stable runs** stay as today: collapsed, full-width, perfectly aligned (anchors).
- **Changed hunks** become a *slot* spanning the three panes. Within a slot each pane's block
  takes its **natural height**, top-anchored at the slot top. The slot's height = max(pane
  heights). After the slot, all panes re-align at the next boundary — so global alignment is
  preserved at every hunk/stable boundary (synced scroll still "just works" because it's still
  one scroll container; only *within* a slot do panes diverge).
- **Ribbons:** a single absolute-positioned SVG overlay over the grid viewport (per Gemini —
  not per-row SVGs). For each changed slot, draw a closed Bézier ribbon in each gutter
  connecting the left block's [top,bottom] edge to the right block's [top,bottom] edge. When
  the two heights differ, the top and bottom curves fan apart → the signature P4Merge bend.
  Insert/delete (empty on one side) collapse the ribbon to a point on the empty side (a
  triangle/wedge), which reads as "added here" / "removed here".
- **Coordinates:** JS reads `getBoundingClientRect()` of the block elements relative to the
  grid-viewport wrapper and rewrites the SVG `<path d="M…C…">` strings. Recompute on:
  scroll (rAF-throttled), window resize/zoom (debounced), selection change, and band resize.
- **Resizable bands:** a drag handle on each pane's block lets the user grow/shrink that
  pane's block height independently; the slot height and ribbons recompute live — this is
  where "animate to fit the different dimensions" becomes interactive.

### Why not keep the strict grid (Option A)

Keeping one shared row per hunk keeps things simplest but yields only flat connectors — it
does **not** deliver the curves Lake asked for. Resizing a shared grid row grows all three
cells together (no mismatch), so even resize wouldn't bend anything. Option A is the fallback
if Option B proves too heavy, but it abandons the signature look.

## Constraints carried in (reviewers)

- **No payload/selection/assembler change** (Codex). Pure presentation.
- **Non-semantic animation** (Codex): hunk type + selected side stay fully conveyed by text +
  label/icon + color + keyboard focus. The tool must be 100% usable with ribbons disabled —
  the thin-cut DOM/controls remain the source of truth; ribbons are an overlay on top.
- **Single SVG overlay, getBoundingClientRect redraw, debounced resize handling, graceful
  degradation to flat color-bands** if SVG math fails or in a low-resource context (Gemini).
- **Reduced-motion fallback** (Codex): under `prefers-reduced-motion`, ribbons render
  statically (no transition animation); positions still update on scroll/resize but without
  tweening.
- **Re-run the jsdom + Chromium checks after 4.1** (Codex) and the :3001 HTTP click-through;
  ribbons must not regress any thin-cut behavior.

## Risk / fallback

Independent-height slots are more JS than the thin cut. Mitigation: build behind the existing
proven DOM — the grid/cells/controls stay; the slot heights + SVG overlay are layered on. If
the overlay errors, catch → hide the SVG → fall back to the flat thin-cut presentation (which
is already verified). So the worst case is "looks like the thin cut," never broken.
