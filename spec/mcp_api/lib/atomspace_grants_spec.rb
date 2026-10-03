# frozen_string_literal: true

require "spec_helper"

# POLICY REV5 grant matrix for the AtomSpace scopes.
#
# Deterministic unit tier: no DB writes, no role cards. Mcp::UserAuthenticator is the seam --
# check_admin_status / get_user_roles are the SAME methods determine_role uses, so stubbing them
# here exercises the real policy branch without seeding Decko roles.
#
# REV5 (owner direction): admin / Raw Data Analyst principals are trusted with FULL AtomSpace
# backend access -- read + write + the namespaced atomspace admin scope that gates the card-scoped
# B3 quarantine surface. The generic `mcp:admin` scope is still never minted here. The ENV
# allowlist stays a READ-only escape hatch.
RSpec.describe McpApi::AtomspaceGrants do
  let(:user_card) { double("user_card", name: "Alice") }

  read_scope  = "mcp:atomspace:read"
  write_scope = "mcp:atomspace:write"
  admin_scope = "mcp:atomspace:admin"
  full = [read_scope, write_scope, admin_scope].freeze

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

  describe "scope constants" do
    it "exposes the three namespaced AtomSpace scopes" do
      expect(described_class::READ_SCOPE).to eq(read_scope)
      expect(described_class::WRITE_SCOPE).to eq(write_scope)
      expect(described_class::ADMIN_SCOPE).to eq(admin_scope)
      expect(described_class::FULL_SCOPES).to eq(full)
    end

    it "keeps the pre-REV5 SCOPE alias pointing at the read scope" do
      expect(described_class::SCOPE).to eq(read_scope)
    end
  end

  describe "explicit ENV allowlist (READ-only escape hatch under REV5)" do
    it "grants READ scope only for a matching user principal" do
      ENV["ATOMSPACE_READ_GRANTS"] = "user:Alice,user:Bob"

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq([read_scope])
    end

    it "grants READ scope only for a matching service/API-key principal (no user card at all)" do
      ENV["ATOMSPACE_READ_GRANTS"] = " key:9f3c , user:Bob "

      expect(described_class.scopes_for("key:9f3c")).to eq([read_scope])
    end

    # The allowlist must never become a back door to the DESTRUCTIVE quarantine surface.
    it "never confers write or atomspace-admin via the allowlist" do
      ENV["ATOMSPACE_READ_GRANTS"] = "key:9f3c"

      scopes = described_class.scopes_for("key:9f3c")
      expect(scopes).not_to include(write_scope)
      expect(scopes).not_to include(admin_scope)
    end

    it "does not grant scope to a principal absent from the allowlist" do
      ENV["ATOMSPACE_READ_GRANTS"] = "user:Bob"

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq([])
    end

    it "fails closed when the allowlist is unset (nobody granted)" do
      expect(described_class.granted?("user:Alice")).to be(false)
      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq([])
    end

    # Policy is evaluated BEFORE the allowlist, so an allowlisted admin keeps FULL scopes.
    it "does not downgrade an allowlisted admin to read-only" do
      ENV["ATOMSPACE_READ_GRANTS"] = "user:Alice"
      admin!

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq(full)
    end
  end

  describe "admin principals (REV5: FULL AtomSpace access, no ENV entry required)" do
    it "grants read + write + atomspace-admin with an EMPTY allowlist" do
      admin!

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq(full)
    end

    # AtomSpace authority is NAMESPACED: the generic mcp:admin scope is out of scope for this module.
    it "never mints the generic mcp:admin scope" do
      admin!

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).not_to include("mcp:admin")
    end
  end

  describe "Raw Data Analyst principals (REV5: FULL AtomSpace access, no ENV entry required)" do
    it "grants read + write + atomspace-admin with an EMPTY allowlist" do
      roles!("Raw Data Analyst")

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq(full)
    end

    it "matches the role name with case and separator folding" do
      ["raw data analyst", "Raw-Data-Analyst", "raw_data_analyst", "  Raw  Data  Analyst "].each do |variant|
        roles!(variant)

        expect(described_class.scopes_for("user:Alice", user_card: user_card))
          .to eq(full), "expected #{variant.inspect} to match"
      end
    end

    it "matches when Raw Data Analyst is one role among several" do
      roles!("Editor", "Raw Data Analyst")

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq(full)
    end

    # REV5 owner direction: a Raw Data Analyst IS trusted with the card-scoped quarantine surface
    # (demo velocity for the two-way card <-> atom path outweighs granular separation). The
    # separation that REV4 relied on is deliberately retired HERE -- but the scope strings remain
    # distinct and independently checked at the surface, so it can be re-tightened without
    # re-architecture.
    it "DOES confer mcp:atomspace:admin, so quarantine is reachable by a non-admin analyst" do
      roles!("Raw Data Analyst")

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to include(admin_scope)
    end

    it "still never confers the generic mcp:admin scope" do
      roles!("Raw Data Analyst")

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).not_to include("mcp:admin")
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
    # self-asserted (legacy ENV key is allowed every role), so it must not imply raw-data access --
    # and under REV5 it must certainly not imply the DESTRUCTIVE quarantine scope.
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

    it "still honors the explicit READ allowlist when role lookups blow up" do
      ENV["ATOMSPACE_READ_GRANTS"] = "user:Alice"
      allow(::Mcp::UserAuthenticator).to receive(:check_admin_status).and_raise(StandardError, "boom")
      allow(::Mcp::UserAuthenticator).to receive(:get_user_roles).and_raise(StandardError, "boom")

      expect(described_class.scopes_for("user:Alice", user_card: user_card)).to eq([read_scope])
    end
  end

  describe "backward compatibility" do
    it "keeps the single-argument arity used by pre-REV5 callers (allowlist -> read)" do
      ENV["ATOMSPACE_READ_GRANTS"] = "user:Alice"

      expect(described_class.scopes_for("user:Alice")).to eq([read_scope])
    end
  end
end
