# frozen_string_literal: true

require "spec_helper"
require_relative "../../../mod/editorial_review/lib/proposal_provenance"

# Pure unit specs for the WS6 +proposal provenance helpers — no database needed.
RSpec.describe ProposalProvenance do
  describe ".content_hash" do
    it "is deterministic and sha256-prefixed over raw content" do
      h = described_class.content_hash("<p>hi</p>")
      expect(h).to start_with("sha256:")
      expect(h).to eq(described_class.content_hash("<p>hi</p>"))
    end

    it "differs when content differs and treats nil as empty string" do
      expect(described_class.content_hash("a")).not_to eq(described_class.content_hash("b"))
      expect(described_class.content_hash(nil)).to eq(described_class.content_hash(""))
    end
  end

  describe ".build_record / .to_json_compact / .parse" do
    let(:record) do
      described_class.build_record(
        parent_id: 8442, parent_name: "Glossary+Overgoal",
        parent_type: "RichText", proposal_type: "RichText",
        base_act_id: 114_217, base_action_id: 123_456,
        base_hash: "sha256:aa", proposal_hash: "sha256:bb",
        actor_id: 17, actor_name: "Lake Watkins",
        source: "mcp:create_card", stamp_source: "server_current",
        override: false, override_reason: nil,
        stamped_at: "2026-06-23T21:15:00Z"
      )
    end

    it "carries schema_version 1 and every contract field" do
      expect(record[:schema_version]).to eq(1)
      expect(record.keys).to include(
        :parent_id, :parent_name, :parent_type, :base_act_id, :base_action_id,
        :base_hash, :proposal_hash, :proposal_type, :actor_id, :actor_name,
        :source, :stamp_source, :override, :override_reason, :stamped_at
      )
    end

    it "serializes to single-line JSON that round-trips" do
      json = described_class.to_json_compact(record)
      expect(json).not_to include("\n")
      parsed = described_class.parse(json)
      expect(parsed["schema_version"]).to eq(1)
      expect(parsed["base_action_id"]).to eq(123_456)
      expect(parsed["stamped_at"]).to eq("2026-06-23T21:15:00Z")
    end
  end
end
