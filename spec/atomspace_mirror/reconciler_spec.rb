# frozen_string_literal: true
#
# L6 reconcile DECISION CORE specs (Lane A, Slice 6 Part 1). The planner is a PURE function over
# pre-resolved drift signals, so these run standalone -- plain Ruby hashes / Structs, NO Decko boot,
# DB, or sidecar. They pin the Section 3 three-way hook-lag branch, the sweep in-flight skip, the
# space_only -> quarantine mapping, and the Codex Option-B requeue resolution order.

require_relative "../../mod/atomspace_mirror/lib/reconciler"

RSpec.describe Reconciler do
  describe ".plan_hook_lag (Section 3 three-way branch on coverage-gap (C,N))" do
    def gap(card_id:, action_id:, later_card_action:, later_delivered_decko:)
      { card_id: card_id, action_id: action_id,
        later_card_action: later_card_action, later_delivered_decko: later_delivered_decko }
    end

    it "Tail (no later card_action) -> ReplayQueued: current state is post-N, replay it" do
      actions = described_class.plan_hook_lag(
        gaps: [gap(card_id: 5, action_id: 100, later_card_action: false, later_delivered_decko: false)],
        run_id: 7
      )
      expect(actions).to eq([Reconciler::ReplayQueued.new(card_id: 5, action_id: 100)])
    end

    it "Case (a) (later DELIVERED decko_action) -> SupersededByLater: Space already post-N" do
      actions = described_class.plan_hook_lag(
        gaps: [gap(card_id: 5, action_id: 100, later_card_action: true, later_delivered_decko: true)],
        run_id: 7
      )
      expect(actions).to eq([Reconciler::SupersededByLater.new(card_id: 5, action_id: 100)])
    end

    it "Case (b) (later card_action exists, none delivered) -> AwaitingWithReconcile carrying run_id" do
      actions = described_class.plan_hook_lag(
        gaps: [gap(card_id: 5, action_id: 100, later_card_action: true, later_delivered_decko: false)],
        run_id: 7
      )
      expect(actions).to eq([Reconciler::AwaitingWithReconcile.new(card_id: 5, action_id: 100, run_id: 7)])
    end

    it "Tail wins even when later_delivered_decko is (impossibly) set -- no later card_action dominates" do
      # later_delivered_decko cannot be true without later_card_action in real data, but the branch
      # must be unambiguous: the FIRST predicate (no later card_action) decides Tail regardless.
      actions = described_class.plan_hook_lag(
        gaps: [gap(card_id: 9, action_id: 1, later_card_action: false, later_delivered_decko: true)],
        run_id: 2
      )
      expect(actions).to eq([Reconciler::ReplayQueued.new(card_id: 9, action_id: 1)])
    end

    it "maps each gap independently, preserving order" do
      actions = described_class.plan_hook_lag(
        gaps: [
          gap(card_id: 1, action_id: 10, later_card_action: false, later_delivered_decko: false),
          gap(card_id: 2, action_id: 20, later_card_action: true,  later_delivered_decko: true),
          gap(card_id: 3, action_id: 30, later_card_action: true,  later_delivered_decko: false)
        ],
        run_id: 42
      )
      expect(actions.map(&:class)).to eq([
        Reconciler::ReplayQueued, Reconciler::SupersededByLater, Reconciler::AwaitingWithReconcile
      ])
    end

    it "an empty gap list yields no actions" do
      expect(described_class.plan_hook_lag(gaps: [], run_id: 1)).to eq([])
    end
  end

  describe ".plan_sweep (Mechanism 3 pg_only / mismatch / space_only)" do
    Diff = Struct.new(:pg_only, :space_only, :mismatch, keyword_init: true)

    let(:none_in_flight) { ->(_card_id) { false } }

    it "pg_only -> ReconcileCreate(reason: pg_only); mismatch -> ReconcileCreate(reason: mismatch)" do
      diff = Diff.new(pg_only: [11], space_only: [], mismatch: [22])
      actions = described_class.plan_sweep(diff: diff, run_id: 3, in_flight: none_in_flight)
      expect(actions).to contain_exactly(
        Reconciler::ReconcileCreate.new(card_id: 11, run_id: 3, reason: "pg_only"),
        Reconciler::ReconcileCreate.new(card_id: 22, run_id: 3, reason: "mismatch")
      )
    end

    it "space_only -> Quarantine, ALWAYS (never in-flight gated; an orphan has no forward path)" do
      diff = Diff.new(pg_only: [], space_only: [99], mismatch: [])
      always_in_flight = ->(_c) { true }
      actions = described_class.plan_sweep(diff: diff, run_id: 3, in_flight: always_in_flight)
      expect(actions).to eq([Reconciler::Quarantine.new(card_id: 99)])
    end

    it "a same-card queued/awaiting row in flight -> SkipInFlight for pg_only/mismatch (not space_only)" do
      diff = Diff.new(pg_only: [11], space_only: [99], mismatch: [22])
      in_flight = ->(card_id) { card_id == 11 }            # only card 11 has a forward row pending
      actions = described_class.plan_sweep(diff: diff, run_id: 3, in_flight: in_flight)
      expect(actions).to include(
        Reconciler::SkipInFlight.new(card_id: 11, reason: "pg_only: same-card queued/awaiting row in flight"),
        Reconciler::ReconcileCreate.new(card_id: 22, run_id: 3, reason: "mismatch"),
        Reconciler::Quarantine.new(card_id: 99)
      )
    end

    it "an all-clean diff yields no actions" do
      diff = Diff.new(pg_only: [], space_only: [], mismatch: [])
      expect(described_class.plan_sweep(diff: diff, run_id: 1, in_flight: none_in_flight)).to eq([])
    end
  end

  describe ".plan_requeue (drain-lag failed rows; Codex Option-B resolution order)" do
    def row(id:, payload_present:)
      { id: id, payload_present: payload_present }
    end

    it "(1) helper proves superseded -> RequeueSupersede (wins even for a payload-present row)" do
      superseded = ->(r) { r[:id] == 1 }
      actions = described_class.plan_requeue(rows: [row(id: 1, payload_present: true)], superseded: superseded)
      expect(actions).to eq([Reconciler::RequeueSupersede.new(row_id: 1)])
    end

    it "(2) nil-payload, not superseded -> RequeueHold (never reset to queued -> would fail validation)" do
      actions = described_class.plan_requeue(
        rows: [row(id: 2, payload_present: false)], superseded: ->(_r) { false }
      )
      expect(actions.first).to be_a(Reconciler::RequeueHold)
      expect(actions.first.row_id).to eq(2)
      expect(actions.first.reason).to match(/not redrivable/)
    end

    it "(3) payload-present, not superseded -> RequeueReset (redrive)" do
      actions = described_class.plan_requeue(
        rows: [row(id: 3, payload_present: true)], superseded: ->(_r) { false }
      )
      expect(actions).to eq([Reconciler::RequeueReset.new(row_id: 3)])
    end

    it "supersede takes precedence over the nil-payload hold (resolution order is strict)" do
      actions = described_class.plan_requeue(
        rows: [row(id: 4, payload_present: false)], superseded: ->(_r) { true }
      )
      expect(actions).to eq([Reconciler::RequeueSupersede.new(row_id: 4)])
    end

    it "accepts model-like rows responding to #id / #payload_present?" do
      model_row = Struct.new(:id, :payload_present?).new(7, false)
      actions = described_class.plan_requeue(rows: [model_row], superseded: ->(_r) { false })
      expect(actions).to eq([Reconciler::RequeueHold.new(row_id: 7, reason: actions.first.reason)])
    end
  end
end
