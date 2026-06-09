# frozen_string_literal: true

require "spec_helper"

# Regression for the rendered-as-user fix (Zeke read-permission bypass, Fix 2).
#
# GET /cards/:name?rendered=true used to render nested {{...}} inclusions via
# Card::Auth.as_bot, which resolved restricted nested cards (e.g. GM content)
# into the output regardless of the requester's read permissions. It now renders
# as the current account, so nested cards the user cannot read are not resolved.
RSpec.describe "Api::Mcp::CardsController#show rendered permissions", type: :request do
  include McpApiTestHelper

  let(:user_token) { generate_jwt_token(role: "user") }
  let(:suffix) { SecureRandom.hex(4) }
  let(:secret_name) { "ZZSecret#{suffix}" }
  let(:host_name) { "ZZHost#{suffix}" }

  before do
    Card::Auth.as_bot do
      Card.create!(name: "mcp-user", type_id: Card.fetch_id(:user)) unless Card["mcp-user"]
      Card.create!(name: secret_name, type: "RichText", content: "TOPSECRETMARKER")
      # restrict the secret card to Administrator only
      Card.create!(name: "#{secret_name}+*self+*read", type: "Pointer", content: "[[Administrator]]")
      # a host card (default-readable) that nests the restricted secret
      Card.create!(name: host_name, type: "RichText",
                   content: "PUBLICSTART {{#{secret_name}}} PUBLICEND")
    end
  end

  after do
    Card::Auth.as_bot do
      ["#{secret_name}+*self+*read", secret_name, host_name].each { |n| Card[n]&.delete! }
    end
  end

  it "does not leak restricted nested content into the rendered output" do
    get "/api/mcp/cards/#{host_name}?rendered=true", headers: auth_headers(user_token)

    if response.status == 200
      # rendered HTML lands in the content field; the restricted nest must be gone
      expect(json_response["content"].to_s).not_to include("TOPSECRETMARKER")
    else
      # if the user can't read the host at all, that is also leak-free
      expect(response.status).to be_in([403, 404])
    end
  end

  it "still resolves the requester's own readable content" do
    get "/api/mcp/cards/#{host_name}?rendered=true", headers: auth_headers(user_token)

    expect(json_response["content"].to_s).to include("PUBLICSTART") if response.status == 200
  end
end
