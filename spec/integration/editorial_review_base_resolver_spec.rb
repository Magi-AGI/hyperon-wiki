# frozen_string_literal: true

require "spec_helper"
require_relative "../../mod/editorial_review/lib/base_resolver"
require_relative "../../mod/editorial_review/lib/proposal_provenance"

# Integration specs for WS6 BaseResolver (Phase 2). Exercise real Decko revision
# history + the +proposal stamp events, so they require a Decko test DATABASE
# (RAILS_ENV=test / scratch DB) — never prod. Lives under spec/integration/
# because CI's structural job runs spec/mod/ with no database.
RSpec.describe BaseResolver, "resolve" do
  def uniq
    "WS6BR#{SecureRandom.hex(4)}"
  end

  let(:parent_name) { uniq }
  let(:proposal_name) { "#{parent_name}+proposal" }

  after do
    Card::Auth.as_bot do
      ["#{proposal_name}+provenance", "#{proposal_name}+base",
       proposal_name, parent_name].each { |n| Card.fetch(n)&.delete! }
    end
  end

  def make_parent_and_proposal
    Card::Auth.as_bot do
      Card.create!(name: parent_name, type: "RichText", content: "<p>base content</p>")
      Card.create!(name: proposal_name, type: "RichText", content: "<p>proposed</p>")
    end
  end

  context "Tier 1 — stamped + intact base" do
    before { make_parent_and_proposal }

    it "resolves :verified / :three_way with the reconstructed base content" do
      res = BaseResolver.resolve(Card.fetch(proposal_name))
      parent = Card.fetch(parent_name)
      expect(res[:tier]).to eq(:verified)
      expect(res[:mode]).to eq(:three_way)
      expect(res[:base_hash_ok]).to be true
      expect(res[:base_content]).to eq(parent.db_content)
      expect(res[:base_action_id]).to be_a(Integer)
    end
  end

  context "Tier 1 — stamped but base_hash tampered (hard failure)" do
    before { make_parent_and_proposal }

    it "resolves :stale / :two_way and withholds base_content" do
      prov = Card.fetch("#{proposal_name}+provenance")
      rec = ProposalProvenance.parse(prov.db_content)
      rec["base_hash"] = "sha256:deadbeef"
      Card::Auth.as_bot { prov.update!(content: ProposalProvenance.to_json_compact(rec)) }

      res = BaseResolver.resolve(Card.fetch(proposal_name))
      expect(res[:tier]).to eq(:stale)
      expect(res[:mode]).to eq(:two_way)
      expect(res[:base_hash_ok]).to be false
      expect(res[:base_content]).to be_nil
      expect(res[:warning]).to match(/mismatch/)
    end
  end

  context "Tier 1 — stamped but base action missing" do
    before { make_parent_and_proposal }

    it "resolves :stale when base_action_id no longer exists" do
      prov = Card.fetch("#{proposal_name}+provenance")
      rec = ProposalProvenance.parse(prov.db_content)
      rec["base_action_id"] = 0 # nonexistent
      Card::Auth.as_bot { prov.update!(content: ProposalProvenance.to_json_compact(rec)) }

      res = BaseResolver.resolve(Card.fetch(proposal_name))
      expect(res[:tier]).to eq(:stale)
      expect(res[:warning]).to match(/not found/)
    end
  end

  context "parent rename after authoring" do
    before { make_parent_and_proposal }

    it "still resolves :verified (base keyed by card id, not name)" do
      # Provenance records the original name; rename the parent card.
      Card::Auth.as_bot { Card.fetch(parent_name).update!(name: "#{parent_name}Renamed", update_referers: true) }
      res = BaseResolver.resolve(Card.fetch("#{parent_name}Renamed+proposal"))
      expect(res[:tier]).to eq(:verified)
      expect(res[:base_hash_ok]).to be true
    ensure
      Card::Auth.as_bot { Card.fetch("#{parent_name}Renamed")&.delete! }
    end
  end

  context "Tier 2/3 — legacy (unstamped) proposals" do
    before { make_parent_and_proposal }

    it "estimates a base (:three_way) when parent history is unambiguous" do
      # Drop the stamp to simulate a legacy proposal.
      Card::Auth.as_bot { Card.fetch("#{proposal_name}+provenance")&.delete!; Card.fetch("#{proposal_name}+base")&.delete! }
      res = BaseResolver.resolve(Card.fetch(proposal_name))
      expect(res[:tier]).to eq(:estimated)
      expect(res[:mode]).to eq(:three_way)
      expect(res[:warning]).to match(/ESTIMATED/)
    end
  end
end
