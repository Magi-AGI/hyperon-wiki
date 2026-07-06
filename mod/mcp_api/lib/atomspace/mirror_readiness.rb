# frozen_string_literal: true

module Atomspace
  # Level 9 read-readiness gate (Phase 5 go-live blocker). The L9 read surface must FAIL CLOSED until
  # the mirror is actually serving a faithful Space -- otherwise an empty or partially-populated
  # PyListSpace (during bootstrap, or after a crash/boot-time restart into an empty in-memory Space)
  # would serve misleading 200s. The pre-existing ReadConsistencyPort only guards `wait_for_event_id`
  # (read-your-writes) paths; NO-WAIT card reads and ALL aggregate/quarantine reads bypassed it. This
  # predicate is consulted by AtomspaceMirrorController#require_mirror_ready! on EVERY read action.
  #
  # FAIL CLOSED: any probe error, missing mirror table, in-progress (re)bootstrap, or an
  # unreachable/empty/UNDER-POPULATED sidecar => not ready. The probes are class-level injectable
  # (mirrors ReadConsistencyPort.impl), so the predicate is unit-testable with plain lambdas and no
  # Decko/DB/sidecar boot; production leaves them nil -> the real defaults query the Lane A models, and
  # the controller passes a sidecar probe built from its request-scoped read client.
  #
  # Readiness requires ALL of:
  #   1. mirroring enabled            (ATOMSPACE_MIRRORING_ENABLED == "true")
  #   2. mirror tables available      (MirrorState reachable)
  #   3. a completed bootstrap        (mirror_state.bootstrap_a_start set + draining_enabled + a
  #                                    'completed' mirror_bootstrap_runs row with a cards_swept count)
  #   4. no (re)bootstrap in progress  (no 'running' mirror_bootstrap_runs row -> mid-rebuild)
  #   5. sidecar reachable + POPULATED (its DeckoCard atom count >= the last completed bootstrap's
  #                                    cards_swept -- NOT merely > 0). This is the reviewer-blocking
  #                                    strengthening (Codex C2): once the drain applies even one row a
  #                                    post-restart empty Space would report atom_count > 0, so a bare
  #                                    non-empty check would false-green a partial Space. The
  #                                    cards_swept threshold catches an under-populated Space because
  #                                    the forward path is additive (POLICY-B upsert + trash-not-remove
  #                                    + new cards), so a faithfully-populated Space never drops below
  #                                    its bootstrap DeckoCard baseline within a bootstrap generation.
  module MirrorReadiness
    Result = Struct.new(:ready, :reason, keyword_init: true) do
      def ready? = ready
    end

    READY = Result.new(ready: true, reason: nil).freeze

    class << self
      # Test seams: set a probe to override its real default; leave nil in production.
      attr_writer :enabled_probe, :state_probe, :running_probe, :expected_cards_probe, :sidecar_probe

      # Returns a Result. `sidecar_override` (optional callable -> {reachable:Bool, card_count:Integer})
      # replaces the sidecar probe for this call; the controller passes one built from its read client.
      # It is called LAZILY -- only once the cheap DB-side checks pass -- so a not-bootstrapped mirror
      # never triggers a live IPC round-trip.
      def check(sidecar_override = nil)
        return not_ready("mirroring_disabled") unless enabled_probe.call

        state = state_probe.call
        return not_ready("mirror_tables_unavailable") if state == :tables_unavailable
        return not_ready("mirror_not_bootstrapped") if state.nil?
        return not_ready("mirror_rebuild_in_progress") if running_probe.call
        return not_ready("mirror_not_bootstrapped") unless bootstrapped?(state)

        expected = expected_cards_probe.call
        # No completed bootstrap run (or a zero-card one) -> the corpus baseline is unknown; treat as
        # not-bootstrapped rather than trust any sidecar count.
        return not_ready("mirror_not_bootstrapped") unless expected.is_a?(Integer) && expected.positive?

        sidecar = (sidecar_override || sidecar_probe).call
        return not_ready("sidecar_unreachable") unless sidecar && sidecar[:reachable]

        count = sidecar[:card_count].to_i
        return not_ready("sidecar_empty_post_restart") if count.zero?
        return not_ready("sidecar_below_expected") if count < expected

        READY
      rescue StandardError => e
        # Any unexpected failure is treated as NOT ready (never a false green).
        not_ready("readiness_probe_error:#{e.class}")
      end

      def reset!
        @enabled_probe = @state_probe = @running_probe = @expected_cards_probe = @sidecar_probe = nil
      end

      # Extract the DeckoCard count from the Ruby ReadClient's NORMALIZED space_stats shape
      # `{ atom_count:, types: { "<kind>" => count, ... }, mirror_lag: }` (both SidecarReadClient and
      # FakeReadClient produce this -- the per-kind map is `types`, NOT the sidecar's raw `by_kind`).
      # Reading `by_kind` here returned 0 forever and pinned readiness at 503 (Codex/Gemini closure
      # blocker). Tolerant of symbol/string keys at both levels; returns 0 on any unexpected shape.
      def card_count_from_stats(stats, kind: "DeckoCard")
        return 0 unless stats.is_a?(Hash)

        types = stats[:types] || stats["types"]
        return 0 unless types.is_a?(Hash)

        (types[kind] || types[kind.to_sym]).to_i
      end

      private

      def enabled_probe
        @enabled_probe || -> { ENV["ATOMSPACE_MIRRORING_ENABLED"].to_s.strip.casecmp?("true") }
      end

      def state_probe
        @state_probe || method(:default_state)
      end

      def running_probe
        @running_probe || -> { MirrorBootstrapRun.where(status: "running").exists? }
      end

      # Expected DeckoCard count = the LAST completed bootstrap run's cards_swept (a re-bootstrap writes
      # a new completed run). nil when no completed run exists.
      def expected_cards_probe
        @expected_cards_probe || -> { MirrorBootstrapRun.where(status: "completed").order(:id).last&.cards_swept }
      end

      # FAIL CLOSED by default (reachable:false): production MUST pass an explicit sidecar_override (the
      # controller does), so an un-wired deployment can never read as ready.
      def sidecar_probe
        @sidecar_probe || -> { { reachable: false, card_count: 0 } }
      end

      # Reference the constant DIRECTLY (no `defined?`, which bypasses the Rails autoloader and would
      # permanently fail a fresh web worker that hasn't yet loaded the Lane A models -- Gemini B2).
      # Referencing MirrorState triggers the autoloader; a genuinely missing model (NameError) or a
      # missing table / no DB (ActiveRecord error, both StandardError) fail closed to tables-unavailable.
      def default_state
        MirrorState.instance
      rescue StandardError
        :tables_unavailable
      end

      def bootstrapped?(state)
        !state.bootstrap_a_start.nil? && !!state.draining_enabled
      end

      def not_ready(reason)
        Result.new(ready: false, reason: reason)
      end
    end
  end
end
