# frozen_string_literal: true

require "spec_helper"
require_relative "../../../mod/editorial_review/lib/block_merge"
require_relative "../../../mod/editorial_review/lib/merge_workbench"

# Pure-Ruby specs for the WS6 Phase 4 payload builder (no database). Verifies the
# frozen schemaVersion-1 contract: verbatim hunk passthrough from BlockMerge,
# human-explicit defaults, conflict-must-choose, 2-way fallback, stable
# aggregation-with-content, and nest restoration for display.
RSpec.describe MergeWorkbench do
  def three_way_resolve(base)
    { tier: :verified, mode: :three_way, base_content: base, base_hash_ok: true,
      warning: nil, parent_id: 1, parent_name: "P" }
  end

  def build(resolve:, current:, proposal:, format: :html)
    described_class.build_payload(resolve: resolve, current: current, proposal: proposal,
                                  format: format, proposal_name: "P+proposal", parent_name: "P")
  end

  describe "3-way payload shape" do
    let(:payload) do
      build(resolve: three_way_resolve("<p>A</p>\n<p>B</p>"),
            current: "<p>A</p>\n<p>B</p>", proposal: "<p>A</p>\n<p>B2</p>")
    end

    it "is schemaVersion 1, three_way, verified" do
      expect(payload[:schemaVersion]).to eq(1)
      expect(payload[:mode]).to eq("three_way")
      expect(payload[:tier]).to eq("verified")
      expect(payload[:parent]).to eq("P")
    end

    it "classifies the changed block as ai_only with a current default" do
      hunk = payload[:hunks].find { |h| h[:type] == "ai_only" }
      expect(hunk).not_to be_nil
      expect(hunk[:default]).to eq("current")
      expect(payload[:selectionDefaults][hunk[:id]]).to eq("current")
      expect(payload[:counts][:ai_only]).to eq(1)
    end

    it "aggregates stable blocks WITH their content (for the client assembler)" do
      stable = payload[:hunks].find { |h| h[:type] == "stable" }
      expect(stable[:id]).to be_nil
      expect(stable[:count]).to be >= 1
      expect(stable[:current].join).to include("<p>A</p>")
    end
  end

  describe "conflict (must choose)" do
    let(:payload) do
      build(resolve: three_way_resolve("<p>A</p>"), current: "<p>HUMAN</p>", proposal: "<p>AI</p>")
    end

    it "emits a conflict hunk with no default and absent from selectionDefaults" do
      hunk = payload[:hunks].find { |h| h[:type] == "conflict" }
      expect(hunk).not_to be_nil
      expect(hunk[:default]).to be_nil
      expect(payload[:selectionDefaults]).not_to have_key(hunk[:id])
      expect(payload[:counts][:conflict]).to eq(1)
    end
  end

  describe "2-way fallback (stale / no base)" do
    let(:payload) do
      build(resolve: { tier: :stale, mode: :two_way, base_content: nil, warning: "bad base" },
            current: "<p>A</p>\n<p>B</p>", proposal: "<p>A</p>\n<p>B</p>\n<p>C</p>")
    end

    it "is two_way, surfaces the resolver warning, and never yields human_only" do
      expect(payload[:mode]).to eq("two_way")
      expect(payload[:warning]).to eq("bad base")
      expect(payload[:hunks].any? { |h| h[:type] == "human_only" }).to be(false)
    end
  end

  describe "nest restoration" do
    let(:payload) do
      build(resolve: three_way_resolve("<p>see {{G+X|core}}</p>"),
            current: "<p>see {{G+X|core}}</p>", proposal: "<p>see {{G+X|core}} now</p>")
    end

    it "shows restored nests and leaks no sentinels anywhere in the payload" do
      hunk = payload[:hunks].find { |h| h[:type] == "ai_only" }
      expect(hunk[:proposal].join).to include("{{G+X|core}}")
      expect(payload.to_s).not_to include(BlockMerge::SENTINEL)
    end
  end

  describe ".to_island_json" do
    it "neutralizes every embedded </ (so content can't close the <script> island) yet stays lossless" do
      payload = build(resolve: three_way_resolve("<p>A</p>"),
                      current: "<p>A</p>", proposal: "<p>A</p>\n<p>B</p>")
      raw = JSON.generate(payload)
      json = described_class.to_island_json(payload)
      expect(raw).to include("</p>")          # the hazard exists in the naive form
      expect(json).not_to include("</")       # ...and is fully neutralized
      expect(json).to include("<\\/p>")
      expect(JSON.parse(json)).to eq(JSON.parse(raw)) # \/ is a valid escape -> lossless
    end
  end
end
