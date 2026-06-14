# frozen_string_literal: true

module Atomspace
  # L9 consumes read-your-writes readiness through this port. The real implementation is
  # Lane A's mod/atomspace_mirror/lib/read_consistency.rb (L7), injected at boot once that
  # engine + the mirror_outbox migration land. Tests inject a fake.
  #
  # Contract: check_event_ready(event_id) -> :ready | :not_yet | :not_yet_inserted |
  #           :failed | :integrity_error   (:integrity_error is terminal -> HTTP 409)
  module ReadConsistencyPort
    class NotWired < StandardError; end

    class << self
      attr_writer :impl

      def check_event_ready(event_id)
        raise NotWired, "ReadConsistency not wired (Lane A L7 / mirror_outbox)" unless @impl

        @impl.check_event_ready(event_id)
      end

      def reset!
        @impl = nil
      end
    end
  end
end
