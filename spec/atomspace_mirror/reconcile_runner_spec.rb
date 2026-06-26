# frozen_string_literal: true
#
# L6 APPLY LAYER specs (Lane A, Slice 6 Part 2a). Reconciler::Runner turns a pure plan into idempotent
# mirror_outbox writes + a mirror_reconcile_runs audit row. STANDALONE: an in-memory FakeOutbox (which
# faithfully resolves the proof-based orphan subquery), injected stub encoder/lookups/sidecar, and a
# fake run model -- no Decko boot, DB, or sidecar. The live SQL predicate resolvers are dev-gated;
# here every predicate is injected so the transaction / coalescing / relink logic is what's exercised.

require "ostruct"
require "json"
require_relative "../../mod/atomspace_mirror/lib/reconciler"

# create_row rescues ActiveRecord::RecordNotUnique; define a minimal stand-in so the rescue resolves.
module ActiveRecord; end unless defined?(ActiveRecord)
unless defined?(ActiveRecord::RecordNotUnique)
  class ActiveRecord::RecordNotUnique < StandardError; end
end

# An in-memory mirror_outbox: captures create!/update_all and answers the apply layer's queries
# (pluck/select/to_a/nested-where). Rows are symbol-keyed hashes.
class FakeOutbox
  attr_reader :creates, :update_calls

  def initialize(rows = [])
    @rows = rows.map(&:dup)
    @creates = []
    @update_calls = []
    @superseded_ids = []
  end

  def all_rows = @rows + @creates
  def mark_superseded(*ids) = @superseded_ids.concat(ids)

  def superseded_by_later_or_reconcile?(row)
    @superseded_ids.include?(row.is_a?(Hash) ? row[:id] : row.id)
  end

  def transaction = yield

  def create!(**attrs)
    raise ActiveRecord::RecordNotUnique, "dup #{attrs[:event_id]}" if all_rows.any? { |r| r[:event_id] == attrs[:event_id] }

    @creates << attrs
    attrs
  end

  def where(**cond) = Relation.new(self, [cond])

  def matching(conds) = all_rows.select { |r| conds.all? { |cond| match?(r, cond) } }

  def apply_update(conds, attrs)
    @update_calls << [conds, attrs]
    matching(conds).each { |r| r.merge!(attrs) }
  end

  def match?(row, cond)
    cond.all? do |k, v|
      case v
      when Relation then v.resolved_values.include?(row[k])
      when Array    then v.include?(row[k])
      else               row[k] == v
      end
    end
  end

  class Relation
    def initialize(store, conds, select_col: nil)
      @store = store
      @conds = conds
      @select_col = select_col
    end

    def where(**more) = Relation.new(@store, @conds + [more], select_col: @select_col)
    def select(col)   = Relation.new(@store, @conds, select_col: col)
    def pluck(col)    = @store.matching(@conds).map { |r| r[col] }
    def to_a          = @store.matching(@conds)
    def update_all(attrs) = @store.apply_update(@conds, attrs)
    def resolved_values   = @store.matching(@conds).map { |r| r[@select_col] }
  end
end

class FakeRun
  attr_reader :attrs

  def initialize(attrs) = (@attrs = attrs)
  def id = 555
  def update!(**a) = @attrs.merge!(a)
  def status = @attrs[:status]
  def remediated = @attrs[:remediated]
  def report_path = @attrs[:report_path]
end

class FakeRunModel
  attr_reader :created

  def initialize(detection: nil)
    @detection = detection
    @created = []
  end

  def find(_id) = @detection
  def create!(**attrs)
    run = FakeRun.new(attrs)
    @created << run
    run
  end
end

RSpec.describe Reconciler::Runner do
  let(:outbox) { FakeOutbox.new }
  let(:run_model) { FakeRunModel.new }

  # A stub encoder: the encoder itself is exhaustively tested in Part 1; here we only need a payload.
  def stub_encoder(raise_encoding: false)
    enc = Object.new
    enc.define_singleton_method(:encode) do |_action, **_kw|
      raise CardAtomEncoder::EncodingError, "corrupt" if raise_encoding

      [{ "atom" => "DeckoCard", "fields" => [["Id", 1]] }]
    end
    enc.define_singleton_method(:encode_reconcile_snapshot) do |_card, **_kw|
      [{ "atom" => "DeckoCard", "fields" => [["Id", 1]] }]
    end
    enc
  end

  def runner(**over)
    Reconciler::Runner.new(**{
      outbox: outbox, reconcile_run_model: run_model, clock: -> { :t }, actor: "ops",
      encoder: stub_encoder, pre_state_fn: ->(_a) { {} },
      card_lookup: ->(_id) { OpenStruct.new(id: 1) }, action_lookup: ->(_id) { Object.new },
      # default every live SQL predicate to a stub so no test touches a real connection
      in_flight_fn: ->(_c) { false }
    }.merge(over))
  end

  def creates_of(kind) = outbox.creates.select { |c| c[:event_kind] == kind }

  describe "#run_sweep! (stability gate, Fix 4)" do
    it "ABORTS an unstable detection run by default: no outbox writes, an 'aborted' run is recorded" do
      detection = OpenStruct.new(stable: false, report_path: "{}", drift_pg_only: 1, drift_space_only: 0, drift_mismatch: 0)
      run = runner(reconcile_run_model: FakeRunModel.new(detection: detection)).run_sweep!(7)
      expect(run.status).to eq("aborted")
      expect(outbox.creates).to be_empty
      expect(JSON.parse(run.report_path)["aborted"]).to match(/not stable/)
    end

    it "force: true remediates an unstable run" do
      detection = OpenStruct.new(stable: false, drift_pg_only: 1, drift_space_only: 0, drift_mismatch: 0,
                                 report_path: JSON.generate(pg_only_sample: [11], space_only_sample: [], mismatch_sample: []))
      rm = FakeRunModel.new(detection: detection)
      runner(reconcile_run_model: rm).run_sweep!(7, force: true)
      expect(creates_of("reconcile").map { |c| c[:card_id] }).to eq([11])
    end
  end

  describe "#run_sweep! (per-class remediation)" do
    let(:detection) do
      OpenStruct.new(stable: true, drift_pg_only: 1, drift_space_only: 1, drift_mismatch: 1,
                     report_path: JSON.generate(pg_only_sample: [11], space_only_sample: [99], mismatch_sample: [22]))
    end
    let(:sidecar) { double_sidecar }

    def double_sidecar
      s = Object.new
      s.define_singleton_method(:quarantined) { @q ||= [] }
      s.define_singleton_method(:quarantine_card_scoped_atoms) do |card_id|
        (@q ||= []) << card_id
        [{ "atom" => "DeckoCard", "fields" => [["Id", card_id]] }]
      end
      s
    end

    it "pg_only + mismatch -> fresh reconcile events; space_only -> sidecar quarantine; run recorded" do
      rm = FakeRunModel.new(detection: detection)
      run = runner(reconcile_run_model: rm, sidecar: sidecar).run_sweep!(3)
      expect(creates_of("reconcile").map { |c| c[:card_id] }).to contain_exactly(11, 22)
      expect(creates_of("reconcile").map { |c| c[:event_id] }).to all(match(/\Areconcile:card:\d+:555\z/))
      expect(sidecar.quarantined).to eq([99])
      expect(run.status).to eq("completed")
      expect(run.remediated).to eq(3)                    # 2 reconcile creates + 1 quarantine
      expect(JSON.parse(run.report_path)["quarantine_audit_sample"]).not_to be_empty
    end

    it "skips a same-card in-flight card (SkipInFlight is NOT counted as remediated)" do
      rm = FakeRunModel.new(detection: detection)
      run = runner(reconcile_run_model: rm, sidecar: sidecar, in_flight_fn: ->(c) { c == 11 }).run_sweep!(3)
      expect(creates_of("reconcile").map { |c| c[:card_id] }).to eq([22])   # 11 skipped, 22 created
      expect(run.remediated).to eq(2)                                       # mismatch(22) + quarantine(99)
    end
  end

  describe "#remediate_hook_lag! (Section 3 three-way -> writes)" do
    def gaps(list) = ->() { list }

    it "Tail -> a queued decko_action replay row with the reconstructed payload" do
      r = runner(gap_source: gaps([{ card_id: 5, action_id: 100 }]),
                 later_card_action_fn: ->(_c, _n) { false }, later_delivered_decko_fn: ->(_c, _n) { false })
      r.remediate_hook_lag!
      row = creates_of("decko_action").first
      expect(row).to include(event_id: "decko:action:100", action_id: 100, status: "queued")
      expect(row[:payload]).to eq("atoms" => [{ "atom" => "DeckoCard", "fields" => [["Id", 1]] }])
    end

    it "Tail with a pruned card_action -> alert, NO row inserted" do
      alerts = []
      r = runner(gap_source: gaps([{ card_id: 5, action_id: 100 }]), action_lookup: ->(_id) { nil },
                 alerter: ->(sig, *) { alerts << sig },
                 later_card_action_fn: ->(*) { false }, later_delivered_decko_fn: ->(*) { false })
      r.remediate_hook_lag!
      expect(outbox.creates).to be_empty
      expect(alerts).to include(:mirror_reconcile_action_pruned)
    end

    it "Tail with a corrupt encode -> a terminal 'failed' row (not a staleness hole)" do
      r = runner(gap_source: gaps([{ card_id: 5, action_id: 100 }]), encoder: stub_encoder(raise_encoding: true),
                 later_card_action_fn: ->(*) { false }, later_delivered_decko_fn: ->(*) { false })
      r.remediate_hook_lag!
      row = creates_of("decko_action").first
      expect(row).to include(status: "failed", error: "corrupt")
      expect(row[:payload]).to be_nil   # compacted out of the INSERT -> DB NULL
    end

    it "Case (a) -> a superseded_by_later row with nil payload (terminal-advance, never drained)" do
      r = runner(gap_source: gaps([{ card_id: 5, action_id: 100 }]),
                 later_card_action_fn: ->(*) { true }, later_delivered_decko_fn: ->(*) { true })
      r.remediate_hook_lag!
      row = creates_of("decko_action").first
      expect(row).to include(event_id: "decko:action:100", status: "superseded_by_later")
      expect(row[:payload]).to be_nil
    end
  end

  describe "#remediate_hook_lag! Case (b) coalescing (Codex req i)" do
    def two_same_card = ->() { [{ card_id: 5, action_id: 100 }, { card_id: 5, action_id: 101 }] }
    def case_b = { later_card_action_fn: ->(*) { true }, later_delivered_decko_fn: ->(*) { false } }

    it "two gaps for the same (card, run) -> ONE reconcile event + TWO awaiting rows linked to it" do
      runner(gap_source: two_same_card, **case_b).remediate_hook_lag!
      reconciles = creates_of("reconcile")
      awaitings = creates_of("decko_action")
      expect(reconciles.size).to eq(1)
      expect(reconciles.first[:event_id]).to eq("reconcile:card:5:555")
      expect(awaitings.map { |a| a[:action_id] }).to contain_exactly(100, 101)
      expect(awaitings.map { |a| a[:source_reconcile_event_id] }).to all(eq("reconcile:card:5:555"))
      expect(awaitings.map { |a| a[:status] }).to all(eq("awaiting_reconcile"))
    end

    it "a rerun whose awaiting rows already exist does NOT orphan a new reconcile (orphan prevention)" do
      existing = [
        { id: 1, event_kind: "decko_action", action_id: 100, status: "awaiting_reconcile", card_id: 5,
          event_id: "decko:action:100", source_reconcile_event_id: "reconcile:card:5:111", payload: nil },
        { id: 2, event_kind: "decko_action", action_id: 101, status: "awaiting_reconcile", card_id: 5,
          event_id: "decko:action:101", source_reconcile_event_id: "reconcile:card:5:111", payload: nil }
      ]
      ob = FakeOutbox.new(existing)
      runner(outbox: ob, gap_source: two_same_card, **case_b).remediate_hook_lag!
      expect(ob.creates).to be_empty   # both gaps already present + no orphans -> nothing written
    end
  end

  describe "fresh-reconcile RELINK of proven orphans (Codex req ii + Fix 1)" do
    # A terminal-failed reconcile and its orphaned, nil-payload failed awaiting row for the same card.
    let(:rows) do
      [
        { id: 10, event_kind: "reconcile", card_id: 5, status: "failed", event_id: "reconcile:card:5:001",
          action_id: nil, payload: nil },
        { id: 11, event_kind: "decko_action", card_id: 5, status: "failed", action_id: 100, payload: nil,
          event_id: "decko:action:100", source_reconcile_event_id: "reconcile:card:5:001", attempts: 5, error: "boom" },
        # a genuine encode-failure (source nil) MUST NOT be relinked
        { id: 12, event_kind: "decko_action", card_id: 5, status: "failed", action_id: 200, payload: nil,
          event_id: "decko:action:200", source_reconcile_event_id: nil, attempts: 5, error: "encode" }
      ]
    end

    it "a fresh sweep reconcile relinks ONLY the proven orphan -> awaiting, clearing stale error/attempts" do
      ob = FakeOutbox.new(rows)
      detection = OpenStruct.new(stable: true, drift_pg_only: 1, drift_space_only: 0, drift_mismatch: 0,
                                 report_path: JSON.generate(pg_only_sample: [5], space_only_sample: [], mismatch_sample: []))
      runner(outbox: ob, reconcile_run_model: FakeRunModel.new(detection: detection)).run_sweep!(9)

      relink = ob.update_calls.find { |(_c, attrs)| attrs[:status] == "awaiting_reconcile" }
      expect(relink).not_to be_nil
      _conds, attrs = relink
      expect(attrs).to include(status: "awaiting_reconcile", error: nil, attempts: 0)
      expect(attrs[:source_reconcile_event_id]).to eq("reconcile:card:5:555")
      # the orphan (id 11) relinked; the encode-failure (id 12) untouched
      expect(ob.all_rows.find { |r| r[:id] == 11 }[:status]).to eq("awaiting_reconcile")
      expect(ob.all_rows.find { |r| r[:id] == 12 }[:status]).to eq("failed")
    end
  end

  describe "#requeue_failed! (Option B resolution -> writes)" do
    it "superseded -> superseded_by_later; payload-present -> queued/attempts0; nil-payload -> HOLD (no write)" do
      rows = [
        { id: 1, payload_present: true },   # will be marked superseded
        { id: 2, payload_present: true },   # reset
        { id: 3, payload_present: false }   # hold (no write)
      ]
      ob = FakeOutbox.new([{ id: 1 }, { id: 2 }, { id: 3 }])
      ob.mark_superseded(1)
      alerts = []
      runner(outbox: ob, failed_rows_source: -> { rows }, alerter: ->(sig, *) { alerts << sig }).requeue_failed!

      by_id = ob.update_calls.to_h { |(conds, attrs)| [conds.first[:id], attrs] }
      expect(by_id[1]).to eq(status: "superseded_by_later")
      expect(by_id[2]).to eq(status: "queued", attempts: 0, error: nil)
      expect(by_id).not_to have_key(3)                 # nil-payload row never written
      expect(alerts).to include(:mirror_reconcile_hold)
    end
  end
end
