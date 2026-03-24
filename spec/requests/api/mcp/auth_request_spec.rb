# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP Auth API", type: :request do
  # Full HTTP request tests - catches routing, constant lookup, and integration issues

  describe "POST /api/mcp/auth" do
    let(:valid_username) { "test@example.com" }
    let(:valid_password) { "password123" }

    context "with username and password" do
      before do
        # Create a real User card in Decko
        @user_card = Card.create!(
          name: valid_username,
          type_id: Card.fetch_id("User")
        )

        # Set password
        password_card = @user_card.fetch(trait: :password, new: {})
        password_card.content = BCrypt::Password.create(valid_password)
        password_card.save!
      end

      it "returns JWT token for valid credentials" do
        post "/api/mcp/auth", params: {
          username: valid_username,
          password: valid_password,
          role: "user"
        }, as: :json

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json).to have_key("token")
        expect(json).to have_key("role")
        expect(json).to have_key("expires_at")
      end

      it "returns authentication_failed for invalid password" do
        post "/api/mcp/auth", params: {
          username: valid_username,
          password: "wrong_password",
          role: "user"
        }, as: :json

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json["error"]["code"]).to eq("authentication_failed")
      end

      it "returns authentication_failed for non-existent user" do
        post "/api/mcp/auth", params: {
          username: "nonexistent@example.com",
          password: "password",
          role: "user"
        }, as: :json

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json["error"]["code"]).to eq("authentication_failed")
      end

      it "does not raise NameError with nested constant lookup" do
        # This would have caught the ::Mcp::UserAuthenticator issue
        expect {
          post "/api/mcp/auth", params: {
            username: valid_username,
            password: valid_password
          }, as: :json
        }.not_to raise_error(NameError)
      end
    end

    context "with API key" do
      before do
        @api_key_record = McpApiKey.generate(
          name: "Test Key",
          roles: ["user"],
          rate_limit: 1000,
          created_by: "test"
        )
        @api_key = @api_key_record[:api_key]
      end

      it "returns JWT token for valid API key" do
        post "/api/mcp/auth", params: {
          api_key: @api_key,
          role: "user"
        }, as: :json

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json).to have_key("token")
      end

      it "returns authentication_failed for invalid API key" do
        post "/api/mcp/auth", params: {
          api_key: "invalid_key_" + ("a" * 50),
          role: "user"
        }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with missing parameters" do
      it "returns validation_error when neither username nor api_key provided" do
        post "/api/mcp/auth", params: {
          role: "user"
        }, as: :json

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json["error"]["code"]).to eq("validation_error")
        expect(json["error"]["message"]).to include("username")
      end
    end

    context "route accessibility" do
      it "is accessible without authentication" do
        # Auth endpoint should not require token
        post "/api/mcp/auth", params: {
          username: "test",
          password: "test"
        }, as: :json

        # Should not get 401 for missing token
        expect(response.status).not_to eq(401)
      end
    end
  end
end
