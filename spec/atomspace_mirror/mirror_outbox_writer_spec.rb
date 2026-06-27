# frozen_string_literal: true
#
# L2a writer specs (Lane A, Slice 2). Unit-test the MirrorOutboxWriter business logic in isolation
# with stubbed MirrorOutbox / MirrorState (no Decko boot / DB) and the real pure CardAtomEncoder.
# The DB semantics (real SELECT FOR UPDATE, real RecordNotUnique on the unique index) are verified
# on dev as part of the L2b mod-install track (OQ#16). Maps to Card 17161 Level 2 + Section 11 L2.

require "ostruct"
require "active_support/core_ext/object/blank"
unless defined?(ActiveRecord::RecordNotUnique)
  module ActiveRecord
    class RecordNotUnique < StandardError; end
  end
end
require_relative "../../mod/atomspace_mirror/lib/mirror_outbox_writer"

RSpec.describe MirrorOutboxWriter do
  NO_AUTH = { current_id: nil, as_id: nil }.freeze

  let(:inserted) { [] }

  # Install fake MirrorOutbox (captures create! attrs; transaction just yields) + MirrorState
  # (lock.first -> a row with the given bootstrap_a_start). raise_dup simulates the unique-index
  # collision.
  def install(bootstrap_a_start: nil, raise_dup: false)
    rows = inserted
    outbox = Class.new do
      define_singleton_method(:transaction) { |&blk| blk.call }
      define_singleton_method(:create!) do |**attrs|
        raise ActiveRecord::RecordNotUnique if raise_dup

        rows << attrs
        attrs
      end
    end
    state_row = OpenStruct.new(bootstrap_a_start: bootstrap_a_start)
    rel = Object.new.tap { |o| o.define_singleton_method(:first) { state_row } }
    state = Object.new.tap { |o| o.define_singleton_method(:lock) { rel } }
    stub_const("MirrorOutbox", outbox)
    stub_const("MirrorState", state)
  end

  def card(**over)
    OpenStruct.new({ id: 1, name: "N", key: "k", codename: nil, type_id: 6, type_name: "RichText",
                     left_id: nil, right_id: nil, db_content: "b", trash: false,
                     created_at: Time.utc(2026, 1, 1), updated_at: Time.utc(2026, 1, 2),
                     creator_id: 3, updater_id: 3, references_out: [] }.merge(over))
  end

  def act
    OpenStruct.new(id: 5, actor_id: 3, acted_at: Time.utc(2026, 1, 2), ip_address: nil)
  end

  def action(card_obj, **over)
    OpenStruct.new({ id: 100, action_type: :update, draft: false, super_action_id: nil,
                     card_id: card_obj.id, act: act, card_changes: [], card: card_obj }.merge(over))
  end

  describe "INSERT discipline" do
    it "inserts a queued decko_action row when bootstrap_a_start is nil" do
      install(bootstrap_a_start: nil)
      MirrorOutboxWriter.write(action(card), auth: NO_AUTH)
      row = inserted.first
      expect(inserted.size).to eq(1)
      expect(row[:status]).to eq("queued")
      expect(row[:event_kind]).to eq("decko_action")
      expect(row[:event_id]).to eq("decko:action:100")
      expect(row[:action_id]).to eq(100)
      expect(row[:card_id]).to eq(1)
      expect(row[:payload]["atoms"].map { |a| a["atom"] }).to include("DeckoCard", "DeckoProvenance")
    end

    it "inserts superseded_by_bootstrap when action.id <= bootstrap_a_start" do
      install(bootstrap_a_start: 100)
      MirrorOutboxWriter.write(action(card, id: 50), auth: NO_AUTH)
      expect(inserted.first[:status]).to eq("superseded_by_bootstrap")
    end

    it "inserts queued when action.id > bootstrap_a_start" do
      install(bootstrap_a_start: 100)
      MirrorOutboxWriter.write(action(card, id: 150), auth: NO_AUTH)
      expect(inserted.first[:status]).to eq("queued")
    end

    it "swallows RecordNotUnique on a duplicate insert (idempotent)" do
      install(raise_dup: true)
      expect { MirrorOutboxWriter.write(action(card), auth: NO_AUTH) }.not_to raise_error
      expect(inserted).to be_empty
    end
  end

  describe "recursion guard (exact codename set, not a key prefix)" do
    it "skips the mirror's own mod card by exact codename" do
      install
      MirrorOutboxWriter.write(action(card(codename: "mod_atomspace_mirror")), auth: NO_AUTH)
      expect(inserted).to be_empty
    end

    it "does NOT skip an ordinary user card whose key merely starts with mirror_" do
      install
      MirrorOutboxWriter.write(action(card(key: "mirror_foo", codename: nil)), auth: NO_AUTH)
      expect(inserted.size).to eq(1)
    end
  end

  describe "draft" do
    it "inserts nothing" do
      install
      MirrorOutboxWriter.write(action(card, draft: true), auth: NO_AUTH)
      expect(inserted).to be_empty
    end
  end

  describe "encoder failure" do
    it "inserts a terminal 'failed' row (so RYW returns event_failed, not a timeout)" do
      install
      a = action(card, card_changes: [OpenStruct.new(field: 99, value: "x")]) # field_name raises (corrupt index)
      MirrorOutboxWriter.write(a, auth: NO_AUTH)
      row = inserted.first
      expect(inserted.size).to eq(1)
      expect(row[:status]).to eq("failed")
      expect(row[:event_id]).to eq("decko:action:100")
      expect(row[:payload]).to be_nil
      expect(row[:error]).to match(/card_changes.field/)
    end

    it "lets superseded_by_bootstrap WIN over a corrupt encode (does not become 'failed')" do
      install(bootstrap_a_start: 100)
      a = action(card, id: 50, card_changes: [OpenStruct.new(field: 99, value: "x")]) # corrupt + pre-A_start
      MirrorOutboxWriter.write(a, auth: NO_AUTH)
      row = inserted.first
      expect(inserted.size).to eq(1)
      expect(row[:status]).to eq("superseded_by_bootstrap")
      expect(row[:payload]).to be_nil # encode failed, but the sweep already covered this card
    end

    it "lets an unexpected (non-EncodingError) error propagate loudly, inserting nothing" do
      install
      allow(CardAtomEncoder).to receive(:encode).and_raise(RuntimeError, "boom")
      expect { MirrorOutboxWriter.write(action(card), auth: NO_AUTH) }.to raise_error(RuntimeError, /boom/)
      expect(inserted).to be_empty
    end
  end

  describe "pre_state derivation (in the writer, normalized via field_name)" do
    # the hook passes no pre_state; the writer derives it from action.previous_value per changed
    # field, normalizing card_changes.field through the locked field_name mapping (name OR integer).

    it "joins each change's previous_value into the provenance changes (real old->new)" do
      install
      a = action(card, card_changes: [OpenStruct.new(field: "db_content", value: "new body")])
      a.define_singleton_method(:previous_value) { |f| f == :db_content ? "old body" : nil }
      MirrorOutboxWriter.write(a, auth: NO_AUTH)
      prov = inserted.first[:payload]["atoms"].find { |x| x["atom"] == "DeckoProvenance" }
      expect(prov["fields"].to_h["changes"]).to eq(
        [{ "field" => "db_content", "old" => "old body", "new" => "new body" }]
      )
    end

    it "normalizes a NUMERIC card_changes.field index (does NOT crash the write path)" do
      install
      a = action(card, card_changes: [OpenStruct.new(field: 2, value: "n")]) # 2 => db_content
      a.define_singleton_method(:previous_value) { |f| f == :db_content ? "o" : nil }
      MirrorOutboxWriter.write(a, auth: NO_AUTH)
      expect(inserted.first[:status]).to eq("queued")
      prov = inserted.first[:payload]["atoms"].find { |x| x["atom"] == "DeckoProvenance" }
      expect(prov["fields"].to_h["changes"]).to eq([{ "field" => "db_content", "old" => "o", "new" => "n" }])
    end
  end

  describe "auth contract" do
    it "raises loudly (not a failed row) when auth is omitted or malformed" do
      install
      expect { MirrorOutboxWriter.write(action(card)) }.to raise_error(ArgumentError)
      expect { MirrorOutboxWriter.write(action(card), auth: {}) }.to raise_error(ArgumentError, /current_id/)
      expect(inserted).to be_empty
    end
  end

  # The integrate hook gates on this -- the deploy-safety master switch (OFF unless explicitly true).
  describe ".enabled? (deploy-safety activation gate)" do
    around do |ex|
      prev = ENV["ATOMSPACE_MIRRORING_ENABLED"]
      ex.run
      ENV["ATOMSPACE_MIRRORING_ENABLED"] = prev
    end

    it "is OFF by default (unset/blank/anything-but-true) so a shipped-but-dormant mirror never fires" do
      [nil, "", "false", "0", "yes", "TRUE!"].each do |v|
        v.nil? ? ENV.delete("ATOMSPACE_MIRRORING_ENABLED") : ENV["ATOMSPACE_MIRRORING_ENABLED"] = v
        expect(MirrorOutboxWriter.enabled?).to be(false), "expected disabled for #{v.inspect}"
      end
    end

    it "is ON only for an explicit true (case/whitespace-insensitive)" do
      ["true", "TRUE", " True "].each do |v|
        ENV["ATOMSPACE_MIRRORING_ENABLED"] = v
        expect(MirrorOutboxWriter.enabled?).to be(true), "expected enabled for #{v.inspect}"
      end
    end
  end
end
