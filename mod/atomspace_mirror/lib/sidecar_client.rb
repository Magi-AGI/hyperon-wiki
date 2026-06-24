# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# Level 8 drain -> Level 3 sidecar IPC. The drain forwards ONE already-encoded outbox payload per
# iteration to the sidecar's POST /apply (localhost; Level 3 B2) and classifies the outcome.
#
# DrainDelivery.classify is the LOCKED failure matrix (Codex 2026-06-22) and is pure (no I/O), so it
# is exhaustively unit-testable. SidecarClient does the HTTP with an injectable transport for tests.
module DrainDelivery
  DELIVERED       = :delivered         # -> mark the outbox row 'delivered'
  FAILED_TERMINAL = :failed_terminal   # -> mark 'failed' (no retry: the sidecar rejected the payload)
  RETRYABLE       = :retryable         # -> increment attempts; leave retryable until max, then 'failed'

  Outcome = Struct.new(:outcome, :reason, keyword_init: true)

  module_function

  # Failure matrix (Codex 2026-06-22):
  #   transport error / timeout            -> RETRYABLE
  #   HTTP 5xx                             -> RETRYABLE
  #   HTTP 4xx (request/payload rejected)  -> FAILED_TERMINAL
  #   HTTP 200, results[0].status:
  #        applied | already_applied       -> DELIVERED
  #        error                           -> FAILED_TERMINAL
  #        (missing / unexpected / malformed body) -> FAILED_TERMINAL (surfaces a contract break loudly)
  def classify(http_status:, body: nil, transport_error: nil)
    return outcome(RETRYABLE, "transport error: #{transport_error}") if transport_error
    return outcome(RETRYABLE, "sidecar #{http_status}") if http_status >= 500
    return outcome(FAILED_TERMINAL, "request rejected (#{http_status}): #{error_of(body)}") if http_status >= 400

    results = body.is_a?(Hash) ? body["results"] : nil
    unless results.is_a?(Array) && results.size == 1
      return outcome(FAILED_TERMINAL, "malformed /apply response (expected one result): #{body.inspect}")
    end

    result = results.first
    status = result.is_a?(Hash) ? result["status"] : nil
    case status
    when "applied", "already_applied"
      outcome(DELIVERED, status)
    when "error"
      outcome(FAILED_TERMINAL, "sidecar event error: #{result["error"]}")
    else
      outcome(FAILED_TERMINAL, "unexpected event status: #{status.inspect}")
    end
  end

  def outcome(kind, reason)
    Outcome.new(outcome: kind, reason: reason)
  end

  def error_of(body)
    body.is_a?(Hash) ? (body["error"] || body) : body
  end
end

# Thin HTTP client for the sidecar's POST /apply. One payload per call (the drain is single-event per
# iteration in Phase 4; batching is a Phase 5+ optimization). Transport is injectable for tests:
# a callable (path, body_hash) -> [http_status_int, parsed_body_or_nil].
class SidecarClient
  # ONLY genuine network/timeout failures are retryable. Everything else (JSON generation bugs,
  # NoMethodError, contract mistakes) is a programming error and MUST propagate loudly -- mapping all
  # StandardError to :retryable would silently retry real bugs forever (Codex 2026-06-22).
  RETRYABLE_TRANSPORT_ERRORS = [
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::EPIPE,
    Errno::ETIMEDOUT, Net::OpenTimeout, Net::ReadTimeout, SocketError, EOFError, IOError, Timeout::Error
  ].freeze

  # Raised when a bootstrap /bulk_load batch fails. Bootstrap is operator-driven (not a per-event
  # retry loop), so a batch failure aborts the sweep loudly; the operator re-runs (against a fresh
  # sidecar, per the §1 acceptance -- the in-memory Space is wiped on sidecar restart).
  class BulkLoadError < StandardError; end

  def initialize(host: "127.0.0.1", port: 9407, open_timeout: 2, read_timeout: 5, transport: nil)
    @host = host
    @port = port
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    @transport = transport
  end

  # Forward ONE outbox payload (a {"atoms"=>[...]} Hash) and return a DrainDelivery::Outcome.
  def apply(payload)
    status, parsed = post("/apply", { "payloads" => [payload] })
    DrainDelivery.classify(http_status: status, body: parsed)
  rescue *RETRYABLE_TRANSPORT_ERRORS => e   # connect refused / timeout / DNS / reset -> retryable
    DrainDelivery.classify(http_status: 0, transport_error: "#{e.class}: #{e.message}")
  end

  # Bulk-load a batch of atom dicts (DeckoCard/DeckoReference, NO provenance) during the §1 bootstrap
  # sweep. POST /bulk_load. Returns the count the sidecar loaded; raises BulkLoadError on any
  # non-200 / transport failure so the sweep aborts loudly (operator re-runs).
  def bulk_load(atoms)
    sent = atoms.length
    status, parsed = post("/bulk_load", { "atoms" => atoms })
    loaded = parsed.is_a?(Hash) ? parsed["loaded"] : nil
    # Require an exact integer ack equal to what we sent -- a partial / malformed success must abort
    # the sweep (it would otherwise silently leave the Space short of the batch). (Codex 2026-06-23.)
    unless status == 200 && loaded.is_a?(Integer) && loaded == sent
      raise BulkLoadError,
            "bulk_load failed (HTTP #{status}, loaded=#{loaded.inspect}, sent=#{sent}): #{(parsed || {}).inspect[0, 200]}"
    end
    loaded
  rescue *RETRYABLE_TRANSPORT_ERRORS => e
    raise BulkLoadError, "bulk_load transport error: #{e.class}: #{e.message}"
  end

  private

  def post(path, body_hash)
    return @transport.call(path, body_hash) if @transport

    uri = URI("http://#{@host}:#{@port}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = @open_timeout
    http.read_timeout = @read_timeout
    request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
    request.body = JSON.generate(body_hash)
    response = http.request(request)
    [response.code.to_i, safe_parse(response.body)]
  end

  def safe_parse(raw)
    JSON.parse(raw)
  rescue JSON::ParserError, TypeError
    nil
  end
end
