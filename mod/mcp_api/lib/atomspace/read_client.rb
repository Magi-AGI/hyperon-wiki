# frozen_string_literal: true

require_dependency "atomspace/errors"
require_dependency "atomspace/atom"

module Atomspace
  # Port to the sidecar Hyperon Space. The Phase 4 read-IPC verb(s) are undefined upstream
  # (Lane B coupling) -- SidecarReadClient is a stub until that lands. FakeReadClient backs
  # dev/test and is bound ONLY by a test/dev initializer.
  #
  # FAIL-CLOSED: with no implementation bound, .for / .watermark_meta raise ServiceUnavailable
  # so production can never silently serve fake/empty AtomSpace data (Codex Finding 1).
  class ReadClient
    SAFE_META = { monitor_status: "unavailable" }.freeze

    class << self
      def bind!(klass)
        @impl = klass
      end

      def reset!
        @impl = nil
      end

      def for(account:)
        raise ServiceUnavailable, "atomspace read client unbound" unless @impl

        @impl.new(account: account)
      end

      def watermark_meta
        raise ServiceUnavailable, "atomspace read client unbound" unless @impl

        @impl.watermark_meta
      end

      # Success-path helper: tolerate an unbound/unavailable client without turning a 200
      # into a 500. Error responses use SAFE_META directly and never call the client.
      def safe_watermark_meta
        watermark_meta
      rescue ServiceUnavailable
        SAFE_META
      end
    end

    def initialize(account:)
      @account = account
    end

    %i[query_atoms get_card_atom get_card_provenance list_references list_atoms_by_type
       atom_types atom_count_by_type space_stats quarantine_list quarantine_delete].each do |m|
      define_method(m) { |*| raise NotImplementedError, "#{m} not implemented for #{self.class}" }
    end
  end

  # Production client. TODO(Lane B): bind the sidecar read-IPC verb(s) over the Unix socket.
  class SidecarReadClient < ReadClient
  end
end
