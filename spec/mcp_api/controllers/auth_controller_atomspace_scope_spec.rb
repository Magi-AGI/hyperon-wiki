# frozen_string_literal: true

require "spec_helper"

# Mint-path proof for POLICY REV5: the scope claim that actually lands in the issued JWT.
#
# The grant matrix itself is unit-tested in spec/mcp_api/lib/atomspace_grants_spec.rb; this tier
# proves AuthController wires the authenticated user card into AtomspaceGrants (and that the API
# key path deliberately does not). Mcp::UserAuthenticator.authenticate is stubbed so no Decko
# user/password/role cards need seeding.
RSpec.describe Api::Mcp::AuthController, type: :request do
  let(:user_card) { double("user_card", name: "Alice") }

  read_scope  = "mcp:atomspace:read"
  write_scope = "mcp:atomspace:write"
  admin_scope = "mcp:atomspace:admin"

  around do |example|
    vars = %w[ATOMSPACE_READ_GRANTS MCP_API_KEY]
    saved = vars.each_with_object({}) { |var, memo| memo[var] = ENV[var] }
    example.run
  ensure
    vars.each { |var| saved[var].nil? ? ENV.delete(var) : ENV[var] = saved[var] }
  end

  before do
    ENV.delete("ATOMSPACE_READ_GRANTS")
    allow(::Mcp::UserAuthenticator).to receive(:check_admin_status).and_return(false)
    allow(::Mcp::UserAuthenticator).to receive(:get_user_roles).and_return([])
  end

  # Scopes carried by the minted token, read back through the real verifier.
  def minted_scopes
    json = JSON.parse(response.body)
    payload = McpApi::JwtService.verify_token(json.fetch("token"))
    (payload["scope"] || "").split
  end

  def authenticate_as(role:)
    allow(::Mcp::UserAuthenticator).to receive(:authenticate)
      .and_return({ user: user_card, role: role })
    post "/api/mcp/auth", params: { username: "Alice", password: "pw" }, as: :json
  end

  describe "human principals" do
    it "mints the FULL AtomSpace scope set for an admin with an EMPTY allowlist" do
      allow(::Mcp::UserAuthenticator).to receive(:check_admin_status).with(user_card).and_return(true)

      authenticate_as(role: "admin")

      expect(response).to have_http_status(:created)
      expect(minted_scopes).to include(read_scope, write_scope, admin_scope)
    end

    it "mints the FULL AtomSpace scope set for a Raw Data Analyst with an EMPTY allowlist" do
      allow(::Mcp::UserAuthenticator).to receive(:get_user_roles)
        .with(user_card).and_return(["Raw Data Analyst"])

      authenticate_as(role: "user")

      expect(response).to have_http_status(:created)
      expect(minted_scopes).to include(read_scope, write_scope, admin_scope)
    end

    # AtomSpace authority is NAMESPACED under REV5: quarantine needs mcp:atomspace:admin, and the
    # generic mcp:admin scope is never minted by this policy for either principal class.
    it "does not mint the generic mcp:admin scope for a Raw Data Analyst" do
      allow(::Mcp::UserAuthenticator).to receive(:get_user_roles)
        .with(user_card).and_return(["Raw Data Analyst"])

      authenticate_as(role: "user")

      expect(minted_scopes).not_to include("mcp:admin")
    end

    it "does not mint the generic mcp:admin scope for an admin principal either" do
      allow(::Mcp::UserAuthenticator).to receive(:check_admin_status).with(user_card).and_return(true)

      authenticate_as(role: "admin")

      expect(minted_scopes).not_to include("mcp:admin")
    end

    it "mints NO atomspace scope for an ordinary user" do
      authenticate_as(role: "user")

      expect(response).to have_http_status(:created)
      expect(minted_scopes).not_to include(read_scope)
    end

    # The ENV allowlist stays READ-only: it must not hand an ordinary user the write or the
    # destructive quarantine scope.
    it "still honors an explicit allowlist entry for an ordinary user, READ only" do
      ENV["ATOMSPACE_READ_GRANTS"] = "user:Alice"

      authenticate_as(role: "user")

      expect(minted_scopes).to eq([read_scope])
    end
  end

  describe "API-key principals" do
    let(:legacy_key) { "abcd1234efgh5678" }

    before do
      # Force the legacy ENV-key branch so the spec does not depend on API-key cards in the DB.
      allow(::Mcp::ApiKeyManager).to receive(:authenticate).and_return(nil)
      ENV["MCP_API_KEY"] = legacy_key
    end

    # allowed_role_for_key? returns true for EVERY role on the legacy key, so role: "admin" here
    # is self-asserted. REV5 keeps keys allowlist-only precisely so that cannot become raw-data
    # access -- let alone the DESTRUCTIVE quarantine surface.
    it "mints NO atomspace scope for a role:admin API key absent an allowlist entry" do
      post "/api/mcp/auth", params: { api_key: legacy_key, role: "admin" }, as: :json

      expect(response).to have_http_status(:created)
      expect(minted_scopes).not_to include(read_scope)
      expect(minted_scopes).not_to include(admin_scope)
    end

    it "mints the READ scope ONLY when the key principal IS allowlisted" do
      ENV["ATOMSPACE_READ_GRANTS"] = "key:#{legacy_key.slice(0, 8)}"

      post "/api/mcp/auth", params: { api_key: legacy_key, role: "user" }, as: :json

      expect(response).to have_http_status(:created)
      expect(minted_scopes).to eq([read_scope])
    end
  end
end
