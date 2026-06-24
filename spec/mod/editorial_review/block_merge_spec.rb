# frozen_string_literal: true

require "spec_helper"
require_relative "../../../mod/editorial_review/lib/block_merge"

# Pure-Ruby specs for the WS6 BlockMerge 3-way engine (needs nokogiri + diff-lcs,
# both bundled; no database).
RSpec.describe BlockMerge do
  def hunk_of(result, type)
    result[:chunks].find { |c| c[:type] == type }
  end

  describe "unchanged content" do
    it "is all stable and assembles back to the input" do
      html = "<p>A</p>\n<p>B</p>"
      res = described_class.merge(base: html, current: html, proposal: html, format: :html)
      expect(res[:chunks].map { |c| c[:type] }).to all(eq(:stable))
      expect(described_class.assemble(res)).to eq("<p>A</p>\n<p>B</p>")
    end
  end

  describe "AI-only insert (human-explicit default)" do
    let(:res) do
      described_class.merge(base: "<p>A</p>", current: "<p>A</p>",
                            proposal: "<p>A</p>\n<p>NEW</p>", format: :html)
    end

    it "classifies the insert as :ai_only" do
      expect(hunk_of(res, :ai_only)).not_to be_nil
    end

    it "does NOT auto-accept the AI insert by default" do
      expect(described_class.assemble(res)).to eq("<p>A</p>")
    end

    it "inserts only when the AI hunk is explicitly accepted" do
      id = hunk_of(res, :ai_only)[:id]
      merged = described_class.assemble(res, {id => :proposal})
      expect(merged).to eq("<p>A</p>\n<p>NEW</p>")
    end

    it "is idempotent" do
      expect(described_class.assemble(res)).to eq(described_class.assemble(res))
    end
  end

  describe "AI-only delete" do
    it "keeps the block by default, removes it when accepted" do
      res = described_class.merge(base: "<p>A</p>\n<p>B</p>", current: "<p>A</p>\n<p>B</p>",
                                  proposal: "<p>A</p>", format: :html)
      hunk = hunk_of(res, :ai_only)
      expect(hunk).not_to be_nil
      expect(described_class.assemble(res)).to include("<p>B</p>")
      expect(described_class.assemble(res, {hunk[:id] => :proposal})).to eq("<p>A</p>")
    end
  end

  describe "human-only change" do
    it "keeps the human edit by default" do
      res = described_class.merge(base: "<p>A</p>", current: "<p>HUMAN</p>",
                                  proposal: "<p>A</p>", format: :html)
      expect(hunk_of(res, :human_only)).not_to be_nil
      expect(described_class.assemble(res)).to eq("<p>HUMAN</p>")
    end
  end

  describe "both sides made the same change" do
    it "is :both_same and keeps the shared change" do
      res = described_class.merge(base: "<p>A</p>", current: "<p>SAME</p>",
                                  proposal: "<p>SAME</p>", format: :html)
      expect(hunk_of(res, :both_same)).not_to be_nil
      expect(described_class.assemble(res)).to eq("<p>SAME</p>")
    end
  end

  describe "conflict" do
    let(:res) do
      described_class.merge(base: "<p>A</p>", current: "<p>HUMAN</p>",
                            proposal: "<p>AI</p>", format: :html)
    end

    it "classifies as :conflict with no default selection" do
      h = hunk_of(res, :conflict)
      expect(h).not_to be_nil
      expect(res[:default_selection]).not_to have_key(h[:id])
    end

    it "refuses to assemble an unresolved conflict" do
      expect { described_class.assemble(res) }.to raise_error(/unresolved/)
    end

    it "assembles the chosen side when resolved" do
      h = hunk_of(res, :conflict)
      expect(described_class.assemble(res, {h[:id] => :proposal})).to eq("<p>AI</p>")
      expect(described_class.assemble(res, {h[:id] => :current})).to eq("<p>HUMAN</p>")
    end
  end

  describe "{{nest}} preservation" do
    it "keeps a nest intact through a merge that changes its block" do
      res = described_class.merge(base: "<p>see {{Glossary+X|core}}</p>",
                                  current: "<p>see {{Glossary+X|core}}</p>",
                                  proposal: "<p>see {{Glossary+X|core}} now</p>", format: :html)
      hunk = hunk_of(res, :ai_only)
      merged = described_class.assemble(res, {hunk[:id] => :proposal})
      expect(merged).to include("{{Glossary+X|core}}")
      expect(merged).not_to include(described_class::SENTINEL)
    end

    it "treats identical nests as equal (no false hunk)" do
      html = "<p>{{A}}</p>\n<p>{{B}}</p>"
      res = described_class.merge(base: html, current: html, proposal: html, format: :html)
      expect(res[:chunks].map { |c| c[:type] }).to all(eq(:stable))
    end
  end

  describe "Markdown atomic blocks" do
    it "keeps a table as a single block/hunk" do
      base = "intro\n\n| a | b |\n| - | - |\n| 1 | 2 |"
      proposal = "intro\n\n| a | b |\n| - | - |\n| 1 | 9 |"
      res = described_class.merge(base: base, current: base, proposal: proposal, format: :markdown)
      hunk = hunk_of(res, :ai_only)
      expect(hunk[:proposal].length).to eq(1)
      expect(hunk[:proposal].first).to include("| 1 | 9 |")
      expect(hunk[:proposal].first.lines.length).to eq(3)
    end

    it "keeps a fenced code block (with blank lines) as one block" do
      fenced = "```\nline1\n\nline2\n```"
      expect(described_class.tokenize_markdown(fenced).length).to eq(1)
    end
  end
end
