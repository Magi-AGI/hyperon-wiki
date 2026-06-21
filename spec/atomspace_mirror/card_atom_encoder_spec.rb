# frozen_string_literal: true
#
# L1 encoder specs (Lane A, Slice 2). The encoder is a PURE function, so these run standalone with
# OpenStruct doubles -- no Decko boot / test DB required (unlike the Slice 1 DB-gated specs).
# Maps to Card 17161 Level 1 + Section 11 Layer 1. Delete-first per the 2026-06-21 reviewer pass.

require "ostruct"
require "active_support/core_ext/object/blank"
require_relative "../../mod/atomspace_mirror/lib/card_atom_encoder"

RSpec.describe CardAtomEncoder do
  NO_AUTH = { current_id: nil, as_id: nil }.freeze

  # encode wrapper: auth is mandatory, so default tests to the explicit "unavailable" snapshot
  # unless a case overrides it.
  def enc(action_obj, **over)
    described_class.encode(action_obj, **{ auth: NO_AUTH }.merge(over))
  end

  def card(**over)
    OpenStruct.new({
      id: 17120, name: "Some Card", key: "some_card", codename: nil, type_id: 6,
      type_name: "RichText", left_id: nil, right_id: nil, db_content: "body",
      trash: false, created_at: Time.utc(2026, 1, 1, 0, 0, 0),
      updated_at: Time.utc(2026, 1, 2, 0, 0, 0), creator_id: 3, updater_id: 3,
      references_out: []
    }.merge(over))
  end

  def act(**over)
    OpenStruct.new({ id: 81234, actor_id: 3, acted_at: Time.utc(2026, 1, 2, 0, 0, 0),
                     ip_address: nil }.merge(over))
  end

  def action(card_obj, act_obj: act, **over)
    OpenStruct.new({ id: 129552, action_type: :update, draft: false, super_action_id: nil,
                     card_id: card_obj.id, act: act_obj, card_changes: [], card: card_obj }.merge(over))
  end

  def change(field, value)
    OpenStruct.new(field: field, value: value)
  end

  def ref(**over)
    OpenStruct.new({ referer_id: 17120, referee_key: "target", referee_id: 17117, ref_type: "L",
                     is_present: true }.merge(over))
  end

  def atom_of(atoms, kind)
    atoms.find { |a| a["atom"] == kind }
  end

  def fields_of(atoms, kind)
    a = atom_of(atoms, kind)
    a && a["fields"].to_h
  end

  def order_of(atoms, kind)
    atom_of(atoms, kind)["fields"].map(&:first)
  end

  describe "input contract" do
    it "requires auth: (raises when omitted) so the dual-actor snapshot cannot silently regress" do
      expect { described_class.encode(action(card)) }.to raise_error(ArgumentError)
      expect { described_class.encode(action(card), auth: {}) }.to raise_error(ArgumentError, /current_id/)
    end
  end

  describe "delete actions" do
    let(:deleted_card) { card(trash: true, db_content: "", references_out: [ref]) }
    let(:atoms) { enc(action(deleted_card, action_type: :delete)) }

    it "emits a DeckoCard with Trash=true and the full ordered 14-field arity" do
      expect(order_of(atoms, "DeckoCard")).to eq(
        %w[Id Name Key Codename TypeId TypeName LeftId RightId Content Trash CreatedAt UpdatedAt CreatorId UpdaterId]
      )
      expect(fields_of(atoms, "DeckoCard")["Trash"]).to be(true)
    end

    it "still emits references for the deleted card" do
      expect(atoms.count { |a| a["atom"] == "DeckoReference" }).to eq(1)
    end

    it "tags provenance action as the :delete symbol" do
      expect(fields_of(atoms, "DeckoProvenance")["action"]).to eq("sym" => "delete")
    end
  end

  describe "draft actions" do
    it "emits zero atoms" do
      expect(enc(action(card, draft: true))).to eq([])
    end
  end

  describe "DeckoCard field encoding" do
    it "uses NoCodename when codename is nil, else the codename symbol" do
      expect(fields_of(enc(action(card)), "DeckoCard")["Codename"]).to eq("sym" => "NoCodename")
      expect(fields_of(enc(action(card(codename: "mod_x"))), "DeckoCard")["Codename"]).to eq("sym" => "mod_x")
    end

    it "uses NoLeft / NoRight sentinels when null, else the integer id" do
      f = fields_of(enc(action(card)), "DeckoCard")
      expect(f["LeftId"]).to eq("sym" => "NoLeft")
      expect(f["RightId"]).to eq("sym" => "NoRight")
      f2 = fields_of(enc(action(card(left_id: 5, right_id: 6))), "DeckoCard")
      expect(f2["LeftId"]).to eq(5)
      expect(f2["RightId"]).to eq(6)
    end

    it "encodes Trash as a native JSON boolean and Content as the raw db_content string" do
      f = fields_of(enc(action(card(db_content: "<h2>x</h2>"))), "DeckoCard")
      expect(f["Trash"]).to be(false)
      expect(f["Content"]).to eq("<h2>x</h2>")
    end
  end

  describe "DeckoReference encoding" do
    it "maps one ordered atom per reference; RefType symbol; Unresolved for nil referee_id" do
      c = card(references_out: [ref(ref_type: "I"), ref(referee_id: nil, is_present: false)])
      atoms = enc(action(c))
      refs = atoms.select { |a| a["atom"] == "DeckoReference" }
      expect(refs.size).to eq(2)
      expect(refs.first["fields"].map(&:first)).to eq(%w[RefererId RefereeKey RefereeId RefType IsPresent])
      expect(refs[0]["fields"].to_h["RefType"]).to eq("sym" => "I")
      expect(refs[1]["fields"].to_h["RefereeId"]).to eq("sym" => "Unresolved")
      expect(refs[1]["fields"].to_h["IsPresent"]).to be(false)
    end
  end

  describe "DeckoProvenance encoding" do
    it "emits the full ordered 21-field provenance envelope" do
      expect(order_of(enc(action(card)), "DeckoProvenance")).to eq(%w[
        source event_schema_version event_id action_id act_id super_action_id action draft card_id
        card_key actor_id auth_current_id auth_as_id acted_at ip_address stage changes
        agent_session_id agent_kind origin_system origin_request_id
      ])
    end

    it "carries the constants + event_id" do
      f = fields_of(enc(action(card)), "DeckoProvenance")
      expect(f["source"]).to eq("decko")
      expect(f["event_schema_version"]).to eq("decko-spaceevent-v1")
      expect(f["event_id"]).to eq("decko:action:129552")
      expect(f["stage"]).to eq("integrate_with_delay")
    end

    it "uses NoSuper / NoIP sentinels when null" do
      f = fields_of(enc(action(card)), "DeckoProvenance")
      expect(f["super_action_id"]).to eq("sym" => "NoSuper")
      expect(f["ip_address"]).to eq("sym" => "NoIP")
    end

    it "encodes the Source-5 dual-actor auth fields from the auth snapshot, distinct from actor_id" do
      a = action(card, act_obj: act(actor_id: 10))
      f = fields_of(enc(a, auth: { current_id: 3, as_id: 5 }), "DeckoProvenance")
      expect(f["actor_id"]).to eq(10)
      expect(f["auth_current_id"]).to eq(3)
      expect(f["auth_as_id"]).to eq(5)
    end

    it "uses JSON null (not a sentinel) for an explicitly-unavailable dual-actor + absent agent fields" do
      f = fields_of(enc(action(card)), "DeckoProvenance")
      %w[auth_current_id auth_as_id agent_session_id agent_kind origin_system origin_request_id].each do |k|
        expect(f[k]).to be_nil
      end
    end

    it "tags present agent_kind / origin_system as symbols and keeps ids/strings native" do
      ctx = { agent_kind: :external_mcp_agent, origin_system: :mcp,
              agent_session_id: "jwt-jti-7f3c2a", origin_request_id: "req-abc" }
      f = fields_of(enc(action(card), request_context: ctx), "DeckoProvenance")
      expect(f["agent_kind"]).to eq("sym" => "external_mcp_agent")
      expect(f["origin_system"]).to eq("sym" => "mcp")
      expect(f["agent_session_id"]).to eq("jwt-jti-7f3c2a")
    end

    it "builds the changes array from card_changes (name OR integer field) joined with pre_state" do
      a = action(card, card_changes: [change("db_content", "new body"), change(3, "t")]) # 3 => trash
      f = fields_of(enc(a, pre_state: { "db_content" => "old body" }), "DeckoProvenance")
      expect(f["changes"]).to eq([
        { "field" => "db_content", "old" => "old body", "new" => "new body" },
        { "field" => "trash", "old" => nil, "new" => "t" }
      ])
    end

    it "tolerates symbol-keyed pre_state" do
      a = action(card, card_changes: [change("db_content", "new")])
      f = fields_of(enc(a, pre_state: { db_content: "old" }), "DeckoProvenance")
      expect(f["changes"]).to eq([{ "field" => "db_content", "old" => "old", "new" => "new" }])
    end

    it "raises on a corrupt out-of-range integer card_changes.field index" do
      a = action(card, card_changes: [change(99, "x")])
      expect { enc(a) }.to raise_error(ArgumentError, /corrupt card_changes.field/)
    end
  end

  describe "referential transparency" do
    it "produces identical output for identical inputs" do
      c = card(left_id: 5, references_out: [ref])
      expect(enc(action(c))).to eq(enc(action(c)))
    end
  end
end
