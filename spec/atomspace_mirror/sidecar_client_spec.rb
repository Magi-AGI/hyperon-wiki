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

  it "maps a transport exception to retryable (never raises)" do
    transport = ->(_path, _body) { raise Errno::ECONNREFUSED }
    out = SidecarClient.new(transport: transport).apply(payload)
    expect(out.outcome).to eq(:retryable)
  end
end
