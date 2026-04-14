# frozen_string_literal: true

require "rspec"

# Structural / behavioral contracts for the hyperon_ui mod.
# No Rails or Decko database required — all assertions are source-text checks.
#
# Track 1 tests: fast regression guards that run in ~ms.
# Track 4 (visual checklist) is in README.md under # TESTING.

HYPERON_UI_ROOT = File.expand_path("../../mod/hyperon_ui", __dir__)

RSpec.describe "hyperon_ui mod" do
  # ── account_links.rb ────────────────────────────────────────────────────────

  describe "account_links override (set/self/)" do
    let(:src) { File.read(File.join(HYPERON_UI_ROOT, "set/self/account_links.rb")) }

    it "overrides sign_in label" do
      expect(src).to include("sign_in:")
      expect(src).to include("Login")
    end

    it "overrides sign_out label" do
      expect(src).to include("sign_out:")
      expect(src).to include("Logout")
    end

    it "overrides sign_up label" do
      expect(src).to include("sign_up:")
      expect(src).to include("Register")
    end

    it "falls back to super for unknown purposes" do
      expect(src).to include("super")
    end

    it "overrides account_dropdown_label with Account emoji" do
      expect(src).to include("account_dropdown_label")
      expect(src).to include("Account")
      expect(src).to include("link_to_mycard")
    end
  end

  # ── layouts.rb ───────────────────────────────────────────────────────────────

  # Note: the two-sidebar HTML structure (body.wiki-layout, #sidebar-left,
  # #sidebar-right) lives in the "Left Sidebar Layout" database card, not here.
  # This file only defines view :page_sidebar, which that layout card invokes
  # via {{_main|page_sidebar}}.

  describe "page_sidebar view (set/all/layouts.rb)" do
    let(:src) { File.read(File.join(HYPERON_UI_ROOT, "set/all/layouts.rb")) }

    it "defines the page_sidebar composition view" do
      expect(src).to include("view :page_sidebar")
    end

    it "composes breadcrumbs and page_toc into page_sidebar" do
      expect(src).to include(":breadcrumbs")
      expect(src).to include(":page_toc")
    end

    it "filters blank parts so empty views produce no whitespace" do
      expect(src).to include("reject(&:blank?)")
    end
  end

  # ── page_sidebar.rb ───────────────────────────────────────────────────────────

  describe "right sidebar views (set/all/page_sidebar.rb)" do
    let(:src) { File.read(File.join(HYPERON_UI_ROOT, "set/all/page_sidebar.rb")) }

    describe "breadcrumbs" do
      it "defines the breadcrumbs view" do
        expect(src).to include("view :breadcrumbs")
      end

      it "uses part_names for hierarchy" do
        expect(src).to include("part_names")
      end

      it "returns blank for top-level (single-part) cards" do
        expect(src).to include("parts.size <= 1")
      end

      it "uses Bootstrap breadcrumb classes" do
        expect(src).to include("breadcrumb-item")
        expect(src).to include("breadcrumb")
      end

      it "marks the last crumb as active with aria-current" do
        expect(src).to include("active")
        expect(src).to include("aria-current")
      end
    end

    describe "page TOC" do
      it "defines the page_toc view" do
        expect(src).to include("view :page_toc")
      end

      it "uses Nokogiri to parse rendered content" do
        expect(src).to include("Nokogiri")
      end

      it "extracts h2, h3, h4 headings" do
        expect(src).to include("h2, h3, h4")
      end

      it "returns blank when no headings found" do
        expect(src).to include("headings.empty?")
      end

      it "slugifies headings without id attributes" do
        expect(src).to include("slugify")
      end
    end
  end

  # ── theme_toggle.js.coffee ────────────────────────────────────────────────────

  describe "theme toggle script" do
    let(:src) { File.read(File.join(HYPERON_UI_ROOT, "assets/script/theme_toggle.js.coffee")) }

    it "reads and writes localStorage for persistence" do
      expect(src).to include("localStorage")
      expect(src).to include("getItem")
      expect(src).to include("setItem")
    end

    it "applies data-bs-theme attribute on html element" do
      expect(src).to include("data-bs-theme")
      expect(src).to include("documentElement")
    end

    it "targets the #theme-toggle button" do
      expect(src).to include("theme-toggle")
    end

    it "detects system prefers-color-scheme as default" do
      expect(src).to include("prefers-color-scheme")
    end

    it "toggles between dark and light" do
      expect(src).to include('"dark"')
      expect(src).to include('"light"')
    end
  end

  # ── hyperon_ui.scss ──────────────────────────────────────────────────────────

  describe "stylesheet" do
    let(:scss) { File.read(File.join(HYPERON_UI_ROOT, "assets/style/hyperon_ui.scss")) }

    it "defines CSS custom properties for navbar height and sidebar width" do
      expect(scss).to include("--navbar-h")
      expect(scss).to include("--sidebar-w")
    end

    it "uses CSS Grid for the wiki-layout body class" do
      expect(scss).to include("body.wiki-layout")
      expect(scss).to include("display: grid")
      expect(scss).to include("grid-template-areas")
    end

    it "defines grid areas for all four layout zones" do
      expect(scss).to include("header")
      expect(scss).to include("left")
      expect(scss).to include("main")
      expect(scss).to include("right")
      expect(scss).to include("footer")
    end

    it "makes both sidebars sticky with independent scroll" do
      expect(scss).to include("position: sticky")
      expect(scss).to include("overflow-y: auto")
    end

    it "collapses sidebars on mobile with a media query" do
      expect(scss).to include("max-width")
      expect(scss).to include("display: none")
    end

    it "defines dark mode overrides under data-bs-theme selector" do
      expect(scss).to include('[data-bs-theme="dark"]')
    end

    it "preserves the full-screen modal styles" do
      expect(scss).to include("modal-full")
      expect(scss).to include("100vw")
      expect(scss).to include("100vh")
    end
  end

  # ── edit_modal.rb ────────────────────────────────────────────────────────────

  describe "edit_modal" do
    let(:src) { File.read(File.join(HYPERON_UI_ROOT, "set/all/edit_modal.rb")) }

    it "sets modal size to full" do
      expect(src).to include(":full")
      expect(src).to include("edit_modal_size")
    end
  end
end
