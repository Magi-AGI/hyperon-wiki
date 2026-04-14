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

  # ── Permission and visibility filtering ───────────────────────────────────

  describe "ok_nav_card? filtering" do
    it "checks read permission on every card" do
      expect(rb).to include(".ok?(:read)")
    end

    it "excludes trashed cards from queries" do
      expect(rb).to include("trash: false")
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
      # e.g. MyCard+*read, MyCard+*self
      expect(rb).to include(".right")
      expect(rb).to include('start_with?("*")')
    end
  end

  # ── Environment variable controls ─────────────────────────────────────────

  describe "environment variable controls" do
    it "reads WIKI_NAV_ROOT to set the tree's starting parent" do
      expect(rb).to include('ENV["WIKI_NAV_ROOT"]')
    end

    it "reads and clamps WIKI_NAV_ROOT_LIMIT" do
      expect(rb).to include("WIKI_NAV_ROOT_LIMIT")
      expect(rb).to include(".clamp(")
    end

    it "reads and clamps WIKI_NAV_CHILD_LIMIT" do
      expect(rb).to include("WIKI_NAV_CHILD_LIMIT")
      expect(rb).to include(".clamp(")
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
