# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP Jobs API", type: :request do
  # Full HTTP request tests - catches routing issues

  let(:gm_token) { generate_test_token(role: "gm") }
  let(:user_token) { generate_test_token(role: "user") }
  let(:admin_token) { generate_test_token(role: "admin") }

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  describe "POST /api/mcp/jobs/spoiler-scan" do
    before do
      # Create test cards
      @terms_card = Card.create!(
        name: "Test+Spoiler Terms",
        type_id: Card.fetch_id("Basic"),
        content: "spoiler1\nspoiler2\nspoiler3"
      )

      @results_card_name = "Test+Spoiler Results"
    end

    context "route existence" do
      it "routes to jobs#spoiler_scan correctly" do
        # This would have caught the missing route error
        post "/api/mcp/jobs/spoiler-scan",
          params: {
            terms_card: @terms_card.name,
            results_card: @results_card_name,
            scope: "player"
          },
          headers: auth_headers(gm_token),
          as: :json

        # Should not be 404
        expect(response).not_to have_http_status(:not_found)
      end

      it "does not raise NameError about uninitialized constant" do
        # This would have caught the Api::Mcp::Jobs constant lookup issue
        expect {
          post "/api/mcp/jobs/spoiler-scan",
            params: {
              terms_card: @terms_card.name,
              results_card: @results_card_name
            },
            headers: auth_headers(gm_token),
            as: :json
        }.not_to raise_error(NameError, /uninitialized constant.*Jobs/)
      end
    end

    context "with GM role" do
      it "executes spoiler scan successfully" do
        post "/api/mcp/jobs/spoiler-scan",
          params: {
            terms_card: @terms_card.name,
            results_card: @results_card_name,
            scope: "player",
            limit: 100
          },
          headers: auth_headers(gm_token),
          as: :json

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("completed")
        expect(json).to have_key("matches")
        expect(json).to have_key("terms_checked")
      end

      it "finds terms card with Card::Auth.as context" do
        # This would have caught the missing Card::Auth.as wrapper
        post "/api/mcp/jobs/spoiler-scan",
          params: {
            terms_card: @terms_card.name,
            results_card: @results_card_name
          },
          headers: auth_headers(gm_token),
          as: :json

        expect(response).to have_http_status(:success)
      end
    end

    context "with Admin role" do
      it "allows admin to run spoiler scan" do
        post "/api/mcp/jobs/spoiler-scan",
          params: {
            terms_card: @terms_card.name,
            results_card: @results_card_name
          },
          headers: auth_headers(admin_token),
          as: :json

        expect(response).to have_http_status(:success)
      end
    end

    context "with User role" do
      it "returns 403 Forbidden" do
        post "/api/mcp/jobs/spoiler-scan",
          params: {
            terms_card: @terms_card.name,
            results_card: @results_card_name
          },
          headers: auth_headers(user_token),
          as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with missing parameters" do
      it "returns validation error for missing terms_card" do
        post "/api/mcp/jobs/spoiler-scan",
          params: {
            results_card: @results_card_name
          },
          headers: auth_headers(gm_token),
          as: :json

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json["error"]["code"]).to eq("validation_error")
      end

      it "returns validation error for missing results_card" do
        post "/api/mcp/jobs/spoiler-scan",
          params: {
            terms_card: @terms_card.name
          },
          headers: auth_headers(gm_token),
          as: :json

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with non-existent terms card" do
      it "returns not_found error" do
        post "/api/mcp/jobs/spoiler-scan",
          params: {
            terms_card: "NonExistent Card",
            results_card: @results_card_name
          },
          headers: auth_headers(gm_token),
          as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  private

  def generate_test_token(role:)
    payload = {
      sub: "user:Test User",
      role: role,
      iss: "magi-archive-mcp",
      iat: Time.now.to_i,
      exp: (Time.now + 1.hour).to_i,
      jti: SecureRandom.uuid
    }

    McpApi::JwtService.generate_token(payload)
  end
end
