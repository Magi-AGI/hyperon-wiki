# frozen_string_literal: true

require "rspec"

# These specs verify the behavioral contracts of wiki_nav_tree without
# requiring a live Decko database or Rails. They catch regressions when
# view definitions, permission guards, slotter wiring, or SCSS classes are
# accidentally modified or removed.
#
# Full rendering tests (card hierarchy, lazy-load expansion, active-ancestor
# highlighting) require a Decko test deck with seeded cards. See spec/TESTING.md
# for how to set one up.

MOD_ROOT = File.expand_path("../../mod", __dir__)

RSpec.describe "wiki_nav_tree mod" do
  let(:rb)   { File.read(File.join(MOD_ROOT, "wiki_nav_tree/set/all/wiki_nav_tree.rb")) }
  let(:scss) { File.read(File.join(MOD_ROOT, "wiki_nav_tree/assets/style/wiki_nav_tree.scss")) }

  # ── View definitions ──────────────────────────────────────────────────────

  describe "view definitions" do
    it "defines the primary wiki_nav_tree view" do
      expect(rb).to include("view :wiki_nav_tree")
    end

    it "defines wiki_nav_tree_branch for lazy branch loading" do
      expect(rb).to include("view :wiki_nav_tree_branch")
    end

    it "defines wiki_nav_tree_leaves for lazy Other group loading" do
      expect(rb).to include("view :wiki_nav_tree_leaves")
    end

    it "wraps the tree in a <nav> element with aria-label" do
      expect(rb).to include("wrap_with :nav")
      expect(rb).to include("aria-label")
    end
  end

  # ── Slotter / lazy-load wiring ────────────────────────────────────────────

  describe "slotter wiring" do
    it "marks expand links as slotter requests" do
      expect(rb).to include("slotter: true")
    end

    it "uses data-slot-selector to target the correct child container" do
      expect(rb).to include("data-slot-selector")
    end

    it "renders a placeholder div for the lazy children container" do
      expect(rb).to include("wiki-nav-children")
    end
  end

  # ── Active ancestor expansion ─────────────────────────────────────────────

  describe "active ancestor expansion" do
    it "detects ancestors of the current page" do
      expect(rb).to include("nav_ancestor_of_current?")
      expect(rb).to include("current_page_ancestors")
    end

    it "uses part_names to build the ancestor chain" do
      expect(rb).to include("part_names")
    end

    it "pre-expands ancestors with a downward triangle (▾)" do
      expect(rb).to include("▾")
    end

    it "applies a current-page CSS class to the active item" do
      expect(rb).to include("wiki-nav-item--current")
    end

    it "memoises the ancestor set to avoid recomputation per row" do
      expect(rb).to include("@current_page_ancestors")
    end

    it "guards against missing params with rescue" do
      expect(rb).to include("rescue")
    end
  end

  # ── Focus Mode (Ben's request) ────────────────────────────────────────────

  describe "Focus Mode" do
    it "reads nav_root from URL params" do
      expect(rb).to include("Env.params[:nav_root]")
    end

    it "falls back to WIKI_NAV_ROOT env var when no URL param" do
      expect(rb).to include('ENV["WIKI_NAV_ROOT"]')
    end

    it "shows a focus banner when a nav root is active" do
      expect(rb).to include("focus_banner")
    end

    it "provides a clear link to remove nav_root from the URL" do
      expect(rb).to include("✕ clear")
      expect(rb).to include("current_path_without")
    end

    it "renders a ⊙ focus button next to each nav item" do
      expect(rb).to include("⊙")
      expect(rb).to include("focus_mode_link")
    end

    it "skips focus button on the card that is already the root" do
      expect(rb).to include("nav_root_param == child.name")
    end
  end

  # ── Permission and visibility filtering ───────────────────────────────────

  describe "ok_nav_card? filtering" do
    it "checks read permission on every card" do
      expect(rb).to include(".ok?(:read)")
    end

    it "excludes trashed cards via c.trash check in ok_nav_card?" do
      expect(rb).to include("c.trash")
    end

    it "excludes Image and File type cards" do
      expect(rb).to include("Image")
      expect(rb).to include("File")
      expect(rb).to include("type_name")
    end

    it "excludes system cards (simple names starting with *)" do
      expect(rb).to include('start_with?("*")')
    end

    it "excludes rule-field compound cards (right side starting with *)" do
      expect(rb).to include(".right")
      expect(rb).to include('start_with?("*")')
    end
  end

  # ── Environment variable controls ─────────────────────────────────────────

  describe "environment variable controls" do
    it "reads and clamps WIKI_NAV_CHILD_LIMIT" do
      expect(rb).to include("WIKI_NAV_CHILD_LIMIT")
      expect(rb).to include(".clamp(")
    end
  end

  # ── Content-type filtering (root cards) ───────────────────────────────────

  describe "content-type root filtering" do
    it "whitelists content types (Draft, Published, RichText) — excludes Basic" do
      expect(rb).to include("Draft")
      expect(rb).to include("Published")
      expect(rb).to include("RichText")
      expect(rb).not_to match(/"Basic"/)
    end

    it "excludes system cards by filtering on codename: nil" do
      expect(rb).to include("codename: nil")
    end

    it "excludes rule-child cards via SQL join on right-card name not starting with *" do
      expect(rb).to include("right_c.name LIKE")
    end

    it "separates section cards (have children) from leaf cards" do
      expect(rb).to include("nav_section_cards")
      expect(rb).to include("card_ids_with_nav_children")
    end

    it "renders a lazy-loaded Other group for leaf content cards" do
      expect(rb).to include("render_other_group")
      expect(rb).to include("Other")
      expect(rb).to include("wiki_nav_tree_leaves")
    end

    it "Other group shows count of leaf cards in label" do
      expect(rb).to include("leaves.size")
    end
  end

  # ── DOM ID stability (used by slotter targeting) ──────────────────────────

  describe "DOM id generation" do
    it "generates per-card DOM ids for child containers" do
      expect(rb).to include("wiki-nav-ch-")
      expect(rb).to include("card.id")
    end
  end

  # ── SCSS contracts ────────────────────────────────────────────────────────

  describe "SCSS" do
    it "defines .wiki-nav-tree container" do
      expect(scss).to include(".wiki-nav-tree")
    end

    it "defines .wiki-nav-item row class" do
      expect(scss).to include(".wiki-nav-item")
    end

    it "defines .wiki-nav-expand toggle button class" do
      expect(scss).to include(".wiki-nav-expand")
    end

    it "hides empty child containers (no flash of empty space)" do
      expect(scss).to include(".wiki-nav-children:empty")
      expect(scss).to include("display: none")
    end
  end
end
