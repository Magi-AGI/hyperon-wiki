# frozen_string_literal: true
#
# L8 drain worker -- the stateful per-row transition (#process_row) + idle gating
# (#drain_one_iteration). STANDALONE: stubbed MirrorOutbox / MirrorState / Mirror + an injected
# SidecarClient (no Decko boot, no DB). The blocking advisory loop + real DB are dev-gated.

require_relative "../../mod/atomspace_mirror/lib/drain_worker"

RSpec.describe DrainWorker do
  # --- fakes ---------------------------------------------------------------------------------
  class DWRow
    attr_accessor :status, :attempts, :event_kind, :card_id, :action_id, :event_id, :payload,
                  :last_attempt_at, :error
    attr_reader :updates

    def initialize(**attrs)
      @attempts = 0
      @updates = []
      attrs.each { |k, v| public_send("#{k}=", v) }
    end

    def update!(**attrs)
      @updates << attrs
      attrs.each { |k, v| public_send("#{k}=", v) if respond_to?("#{k}=") }
      true
    end
  end

  class DWState
    attr_accessor :draining_enabled, :bootstrap_a_start, :last_drained_action_id
    attr_reader :updates

    def initialize(draining_enabled: true, bootstrap_a_start: 0)
      @draining_enabled = draining_enabled
      @bootstrap_a_start = bootstrap_a_start
      @updates = []
    end

    def update!(**attrs)
      @updates << attrs
      attrs.each { |k, v| instance_variable_set("@#{k}", v) }
      true
    end
  end

  class DWSidecar
    attr_reader :calls

    def initialize(outcome)
      @outcome = outcome
      @calls = []
    end

    def apply(payload)
      @calls << payload
      @outcome
    end
  end

  def outcome(kind, reason = "r") = DrainDelivery::Outcome.new(outcome: kind, reason: reason)

  # a MirrorOutbox stub: transaction yields; superseded? configurable; where().update_all + where().order().first captured
  def stub_outbox(superseded: false, queued_row: nil)
    releases = []
    klass = Class.new
    klass.define_singleton_method(:transaction) { |&blk| blk.call }
    klass.define_singleton_method(:superseded_by_later_or_reconcile?) { |_row| superseded }
    klass.define_singleton_method(:releases) { releases }
    klass.define_singleton_method(:where) do |**cond|
      rel = Object.new
      rel.define_singleton_method(:update_all) { |attrs| releases << [cond, attrs] }
      rel.define_singleton_method(:order) { |*_| Object.new.tap { |o| o.define_singleton_method(:first) { queued_row } } }
      rel
    end
    stub_const("MirrorOutbox", klass)
    klass
  end

  let(:alerts) { [] }
  let(:alerter) { ->(signal, row, msg) { alerts << [signal, row.event_id, msg] } }

  def worker(sidecar:, max_attempts: 3)
    DrainWorker.new(sidecar: sidecar, alerter: alerter, max_attempts: max_attempts, clock: -> { :t })
  end

  before do
    allow(Mirror).to receive(:compute_contiguous_watermark).and_return(77)
    # transition tests bypass the (separately, exhaustively tested) validator halves unless overridden
    allow(MirrorDrainValidator).to receive(:validate_row_shape!).and_return(nil)
    allow(MirrorDrainValidator).to receive(:validate_payload!).and_return(true)
  end

  def decko_row(**o)
    DWRow.new(**{ status: "queued", event_kind: "decko_action", card_id: 1, action_id: 50,
                  event_id: "decko:action:50", payload: { "atoms" => [] } }.merge(o))
  end

  describe "#process_row" do
    it "delivered: marks delivered, advances watermark, returns :delivered" do
      stub_outbox
      sc = DWSidecar.new(outcome(DrainDelivery::DELIVERED, "applied"))
      row = decko_row
      state = DWState.new
      expect(worker(sidecar: sc).process_row(row, state)).to eq(:delivered)
      expect(row.status).to eq("delivered")
      expect(sc.calls.size).to eq(1)
      expect(state.updates.last).to eq(last_drained_action_id: 77)
    end

    it "delivered reconcile: releases linked awaiting_reconcile rows in the same txn" do
      ob = stub_outbox
      sc = DWSidecar.new(outcome(DrainDelivery::DELIVERED, "applied"))
      row = decko_row(event_kind: "reconcile", action_id: nil, event_id: "decko:reconcile:9")
      worker(sidecar: sc).process_row(row, DWState.new)
      expect(ob.releases).to eq([[
        { event_kind: "decko_action", status: "awaiting_reconcile", card_id: 1,
          source_reconcile_event_id: "decko:reconcile:9" },
        { status: "superseded_by_reconcile" }
      ]])
      # the release is constrained to the reconcile's own card_id (cross-card rows can't be advanced)
      expect(ob.releases.first.first).to include(card_id: 1)
    end

    it "superseded: guard true -> superseded_by_later, NO IPC, watermark advanced" do
      stub_outbox(superseded: true)
      sc = DWSidecar.new(outcome(DrainDelivery::DELIVERED))
      row = decko_row
      expect(worker(sidecar: sc).process_row(row, DWState.new)).to eq(:superseded)
      expect(row.status).to eq("superseded_by_later")
      expect(sc.calls).to be_empty
    end

    it "invalid row shape -> failed locally before the guard, NO IPC" do
      stub_outbox
      allow(MirrorDrainValidator).to receive(:validate_row_shape!).and_raise(MirrorDrainValidator::InvalidRow, "bad shape")
      sc = DWSidecar.new(outcome(DrainDelivery::DELIVERED))
      row = decko_row
      expect(worker(sidecar: sc).process_row(row, DWState.new)).to eq(:invalid)
      expect(row.status).to eq("failed")
      expect(row.error).to match(/bad shape/)
      expect(sc.calls).to be_empty
      expect(alerts.map(&:first)).to include(:mirror_structural_invalid)
    end

    it "invalid payload (non-superseded) -> failed locally, NO IPC" do
      stub_outbox(superseded: false)
      allow(MirrorDrainValidator).to receive(:validate_payload!).and_raise(MirrorDrainValidator::InvalidRow, "corrupt payload")
      sc = DWSidecar.new(outcome(DrainDelivery::DELIVERED))
      row = decko_row
      expect(worker(sidecar: sc).process_row(row, DWState.new)).to eq(:invalid)
      expect(row.status).to eq("failed")
      expect(row.error).to match(/corrupt payload/)
      expect(sc.calls).to be_empty
    end

    it "supersedes an OBSOLETE row even when its payload is corrupt -- payload validation never runs, no IPC, no failed hole (Codex)" do
      stub_outbox(superseded: true)
      expect(MirrorDrainValidator).not_to receive(:validate_payload!)
      sc = DWSidecar.new(outcome(DrainDelivery::DELIVERED))
      row = decko_row
      state = DWState.new
      expect(worker(sidecar: sc).process_row(row, state)).to eq(:superseded)
      expect(row.status).to eq("superseded_by_later")
      expect(sc.calls).to be_empty
      expect(state.updates.last).to eq(last_drained_action_id: 77)
    end

    it "failed_terminal: sidecar rejection -> failed + alert" do
      stub_outbox
      sc = DWSidecar.new(outcome(DrainDelivery::FAILED_TERMINAL, "4xx rejected"))
      row = decko_row
      expect(worker(sidecar: sc).process_row(row, DWState.new)).to eq(:failed)
      expect(row.status).to eq("failed")
      expect(alerts.map(&:first)).to include(:mirror_drain_failed)
    end

    # Section 3 / Level 6 release-on-FAILURE: a terminal-failed RECONCILE must not strand its linked
    # awaiting_reconcile rows at :not_yet. They go to 'failed' (NOT superseded_by_reconcile, which would
    # falsely advance the watermark past unapplied actions).
    def reconcile_row(**o)
      decko_row(event_kind: "reconcile", action_id: nil, event_id: "reconcile:card:1:7", **o)
    end

    def failure_release(event_id = "reconcile:card:1:7")
      [{ event_kind: "decko_action", status: "awaiting_reconcile", card_id: 1, source_reconcile_event_id: event_id },
       { status: "failed", error: "linked reconcile #{event_id} failed terminally" }]
    end

    it "reconcile FAILED_TERMINAL: propagates linked awaiting rows to failed (watermark holds the hole)" do
      ob = stub_outbox
      sc = DWSidecar.new(outcome(DrainDelivery::FAILED_TERMINAL, "rejected"))
      expect(worker(sidecar: sc).process_row(reconcile_row, DWState.new)).to eq(:failed)
      expect(ob.releases).to include(failure_release)
    end

    it "reconcile retry-EXHAUSTED: also propagates linked awaiting rows to failed" do
      ob = stub_outbox
      sc = DWSidecar.new(outcome(DrainDelivery::RETRYABLE, "timeout"))
      expect(worker(sidecar: sc, max_attempts: 3).process_row(reconcile_row(attempts: 2), DWState.new)).to eq(:failed)
      expect(ob.releases).to include(failure_release)
    end

    it "reconcile INVALID payload (terminalized) also propagates the failure" do
      ob = stub_outbox
      allow(MirrorDrainValidator).to receive(:validate_payload!).and_raise(MirrorDrainValidator::InvalidRow, "bad")
      sc = DWSidecar.new(outcome(DrainDelivery::DELIVERED))
      expect(worker(sidecar: sc).process_row(reconcile_row, DWState.new)).to eq(:invalid)
      expect(ob.releases).to include(failure_release)
    end

    it "a failing decko_action row does NOT propagate (only reconcile rows release on failure)" do
      ob = stub_outbox
      sc = DWSidecar.new(outcome(DrainDelivery::FAILED_TERMINAL, "rejected"))
      worker(sidecar: sc).process_row(decko_row, DWState.new)
      expect(ob.releases).to be_empty
    end

    it "retryable below max: increments attempts, stays queued, no watermark advance" do
      stub_outbox
      sc = DWSidecar.new(outcome(DrainDelivery::RETRYABLE, "timeout"))
      row = decko_row(attempts: 0)
      state = DWState.new
      expect(worker(sidecar: sc, max_attempts: 3).process_row(row, state)).to eq(:retried)
      expect(row.status).to eq("queued")
      expect(row.attempts).to eq(1)
      expect(state.updates).to be_empty   # watermark not advanced for a still-queued row
    end

    it "retryable at max: terminalizes to failed + alert + watermark advance" do
      stub_outbox
      sc = DWSidecar.new(outcome(DrainDelivery::RETRYABLE, "timeout"))
      row = decko_row(attempts: 2)
      expect(worker(sidecar: sc, max_attempts: 3).process_row(row, DWState.new)).to eq(:failed)
      expect(row.status).to eq("failed")
      expect(row.attempts).to eq(3)
      expect(alerts.map(&:first)).to include(:mirror_drain_failed)
    end
  end

  describe "#drain_one_iteration idle gating" do
    it "is idle (true) when draining is disabled -- never fetches a row" do
      stub_outbox(queued_row: decko_row)
      stub_const("MirrorState", Class.new { define_singleton_method(:first) { DWState.new(draining_enabled: false) } })
      w = worker(sidecar: DWSidecar.new(outcome(DrainDelivery::DELIVERED)))
      expect(w.drain_one_iteration).to be(true)
    end

    it "is idle (true) when no queued row" do
      stub_outbox(queued_row: nil)
      stub_const("MirrorState", Class.new { define_singleton_method(:first) { DWState.new(draining_enabled: true) } })
      w = worker(sidecar: DWSidecar.new(outcome(DrainDelivery::DELIVERED)))
      expect(w.drain_one_iteration).to be(true)
    end

    it "processes (false=keep draining) when enabled and a row delivers" do
      stub_outbox(queued_row: decko_row)
      stub_const("MirrorState", Class.new { define_singleton_method(:first) { DWState.new(draining_enabled: true) } })
      sc = DWSidecar.new(outcome(DrainDelivery::DELIVERED, "applied"))
      expect(worker(sidecar: sc).drain_one_iteration).to be(false)
      expect(sc.calls.size).to eq(1)
    end

    it "backs off (true) on a retryable outage so drain_loop sleeps instead of tight-looping" do
      stub_outbox(queued_row: decko_row)
      stub_const("MirrorState", Class.new { define_singleton_method(:first) { DWState.new(draining_enabled: true) } })
      sc = DWSidecar.new(outcome(DrainDelivery::RETRYABLE, "timeout"))
      expect(worker(sidecar: sc, max_attempts: 3).drain_one_iteration).to be(true)
    end
  end
end
