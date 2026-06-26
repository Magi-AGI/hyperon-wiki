# frozen_string_literal: true
#
# L8 drain structural + identity preflight (OQ#15 + Codex row<->payload identity). STANDALONE:
# pure logic over OpenStruct rows + Hash payloads, no Decko boot / DB.

require "ostruct"
require_relative "../../mod/atomspace_mirror/lib/mirror_drain_validator"

RSpec.describe MirrorDrainValidator do
  def row(**over)
    OpenStruct.new({ event_kind: "decko_action", card_id: 724, action_id: 893,
                     event_id: "decko:action:893" }.merge(over))
  end

  def atom(kind, fields) = { "atom" => kind, "fields" => fields }
  def card_atom(id: 724) = atom("DeckoCard", [["Id", id], ["Name", "Foo"], ["Trash", false]])
  def ref_atom(referer: 724) = atom("DeckoReference", [["RefererId", referer], ["RefType", { "sym" => "L" }]])

  def prov_atom(event_id: "decko:action:893", action_id: 893, card_id: 724)
    atom("DeckoProvenance",
         [["event_id", event_id], ["action_id", action_id], ["card_id", card_id], ["action", { "sym" => "create" }]])
  end

  def payload(*atoms) = { "atoms" => atoms }

  describe "valid" do
    it "accepts a well-formed decko_action row + payload" do
      expect(MirrorDrainValidator.validate!(row, payload(card_atom, ref_atom, prov_atom))).to be(true)
    end

    it "accepts a reconcile row (nil action_id) with a matching payload" do
      r = row(event_kind: "reconcile", action_id: nil, event_id: "decko:reconcile:5")
      p = payload(card_atom, prov_atom(event_id: "decko:reconcile:5", action_id: nil))
      expect(MirrorDrainValidator.validate!(r, p)).to be(true)
    end
  end

  describe "row shape (OQ#15)" do
    it "rejects an unknown event_kind" do
      expect { MirrorDrainValidator.validate!(row(event_kind: "bogus"), payload(card_atom, prov_atom)) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /event_kind/)
    end

    it "rejects a missing card_id" do
      expect { MirrorDrainValidator.validate!(row(card_id: nil), payload(card_atom, prov_atom)) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /card_id/)
    end

    it "rejects a decko_action with nil action_id" do
      expect { MirrorDrainValidator.validate!(row(action_id: nil), payload(card_atom, prov_atom)) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /action_id/)
    end

    it "rejects a reconcile with a non-nil action_id" do
      r = row(event_kind: "reconcile", action_id: 5, event_id: "decko:reconcile:5")
      expect { MirrorDrainValidator.validate!(r, payload(card_atom, prov_atom(event_id: "decko:reconcile:5", action_id: 5))) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /reconcile requires a nil action_id/)
    end

    it "rejects a missing/empty atoms array" do
      expect { MirrorDrainValidator.validate!(row, { "atoms" => [] }) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /atoms/)
      expect { MirrorDrainValidator.validate!(row, {}) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /atoms/)
    end

    it "rejects an unknown atom kind" do
      bad = atom("DeckoWidget", [["Id", 1]])
      expect { MirrorDrainValidator.validate!(row, payload(card_atom, prov_atom, bad)) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /unknown atom kind/)
    end

    it "rejects not-exactly-one DeckoCard / DeckoProvenance" do
      expect { MirrorDrainValidator.validate!(row, payload(card_atom, card_atom, prov_atom)) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /exactly one DeckoCard/)
      expect { MirrorDrainValidator.validate!(row, payload(card_atom)) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /exactly one DeckoProvenance/)
    end
  end

  describe "row <-> payload identity (Codex blocker)" do
    it "rejects DeckoCard.Id != row.card_id" do
      expect { MirrorDrainValidator.validate!(row, payload(card_atom(id: 999), prov_atom)) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /DeckoCard.Id/)
    end

    it "rejects DeckoProvenance.event_id != row.event_id" do
      expect { MirrorDrainValidator.validate!(row, payload(card_atom, prov_atom(event_id: "decko:action:999"))) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /event_id/)
    end

    it "rejects DeckoProvenance.action_id != row.action_id" do
      expect { MirrorDrainValidator.validate!(row, payload(card_atom, prov_atom(action_id: 999))) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /action_id/)
    end

    it "rejects DeckoProvenance.card_id != row.card_id (corrupt provenance, Codex)" do
      expect { MirrorDrainValidator.validate!(row, payload(card_atom, prov_atom(card_id: 999))) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /DeckoProvenance.card_id/)
    end

    it "rejects missing DeckoProvenance.card_id" do
      prov = atom("DeckoProvenance", [["event_id", "decko:action:893"], ["action_id", 893]])
      expect { MirrorDrainValidator.validate!(row, payload(card_atom, prov)) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /DeckoProvenance.card_id/)
    end

    it "rejects a DeckoReference.RefererId != row.card_id" do
      expect { MirrorDrainValidator.validate!(row, payload(card_atom, ref_atom(referer: 999), prov_atom)) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /RefererId/)
    end
  end

  describe "field well-formedness (Codex)" do
    it "rejects an atom with a repeated field name (Id=724, Id=999 could pass first-match identity)" do
      dup_card = atom("DeckoCard", [["Id", 724], ["Id", 999], ["Trash", false]])
      expect { MirrorDrainValidator.validate!(row, payload(dup_card, prov_atom)) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /duplicate field name/)
    end

    it "rejects a malformed field pair even when the identity fields are correct" do
      bad_card = atom("DeckoCard", [["Id", 724], ["bad_only"], ["Trash", false]])
      expect { MirrorDrainValidator.validate!(row, payload(bad_card, prov_atom)) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /malformed field/)
    end

    it "rejects a field with a non-string / empty name" do
      bad_card = atom("DeckoCard", [["Id", 724], ["", "x"]])
      expect { MirrorDrainValidator.validate!(row, payload(bad_card, prov_atom)) }
        .to raise_error(MirrorDrainValidator::InvalidRow, /non-string\/empty name/)
    end
  end
end
