# frozen_string_literal: true

require "spec_helper"
require_relative "../../../mod/editorial_review/lib/proposal_provenance"

# Integration specs for the +proposal model layer (WS6 Phase 1). These exercise
# real Decko events + revision history, so they require a Decko test DATABASE
# (run on a provisioned runtime — RAILS_ENV=test / scratch DB — never prod).
RSpec.describe "editorial_review +proposal set" do
  def uniq
    "WS6Proposal#{SecureRandom.hex(4)}"
  end

  let(:parent_name) { uniq }
  let(:proposal_name) { "#{parent_name}+proposal" }

  def provenance
    Card::Auth.as_bot { Card.fetch("#{proposal_name}+provenance") }
  end

  def base_card
    Card::Auth.as_bot { Card.fetch("#{proposal_name}+base") }
  end

  after do
    Card::Auth.as_bot do
      ["#{proposal_name}+provenance", "#{proposal_name}+base",
       proposal_name, parent_name].each { |n| Card.fetch(n)&.delete! }
    end
  end

  context "created against an existing parent" do
    before do
      Card::Auth.as_bot do
        Card.create!(name: parent_name, type: "RichText", content: "<p>base content</p>")
        Card.create!(name: proposal_name, type: "RichText", content: "<p>proposed</p>")
      end
    end

    it "stamps +base with the parent's current act_id (Number)" do
      parent = Card::Auth.as_bot { Card.fetch(parent_name) }
      expect(base_card).not_to be_nil
      expect(base_card.type_name).to eq("Number")
      expect(base_card.db_content.to_i).to eq(parent.acts.last&.id)
    end

    it "writes a verifiable +provenance record" do
      parent = Card::Auth.as_bot { Card.fetch(parent_name) }
      rec = JSON.parse(provenance.db_content)
      expect(rec["schema_version"]).to eq(1)
      expect(rec["parent_id"]).to eq(parent.id)
      expect(rec["parent_type"]).to eq("RichText")
      expect(rec["stamp_source"]).to eq("server_current")
      expect(rec["base_hash"]).to eq(ProposalProvenance.content_hash(parent.db_content))
      expect(rec["proposal_hash"]).to eq(ProposalProvenance.content_hash("<p>proposed</p>"))
      expect(rec["base_action_id"]).to be_a(Integer)
    end

    it "refreshes proposal_hash (not base_hash) when the proposal is edited" do
      before_rec = JSON.parse(provenance.db_content)
      Card::Auth.as_bot { Card.fetch(proposal_name).update!(content: "<p>edited</p>") }
      after_rec = JSON.parse(provenance.db_content)
      expect(after_rec["proposal_hash"]).to eq(ProposalProvenance.content_hash("<p>edited</p>"))
      expect(after_rec["proposal_hash"]).not_to eq(before_rec["proposal_hash"])
      expect(after_rec["base_hash"]).to eq(before_rec["base_hash"])
    end
  end

  context "type alignment" do
    it "coerces the proposal to a Markdown parent's format" do
      Card::Auth.as_bot do
        Card.create!(name: parent_name, type: "Markdown", content: "# base")
        Card.create!(name: proposal_name, type: "RichText", content: "# proposed")
      end
      expect(Card::Auth.as_bot { Card.fetch(proposal_name).type_name }).to eq("Markdown")
    end
  end

  context "generator-supplied base override" do
    before do
      Card::Auth.as_bot do
        Card.create!(name: parent_name, type: "RichText", content: "<p>v1</p>")
        first_act = Card.fetch(parent_name).acts.last.id
        Card.fetch(parent_name).update!(content: "<p>v2</p>") # parent moves on
        # Generator pre-stamps the read-time base (the older act).
        Card.create!(name: "#{proposal_name}+base", type: "Number", content: first_act.to_s)
        Card.create!(name: proposal_name, type: "RichText", content: "<p>proposed</p>")
      end
    end

    it "preserves the pre-stamped base and records generator_read_time" do
      parent = Card::Auth.as_bot { Card.fetch(parent_name) }
      create_act = parent.acts.first.id
      expect(base_card.db_content.to_i).to eq(create_act)
      rec = JSON.parse(provenance.db_content)
      expect(rec["stamp_source"]).to eq("generator_read_time")
      expect(rec["base_act_id"]).to eq(create_act)
    end
  end
end
