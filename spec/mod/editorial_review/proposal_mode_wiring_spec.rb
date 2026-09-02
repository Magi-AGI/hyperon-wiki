# frozen_string_literal: true

# CP006C FALLBACK source-wiring specs.
#
# WHY THIS EXISTS, AND WHAT IT IS NOT. The real coverage for these three
# enforcement points is DB-backed integration specs (render the workbench, POST
# crafted hunk_selections, apply a stale draft). Those cannot run in this
# environment: the local Windows Ruby toolchain has no make/gcc, native
# extension builds for json/bigdecimal fail on missing ruby.h, and `bundle
# check` still reports the locked Decko/Rails gems missing. So this file does
# something weaker but honest — it reads the source and asserts the fail-closed
# helper is actually WIRED IN, and wired in at the right point in each path.
#
# It proves ordering and presence. It does NOT prove runtime behavior. Treat a
# green run here as "the gate is installed where it should be", not as "the gate
# works". The behavioral guarantee comes from proposal_mode_spec.rb (pure, runs)
# plus integration specs once the toolchain is fixed.
#
# Deliberately requires no spec_helper so it runs without booting Rails.

RSpec.describe "CP006C fail-closed wiring" do
  MOD_ROOT = File.expand_path("../../../mod/editorial_review", __dir__)

  def source(relative)
    File.read(File.join(MOD_ROOT, relative))
  end

  # Index of the first occurrence, failing loudly rather than returning nil so a
  # renamed constant surfaces as a clear message instead of a nil comparison.
  def index_of(text, needle, label)
    idx = text.index(needle)
    raise "expected to find #{label} (#{needle.inspect}) in source" if idx.nil?

    idx
  end

  describe "the pure helper is available to the set files" do
    it "lives in the mod lib dir so Decko autoloads it by constant name" do
      expect(File).to exist(File.join(MOD_ROOT, "lib/proposal_mode.rb"))
    end

    it "is never require_relative'd from a set file" do
      # The merge_draft header documents the trap: the set loader has no stable
      # __FILE__, and a relative require silently drops the whole set.
      %w[set/right/proposal.rb set/right/merge_draft.rb].each do |f|
        expect(source(f)).not_to match(/require_relative.*proposal_mode/),
                                 "#{f} must let Decko autoload ProposalMode, not require_relative it"
      end
    end
  end

  describe "view :merge_workbench" do
    let(:text) { source("set/right/proposal.rb") }

    it "gates on the mode sidecar before building the workbench payload" do
      gate = index_of(text, "ProposalMode.for_proposal", "the mode gate")
      payload = index_of(text, "MergeWorkbench.build_payload", "the payload build")
      expect(gate).to be < payload
    end

    it "returns the blocked notice instead of the workbench shell" do
      gate = index_of(text, "ProposalMode.blocked_notice_html", "the blocked notice")
      shell = index_of(text, "merge_workbench_shell(payload)", "the workbench shell")
      expect(gate).to be < shell
    end

    it "places the gate inside view :merge_workbench, not some other view" do
      view_start = index_of(text, "view :merge_workbench do", "the merge_workbench view")
      gate = index_of(text, "ProposalMode.for_proposal", "the mode gate")
      expect(gate).to be > view_start
    end
  end

  describe "event :rederive_merge_draft" do
    let(:text) { source("set/right/merge_draft.rb") }

    it "gates before server-side assembly" do
      event = index_of(text, "event :rederive_merge_draft", "the seed event")
      gate = text.index("ProposalMode.for_proposal", event)
      assemble = index_of(text, "BlockMerge.merge", "server-side assembly")
      expect(gate).not_to be_nil, "seed event must gate on ProposalMode"
      expect(gate).to be < assemble
    end

    it "rejects the save rather than silently skipping" do
      # A bare `next` would let the client's own assembled content stand, which
      # is exactly the bypass this gate closes.
      event = index_of(text, "event :rederive_merge_draft", "the seed event")
      assemble = index_of(text, "BlockMerge.merge", "server-side assembly")
      window = text[event...assemble]
      expect(window).to include("errors.add(:proposal_mode")
    end
  end

  describe "event :apply_merge_draft" do
    let(:text) { source("set/right/merge_draft.rb") }

    it "gates before the audit lookup and before any parent write" do
      event = index_of(text, "event :apply_merge_draft", "the apply event")
      gate = text.index("ProposalMode.for_proposal", event)
      audit = text.index('audit = Card.fetch("#{name}+audit")', event)
      parent_write = text.index("parent.content = merged_content", event)

      expect(gate).not_to be_nil, "apply event must gate on ProposalMode"
      expect(audit).not_to be_nil
      expect(parent_write).not_to be_nil
      expect(gate).to be < audit
      expect(gate).to be < parent_write
    end

    it "rejects through the rollback helper so the act is rolled back" do
      event = index_of(text, "event :apply_merge_draft", "the apply event")
      audit = text.index('audit = Card.fetch("#{name}+audit")', event)
      window = text[event...audit]
      expect(window).to include("merge_apply_reject")
    end

    it "re-reads the sidecar at apply time rather than trusting seed time" do
      # A draft assembled while the proposal was full-replacement must not be
      # applicable after the mode is removed or changed, so the apply path needs
      # its own lookup, not a value carried in the draft audit.
      text_after_event = text[index_of(text, "event :apply_merge_draft", "the apply event")..]
      expect(text_after_event).to include("ProposalMode.for_proposal(proposal)")
    end
  end

  describe "scope discipline" do
    it "does not auto-create a mode sidecar anywhere in the mod" do
      # CP006C is enforcement, not bulk migration. Stamping
      # +mode=full-replacement on every proposal would encode a false claim for
      # packet-like proposals.
      Dir.glob(File.join(MOD_ROOT, "**/*.rb")).each do |path|
        body = File.read(path)
        expect(body).not_to match(/Card\.create!?\([^)]*\+mode/),
                            "#{path} must not auto-create a +mode sidecar"
      end
    end

    it "does not reintroduce in-body Proposal mode parsing" do
      Dir.glob(File.join(MOD_ROOT, "**/*.rb")).each do |path|
        body = File.read(path)
        expect(body).not_to match(/db_content.*=~.*Proposal mode|match.*\AProposal mode:/),
                            "#{path} must not parse an in-body Proposal mode marker"
      end
    end
  end
end
