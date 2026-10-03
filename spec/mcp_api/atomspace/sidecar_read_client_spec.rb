# frozen_string_literal: true
#
# C2 SidecarReadClient: maps the L9 ReadClient contract onto the sidecar's POST /read (+ /space_stats,
# /health/watermark). STANDALONE -- a class-level injected `transport` replaces the real UNIX socket,
# so the request shaping, action_id_range parsing, DTO mapping, and fail-closed paths are tested with
# no sidecar.

require_relative "../../../mod/mcp_api/lib/atomspace/sidecar_read_client"
require_relative "../../../mod/mcp_api/lib/atomspace/fake_read_client"

RSpec.describe Atomspace::SidecarReadClient do
  let(:calls) { [] }

  def stub_transport(responses = {})
    Atomspace::SidecarReadClient.transport = lambda do |verb, path, body|
      calls << [verb, path, body]
      responses.fetch([verb, path], [200, { "results" => [] }])
    end
  end

  after { Atomspace::SidecarReadClient.transport = nil }

  subject(:client) { described_class.new(account: nil) }

  it "get_card_atom -> POST /read get_card_atom; maps the DeckoCard DTO" do
    stub_transport([:post, "/read"] => [200, { "results" => [
      { "atom" => "DeckoCard", "fields" => [["Id", 10], ["Name", "X"], ["Trash", false]] }
    ] }])
    atoms = client.get_card_atom(card_id: "10")
    expect(calls.last).to eq([:post, "/read", { op: "get_card_atom", card_id: 10, include_trash: false }])
    expect(atoms.map(&:type)).to eq(["DeckoCard"])
    expect(atoms.first.card_id).to eq(10)
    expect(atoms.first.associated_card_ids).to eq([10])
    expect(atoms.first.to_h).to include(type: "DeckoCard", card_id: 10, "Name" => "X")
  end

  it "maps a DeckoReference DTO (referer/referee ids for the auth filter; Unresolved -> nil referee)" do
    stub_transport([:post, "/read"] => [200, { "results" => [
      { "atom" => "DeckoReference", "fields" => [["RefererId", 10], ["RefereeId", 99], ["RefType", { "sym" => "L" }]] },
      { "atom" => "DeckoReference", "fields" => [["RefererId", 10], ["RefereeId", { "sym" => "Unresolved" }]] }
    ] }])
    refs = client.list_references(card_id: 10)
    expect(refs[0].associated_card_ids).to eq([10, 99])   # resolved: both ids gate auth
    expect(refs[1].associated_card_ids).to eq([10])       # unresolved referee -> nil -> excluded
  end

  it "get_card_provenance parses action_id_range into inclusive min/max" do
    stub_transport
    client.get_card_provenance(card_id: 7, action_id_range: "100-200")
    expect(calls.last[2]).to eq({ op: "get_card_provenance", card_id: 7, action_id_min: 100, action_id_max: 200 })
  end

  describe "action_id_range parsing" do
    def range_call(range)
      stub_transport
      client.get_card_provenance(card_id: 1, action_id_range: range)
      calls.last[2].slice(:action_id_min, :action_id_max)
    end

    it "accepts MIN-MAX, open sides, single N, and blank" do
      expect(range_call("100-200")).to eq(action_id_min: 100, action_id_max: 200)
      expect(range_call("100-")).to eq(action_id_min: 100)            # max nil -> compacted out
      expect(range_call("-200")).to eq(action_id_max: 200)
      expect(range_call("50")).to eq(action_id_min: 50, action_id_max: 50)
      expect(range_call(nil)).to eq({})                                # no bounds
    end

    it "raises InvalidRequest on non-numeric or min>max" do
      stub_transport
      expect { client.get_card_provenance(card_id: 1, action_id_range: "abc") }
        .to raise_error(Atomspace::InvalidRequest, /invalid action_id_range/)
      expect { client.get_card_provenance(card_id: 1, action_id_range: "200-100") }
        .to raise_error(Atomspace::InvalidRequest, /min > max/)
    end
  end

  it "aggregates reuse /space_stats" do
    stub_transport([:get, "/space_stats"] => [200, { "atom_count" => 3, "by_kind" => { "DeckoCard" => 2, "DeckoReference" => 1 } }])
    expect(client.atom_types).to match_array(%w[DeckoCard DeckoReference])
    expect(client.atom_count_by_type).to eq("DeckoCard" => 2, "DeckoReference" => 1)
    expect(client.space_stats).to eq(atom_count: 3, types: { "DeckoCard" => 2, "DeckoReference" => 1 }, mirror_lag: 0)
  end

  it "watermark_meta (class) maps /health/watermark; stub staleness" do
    stub_transport([:get, "/health/watermark"] => [200, { "last_applied_action_id" => 42 }])
    expect(described_class.watermark_meta).to eq(atomspace_watermark: 42, monitor_status: "healthy", staleness_seconds: 0.0)
  end

  # POLICY REV5: quarantine is wired to the sidecar's real card-scoped B3 admin surface.
  describe "card-scoped B3 admin quarantine (POLICY REV5)" do
    it "quarantine_list POSTs /admin/list_card_scoped_atoms with a strict integer card_id" do
      stub_transport([:post, "/admin/list_card_scoped_atoms"] =>
        [200, { "card_id" => 5, "atoms" => [{ "atom" => "DeckoCard", "fields" => [["Id", 5]] }] }])
      result = client.quarantine_list(card_id: "5")
      expect(calls.last).to eq([:post, "/admin/list_card_scoped_atoms", { "card_id" => 5 }])
      expect(result["card_id"]).to eq(5)
      expect(result["atoms"].length).to eq(1)
    end

    it "quarantine_delete POSTs /admin/quarantine_card_scoped_atoms and returns the removal audit" do
      stub_transport([:post, "/admin/quarantine_card_scoped_atoms"] =>
        [200, { "card_id" => 5, "removed" => [{ "atom" => "DeckoCard", "fields" => [["Id", 5]] }],
                "removed_count" => 1 }])
      result = client.quarantine_delete(card_id: 5)
      expect(calls.last).to eq([:post, "/admin/quarantine_card_scoped_atoms", { "card_id" => 5 }])
      expect(result["removed_count"]).to eq(1)
      expect(result["removed"].length).to eq(1)
    end

    # A DESTRUCTIVE boundary must never coerce its target ("abc" -> 0 would quarantine card 0).
    it "rejects a non-integer / non-positive card_id with InvalidRequest, issuing NO request" do
      stub_transport
      ["abc", "12x", "", nil, "0", "-3"].each do |bad|
        expect { client.quarantine_delete(card_id: bad) }
          .to raise_error(Atomspace::InvalidRequest, /card_id/), "expected #{bad.inspect} rejected"
      end
      expect(calls).to be_empty
    end

    it "fails closed on a non-200, a socket error, or an inconsistent response shape" do
      [[500, nil],
       [200, { "card_id" => 5, "removed" => [], "removed_count" => 2 }],          # count != length
       [200, { "card_id" => 9, "removed" => [], "removed_count" => 0 }],          # echoed id mismatch
       [200, { "card_id" => 5, "removed_count" => 0 }],                           # removed missing
       [200, { "card_id" => 5, "removed" => [], "removed_count" => "0" }]].each do |response|
        stub_transport([:post, "/admin/quarantine_card_scoped_atoms"] => response)
        expect { client.quarantine_delete(card_id: 5) }
          .to raise_error(Atomspace::ServiceUnavailable), "expected #{response.inspect} to fail closed"
      end

      Atomspace::SidecarReadClient.transport = ->(_v, _p, _b) { raise Errno::ECONNREFUSED }
      expect { client.quarantine_delete(card_id: 5) }
        .to raise_error(Atomspace::ServiceUnavailable, /unreachable/)
      expect { client.quarantine_list(card_id: 5) }
        .to raise_error(Atomspace::ServiceUnavailable, /unreachable/)
    end

    it "fails closed when the list response is non-200 or malformed" do
      [[503, nil],
       [200, { "card_id" => 9, "atoms" => [] }],   # echoed id mismatch
       [200, { "card_id" => 5 }]].each do |response|
        stub_transport([:post, "/admin/list_card_scoped_atoms"] => response)
        expect { client.quarantine_list(card_id: 5) }
          .to raise_error(Atomspace::ServiceUnavailable), "expected #{response.inspect} to fail closed"
      end
    end
  end

  it "a non-200 from the sidecar fails closed (ServiceUnavailable, never 500)" do
    stub_transport([:post, "/read"] => [503, nil])
    expect { client.get_card_atom(card_id: 1) }.to raise_error(Atomspace::ServiceUnavailable, /failed/)
  end

  describe "strict card_id parsing (never coerce 'abc' -> 0)" do
    before { stub_transport }

    it "rejects a non-integer or blank card_id with InvalidRequest (400)" do
      expect { client.get_card_atom(card_id: "abc") }.to raise_error(Atomspace::InvalidRequest, /card_id/)
      expect { client.get_card_atom(card_id: "") }.to raise_error(Atomspace::InvalidRequest, /required/)
      expect { client.list_references(card_id: "12x") }.to raise_error(Atomspace::InvalidRequest, /integer/)
      expect { client.get_card_provenance(card_id: "abc") }.to raise_error(Atomspace::InvalidRequest, /integer/)
    end

    it "accepts integer-ish ids and a nil optional provenance card_id" do
      client.get_card_atom(card_id: "10")
      expect(calls.last[2][:card_id]).to eq(10)
      client.get_card_provenance(card_id: nil)              # optional -> compacted out
      expect(calls.last[2]).not_to have_key(:card_id)
    end
  end

  describe "query_atoms pattern transport shapes" do
    before { stub_transport }

    def pattern_sent(pattern)
      client.query_atoms(pattern: pattern)
      calls.last[2][:pattern]
    end

    it "accepts a Hash (symbol keys stringified)" do
      expect(pattern_sent(kind: "DeckoCard", fields: { Name: "x" })).to eq("kind" => "DeckoCard", "fields" => { "Name" => "x" })
    end

    it "accepts a JSON string" do
      expect(pattern_sent('{"kind":"DeckoCard","fields":{"Name":"x"}}')).to eq("kind" => "DeckoCard", "fields" => { "Name" => "x" })
    end

    it "accepts an ActionController::Parameters-like object (to_unsafe_h)" do
      params = Object.new
      def params.to_unsafe_h = { "fields" => { "Name" => "x" } }
      expect(pattern_sent(params)).to eq("fields" => { "Name" => "x" })
    end

    it "treats a bare field map as fields" do
      expect(pattern_sent("Name" => "x")).to eq("fields" => { "Name" => "x" })
    end

    it "rejects malformed patterns with InvalidRequest" do
      expect { client.query_atoms(pattern: ["bad"]) }.to raise_error(Atomspace::InvalidRequest, /object/)
      expect { client.query_atoms(pattern: '{bad json') }.to raise_error(Atomspace::InvalidRequest, /JSON/)
      expect { client.query_atoms(pattern: { fields: ["bad"] }) }.to raise_error(Atomspace::InvalidRequest, /fields/)
    end
  end
end

RSpec.describe Atomspace::FakeReadClient do
  it "get_card_atom returns ONLY the DeckoCard (aligned with the C2 contract)" do
    Atomspace::FakeReadClient.seed!([
      Atomspace::Atom.new(type: "DeckoCard", card_id: 5, fields: { "Name" => "c5" }),
      Atomspace::Atom.new(type: "DeckoReference", card_id: 5, referer_id: 5, referee_id: 9)
    ])
    atoms = Atomspace::FakeReadClient.new(account: nil).get_card_atom(card_id: 5)
    expect(atoms.map(&:type)).to eq(["DeckoCard"])
  end
end
