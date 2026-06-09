# frozen_string_literal: true

require "rails_helper"

# Lane C / Level 9 acceptance matrix. Behavioral, FakeReadClient-backed, no sidecar.
# NOTE(scaffold): JWT minting + route wiring helpers are marked TODO until the
# mcp:atomspace:read scope claim lands in token issuance (shared infra; see Chris heads-up
# and INTEGRATION.md). Examples that depend on that are `pending` rather than silently green.
RSpec.describe Api::Mcp::AtomspaceMirrorController, type: :request do
  # TODO(integration): mint a real RS256 MCP JWT carrying the given scopes.
  def auth_headers(scopes:)
    skip "TODO: mint MCP JWT with scope claim once issuance carries explicit scopes"
  end

  let(:public_card)     { Card.create!(name: "AtomSpaceSpec Public #{SecureRandom.hex(3)}") }
  let(:restricted_card) { Card.create!(name: "AtomSpaceSpec Private #{SecureRandom.hex(3)}") } # + read-rule fixture

  before { Atomspace::ReadClient.bind!(Atomspace::FakeReadClient) }
  after  { Atomspace::FakeReadClient.seed!([]); Atomspace::ReadConsistencyPort.reset! }

  describe "scope gate" do
    it "403s every read tool without mcp:atomspace:read" do
      pending "needs JWT minting"
      get "/api/mcp/atomspace_mirror/query_atoms", params: { pattern: "(card $x)" },
                                                   headers: auth_headers(scopes: %w[mcp:read])
      expect(response).to have_http_status(:forbidden)
    end

    it "allows read tools with mcp:atomspace:read" do
      pending "needs JWT minting"
    end

    # Codex Finding 1.1 / Gemini: invocation-boundary enforcement is also covered gem-side.
    it "rejects a direct invocation of a hidden tool when the scope is absent" do
      pending "gem-side dispatch spec covers the JSON-RPC path"
    end
  end

  describe "quarantine matrix (mcp:atomspace:read + mcp:admin)" do
    it "denies scope-without-admin (403)"  do pending "needs JWT minting" end
    it "denies admin-without-scope (403)"  do pending "needs JWT minting" end
    it "allows scope + admin"              do pending "needs JWT minting" end
  end

  describe "multi-card auth filter (Invariant 9)" do
    it "drops an atom whose card_id is nil or unresolvable" do
      filter = Class.new { include AtomspaceReadFilter }.new
      atoms = [Atomspace::Atom.new(type: "DeckoCard", card_id: nil)]
      expect(filter.send(:filter_by_read_auth, atoms, Card::Auth.current)).to be_empty
    end

    it "drops a reference when the referee is restricted even if the referer is public" do
      pending "needs read-rule fixtures + account roles"
    end

    it "returns an unresolved reference iff the referer is readable" do
      pending "needs read-rule fixtures"
    end
  end

  describe "read-your-writes (wait_for_event_id)" do
    def stub_readiness(status)
      Atomspace::ReadConsistencyPort.impl = Class.new { define_method(:check_event_ready) { |_| status } }.new
    end

    it ":integrity_error short-circuits with HTTP 409 (no further polling)" do
      pending "needs route + JWT; logic asserted via ReadConsistencyPort stub"
      stub_readiness(:integrity_error)
    end

    it "times out cleanly with 503 when the event never lands" do
      pending "needs route + JWT"
    end
  end

  describe "fail-closed wiring" do
    it "returns 503 (not fake data) when no read client is bound" do
      Atomspace::ReadClient.reset!
      expect { Atomspace::ReadClient.for(account: double(name: "x")) }
        .to raise_error(Atomspace::ServiceUnavailable)
    end

    it "watermark_meta also fails closed" do
      Atomspace::ReadClient.reset!
      expect { Atomspace::ReadClient.watermark_meta }.to raise_error(Atomspace::ServiceUnavailable)
      expect(Atomspace::ReadClient.safe_watermark_meta).to eq(Atomspace::ReadClient::SAFE_META)
    end
  end
end
