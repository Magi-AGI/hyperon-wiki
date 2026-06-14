# frozen_string_literal: true

module Atomspace
  class Error < StandardError; end

  # Raised by ReadClient.for / .watermark_meta when no read client is bound.
  # FAIL-CLOSED: production must never silently serve FakeReadClient data.
  class ServiceUnavailable < Error; end
end
