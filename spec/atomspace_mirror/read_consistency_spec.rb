# frozen_string_literal: true
#
# Behavioral specs for ReadConsistency.check_event_ready (Lane A, Slice 1; L7 / Card 17120
# Section 4). Covers every readiness and corruption path of the event-kind-first algorithm.
#
# REQUIRES: the Decko test DB with mod/atomspace_mirror migrations applied
# (RAILS_ENV=test decko update). DB-gated.
#
# Reachable states are persisted as real rows. States the OQ#12 CHECK constraints make unreachable
# in PostgreSQL (a decko_action with NULL action_id; a reconcile with non-NULL action_id) are
# exercised via in-memory rows + a stubbed find_by, since the read path must still fail closed if a
# raw write or a non-PG dev DB bypasses the CHECKs.

require "spec_helper"

RSpec.describe ReadConsistency, type: :model do
  def queue(event_kind: "decko_action", action_id: 1, card_id: 1, status: "queued",
            event_id: nil, source_reconcile_event_id: nil)
    suffix = action_id || SecureRandom.hex(4)
    MirrorOutbox.create!(
      event_id: event_id || "#{event_kind}:#{card_id}:#{suffix}:#{SecureRandom.hex(3)}",
      event_kind: event_kind, action_id: action_id, card_id: card_id, status: status,
      source_reconcile_event_id: source_reconcile_event_id
    )
  end

  def ready(event_id)
    described_class.check_event_ready(event_id)
  end

  it "returns :not_yet_inserted for an unknown event_id" do
    expect(ready("decko:action:nope")).to eq(:not_yet_inserted)
  end

  context "decko_action rows" do
    it ":ready when delivered" do
      expect(ready(queue(status: "delivered").event_id)).to eq(:ready)
    end

    it ":ready when superseded_by_bootstrap" do
      expect(ready(queue(status: "superseded_by_bootstrap").event_id)).to eq(:ready)
    end

    it ":not_yet when queued" do
      expect(ready(queue(status: "queued").event_id)).to eq(:not_yet)
    end

    it ":not_yet when awaiting_reconcile" do
      expect(ready(queue(status: "awaiting_reconcile").event_id)).to eq(:not_yet)
    end

    it ":failed when failed" do
      expect(ready(queue(status: "failed").event_id)).to eq(:failed)
    end

    it ":integrity_error on an unknown status" do
      expect(ready(queue(status: "bogus").event_id)).to eq(:integrity_error)
    end

    context "superseded_by_later" do
      it ":ready when the shared helper proves supersession" do
        r = queue(action_id: 100, card_id: 7, status: "superseded_by_later")
        queue(action_id: 101, card_id: 7, status: "delivered")
        expect(ready(r.event_id)).to eq(:ready)
      end

      it ":not_yet when the helper finds no proof" do
        r = queue(action_id: 100, card_id: 7, status: "superseded_by_later")
        expect(ready(r.event_id)).to eq(:not_yet)
      end
    end

    context "superseded_by_reconcile" do
      # Persist a primary decko_action linked to a reconcile event. reconcile_status: nil skips
      # inserting the reconcile row (the missing-linked case).
      def primary_with_reconcile(reconcile_status:, link: "reconcile:card:7:run1", reconcile_card_id: 7)
        r = queue(action_id: 100, card_id: 7, status: "superseded_by_reconcile",
                  source_reconcile_event_id: link)
        if reconcile_status
          queue(event_kind: "reconcile", action_id: nil, card_id: reconcile_card_id,
                status: reconcile_status, event_id: link)
        end
        r
      end

      it ":ready when the linked reconcile is delivered (same card, NULL action_id)" do
        expect(ready(primary_with_reconcile(reconcile_status: "delivered").event_id)).to eq(:ready)
      end

      it ":failed when the linked reconcile is failed" do
        expect(ready(primary_with_reconcile(reconcile_status: "failed").event_id)).to eq(:failed)
      end

      it ":not_yet when the linked reconcile is still queued" do
        expect(ready(primary_with_reconcile(reconcile_status: "queued").event_id)).to eq(:not_yet)
      end

      it ":integrity_error when the linked reconcile has a corrupt status (awaiting_reconcile)" do
        expect(ready(primary_with_reconcile(reconcile_status: "awaiting_reconcile").event_id)).to eq(:integrity_error)
      end

      it ":integrity_error when the linked reconcile is for a different card" do
        expect(ready(primary_with_reconcile(reconcile_status: "delivered", reconcile_card_id: 99).event_id)).to eq(:integrity_error)
      end

      it ":integrity_error when source_reconcile_event_id is blank" do
        r = queue(action_id: 100, card_id: 7, status: "superseded_by_reconcile",
                  source_reconcile_event_id: nil)
        expect(ready(r.event_id)).to eq(:integrity_error)
      end

      it ":integrity_error when the linked reconcile row is missing" do
        expect(ready(primary_with_reconcile(reconcile_status: nil).event_id)).to eq(:integrity_error)
      end

      it ":integrity_error when the linked reconcile has a non-NULL action_id (CHECK-bypassed; stubbed)" do
        link = "reconcile:card:7:runX"
        r = queue(action_id: 100, card_id: 7, status: "superseded_by_reconcile",
                  source_reconcile_event_id: link)
        corrupt = MirrorOutbox.new(event_kind: "reconcile", action_id: 5, card_id: 7,
                                   status: "delivered", event_id: link)
        allow(MirrorOutbox).to receive(:find_by).and_call_original
        allow(MirrorOutbox).to receive(:find_by).with(event_id: link).and_return(corrupt)
        expect(ready(r.event_id)).to eq(:integrity_error)
      end
    end
  end

  context "reconcile rows (primary)" do
    it ":ready when delivered" do
      expect(ready(queue(event_kind: "reconcile", action_id: nil, status: "delivered").event_id)).to eq(:ready)
    end

    it ":failed when failed" do
      expect(ready(queue(event_kind: "reconcile", action_id: nil, status: "failed").event_id)).to eq(:failed)
    end

    it ":not_yet when queued" do
      expect(ready(queue(event_kind: "reconcile", action_id: nil, status: "queued").event_id)).to eq(:not_yet)
    end

    it ":integrity_error at a decko_action-only status (superseded_by_bootstrap)" do
      expect(ready(queue(event_kind: "reconcile", action_id: nil, status: "superseded_by_bootstrap").event_id)).to eq(:integrity_error)
    end

    it ":integrity_error at awaiting_reconcile (decko_action-only)" do
      expect(ready(queue(event_kind: "reconcile", action_id: nil, status: "awaiting_reconcile").event_id)).to eq(:integrity_error)
    end
  end

  context "unknown event_kind (persistable: no value CHECK on event_kind)" do
    it ":integrity_error" do
      expect(ready(queue(event_kind: "weird", action_id: 1, status: "delivered").event_id)).to eq(:integrity_error)
    end
  end

  context "structurally corrupt rows the OQ#12 CHECKs block (in-memory + stubbed find_by)" do
    it ":integrity_error for a decko_action with NULL action_id" do
      corrupt = MirrorOutbox.new(event_kind: "decko_action", action_id: nil, card_id: 1, status: "delivered")
      allow(MirrorOutbox).to receive(:find_by).with(event_id: "x").and_return(corrupt)
      expect(ready("x")).to eq(:integrity_error)
    end

    it ":integrity_error for a reconcile with a non-NULL action_id" do
      corrupt = MirrorOutbox.new(event_kind: "reconcile", action_id: 9, card_id: 1, status: "delivered")
      allow(MirrorOutbox).to receive(:find_by).with(event_id: "y").and_return(corrupt)
      expect(ready("y")).to eq(:integrity_error)
    end
  end
end
