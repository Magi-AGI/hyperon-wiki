# frozen_string_literal: true

module Api
  module Mcp
    class JwksController < BaseController
      # No authentication required for JWKS endpoint (public keys)

      # GET /api/mcp/.well-known/jwks.json
      # Returns JSON Web Key Set for JWT verification
      def show
        render json: McpApi::JwtService.jwks
      end
    end
  end
end
