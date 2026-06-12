# frozen_string_literal: true

require "spec_helper"

# Lane C / Level 9 behavioral harness.
#
# Two tiers:
#   * AtomspaceReadFilter unit specs -- deterministic; stub Card.fetch; no DB writes. These
#     lock the security-critical multi-card default-deny logic (Invariant 9).
#   * Request specs -- mint a scoped MCP test token (MessageVerifier, matching the repo's
#     existing generate_test_token pattern, plus a `scope` claim) and exercise the scope gate,
#     quarantine matrix, and read-your-writes terminal states via the FakeReadClient +
#     ReadConsistencyPort stub. No sidecar / no Lane A engine needed.
#
# NOTE: read-rule reference fixtures over *real* restricted cards are covered at the filter-unit
# tier via stubs; an end-to-end restricted-card request fixture is a follow-up once the deck
# test DB seeding for +*read rules is in place.

RSpec.describe Api::Mcp::AtomspaceMirrorController, type: :request do
  # Stub the REAL verify path. BaseController authenticates via McpApi::JwtService.verify_token
  # (RS256), not MessageVerifier -- so we stub it to return a controlled payload (string keys,
  # as the controller reads them). This exercises the actual auth + scope-gate code path without
  # minting RS256 tokens (Codex). `sub` resolves @current_mcp_account via find_mcp_account.
  def auth(role: "user", scope: nil, sub: "user:Administrator")
    payload = { "sub" => sub, "role" => role }
    payload["scope"] = scope if scope
    allow(McpApi::JwtService).to receive(:verify_token).and_return(payload)
    { "Authorization" => "Bearer test-token" }
  end

  before { Atomspace::ReadClient.bind!(Atomspace::FakeReadClient) }
  after do
    Atomspace::FakeReadClient.seed!([])
    Atomspace::ReadConsistencyPort.reset!
  end

  # ====================================================================================
  # Tier 1 -- AtomspaceReadFilter: strict multi-card default-deny (Invariant 9). Deterministic.
  # ====================================================================================
  describe AtomspaceReadFilter do
    subject(:filter) { Class.new { include AtomspaceReadFilter }.new }

    let(:account) { double("account", name: "Anonymous") }

    around { |example| Card::Auth.as("Anonymous") { example.run } }

    def stub_card(id, readable:)
      allow(Card).to receive(:fetch).with(id).and_return(double("card", "ok?" => readable))
    end

    def run(atoms)
      filter.send(:filter_by_read_auth, atoms, account)
    end

    it "drops a card-scoped atom with a nil card_id" do
      expect(run([Atomspace::Atom.new(type: "DeckoCard", card_id: nil)])).to be_empty
    end

    it "drops a card whose card_id does not resolve" do
      allow(Card).to receive(:fetch).with(999).and_return(nil)
      expect(run([Atomspace::Atom.new(type: "DeckoCard", card_id: 999)])).to be_empty
    end

    it "keeps a readable card" do
      stub_card(1, readable: true)
      expect(run([Atomspace::Atom.new(type: "DeckoCard", card_id: 1)]).size).to eq(1)
    end

    it "drops a reference when the referee is restricted even though the referer is public" do
      stub_card(1, readable: true)  # referer
      stub_card(2, readable: false) # referee
      atom = Atomspace::Atom.new(type: "DeckoReference", referer_id: 1, referee_id: 2)
      expect(run([atom])).to be_empty
    end

    it "drops a reference when the referer is restricted even though the referee is public" do
      stub_card(1, readable: false) # referer
      stub_card(2, readable: true)  # referee
      atom = Atomspace::Atom.new(type: "DeckoReference", referer_id: 1, referee_id: 2)
      expect(run([atom])).to be_empty
    end

    it "returns an unresolved-target reference iff the referer is readable" do
      stub_card(1, readable: true)
      readable = Atomspace::Atom.new(type: "DeckoReference", referer_id: 1, referee_id: nil)
      expect(run([readable]).size).to eq(1)

      stub_card(3, readable: false)
      hidden = Atomspace::Atom.new(type: "DeckoReference", referer_id: 3, referee_id: nil)
      expect(run([hidden])).to be_empty
    end
  end

  # ====================================================================================
  # Tier 2 -- request specs: gate, quarantine matrix, RYW terminals.
  # ====================================================================================
  describe "scope gate" do
    it "403s a read tool without mcp:atomspace:read" do
      get "/api/mcp/atomspace_mirror/atom_types", headers: auth(role: "user", scope: "mcp:read")
      expect(response).to have_http_status(:forbidden)
    end

    it "permits a read tool with mcp:atomspace:read" do
      Atomspace::FakeReadClient.seed!([])
      get "/api/mcp/atomspace_mirror/atom_types", headers: auth(scope: "mcp:atomspace:read")
      expect(response).not_to have_http_status(:forbidden)
      expect(JSON.parse(response.body)).to have_key("_meta")
    end
  end

  describe "quarantine matrix (mcp:atomspace:read + mcp:admin)" do
    it "denies scope-without-admin (403)" do
      get "/api/mcp/atomspace_mirror/quarantine", headers: auth(scope: "mcp:atomspace:read")
      expect(response).to have_http_status(:forbidden)
    end

    it "denies admin-without-scope (403)" do
      get "/api/mcp/atomspace_mirror/quarantine", headers: auth(role: "admin", scope: "mcp:admin")
      expect(response).to have_http_status(:forbidden)
    end

    it "allows scope + admin" do
      Atomspace::FakeReadClient.seed!([])
      get "/api/mcp/atomspace_mirror/quarantine",
          headers: auth(role: "admin", scope: "mcp:atomspace:read mcp:admin")
      expect(response).not_to have_http_status(:forbidden)
    end
  end

  describe "read-your-writes terminals" do
    before { Atomspace::FakeReadClient.seed!([]) }

    def stub_readiness(status)
      impl = Class.new { define_method(:check_event_ready) { |_event_id| status } }.new
      Atomspace::ReadConsistencyPort.impl = impl
    end

    def ryw_get(scope: "mcp:atomspace:read")
      get "/api/mcp/atomspace_mirror/query_atoms",
          params: { pattern: "(card $x)", wait_for_event_id: "decko:action:1" },
          headers: auth(scope: scope)
    end

    it "mirror_integrity is terminal -> 409" do
      stub_readiness(:integrity_error)
      ryw_get
      expect(response).to have_http_status(409)
      expect(JSON.parse(response.body)["error"]).to eq("mirror_integrity")
    end

    it "event_failed -> 503" do
      stub_readiness(:failed)
      ryw_get
      expect(response).to have_http_status(503)
      expect(JSON.parse(response.body)["error"]).to eq("event_failed")
    end

    it "never-lands -> 503 staleness_timeout" do
      original = ENV["READ_YOUR_WRITES_MAX_WAIT_SECONDS"]
      ENV["READ_YOUR_WRITES_MAX_WAIT_SECONDS"] = "0"
      stub_readiness(:not_yet)
      ryw_get
      expect(response).to have_http_status(503)
      expect(JSON.parse(response.body)["error"]).to eq("staleness_timeout")
    ensure
      ENV["READ_YOUR_WRITES_MAX_WAIT_SECONDS"] = original
    end

    it "ReadConsistencyPort unwired -> 503 read_consistency_not_wired (fail-closed, not 500)" do
      Atomspace::ReadConsistencyPort.reset!
      ryw_get
      expect(response).to have_http_status(503)
      expect(JSON.parse(response.body)["reason"]).to eq("read_consistency_not_wired")
    end
  end
end
