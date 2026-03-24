# frozen_string_literal: true

require "spec_helper"

RSpec.describe McpApi::JwtService do
  describe ".generate_token" do
    it "generates a valid JWT token" do
      token = described_class.generate_token(
        role: "admin",
        api_key_id: "test-key-123"
      )

      expect(token).to be_a(String)
      expect(token.split(".").size).to eq(3) # JWT has 3 parts
    end

    it "includes required claims in payload" do
      token = described_class.generate_token(
        role: "gm",
        api_key_id: "test-key-456",
        expires_in: 7200
      )

      payload = described_class.verify_token(token)

      expect(payload["role"]).to eq("gm")
      expect(payload["sub"]).to eq("test-key-456")
      expect(payload["iss"]).to eq(ENV.fetch("JWT_ISSUER", "magi-archive"))
      expect(payload["iat"]).to be_a(Integer)
      expect(payload["exp"]).to be_a(Integer)
      expect(payload["jti"]).to be_a(String)
      expect(payload["kid"]).to be_a(String)
    end

    it "respects custom expiry time" do
      token = described_class.generate_token(
        role: "user",
        api_key_id: "test",
        expires_in: 1800
      )

      payload = described_class.verify_token(token)
      expiry_delta = payload["exp"] - payload["iat"]

      expect(expiry_delta).to eq(1800)
    end
  end

  describe ".verify_token" do
    it "verifies and decodes valid tokens" do
      original_payload = {
        role: "admin",
        api_key_id: "test-key"
      }

      token = described_class.generate_token(**original_payload)
      decoded = described_class.verify_token(token)

      expect(decoded["role"]).to eq("admin")
      expect(decoded["sub"]).to eq("test-key")
    end

    it "returns nil for invalid tokens" do
      invalid_token = "invalid.jwt.token"
      result = described_class.verify_token(invalid_token)

      expect(result).to be_nil
    end

    it "returns nil for expired tokens" do
      token = described_class.generate_token(
        role: "user",
        api_key_id: "test",
        expires_in: -10 # Already expired
      )

      result = described_class.verify_token(token)

      expect(result).to be_nil
    end

    it "returns nil for tokens with wrong issuer" do
      # Generate token with different service
      payload = {
        sub: "test",
        role: "user",
        iss: "wrong-issuer",
        iat: Time.now.to_i,
        exp: Time.now.to_i + 3600
      }

      # We need access to private key for this test
      private_key = described_class.send(:private_key)
      token = JWT.encode(payload, private_key, "RS256")

      result = described_class.verify_token(token)

      expect(result).to be_nil
    end
  end

  describe ".jwks" do
    it "returns valid JWKS structure" do
      jwks = described_class.jwks

      expect(jwks).to have_key(:keys)
      expect(jwks[:keys]).to be_an(Array)
      expect(jwks[:keys].first).to include(:kty, :kid, :use, :alg, :n, :e)
    end

    it "includes RS256 algorithm" do
      jwks = described_class.jwks

      expect(jwks[:keys].first[:alg]).to eq("RS256")
      expect(jwks[:keys].first[:use]).to eq("sig")
    end

    it "includes key ID" do
      jwks = described_class.jwks

      expect(jwks[:keys].first[:kid]).to eq(ENV.fetch("JWT_KEY_ID", "key-001"))
    end
  end

  describe "key generation" do
    context "when no key files exist" do
      it "generates ephemeral keys for development" do
        # This happens automatically in the service
        token = described_class.generate_token(role: "user", api_key_id: "test")

        expect(token).to be_a(String)
      end

      it "logs warning about ephemeral keys" do
        expect(Rails.logger).to receive(:warn).with(/generating ephemeral key/)

        # Force regeneration by clearing memoization
        described_class.instance_variable_set(:@private_key, nil)
        described_class.send(:private_key)
      end
    end
  end
end
