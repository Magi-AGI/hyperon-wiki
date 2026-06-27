# frozen_string_literal: true

require "spec_helper"
require_relative "../../mod/editorial_review/lib/block_merge"

# WS6 Phase 8.1 — capability gating + the mutual-exclusion invariant.
#
# Ports the dev-runner regressions (16/16 capability-gating, 6/6 invariant) into
# the permanent suite so future changes cannot silently reintroduce a blunt
# AI-draft -> parent overwrite. Needs a Decko test DATABASE (provisioned at
# runtime — never prod).
#
# "Editor" here = any user who passes parent.ok?(:update). We model that with a
# parent whose +*self+*update rule is restricted to Administrator: a user holding
# the Administrator role is update-capable ("editor"); a plain signed-in user is
# not. WS6 hard-codes no role name — the gate is purely the capability.
RSpec.describe "editorial_review capability gating (WS6 Phase 8.1)" do
  def uniq
    "WS6CG#{SecureRandom.hex(4)}"
  end

  let(:parent_name)   { uniq }
  let(:ai_name)       { "#{parent_name}+ai draft" }
  let(:proposal_name) { "#{parent_name}+proposal" }
  let(:draft_name)    { "#{proposal_name}+merge draft" }
  let(:editor_name)   { "#{parent_name} Editor" }
  let(:plain_name)    { "#{parent_name} Plain" }

  let(:parent0) { "<p>A</p>\n<p>B</p>" }
  let(:ai0)     { "<p>A</p>\n<p>B-ai</p>" }

  # The ai_only hunk id for parent0 (base==current) -> ai0.
  let(:ai_hunk) do
    BlockMerge.merge(base: parent0, current: parent0, proposal: ai0, format: :html)[:chunks]
              .find { |c| c[:type] == :ai_only }[:id]
  end

  def parent_content
    Card::Auth.as_bot { Card.fetch(parent_name)&.db_content }
  end

  def as_editor(&blk)
    Card::Auth.as(Card.fetch(editor_name).id, &blk)
  end

  def as_plain(&blk)
    Card::Auth.as(Card.fetch(plain_name).id, &blk)
  end

  def parent_act_id
    Card::Auth.as_bot do
      Card::Action.where(card_id: Card.fetch(parent_name).id)
                  .where(draft: [false, nil]).order(id: :desc).first&.act&.id
    end
  end

  before do
    Card::Auth.as_bot do
      Card.create!(name: parent_name, type: "RichText", content: parent0)
      Card.create!(name: ai_name, type: "RichText", content: ai0)
      # Restrict parent update to Administrator: a plain signed-in user is a non-editor here.
      Card.create!(name: "#{parent_name}+*self+*update", type_id: Card::PointerID,
                   content: "[[Administrator]]")
      # An update-capable "editor" (Administrator) and a plain signed-in non-editor.
      Card.create!(name: editor_name, type_id: Card::UserID)
      Card.create!(name: "#{editor_name}+*roles", type_id: Card::PointerID,
                   content: "[[Administrator]]")
      Card.create!(name: plain_name, type_id: Card::UserID)
    end
  end

  after do
    %i[legacy_bridge_from proposal_source apply_to_parent merge_draft hunk_selections parent_act_id]
      .each { |k| Card::Env.params.delete(k) }
    Card::Auth.as_bot do
      ["#{proposal_name}+merge audit", "#{draft_name}+audit", draft_name,
       "#{proposal_name}+provenance", "#{proposal_name}+base", proposal_name,
       "#{editor_name}+*roles", editor_name, plain_name,
       "#{parent_name}+*self+*update", "#{parent_name}+tag", ai_name, parent_name]
        .each { |n| Card.fetch(n)&.delete! }
    end
  end

  describe "capability gate on the legacy bridge (server-side guard_legacy_bridge)" do
    it "rejects a bridge started by a signed-in non-editor and leaves the parent unchanged" do
      Card::Env.params[:legacy_bridge_from] = ai_name
      expect do
        as_plain { Card.create!(name: proposal_name, type: "RichText", content: "") }
      end.to raise_error(/permission/i)
      expect(Card.fetch(proposal_name)).to be_nil
      expect(parent_content).to eq(parent0)
    end

    it "allows an update-capable editor to start the bridge (proposal seeded from +AI)" do
      Card::Env.params[:legacy_bridge_from] = ai_name
      Card::Env.params[:proposal_source] = "legacy_bridge"
      as_editor { Card.create!(name: proposal_name, type: "RichText", content: "") }
      expect(Card.fetch(proposal_name)).not_to be_nil
      expect(Card::Auth.as_bot { Card.fetch(proposal_name).db_content }).to eq(ai0)
      expect(parent_content).to eq(parent0)
    end
  end

  describe "ai_draft_can_bridge? capability check (UI gate)" do
    it "is false for a non-editor and true for an editor" do
      ad = Card.fetch(ai_name).format(:html)
      expect(as_plain  { ad.send(:ai_draft_can_bridge?, Card.fetch(parent_name)) }).to be_falsey
      expect(as_editor { ad.send(:ai_draft_can_bridge?, Card.fetch(parent_name)) }).to be_truthy
    end
  end

  describe "ai_draft_aware 'Merge AI Draft -> Parent' button (Option A redirect)" do
    it "carries no direct parent-update payload or merge event; routes to workbench/bridge" do
      html = as_editor { Card.fetch(parent_name).format(:html).render(:ai_draft_link) }
      expect(html).to include("Merge AI Draft")
      expect(html).not_to include("merge_draft")            # no removed blunt event param
      expect(html).not_to match(/action["':> ]+update/i)    # no direct update action
      expect(html).not_to include("card[content]")          # no parent content overwrite
      # no proposal yet -> capability-gated legacy bridge form whose success lands in the workbench
      expect(html).to include("legacy_bridge_from")
      expect(html).to include("view=merge_workbench")
    end

    it "hides the merge button from a non-editor" do
      html = as_plain { Card.fetch(parent_name).format(:html).render(:ai_draft_link) }
      expect(html).not_to include("Merge AI Draft")
    end
  end

  describe "mutual exclusion: the parent changes ONLY via apply_merge_draft" do
    it "does not write the parent through the removed ?merge_draft=true event path" do
      Card::Env.params[:merge_draft] = "true"
      begin
        as_editor { Card.fetch(ai_name).update!(content: ai0) }
      rescue StandardError
        # no-op update may raise; the security assertion is the parent is untouched
      end
      expect(parent_content).to eq(parent0)
    end

    it "does not write the parent when a proposal is created or edited" do
      Card::Auth.as_bot { Card.create!(name: proposal_name, type: "RichText", content: ai0) }
      expect(parent_content).to eq(parent0)
      Card::Auth.as_bot { Card.fetch(proposal_name).update!(content: "<p>A</p>\n<p>B-ai2</p>") }
      expect(parent_content).to eq(parent0)
    end

    it "writes the parent ONLY through apply_merge_draft, and only for an update-capable user" do
      Card::Auth.as_bot { Card.create!(name: proposal_name, type: "RichText", content: ai0) }
      # Seed a merge draft that accepts the AI hunk (server re-derives from selections).
      Card::Env.params[:hunk_selections] = JSON.generate(ai_hunk => "proposal")
      Card::Env.params[:parent_act_id] = parent_act_id.to_s
      Card::Auth.as_bot { Card.create!(name: draft_name, type: "RichText", content: "seed") }
      Card::Env.params.delete(:hunk_selections)
      Card::Env.params.delete(:parent_act_id)

      draft_body = Card::Auth.as_bot { Card.fetch(draft_name).db_content }
      expect(draft_body).to eq(ai0)

      # (a) non-editor apply -> rejected; parent unchanged, no audit.
      Card::Env.params[:apply_to_parent] = "true"
      Card::Env.params[:parent_act_id] = parent_act_id.to_s
      begin
        as_plain { Card.fetch(draft_name).update!(content: draft_body) }
      rescue StandardError
        # rejected by the apply gate (or by draft perms) — either way no parent write
      end
      Card::Env.params.delete(:apply_to_parent)
      Card::Env.params.delete(:parent_act_id)
      expect(parent_content).to eq(parent0)
      expect(Card.fetch("#{proposal_name}+merge audit")).to be_nil

      # (b) editor apply -> parent updated via the gate, audit recorded.
      Card::Env.params[:apply_to_parent] = "true"
      Card::Env.params[:parent_act_id] = parent_act_id.to_s
      as_editor { Card.fetch(draft_name).update!(content: draft_body) }
      Card::Env.params.delete(:apply_to_parent)
      Card::Env.params.delete(:parent_act_id)

      expect(parent_content).to eq(ai0)
      expect(Card::Auth.as_bot { Card.fetch("#{proposal_name}+merge audit")&.db_content }).to be_present
    end
  end
end
