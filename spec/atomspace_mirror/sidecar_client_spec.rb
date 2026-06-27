# frozen_string_literal: true
#
# L8 -> L3 IPC: the locked failure matrix (DrainDelivery.classify, pure) + SidecarClient with an
# injected transport. STANDALONE: no Decko boot, no real network.

require_relative "../../mod/atomspace_mirror/lib/sidecar_client"

RSpec.describe DrainDelivery do
  def result(status, **over) = { "results" => [{ "status" => status }.merge(over)] }

  it "200 applied / already_applied -> delivered" do
    expect(DrainDelivery.classify(http_status: 200, body: result("applied")).outcome).to eq(:delivered)
    expect(DrainDelivery.classify(http_status: 200, body: result("already_applied")).outcome).to eq(:delivered)
  end

  it "200 per-event error -> failed_terminal" do
    out = DrainDelivery.classify(http_status: 200, body: result("error", "error" => "bad ref"))
    expect(out.outcome).to eq(:failed_terminal)
    expect(out.reason).to match(/bad ref/)
  end

  it "200 with malformed body (no single result) -> failed_terminal" do
    expect(DrainDelivery.classify(http_status: 200, body: { "nope" => 1 }).outcome).to eq(:failed_terminal)
    expect(DrainDelivery.classify(http_status: 200, body: { "results" => [] }).outcome).to eq(:failed_terminal)
    expect(DrainDelivery.classify(http_status: 200, body: nil).outcome).to eq(:failed_terminal)
  end

  it "200 unexpected event status -> failed_terminal" do
    expect(DrainDelivery.classify(http_status: 200, body: result("weird")).outcome).to eq(:failed_terminal)
  end

  it "4xx request/payload rejection -> failed_terminal" do
    expect(DrainDelivery.classify(http_status: 400, body: { "error" => "bad json" }).outcome).to eq(:failed_terminal)
    expect(DrainDelivery.classify(http_status: 404).outcome).to eq(:failed_terminal)
  end

  it "5xx -> retryable" do
    expect(DrainDelivery.classify(http_status: 503).outcome).to eq(:retryable)
  end

  it "transport error -> retryable" do
    out = DrainDelivery.classify(http_status: 0, transport_error: "Errno::ECONNREFUSED")
    expect(out.outcome).to eq(:retryable)
    expect(out.reason).to match(/ECONNREFUSED/)
  end
end

RSpec.describe SidecarClient do
  let(:payload) { { "atoms" => [{ "atom" => "DeckoCard", "fields" => [["Id", 1]] }] } }

  it "posts exactly one payload (wrapped) and maps applied -> delivered" do
    seen = []
    transport = ->(path, body) { seen << [path, body]; [200, { "results" => [{ "status" => "applied" }] }] }
    out = SidecarClient.new(transport: transport).apply(payload)
    expect(out.outcome).to eq(:delivered)
    expect(seen).to eq([["/apply", { "payloads" => [payload] }]])
  end

  it "maps genuine transport errors to retryable (never raises)" do
    [Errno::ECONNREFUSED, Net::ReadTimeout, SocketError].each do |err|
      transport = ->(_path, _body) { raise err }
      expect(SidecarClient.new(transport: transport).apply(payload).outcome).to eq(:retryable)
    end
  end

  it "lets a programming error PROPAGATE (not silently retried)" do
    transport = ->(_path, _body) { raise NoMethodError, "boom" }
    expect { SidecarClient.new(transport: transport).apply(payload) }.to raise_error(NoMethodError, /boom/)
  end

  describe "#bulk_load" do
    let(:atoms) { [{ "atom" => "DeckoCard", "fields" => [["Id", 1]] }, { "atom" => "DeckoReference", "fields" => [["RefererId", 1]] }] }

    it "POSTs to /bulk_load and returns the loaded count when it equals what was sent" do
      seen = []
      transport = ->(path, body) { seen << [path, body]; [200, { "loaded" => 2 }] }
      expect(SidecarClient.new(transport: transport).bulk_load(atoms)).to eq(2)
      expect(seen).to eq([["/bulk_load", { "atoms" => atoms }]])
    end

    it "raises BulkLoadError when loaded != sent (partial / wrong-count ack)" do
      transport = ->(_p, _b) { [200, { "loaded" => 1 }] } # sent 2
      expect { SidecarClient.new(transport: transport).bulk_load(atoms) }
        .to raise_error(SidecarClient::BulkLoadError, /loaded=1, sent=2/)
    end

    it "raises BulkLoadError on a non-integer loaded" do
      transport = ->(_p, _b) { [200, { "loaded" => "2" }] }
      expect { SidecarClient.new(transport: transport).bulk_load(atoms) }.to raise_error(SidecarClient::BulkLoadError)
    end

    it "raises BulkLoadError on a non-200 (sweep aborts loudly)" do
      transport = ->(_p, _b) { [500, { "error" => "boom" }] }
      expect { SidecarClient.new(transport: transport).bulk_load(atoms) }.to raise_error(SidecarClient::BulkLoadError)
    end

    it "raises BulkLoadError on a transport error (no per-batch retry loop)" do
      transport = ->(_p, _b) { raise Errno::ECONNREFUSED }
      expect { SidecarClient.new(transport: transport).bulk_load(atoms) }.to raise_error(SidecarClient::BulkLoadError, /transport/)
    end
  end

  describe "#projection_index (L5 Mechanism 3)" do
    it "GETs /projection_index and coerces integer-string keys" do
      seen = []
      transport = ->(path, body) { seen << [path, body]; [200, { "index" => { "100" => "abc", "5" => "DUPLICATE:2" } }] }
      idx = SidecarClient.new(transport: transport).projection_index
      expect(idx).to eq(100 => "abc", 5 => "DUPLICATE:2")    # DUPLICATE sentinel is a valid non-empty string
      expect(seen).to eq([["/projection_index", nil]])
    end

    it "raises DriftQueryError on a non-integer key (never silently to_i-coerces 'abc' -> 0)" do
      transport = ->(_p, _b) { [200, { "index" => { "12x" => "h" } }] }
      expect { SidecarClient.new(transport: transport).projection_index }
        .to raise_error(SidecarClient::DriftQueryError, /non-integer card id/)
    end

    it "raises DriftQueryError on a non-string hash value, a missing index, or a non-200" do
      expect { SidecarClient.new(transport: ->(_p, _b) { [200, { "index" => { "1" => 5 } }] }).projection_index }
        .to raise_error(SidecarClient::DriftQueryError, /non-string hash/)
      expect { SidecarClient.new(transport: ->(_p, _b) { [200, { "nope" => 1 }] }).projection_index }
        .to raise_error(SidecarClient::DriftQueryError)
      expect { SidecarClient.new(transport: ->(_p, _b) { [500, nil] }).projection_index }
        .to raise_error(SidecarClient::DriftQueryError)
    end

    it "maps transport errors to DriftQueryError" do
      expect { SidecarClient.new(transport: ->(_p, _b) { raise Errno::ECONNREFUSED }).projection_index }
        .to raise_error(SidecarClient::DriftQueryError, /transport/)
    end
  end

  describe "#card_projection (L5 Mechanism 3)" do
    it "GETs /card_projection/<id> and returns the parsed hash" do
      seen = []
      transport = ->(path, body) { seen << [path, body]; [200, { "card_id" => 7, "present" => true, "sha256" => "h" }] }
      expect(SidecarClient.new(transport: transport).card_projection(7)).to include("present" => true, "sha256" => "h")
      expect(seen).to eq([["/card_projection/7", nil]])
    end

    it "raises DriftQueryError on non-200 / transport error" do
      expect { SidecarClient.new(transport: ->(_p, _b) { [404, nil] }).card_projection(7) }.to raise_error(SidecarClient::DriftQueryError)
      expect { SidecarClient.new(transport: ->(_p, _b) { raise Net::ReadTimeout }).card_projection(7) }.to raise_error(SidecarClient::DriftQueryError)
    end
  end

  describe "#space_stats" do
    it "GETs /space_stats and returns the parsed stats" do
      seen = []
      transport = ->(path, body) { seen << [path, body]; [200, { "atom_count" => 0, "by_kind" => {} }] }
      expect(SidecarClient.new(transport: transport).space_stats).to eq("atom_count" => 0, "by_kind" => {})
      expect(seen).to eq([["/space_stats", nil]])
    end

    it "raises BulkLoadError on a non-200 / transport error" do
      expect { SidecarClient.new(transport: ->(_p, _b) { [500, nil] }).space_stats }.to raise_error(SidecarClient::BulkLoadError)
      expect { SidecarClient.new(transport: ->(_p, _b) { raise Errno::ECONNREFUSED }).space_stats }.to raise_error(SidecarClient::BulkLoadError)
    end
  end

  describe "#quarantine_card_scoped_atoms (L6 B3 admin)" do
    let(:removed) { [{ "atom" => "DeckoCard", "fields" => [["Id", 5]] }, { "atom" => "DeckoProvenance", "fields" => [["card_id", 5]] }] }

    it "POSTs /admin/quarantine_card_scoped_atoms with {card_id} and returns the removed audit set" do
      seen = []
      transport = ->(path, body) { seen << [path, body]; [200, { "card_id" => 5, "removed" => removed, "removed_count" => 2 }] }
      audit = SidecarClient.new(transport: transport).quarantine_card_scoped_atoms("5")
      expect(seen).to eq([["/admin/quarantine_card_scoped_atoms", { "card_id" => 5 }]])  # strict int coercion
      expect(audit).to eq(removed)
    end

    it "raises QuarantineError on a non-200, a malformed body, or a transport error (fail-closed)" do
      expect { SidecarClient.new(transport: ->(_p, _b) { [500, nil] }).quarantine_card_scoped_atoms(5) }
        .to raise_error(SidecarClient::QuarantineError, /HTTP 500/)
      expect { SidecarClient.new(transport: ->(_p, _b) { [200, { "no_removed" => true }] }).quarantine_card_scoped_atoms(5) }
        .to raise_error(SidecarClient::QuarantineError)
      expect { SidecarClient.new(transport: ->(_p, _b) { raise Errno::ECONNREFUSED }).quarantine_card_scoped_atoms(5) }
        .to raise_error(SidecarClient::QuarantineError, /transport error/)
    end

    it "STRICT card_id: a non-integer / non-positive id fails closed WITHOUT calling the sidecar (Codex)" do
      called = false
      transport = ->(_p, _b) { called = true; [200, { "card_id" => 0, "removed" => [], "removed_count" => 0 }] }
      %w[abc 12x 0 -5].each do |bad|
        expect { SidecarClient.new(transport: transport).quarantine_card_scoped_atoms(bad) }
          .to raise_error(SidecarClient::QuarantineError, /integer/)
      end
      expect(called).to be(false)   # never reached the destructive call
    end

    it "validates the FULL mutating-call contract: card_id echo + removed_count == removed.length (Codex)" do
      mismatch_count = ->(_p, _b) { [200, { "card_id" => 5, "removed" => removed, "removed_count" => 99 }] }
      wrong_card = ->(_p, _b) { [200, { "card_id" => 6, "removed" => removed, "removed_count" => 2 }] }
      expect { SidecarClient.new(transport: mismatch_count).quarantine_card_scoped_atoms(5) }
        .to raise_error(SidecarClient::QuarantineError, /inconsistent/)
      expect { SidecarClient.new(transport: wrong_card).quarantine_card_scoped_atoms(5) }
        .to raise_error(SidecarClient::QuarantineError, /inconsistent/)
    end
  end
end
