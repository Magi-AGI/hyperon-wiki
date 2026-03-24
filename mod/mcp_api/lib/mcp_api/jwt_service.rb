# frozen_string_literal: true

require "jwt"
require "openssl"

module McpApi
  class JwtService
    class << self
      # Generate RS256 JWT for given role and API key
      def generate_token(role:, api_key_id:, expires_in: nil)
        expires_in ||= token_ttl
        now = Time.now.to_i

        payload = {
          sub: api_key_id,
          role: role,
          iss: issuer,
          iat: now,
          exp: now + expires_in,
          jti: SecureRandom.uuid,
          kid: key_id
        }

        JWT.encode(payload, private_key, "RS256", kid: key_id)
      end

      # Verify and decode JWT token
      def verify_token(token)
        JWT.decode(
          token,
          public_key,
          true,
          {
            algorithm: "RS256",
            iss: issuer,
            verify_iss: true,
            verify_iat: true,
            verify_exp: true
          }
        ).first
      rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::InvalidIssuerError => e
        Rails.logger.warn("JWT verification failed: #{e.message}")
        nil
      end

      # Get JWKS (JSON Web Key Set) for public key distribution
      def jwks
        jwk = JWT::JWK.new(public_key)
        {
          keys: [
            {
              kty: jwk[:kty],
              kid: key_id,
              use: "sig",
              alg: "RS256",
              n: jwk[:n],
              e: jwk[:e]
            }
          ]
        }
      end

      private

      def private_key
        @private_key ||= begin
          key_path = ENV["JWT_PRIVATE_KEY_PATH"]
          if key_path && File.exist?(key_path)
            OpenSSL::PKey::RSA.new(File.read(key_path))
          elsif Rails.env.production?
            # Fail fast in production - require configured keys
            raise "JWT_PRIVATE_KEY_PATH must be set and point to a valid key file in production"
          else
            # Generate ephemeral key if no key file (development/test only)
            Rails.logger.warn("No JWT private key found; generating ephemeral key (not for production!)")
            generate_key_pair[:private]
          end
        end
      end

      def public_key
        @public_key ||= begin
          key_path = ENV["JWT_PUBLIC_KEY_PATH"]
          if key_path && File.exist?(key_path)
            OpenSSL::PKey::RSA.new(File.read(key_path))
          elsif Rails.env.production?
            # Fail fast in production - require configured keys
            raise "JWT_PUBLIC_KEY_PATH must be set and point to a valid key file in production"
          else
            # Use public key from private key (development/test only)
            private_key.public_key
          end
        end
      end

      def generate_key_pair
        rsa_key = OpenSSL::PKey::RSA.new(2048)
        {
          private: rsa_key,
          public: rsa_key.public_key
        }
      end

      def key_id
        ENV.fetch("JWT_KEY_ID", "key-001")
      end

      def issuer
        ENV.fetch("JWT_ISSUER", "hyperon")
      end

      def token_ttl
        (ENV["JWT_EXPIRY"] || 3600).to_i
      end
    end
  end
end
