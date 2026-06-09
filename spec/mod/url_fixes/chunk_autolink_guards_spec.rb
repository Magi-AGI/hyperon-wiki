# frozen_string_literal: true

require "spec_helper"
require_relative "../../../mod/url_fixes/lib/chunk_autolink_guards"

# Unit tests for the URI/Host/Email auto-link guards (T9).
#
# Decko's chunk auto-linker (card-mod-content) had two failure modes reported in
# the field (MCP feedback log 2026-06-09):
#   1. It re-linkified URL/email text already inside an authored <a> on every
#      render (context_ok? only inspected 2 preceding chars), nesting anchors
#      up to ~13 levels deep in stored content as the editor round-tripped them.
#   2. HostUri linkified schemeless bare source-filenames (nace.py, foo.rs) into
#      http:// URLs because its ccTLD list overlaps code extensions.
#
# ChunkAutolinkGuards is prepended to Card::Content::Chunk::Uri.singleton_class
# and adds two context_ok? rejections.
RSpec.describe ChunkAutolinkGuards do
  # Minimal stand-in for a Decko chunk class: a base (super) context_ok? that
  # always passes, with the guards prepended on top — mirrors the real wiring.
  let(:guarded) do
    Class.new do
      def self.context_ok?(_content, _chunk_start)
        true
      end
      singleton_class.prepend ChunkAutolinkGuards
    end
  end

  describe ".inside_anchor?" do
    it "is true when the position is inside an open <a>" do
      content = %(before <a href="x">click here)
      expect(guarded.inside_anchor?(content, content.index("click"))).to be true
    end

    it "is false once the anchor has closed" do
      content = %(<a href="x">click</a> then http://foo.com)
      expect(guarded.inside_anchor?(content, content.index("http"))).to be false
    end

    it "is false when there is no anchor at all" do
      expect(guarded.inside_anchor?("just http://foo.com here", 5)).to be false
    end
  end

  describe ".schemeless_code_filename?" do
    it "matches a bare source filename (nace.py)" do
      content = "see nace.py here"
      expect(guarded.schemeless_code_filename?(content, content.index("nace"))).to be true
    end

    it "matches the host-shaped tail of airis_stable.py (stable.py)" do
      expect(guarded.schemeless_code_filename?("stable.py", 0)).to be true
    end

    it "does not match a real domain whose TLD is not a code extension" do
      expect(guarded.schemeless_code_filename?("docs.asichain.io/docs", 0)).to be false
    end

    it "does not match when preceded by a path slash (part of a URL)" do
      content = "http://x/nace.py"
      expect(guarded.schemeless_code_filename?(content, content.index("nace"))).to be false
    end
  end

  describe ".context_ok?" do
    it "rejects a match inside an existing anchor (anti-nesting)" do
      content = %(<a class="external-link" href="http://x.io">x.io</a>)
      expect(guarded.context_ok?(content, content.index("x.io"))).to be false
    end

    it "rejects a schemeless source-filename match" do
      content = "open nace.py please"
      expect(guarded.context_ok?(content, content.index("nace"))).to be false
    end

    it "allows a real scheme URL" do
      content = "go to https://example.com/path now"
      expect(guarded.context_ok?(content, content.index("https"))).to be true
    end

    it "allows a real bare domain" do
      content = "visit docs.asichain.io/docs today"
      expect(guarded.context_ok?(content, content.index("docs"))).to be true
    end

    it "defers to super (returns false when the base rejects)" do
      base_rejects = Class.new do
        def self.context_ok?(_content, _chunk_start)
          false
        end
        singleton_class.prepend ChunkAutolinkGuards
      end
      expect(base_rejects.context_ok?("anything", 0)).to be false
    end
  end
end
