# frozen_string_literal: true

require "spec_helper"

RSpec.describe "MCP API Full Integration Flow", type: :request do
  include McpApiTestHelper

  let(:api_key) { ENV["MCP_API_KEY"] || "test-integration-key" }

  before do
    ENV["MCP_API_KEY"] = api_key
    ENV["MCP_JWT_ENABLED"] = "true"

    # Create service accounts
    Card::Auth.as_bot do
      %w[mcp-user mcp-gm mcp-admin].each do |name|
        unless Card[name]
          Card.create!(
            name: name,
            type_id: Card.fetch_id(:user)
          )
        end
      end
    end
  end

  describe "Complete workflow: Auth → Render → Cards → JWKS" do
    it "completes full MCP workflow successfully" do
      # Step 1: Get JWT token
      post "/api/mcp/auth", params: {
        api_key: api_key,
        role: "admin"
      }

      expect(response).to have_http_status(:created)
      auth_data = json_response
      token = auth_data["token"]

      expect(token).to be_present
      expect(auth_data["role"]).to eq("admin")

      headers = { "Authorization" => "Bearer #{token}" }

      # Step 2: Verify JWKS is accessible
      get "/api/mcp/.well-known/jwks.json"

      expect(response).to have_http_status(:ok)
      jwks = json_response
      expect(jwks["keys"]).to be_an(Array)

      # Step 3: Convert Markdown to HTML
      markdown_content = <<~MD
        # Test Card

        This is a **test card** with [[Wiki+Link]].

        - Feature 1
        - Feature 2
      MD

      post "/api/mcp/render/markdown",
           params: { markdown: markdown_content },
           headers: headers

      expect(response).to have_http_status(:ok)
      render_data = json_response
      html_content = render_data["html"]

      expect(html_content).to include("<h1>Test Card</h1>")
      expect(html_content).to include("[[Wiki+Link]]")

      # Step 4: Create card with rendered HTML
      post "/api/mcp/cards",
           params: {
             name: "Test+Integration+Card",
             type: "RichText",
             content: html_content
           },
           headers: headers

      expect(response).to have_http_status(:created)
      card_data = json_response

      expect(card_data["name"]).to eq("Test+Integration+Card")
      expect(card_data["content"]).to include("[[Wiki+Link]]")

      # Step 5: Retrieve the card
      get "/api/mcp/cards/Test+Integration+Card", headers: headers

      expect(response).to have_http_status(:ok)
      retrieved_card = json_response

      expect(retrieved_card["name"]).to eq("Test+Integration+Card")
      expect(retrieved_card["content"]).to eq(html_content)

      # Step 6: Convert HTML back to Markdown
      post "/api/mcp/render",
           params: { html: retrieved_card["content"] },
           headers: headers

      expect(response).to have_http_status(:ok)
      markdown_result = json_response["markdown"]

      expect(markdown_result).to include("# Test Card")
      expect(markdown_result).to include("[[Wiki+Link]]")

      # Step 7: Update card with Markdown
      new_markdown = "# Updated Card\n\nUpdated content with [[New+Link]]."

      post "/api/mcp/render/markdown",
           params: { markdown: new_markdown },
           headers: headers

      new_html = json_response["html"]

      patch "/api/mcp/cards/Test+Integration+Card",
            params: { content: new_html },
            headers: headers

      expect(response).to have_http_status(:ok)
      updated_card = json_response

      expect(updated_card["content"]).to include("Updated content")
      expect(updated_card["content"]).to include("[[New+Link]]")

      # Step 8: Delete card (admin only)
      delete "/api/mcp/cards/Test+Integration+Card", headers: headers

      expect(response).to have_http_status(:ok)
      delete_result = json_response

      expect(delete_result["status"]).to eq("deleted")

      # Step 9: Verify card is deleted
      get "/api/mcp/cards/Test+Integration+Card", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "Authentication backward compatibility" do
    it "supports both JWT and MessageVerifier tokens" do
      # Get JWT token
      ENV["MCP_JWT_ENABLED"] = "true"
      post "/api/mcp/auth", params: { api_key: api_key, role: "user" }
      jwt_token = json_response["token"]

      # Get MessageVerifier token
      ENV["MCP_JWT_ENABLED"] = "false"
      post "/api/mcp/auth", params: { api_key: api_key, role: "user" }
      mv_token = json_response["token"]

      # Both tokens should work for authenticated requests
      get "/api/mcp/types", headers: { "Authorization" => "Bearer #{jwt_token}" }
      expect(response).to have_http_status(:ok)

      get "/api/mcp/types", headers: { "Authorization" => "Bearer #{mv_token}" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "Role-based access control" do
    it "enforces role restrictions on delete operations" do
      # Create test card as admin
      admin_token = generate_jwt_token(role: "admin")
      post "/api/mcp/cards",
           params: { name: "Test+RBAC+Card", type: "RichText", content: "<p>Test</p>" },
           headers: auth_headers(admin_token)

      expect(response).to have_http_status(:created)

      # Try to delete as user (should fail)
      user_token = generate_jwt_token(role: "user")
      delete "/api/mcp/cards/Test+RBAC+Card", headers: auth_headers(user_token)

      expect(response).to have_http_status(:forbidden)
      error = json_response["error"]
      expect(error["code"]).to eq("permission_denied")

      # Try to delete as GM (should fail)
      gm_token = generate_jwt_token(role: "gm")
      delete "/api/mcp/cards/Test+RBAC+Card", headers: auth_headers(gm_token)

      expect(response).to have_http_status(:forbidden)

      # Delete as admin (should succeed)
      delete "/api/mcp/cards/Test+RBAC+Card", headers: auth_headers(admin_token)

      expect(response).to have_http_status(:ok)
    end
  end
end
