# frozen_string_literal: true

require_relative "mirror"
require_relative "mirror_drain_validator"
require_relative "sidecar_client"

# Level 8 -- the singleton forward-drain worker (Section 10 v9). Polls mirror_outbox, validates +
# forwards one queued event per iteration to the sidecar, and advances row status + the diagnostic
# watermark. Correctness is STRUCTURAL (the superseded_by_later_or_reconcile? guard), NOT
# ordering-dependent; mirror_outbox.id order is only a delivery heuristic. Singleton across replicas
# via a per-iteration Postgres advisory lock (Mirror::DRAIN_LOCK_ID). Co-located with the sidecar
# (localhost IPC, Level 3).
#
# Split for testability: #process_row (the stateful per-row transition) is unit-tested with stubbed
# models + an injected SidecarClient; #drain_loop + the advisory lock + the real mirror_outbox query
# are the dev-gated shell, validated end-to-end once the host Python env + a fresh snapshot are in
# place. Live execution is NOT run from here outside that gated dev session.
class DrainWorker
  DEFAULT_POLL_INTERVAL = 0.1   # seconds; slept ONLY between lock releases (when idle)
  DEFAULT_MAX_ATTEMPTS  = 5

  def initialize(sidecar: SidecarClient.new, poll_interval: DEFAULT_POLL_INTERVAL,
                 max_attempts: DEFAULT_MAX_ATTEMPTS, alerter: nil, clock: -> { Time.now.utc })
    @sidecar = sidecar
    @poll_interval = poll_interval
    @max_attempts = max_attempts
    @alerter = alerter             # L10 hook: call(signal_sym, row, message); nil -> warn log
    @clock = clock
    @running = false
  end

  def running? = @running
  def stop = (@running = false)

  # Dev-gated daemon loop: a BLOCKING advisory lock per iteration (a second worker blocks here, not
  # spin-polls); sleep only AFTER releasing the lock (Section 10 v9). Never run outside a gated dev
  # session in Phase 4.
  def drain_loop
    @running = true
    conn = ActiveRecord::Base.connection
    while @running
      conn.execute("SELECT pg_advisory_lock(#{Mirror::DRAIN_LOCK_ID})")
      begin
        idle = drain_one_iteration
      ensure
        conn.execute("SELECT pg_advisory_unlock(#{Mirror::DRAIN_LOCK_ID})")
      end
      sleep(@poll_interval) if idle
    end
  end

  # One iteration (runs inside the lock). Returns true when idle (nothing to do -> caller sleeps).
  # No card_actions cursor: queries mirror_outbox directly for the oldest visible queued row.
  def drain_one_iteration
    state = MirrorState.first
    return true unless state&.draining_enabled

    row = MirrorOutbox.where(status: "queued").order(:id).first
    return true unless row

    process_row(row, state)
    false
  end

  # The stateful transition for one queued row (UNIT-TESTED). Each branch wraps its writes in a
  # MirrorOutbox.transaction; the diagnostic watermark is recomputed on every TERMINAL transition.
  # Returns a symbol: :invalid | :superseded | :delivered | :failed | :retried.
  def process_row(row, state)
    # (1) OQ#15 preflight: a structurally invalid / mismatched row terminalizes LOCALLY -- never IPC
    # (so a corrupt row can't masquerade as a retryable sidecar outage).
    begin
      MirrorDrainValidator.validate!(row, row.payload)
    rescue MirrorDrainValidator::InvalidRow => e
      terminalize(row, state, "structural validation failed: #{e.message}")
      alert(:mirror_structural_invalid, row, e.message)
      return :invalid
    end

    # (2) same-card stale-overwrite guard (decko_action only; reconcile bypasses by construction).
    if row.event_kind == "decko_action" && MirrorOutbox.superseded_by_later_or_reconcile?(row)
      MirrorOutbox.transaction do
        row.update!(status: "superseded_by_later", last_attempt_at: now)
        advance_watermark(state)
      end
      return :superseded
    end

    # (3) forward to the sidecar; classify per the locked failure matrix.
    outcome = @sidecar.apply(row.payload)
    case outcome.outcome
    when DrainDelivery::DELIVERED
      MirrorOutbox.transaction do
        row.update!(status: "delivered", last_attempt_at: now)
        release_linked_reconcile(row) if row.event_kind == "reconcile"  # Section 3 two-phase release
        advance_watermark(state)
      end
      :delivered
    when DrainDelivery::FAILED_TERMINAL
      terminalize(row, state, outcome.reason)
      alert(:mirror_drain_failed, row, outcome.reason)
      :failed
    else # DrainDelivery::RETRYABLE
      retry_or_fail(row, state, outcome.reason)
    end
  end

  private

  def retry_or_fail(row, state, reason)
    attempts = row.attempts.to_i + 1
    failed = attempts >= @max_attempts
    MirrorOutbox.transaction do
      if failed
        row.update!(status: "failed", attempts: attempts, last_attempt_at: now, error: reason)
        advance_watermark(state)
      else
        row.update!(attempts: attempts, last_attempt_at: now, error: reason)  # stays 'queued'
      end
    end
    return :retried unless failed

    alert(:mirror_drain_failed, row, reason)
    :failed
  end

  def terminalize(row, state, message)
    MirrorOutbox.transaction do
      row.update!(status: "failed", attempts: row.attempts.to_i + 1, last_attempt_at: now, error: message)
      advance_watermark(state)
    end
  end

  # Section 3 two-phase release: when a reconcile row is delivered, the decko_action rows it was
  # holding (awaiting_reconcile, linked by source_reconcile_event_id) advance in the SAME transaction.
  def release_linked_reconcile(reconcile_row)
    MirrorOutbox.where(event_kind: "decko_action", status: "awaiting_reconcile",
                       source_reconcile_event_id: reconcile_row.event_id)
                .update_all(status: "superseded_by_reconcile")
  end

  def advance_watermark(state)
    state.update!(last_drained_action_id: Mirror.compute_contiguous_watermark(state.bootstrap_a_start.to_i))
  end

  def alert(signal, row, message)
    return @alerter.call(signal, row, message) if @alerter

    if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
      Rails.logger.warn("[atomspace_mirror] #{signal} event_id=#{row.event_id} card_id=#{row.card_id}: #{message}")
    end
  end

  def now = @clock.call
end
