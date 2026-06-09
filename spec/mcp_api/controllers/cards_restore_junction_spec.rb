# frozen_string_literal: true

require "spec_helper"

# T4 regression (MCP Bug #5): restore_card must recover trashed JUNCTION (+tag)
# cards. Trashed junction cards have null name/key columns (Decko keys them by
# left_id+right_id), so set_card's name-based lookup used to miss them and
# restore returned 404. The fix resolves trashed junctions by left_id+right_id
# (find_trashed_junction) and expires the cache after un-trashing so the card
# resolves by name again.
RSpec.describe "Api::Mcp::CardsController restore (trashed junction)", type: :request do
  include McpApiTestHelper

  let(:admin_token) { generate_jwt_token(role: "admin") }
  let(:parent_name) { "ZZRestoreParent#{SecureRandom.hex(4)}" }
  let(:tag_name) { "#{parent_name}+tag" }

  before do
    Card::Auth.as_bot do
      Card.create!(name: "mcp-admin", type_id: Card.fetch_id(:user)) unless Card["mcp-admin"]
      Card.create!(name: parent_name, type: "RichText", content: "parent")
      Card.create!(name: tag_name, type: "Pointer", content: "ai_generated")
      Card[tag_name].delete! # move the +tag junction card to trash
    end
  end

  after do
    Card::Auth.as_bot do
      [tag_name, parent_name].each { |n| Card[n]&.delete! }
    end
  end

  it "is genuinely trashed and not fetchable by name beforehand" do
    expect(Card::Auth.as_bot { Card.fetch(tag_name) }).to be_nil
  end

  it "finds and restores a trashed +tag junction card" do
    post "/api/mcp/cards/#{tag_name}/restore",
         params: { from_trash: true }, headers: auth_headers(admin_token)

    expect(response).to have_http_status(:ok)
    expect(json_response["success"]).to be true

    # Resolves by name again (cache expired) with content intact.
    restored = Card::Auth.as_bot { Card.fetch(tag_name) }
    expect(restored).not_to be_nil
    expect(restored.trash).to be false
    expect(restored.db_content.to_s).to include("ai_generated")
  end

  it "does not return 404 for a trashed junction (the Bug #5 symptom)" do
    post "/api/mcp/cards/#{tag_name}/restore",
         params: { from_trash: true }, headers: auth_headers(admin_token)

    expect(response.status).not_to eq(404)
  end
end
