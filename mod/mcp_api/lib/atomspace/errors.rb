# frozen_string_literal: true

module Atomspace
  class Error < StandardError; end

  # Raised by ReadClient.for / .watermark_meta when no read client is bound.
  # FAIL-CLOSED: production must never silently serve FakeReadClient data.
  class ServiceUnavailable < Error; end

  # Raised for a malformed read parameter (e.g. a bad action_id_range / query pattern). The controller
  # renders it as a 400 -- a client error, not a 500/503.
  class InvalidRequest < Error; end
end
