# frozen_string_literal: true

require "spec_helper"

RSpec.describe "JWKS Endpoint", type: :request do
  describe "GET /api/mcp/.well-known/jwks.json" do
    it "returns JWKS without authentication" do
      get "/api/mcp/.well-known/jwks.json"

      expect(response).to have_http_status(:ok)
    end

    it "returns valid JWKS structure" do
      get "/api/mcp/.well-known/jwks.json"

      json = JSON.parse(response.body)

      expect(json).to have_key("keys")
      expect(json["keys"]).to be_an(Array)
      expect(json["keys"]).not_to be_empty
    end

    it "includes required JWK fields" do
      get "/api/mcp/.well-known/jwks.json"

      json = JSON.parse(response.body)
      key = json["keys"].first

      expect(key).to include("kty", "kid", "use", "alg", "n", "e")
    end

    it "specifies RS256 algorithm" do
      get "/api/mcp/.well-known/jwks.json"

      json = JSON.parse(response.body)
      key = json["keys"].first

      expect(key["alg"]).to eq("RS256")
      expect(key["use"]).to eq("sig")
      expect(key["kty"]).to eq("RSA")
    end

    it "includes key ID from configuration" do
      get "/api/mcp/.well-known/jwks.json"

      json = JSON.parse(response.body)
      key = json["keys"].first

      expected_kid = ENV.fetch("JWT_KEY_ID", "key-001")
      expect(key["kid"]).to eq(expected_kid)
    end

    it "can be used to verify tokens" do
      # Generate a token
      token = McpApi::JwtService.generate_token(
        role: "user",
        api_key_id: "test"
      )

      # Get JWKS
      get "/api/mcp/.well-known/jwks.json"
      jwks = JSON.parse(response.body)

      # Extract public key from JWKS
      key_data = jwks["keys"].first
      n = Base64.urlsafe_decode64(key_data["n"])
      e = Base64.urlsafe_decode64(key_data["e"])

      public_key = OpenSSL::PKey::RSA.new
      public_key.set_key(
        OpenSSL::BN.new(n, 2),
        OpenSSL::BN.new(e, 2),
        nil
      )

      # Verify token with public key from JWKS
      decoded = JWT.decode(token, public_key, true, algorithm: "RS256")

      expect(decoded).to be_an(Array)
      expect(decoded.first["role"]).to eq("user")
    end
  end
end
