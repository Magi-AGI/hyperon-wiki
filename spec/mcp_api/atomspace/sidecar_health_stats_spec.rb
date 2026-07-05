# frozen_string_literal: true
#
# Regression for the closure-review blocker READINESS_CARD_COUNT_EXTRACTION_BROKEN / Gemini B3.
# The controller's sidecar_health read the sidecar's RAW `by_kind` key, but the Ruby ReadClient
# boundary NORMALIZES space_stats to `{ atom_count:, types: {<kind> => count}, mirror_lag: }`, so the
# DeckoCard count was always 0 and readiness stayed 503 forever. These specs exercise the extraction
# against the REAL FakeReadClient.space_stats shape (STANDALONE -- no Decko/Rails boot), so they FAIL
# under the old `by_kind` implementation and PASS with `types`.

require_relative "../../../mod/mcp_api/lib/atomspace/mirror_readiness"
require_relative "../../../mod/mcp_api/lib/atomspace/fake_read_client"

RSpec.describe "MirrorReadiness.card_count_from_stats (sidecar_health extraction)" do
  def deck_card(id) = Atomspace::Atom.new(type: "DeckoCard", card_id: id)
  def reference(referer) = Atomspace::Atom.new(type: "DeckoReference", referer_id: referer, referee_id: referer)

  after { Atomspace::FakeReadClient.seed!([]) }

  it "extracts the DeckoCard count from the REAL normalized ReadClient shape (`types`)" do
    # 3 DeckoCards + 2 DeckoReferences -> DeckoCard count is 3, atom_count is 5.
    Atomspace::FakeReadClient.seed!([deck_card(1), deck_card(2), deck_card(3), reference(1), reference(2)])
    stats = Atomspace::FakeReadClient.new(account: nil).space_stats

    # Guard the contract the fix depends on: `types` holds the per-kind map, NOT `by_kind`.
    expect(stats).to include(:types)
    expect(stats).not_to have_key("by_kind")

    expect(Atomspace::MirrorReadiness.card_count_from_stats(stats)).to eq(3)
  end

  it "returns 0 for the OLD sidecar-raw `by_kind` shape (proves the old extraction was broken)" do
    old_shape = { "atom_count" => 5, "by_kind" => { "DeckoCard" => 3 } }
    expect(Atomspace::MirrorReadiness.card_count_from_stats(old_shape)).to eq(0)
  end

  it "tolerates string-keyed `types` (SidecarReadClient passes the JSON by_kind through verbatim)" do
    sidecar_shape = { atom_count: 17_000, types: { "DeckoCard" => 9663, "DeckoReference" => 7000 }, mirror_lag: 0 }
    expect(Atomspace::MirrorReadiness.card_count_from_stats(sidecar_shape)).to eq(9663)
  end

  it "returns 0 on a malformed / empty stats shape (fail closed)" do
    expect(Atomspace::MirrorReadiness.card_count_from_stats(nil)).to eq(0)
    expect(Atomspace::MirrorReadiness.card_count_from_stats({})).to eq(0)
    expect(Atomspace::MirrorReadiness.card_count_from_stats({ types: {} })).to eq(0)
  end

  # End-to-end: the exact wiring the controller uses (space_stats -> card_count_from_stats -> the
  # sidecar_override) drives readiness GREEN with the fix, and would be RED (sidecar_empty_post_restart)
  # under the old by_kind extraction (card_count 0).
  it "drives MirrorReadiness.check READY through the real space_stats + extraction path" do
    Atomspace::FakeReadClient.seed!([deck_card(1), deck_card(2), deck_card(3)])
    client = Atomspace::FakeReadClient.new(account: nil)

    Atomspace::MirrorReadiness.enabled_probe        = -> { true }
    Atomspace::MirrorReadiness.state_probe          = -> { Struct.new(:bootstrap_a_start, :draining_enabled).new(100, true) }
    Atomspace::MirrorReadiness.running_probe        = -> { false }
    Atomspace::MirrorReadiness.expected_cards_probe = -> { 3 }
    sidecar_override = -> { { reachable: true, card_count: Atomspace::MirrorReadiness.card_count_from_stats(client.space_stats) } }

    expect(Atomspace::MirrorReadiness.check(sidecar_override)).to be_ready
  ensure
    Atomspace::MirrorReadiness.reset!
  end
end
