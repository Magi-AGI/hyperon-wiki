# frozen_string_literal: true
#
# L5 / Mechanism 3 drift sweep (Slice 5b). STANDALONE: fake sidecar + injected card source / lookup /
# drain-lag / max-action / pg-hash / run model -- no Decko, DB, or real sidecar. The canonical
# serializer parity itself is covered by canonical_projection_spec (Ruby) + the sidecar's Python test.

require "json"
require_relative "../../mod/atomspace_mirror/lib/drift_reconciler"

RSpec.describe DriftReconciler do
  FakeCard = Struct.new(:id, :hash_val)

  # capturing fake for MirrorReconcileRun
  class FakeRun
    attr_reader :attrs
    def initialize(attrs)
      @attrs = attrs
    end

    def id = 1
    def method_missing(name, *) = @attrs.fetch(name) { super }
    def respond_to_missing?(name, _ = false) = @attrs.key?(name)
  end

  let(:run_model) do
    Class.new do
      def self.last_created = @last
      def self.create!(**attrs)
        @last = FakeRun.new(attrs)
      end
    end
  end

  def sidecar(index:, card_projections: {})
    instance_double(SidecarClient).tap do |sc|
      allow(sc).to receive(:projection_index).and_return(index)
      allow(sc).to receive(:card_projection) { |id| card_projections.fetch(id) }
    end
  end

  def reconciler(sc, cards:, lookups: {}, lags: [0, 0], maxes: [100, 100])
    lag_seq = lags.dup
    max_seq = maxes.dup
    DriftReconciler.new(
      sidecar: sc, clock: -> { Time.utc(2026, 6, 24, 12, 0, 0) }, reconcile_run_model: run_model,
      card_source: -> { double(find_each: nil).tap { |d| allow(d).to receive(:find_each) { |&b| cards.each(&b) } } },
      card_lookup: ->(id) { lookups[id] },
      drain_lag_fn: ->(_a) { lag_seq.shift }, max_action_fn: -> { max_seq.shift },
      a_start_provider: -> { 0 }, pg_hash_fn: ->(card) { card.hash_val }
    )
  end

  it "diffs PG vs Space into pg_only / space_only / mismatch (stable run, no re-verify)" do
    sc = sidecar(index: { 2 => "h2", 3 => "hX", 4 => "h4" })
    cards = [FakeCard.new(1, "h1"), FakeCard.new(2, "h2"), FakeCard.new(3, "h3")]
    run = reconciler(sc, cards: cards).run!

    expect(run.attrs[:status]).to eq("completed")
    expect(run.stable).to be(true)
    expect(run.drift_pg_only).to eq(1)      # card 1 in PG, not Space
    expect(run.drift_space_only).to eq(1)   # card 4 in Space, not PG
    expect(run.drift_mismatch).to eq(1)     # card 3 hashes differ (h3 vs hX); card 2 matches
    expect(sc).not_to have_received(:card_projection)   # stable -> no per-card re-verify
    report = JSON.parse(run.report_path)
    expect(report).to include("stable" => true, "pg_only_sample" => [1], "mismatch_sample" => [3])
  end

  it "re-verifies by RECLASSIFYING from current state, not just filtering (Codex blocker)" do
    # initial diff: pg_only=[1,5], space_only=[4], mismatch=[3]
    sc = sidecar(
      index: { 3 => "hX", 4 => "hOld" },                 # space side at sweep time
      card_projections: {
        1 => { "present" => true, "sha256" => "h1" },     # card 1 drained, now MATCHES PG -> clean
        5 => { "present" => true, "sha256" => "hZ" },      # card 5 drained but WRONG hash -> becomes mismatch
        3 => { "present" => true, "sha256" => "hX" },      # card 3 still mismatches
        4 => { "present" => true, "sha256" => "hOld" }     # card 4 still Space-only (absent from PG below)
      }
    )
    cards = [FakeCard.new(1, "h1"), FakeCard.new(3, "h3"), FakeCard.new(5, "h5")]  # PG inventory (no 4)
    lookups = { 1 => FakeCard.new(1, "h1"), 3 => FakeCard.new(3, "h3"), 5 => FakeCard.new(5, "h5") } # 4 absent
    run = reconciler(sc, cards: cards, lookups: lookups, maxes: [100, 105]).run!  # writes during sweep

    expect(run.stable).to be(false)
    expect(run.attrs[:status]).to eq("unstable")
    expect(run.drift_pg_only).to eq(0)      # card 1 cleaned (drained + matches)
    expect(run.drift_space_only).to eq(1)   # card 4 still orphan
    expect(run.drift_mismatch).to eq(2)     # card 3 persists AND card 5 RECLASSIFIED pg_only -> mismatch
    expect(JSON.parse(run.report_path)["mismatch_sample"]).to eq([3, 5])
  end

  it "is unstable when drain lag is nonzero even if no writes occurred" do
    sc = sidecar(index: {}, card_projections: {})
    run = reconciler(sc, cards: [], lags: [3, 0]).run!   # drain lag 3 at start
    expect(run.stable).to be(false)
  end
end
