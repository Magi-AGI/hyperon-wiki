# frozen_string_literal: true

# MCP API test helper - loaded after main spec_helper
module McpApiTestHelper
  def generate_test_api_key
    "test-api-key-#{SecureRandom.hex(8)}"
  end

  def generate_jwt_token(role: "user", api_key_id: "test-key")
    McpApi::JwtService.generate_token(
      role: role,
      api_key_id: api_key_id,
      expires_in: 3600
    )
  end

  def generate_message_verifier_token(role: "user", api_key: "test-key")
    payload = {
      role: role,
      api_key: api_key.slice(0, 8),
      iat: Time.now.to_i,
      exp: Time.now.to_i + 3600
    }
    Rails.application.message_verifier(:mcp_auth).generate(payload)
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def json_response
    JSON.parse(response.body)
  end
end

RSpec.configure do |config|
  config.include McpApiTestHelper, type: :request
end
