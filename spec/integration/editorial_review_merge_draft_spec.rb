# frozen_string_literal: true

require "spec_helper"
require_relative "../../mod/editorial_review/lib/block_merge"

# Integration specs for the +merge draft set (WS6 Phase 5). Exercise real Decko
# events + the workbench seed/reset/polish handoff, so they need a Decko test
# DATABASE (provisioned runtime — never prod). Mirrors the dev runner regressions
# for the polish-preserved / reset-rebuild / stale-reset behaviour Codex required.
RSpec.describe "editorial_review +merge draft set" do
  def uniq
    "WS6MD#{SecureRandom.hex(4)}"
  end

  let(:parent_name) { uniq }
  let(:proposal_name) { "#{parent_name}+proposal" }
  let(:draft_name) { "#{proposal_name}+merge draft" }
  let(:audit_name) { "#{draft_name}+audit" }

  def audit
    Card::Auth.as_bot { JSON.parse(Card.fetch(audit_name).db_content) }
  end

  def draft_content
    Card::Auth.as_bot { Card.fetch(draft_name).db_content }
  end

  def sha(str)
    "sha256:#{Digest::SHA256.hexdigest(str)}"
  end

  def parent_act_id
    Card::Auth.as_bot do
      Card::Action.where(card_id: Card.fetch(parent_name).id)
                  .where(draft: [false, nil]).order(id: :desc).first&.act&.id
    end
  end

  # The ai_only hunk id for "<p>A</p><p>B</p>" -> "<p>A</p><p>B-ai</p>".
  let(:ai_hunk) do
    BlockMerge.merge(base: "<p>A</p>\n<p>B</p>", current: "<p>A</p>\n<p>B</p>",
                     proposal: "<p>A</p>\n<p>B-ai</p>", format: :html)[:chunks]
              .find { |c| c[:type] == :ai_only }[:id]
  end

  before do
    Card::Auth.as_bot do
      Card.create!(name: parent_name, type: "RichText", content: "<p>A</p>\n<p>B</p>")
      Card.create!(name: proposal_name, type: "RichText", content: "<p>A</p>\n<p>B-ai</p>")
    end
  end

  after do
    Card::Env.params.delete(:hunk_selections)
    Card::Env.params.delete(:parent_act_id)
    Card::Auth.as_bot do
      [audit_name, draft_name, "#{proposal_name}+provenance", "#{proposal_name}+base",
       proposal_name, parent_name].each { |n| Card.fetch(n)&.delete! }
    end
  end

  def seed(selections, act_id: parent_act_id)
    Card::Env.params[:hunk_selections] = JSON.generate(selections)
    Card::Env.params[:parent_act_id] = act_id.to_s
    Card::Auth.as_bot { Card.create!(name: draft_name, type: "RichText", content: "client-junk") }
  end

  context "seed -> polish -> return (the silent-overwrite fix)" do
    it "re-derives content from selections at seed (client HTML ignored)" do
      seed({ ai_hunk => "proposal" })
      expect(draft_content).to eq("<p>A</p>\n<p>B-ai</p>")
      expect(audit["assembled_hash"]).to eq(audit["polished_hash"])
    end

    it "preserves manual polish and keeps assembled_hash immutable on native save" do
      seed({ ai_hunk => "proposal" })
      origin = audit["assembled_hash"]
      Card::Env.params.delete(:hunk_selections) # native editor save has no selections
      Card::Env.params.delete(:parent_act_id)
      Card::Auth.as_bot { Card.fetch(draft_name).update!(content: "<p>A</p>\n<p>B-ai</p><p>HUMAN POLISH</p>") }

      expect(draft_content).to include("HUMAN POLISH")
      expect(audit["assembled_hash"]).to eq(origin)            # immutable origin
      expect(audit["polished_hash"]).to eq(sha(draft_content)) # tracks the polish
      expect(audit["polished_hash"]).not_to eq(origin)
    end
  end

  context "explicit Reset & re-merge" do
    it "rebuilds content + assembled_hash from new selections, discarding polish" do
      seed({ ai_hunk => "proposal" })
      origin = audit["assembled_hash"]
      Card::Env.params.delete(:hunk_selections)
      Card::Auth.as_bot { Card.fetch(draft_name).update!(content: "<p>A</p>\n<p>B-ai</p><p>HUMAN POLISH</p>") }

      # reset: reject the AI change this time
      Card::Env.params[:hunk_selections] = JSON.generate({})
      Card::Env.params[:parent_act_id] = parent_act_id.to_s
      Card::Auth.as_bot { Card.fetch(draft_name).update!(content: "client-junk-again") }

      expect(draft_content).to eq("<p>A</p>\n<p>B</p>")    # current side; AI rejected
      expect(draft_content).not_to include("HUMAN POLISH") # polish discarded
      expect(audit["assembled_hash"]).to eq(sha(draft_content)) # REBUILT
      expect(audit["assembled_hash"]).not_to eq(origin)
      expect(audit["polished_hash"]).to eq(audit["assembled_hash"])
    end

    it "rejects a reset whose parent_act_id is stale (drift gate) and leaves content unchanged" do
      seed({ ai_hunk => "proposal" })
      before_content = draft_content

      Card::Env.params[:hunk_selections] = JSON.generate({ ai_hunk => "proposal" })
      Card::Env.params[:parent_act_id] = (parent_act_id + 999).to_s
      expect do
        Card::Auth.as_bot { Card.fetch(draft_name).update!(content: "should-not-take") }
      end.to raise_error(/parent changed/)
      expect(draft_content).to eq(before_content)
    end
  end

  context "workbench action buttons" do
    it "offers create when no draft, and open/reset (not create) once a draft exists" do
      html1 = Card::Auth.as_bot { Card.fetch(proposal_name).format(:html).render(:merge_workbench) }
      expect(html1).to include('<button type="button" data-ws6="polish"')
      expect(html1).not_to include('<button type="button" data-ws6="open-draft"')

      seed({ ai_hunk => "proposal" })
      html2 = Card::Auth.as_bot { Card.fetch(proposal_name).format(:html).render(:merge_workbench) }
      expect(html2).to include('<button type="button" data-ws6="open-draft"')
      expect(html2).to include('<button type="button" data-ws6="reset"')
      expect(html2).not_to include('<button type="button" data-ws6="polish"')
      expect(html2).to include('class="ws6-draft-notice"')
    end
  end
end
