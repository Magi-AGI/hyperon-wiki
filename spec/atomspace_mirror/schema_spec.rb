# frozen_string_literal: true
#
# Schema-presence specs for the AtomSpace Mirror tables (Lane A, Slice 1).
# Maps to the Card 17120 Section 11 / Level 11 schema-presence assertions.
#
# REQUIRES: the Decko test DB with mod/atomspace_mirror migrations applied
# (RAILS_ENV=test decko update). DB-gated -- cannot run until the deck test-DB
# bootstrap is in place (see Lane C dev-capstone notes / the unresolved test-DB blocker).

require "spec_helper"

RSpec.describe "AtomSpace Mirror schema", type: :model do
  let(:conn) { ActiveRecord::Base.connection }

  describe "tables" do
    %w[mirror_state mirror_outbox mirror_bootstrap_runs mirror_reconcile_runs].each do |tbl|
      it "creates #{tbl}" do
        expect(conn.tables).to include(tbl)
      end
    end
  end

  describe "mirror_state" do
    it "has the bootstrap_a_start column (mirror_state_bootstrap_a_start_present)" do
      expect(conn.columns("mirror_state").map(&:name)).to include("bootstrap_a_start")
    end

    it "has the singleton_guard column" do
      expect(conn.columns("mirror_state").map(&:name)).to include("singleton_guard")
    end

    # mirror_state_singleton_constraint_present: BOTH the UNIQUE index AND the CHECK are required
    # (UNIQUE on a boolean alone is not a singleton -- PG allows one true + one false row).
    it "has a UNIQUE index on singleton_guard" do
      idx = conn.indexes("mirror_state").find { |i| i.columns == ["singleton_guard"] }
      expect(idx).not_to be_nil
      expect(idx.unique).to be(true)
    end

    it "has the mirror_state_singleton_true CHECK constraint" do
      expect(conn.check_constraints("mirror_state").map(&:name)).to include("mirror_state_singleton_true")
    end

    it "is seeded with exactly one row" do
      expect(MirrorState.count).to eq(1)
    end
  end

  describe "mirror_outbox indexes" do
    let(:indexes) { conn.indexes("mirror_outbox") }

    it "has a UNIQUE index on event_id (event_id_unique_index_present)" do
      idx = indexes.find { |i| i.columns == ["event_id"] }
      expect(idx&.unique).to be(true)
    end

    it "has the partial-UNIQUE decko_action index (decko_action_partial_unique_index_present)" do
      idx = indexes.find { |i| i.name == "mirror_outbox_decko_action_unique" }
      expect(idx).not_to be_nil
      expect(idx.unique).to be(true)
      expect(idx.where).to match(/event_kind/)
    end

    it "indexes card_id (card_id_indexed)" do
      expect(indexes.any? { |i| i.columns.first == "card_id" }).to be(true)
    end

    it "has the [event_kind, status, action_id] composite index" do
      expect(indexes.map(&:columns)).to include(%w[event_kind status action_id])
    end

    it "has the partial source_reconcile_event_id index (source_reconcile_event_id_indexed_partial)" do
      idx = indexes.find { |i| i.columns == ["source_reconcile_event_id"] }
      expect(idx).not_to be_nil
      expect(idx.where).to match(/source_reconcile_event_id/)
    end
  end

  describe "mirror_outbox OQ#12 CHECK constraints" do
    let(:names) { conn.check_constraints("mirror_outbox").map(&:name) }

    it "requires action_id for decko_action rows (mirror_outbox_decko_action_id_present)" do
      expect(names).to include("mirror_outbox_decko_action_id_present")
    end

    it "requires NULL action_id for reconcile rows (mirror_outbox_reconcile_action_id_null)" do
      expect(names).to include("mirror_outbox_reconcile_action_id_null")
    end
  end
end
