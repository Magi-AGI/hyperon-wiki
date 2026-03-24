# frozen_string_literal: true

require "spec_helper"

RSpec.describe Api::Mcp::AuthController, type: :request do
  let(:valid_api_key) { ENV["MCP_API_KEY"] || "test-api-key" }

  before do
    ENV["MCP_API_KEY"] = valid_api_key
  end

  describe "POST /api/mcp/auth" do
    context "with valid credentials" do
      it "returns JWT token when JWT enabled" do
        ENV["MCP_JWT_ENABLED"] = "true"

        post "/api/mcp/auth", params: {
          api_key: valid_api_key,
          role: "user"
        }

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)

        expect(json).to have_key("token")
        expect(json["role"]).to eq("user")
        expect(json["expires_in"]).to be > 0
        expect(json["expires_at"]).to be > Time.now.to_i

        # Verify it's actually a JWT (3 parts separated by dots)
        expect(json["token"].split(".").size).to eq(3)
      end

      it "returns MessageVerifier token when JWT disabled" do
        ENV["MCP_JWT_ENABLED"] = "false"

        post "/api/mcp/auth", params: {
          api_key: valid_api_key,
          role: "gm"
        }

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)

        expect(json).to have_key("token")
        expect(json["role"]).to eq("gm")

        # MessageVerifier tokens don't have JWT format
        expect(json["token"].split(".").size).not_to eq(3)
      end

      it "accepts api_key from header" do
        post "/api/mcp/auth",
             params: { role: "admin" },
             headers: { "X-API-Key" => valid_api_key }

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["role"]).to eq("admin")
      end

      it "supports all three roles" do
        %w[user gm admin].each do |role|
          post "/api/mcp/auth", params: {
            api_key: valid_api_key,
            role: role
          }

          expect(response).to have_http_status(:created)
          json = JSON.parse(response.body)
          expect(json["role"]).to eq(role)
        end
      end
    end

    context "with invalid credentials" do
      it "rejects missing api_key" do
        post "/api/mcp/auth", params: { role: "user" }

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json["error"]["code"]).to eq("validation_error")
        expect(json["error"]["message"]).to include("Missing api_key")
      end

      it "rejects missing role" do
        post "/api/mcp/auth", params: { api_key: valid_api_key }

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json["error"]["code"]).to eq("validation_error")
        expect(json["error"]["message"]).to include("Missing role")
      end

      it "rejects invalid role" do
        post "/api/mcp/auth", params: {
          api_key: valid_api_key,
          role: "superadmin"
        }

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json["error"]["code"]).to eq("validation_error")
        expect(json["error"]["message"]).to include("Invalid role")
        expect(json["error"]["details"]["valid_roles"]).to eq(%w[user gm admin])
      end

      it "rejects wrong api_key" do
        post "/api/mcp/auth", params: {
          api_key: "wrong-key",
          role: "user"
        }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json["error"]["code"]).to eq("invalid_credentials")
      end
    end

    context "token expiry configuration" do
      it "respects MCP_TOKEN_TTL environment variable" do
        ENV["MCP_TOKEN_TTL"] = "7200"

        post "/api/mcp/auth", params: {
          api_key: valid_api_key,
          role: "user"
        }

        json = JSON.parse(response.body)
        expect(json["expires_in"]).to eq(7200)
      end

      it "uses default TTL when not configured" do
        ENV.delete("MCP_TOKEN_TTL")
        ENV.delete("JWT_EXPIRY")

        post "/api/mcp/auth", params: {
          api_key: valid_api_key,
          role: "user"
        }

        json = JSON.parse(response.body)
        expect(json["expires_in"]).to eq(3600) # Default 1 hour
      end
    end
  end
end
