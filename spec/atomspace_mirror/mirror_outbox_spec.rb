# frozen_string_literal: true
#
# Helper specs for MirrorOutbox.superseded_by_later_or_reconcile? (Lane A, Slice 1; Card 17120
# Section 10). Maps to the Section 11 Layer-3 / Level 11 Layer-4 helper test list.
#
# REQUIRES: the Decko test DB with mod/atomspace_mirror migrations applied
# (RAILS_ENV=test decko update). DB-gated.

require "spec_helper"

RSpec.describe MirrorOutbox, type: :model do
  # Persist a structurally-valid outbox row. decko_action rows carry an action_id; reconcile rows
  # do not (the OQ#12 CHECK constraints enforce this, so everything persisted here is valid).
  def queue(event_kind: "decko_action", action_id: 1, card_id: 1, status: "queued")
    suffix = action_id || SecureRandom.hex(4)
    described_class.create!(
      event_id: "#{event_kind}:#{card_id}:#{suffix}:#{SecureRandom.hex(3)}",
      event_kind: event_kind, action_id: action_id, card_id: card_id, status: status
    )
  end

  describe ".superseded_by_later_or_reconcile?" do
    it "returns false for a reconcile row (reconcile rows are never superseded)" do
      row = described_class.new(event_kind: "reconcile", action_id: nil, card_id: 1)
      expect(described_class.superseded_by_later_or_reconcile?(row)).to be(false)
    end

    it "returns false for a corrupt decko_action row with a nil action_id (defensive guard)" do
      row = described_class.new(event_kind: "decko_action", action_id: nil, card_id: 1)
      expect(described_class.superseded_by_later_or_reconcile?(row)).to be(false)
    end

    it "returns false on an otherwise empty outbox (no later same-card event)" do
      row = queue(action_id: 100, card_id: 1, status: "superseded_by_later")
      expect(described_class.superseded_by_later_or_reconcile?(row)).to be(false)
    end

    context "branch (a): later same-card delivered decko_action" do
      it "returns true when a later same-card decko_action is delivered" do
        row = queue(action_id: 100, card_id: 7, status: "superseded_by_later")
        queue(action_id: 101, card_id: 7, status: "delivered")
        expect(described_class.superseded_by_later_or_reconcile?(row)).to be(true)
      end

      it "returns false when the later same-card decko_action is not delivered" do
        row = queue(action_id: 100, card_id: 7, status: "superseded_by_later")
        queue(action_id: 101, card_id: 7, status: "queued")
        expect(described_class.superseded_by_later_or_reconcile?(row)).to be(false)
      end

      it "returns false when the later delivered decko_action is for a different card" do
        row = queue(action_id: 100, card_id: 7, status: "superseded_by_later")
        queue(action_id: 101, card_id: 8, status: "delivered")
        expect(described_class.superseded_by_later_or_reconcile?(row)).to be(false)
      end
    end

    context "branch (b): same-card later-inserted delivered reconcile" do
      it "returns true when a delivered reconcile for the card was inserted after this row (higher id)" do
        row = queue(action_id: 100, card_id: 7, status: "superseded_by_later")
        queue(event_kind: "reconcile", action_id: nil, card_id: 7, status: "delivered")
        expect(described_class.superseded_by_later_or_reconcile?(row)).to be(true)
      end

      it "returns false when the delivered reconcile was inserted before this row (lower id)" do
        queue(event_kind: "reconcile", action_id: nil, card_id: 7, status: "delivered")
        row = queue(action_id: 100, card_id: 7, status: "superseded_by_later")
        expect(described_class.superseded_by_later_or_reconcile?(row)).to be(false)
      end

      it "returns false when the delivered reconcile is for a different card" do
        row = queue(action_id: 100, card_id: 7, status: "superseded_by_later")
        queue(event_kind: "reconcile", action_id: nil, card_id: 8, status: "delivered")
        expect(described_class.superseded_by_later_or_reconcile?(row)).to be(false)
      end

      # Defense-in-depth: query (b) filters action_id IS NULL, so a (corrupt) reconcile carrying a
      # non-NULL action_id must not prove supersession. The OQ#12 CHECK normally prevents that row,
      # so it is dropped for this example to exercise the filter directly.
      it "returns false for a corrupt later same-card reconcile with a non-NULL action_id" do
        row = queue(action_id: 100, card_id: 7, status: "superseded_by_later")
        conn = described_class.connection
        conn.remove_check_constraint(:mirror_outbox, name: "mirror_outbox_reconcile_action_id_null")
        begin
          conn.execute(<<~SQL)
            INSERT INTO mirror_outbox
              (event_id, event_kind, action_id, card_id, status, attempts, created_at, updated_at)
            VALUES ('reconcile:corrupt:7', 'reconcile', 999, 7, 'delivered', 0, NOW(), NOW())
          SQL
          expect(described_class.superseded_by_later_or_reconcile?(row)).to be(false)
        ensure
          conn.add_check_constraint(:mirror_outbox, "event_kind <> 'reconcile' OR action_id IS NULL",
                                    name: "mirror_outbox_reconcile_action_id_null")
        end
      end
    end
  end
end
