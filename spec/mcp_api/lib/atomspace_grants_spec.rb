# frozen_string_literal: true

require "spec_helper"

# POLICY REV4 grant matrix for the mcp:atomspace:read scope.
#
# Deterministic unit tier: no DB writes, no role cards. Mcp::UserAuthenticator is the seam --
# check_admin_status / get_user_roles are the SAME methods determine_role uses, so stubbing them
# here exercises the real policy branch without seeding Decko roles.
RSpec.describe McpApi::AtomspaceGrants do
  let(:user_card) { double("user_card", name: "Alice") }

  around do |example|
    original = ENV["ATOMSPACE_READ_GRANTS"]
    example.run
  ensure
    if original.nil?
      ENV.delete("ATOMSPACE_READ_GRANTS")
    else
      ENV["ATOMSPACE_READ_GRANTS"] = original
    end
  end

  # Default posture for every example: NOT admin, NO roles. Each context opts in.
  before do
    ENV.delete("ATOMSPACE_READ_GRANTS")
    allow(::Mcp::UserAuthenticator).to receive(:check_admin_status).and_return(false)
    allow(::Mcp::UserAuthenticator).to receive(:get_user_roles).and_return([])
  end

  def admin!
    allow(::Mcp::UserAuthenticator).to receive(:check_admin_status).with(user_card).and_return(true)
  end

  def roles!(*names)
    allow(::Mcp::UserAuthenticator).to receive(:get_user_roles).with(user_card).and_return(names)
  end

  describe "explicit ENV allowlist (retained under REV4)" do
    it "grants scope for a matching user principal without any role lookup" do
      ENV["ATOMSPACE_READ_GRANTS"] = "user:Alice,user:Bob"

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq(["mcp:atomspace:read"])
    end

    it "grants scope for a matching service/API-key principal (no user card at all)" do
      ENV["ATOMSPACE_READ_GRANTS"] = " key:9f3c , user:Bob "

      expect(described_class.scopes_for("key:9f3c")).to eq(["mcp:atomspace:read"])
    end

    it "does not grant scope to a principal absent from the allowlist" do
      ENV["ATOMSPACE_READ_GRANTS"] = "user:Bob"

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq([])
    end

    it "fails closed when the allowlist is unset (nobody granted)" do
      expect(described_class.granted?("user:Alice")).to be(false)
      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq([])
    end
  end

  describe "admin principals (REV4: auto-granted, no ENV entry required)" do
    it "grants scope to an admin user with an EMPTY allowlist" do
      admin!

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq(["mcp:atomspace:read"])
    end

    it "grants read scope only -- never mcp:admin (quarantine stays separately gated)" do
      admin!

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).not_to include("mcp:admin")
    end
  end

  describe "Raw Data Analyst principals (REV4: auto-granted, no ENV entry required)" do
    it "grants scope to a Raw Data Analyst with an EMPTY allowlist" do
      roles!("Raw Data Analyst")

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq(["mcp:atomspace:read"])
    end

    it "matches the role name with case and separator folding" do
      ["raw data analyst", "Raw-Data-Analyst", "raw_data_analyst", "  Raw  Data  Analyst "].each do |variant|
        roles!(variant)

        expect(described_class.scopes_for("user:Alice", user_card: user_card))
          .to eq(["mcp:atomspace:read"]), "expected #{variant.inspect} to match"
      end
    end

    it "matches when Raw Data Analyst is one role among several" do
      roles!("Editor", "Raw Data Analyst")

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq(["mcp:atomspace:read"])
    end

    # THE load-bearing separation: RDA is a raw-data reader, not an operator. Quarantine requires
    # mcp:atomspace:read AND mcp:admin (AtomspaceMirrorController#require_quarantine_scope!).
    it "does NOT confer mcp:admin, so quarantine remains closed to a non-admin analyst" do
      roles!("Raw Data Analyst")

      scopes = described_class.scopes_for("user:Alice", user_card: user_card)
      expect(scopes).to eq(["mcp:atomspace:read"])
      expect(scopes).not_to include("mcp:admin")
    end

    it "does not match a merely similar role name" do
      roles!("Data Analyst", "Raw Data")

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq([])
    end
  end

  describe "ordinary users" do
    it "gets NO scope absent both allowlist and policy role" do
      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq([])
    end
  end

  describe "API-key principals (deliberately NOT role-derived)" do
    # AuthController#generate_token_for_api_key passes no user_card: an API key's role is
    # self-asserted (legacy ENV key is allowed every role), so it must not imply raw-data access.
    it "gets no scope when no user card is supplied, even if some admin exists" do
      allow(::Mcp::UserAuthenticator).to receive(:check_admin_status).and_return(true)

      expect(described_class.scopes_for("key:deadbeef")).to eq([])
    end
  end

  describe "fail-closed behavior" do
    it "denies scope (does not raise) when the admin lookup blows up" do
      allow(::Mcp::UserAuthenticator).to receive(:check_admin_status).and_raise(StandardError, "boom")

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq([])
    end

    it "denies scope (does not raise) when the role lookup blows up" do
      allow(::Mcp::UserAuthenticator).to receive(:get_user_roles).and_raise(StandardError, "boom")

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq([])
    end

    it "still honors the explicit allowlist when role lookups blow up" do
      ENV["ATOMSPACE_READ_GRANTS"] = "user:Alice"
      allow(::Mcp::UserAuthenticator).to receive(:check_admin_status).and_raise(StandardError, "boom")

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq(["mcp:atomspace:read"])
    end
  end

  describe "backward compatibility" do
    it "keeps the single-argument arity used by pre-REV4 callers" do
      ENV["ATOMSPACE_READ_GRANTS"] = "user:Alice"

      expect(described_class.scopes_for("user:Alice")).to eq(["mcp:atomspace:read"])
    end
  end
end
