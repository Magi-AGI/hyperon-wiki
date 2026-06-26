# frozen_string_literal: true

require_relative "mirror"
require_relative "card_atom_encoder"
require_relative "sidecar_client"

# Level 4 -- first-time mirror population (Section 1 hybrid sweep, Option A: fresh-sidecar/full-rerun).
#
# Our integrate hook is ALWAYS attached (auto-discovered), so the §1 "attach hook before A_start"
# race protection holds by construction: every committed action since boot is already in the outbox,
# the worker is paused (draining_enabled=false until completion), and the sweep + the
# superseded_by_bootstrap mark clean the overlap. Procedure: guard -> assert empty Space ->
# A_start snapshot -> run row(status=running) -> sweep (bulk_load) -> completion txn -> activate.
#
# Split for testability: #run is the dev-gated shell (dedicated Postgres advisory lock); #run_locked
# is the unit-tested orchestration (stubbed models + injected SidecarClient). NOT run outside a gated
# dev session in Phase 4.
class Bootstrap
  DEFAULT_BATCH_SIZE = 500

  class AlreadyRunning < StandardError; end
  class NonEmptySpace < StandardError; end

  def initialize(sidecar: SidecarClient.new, batch_size: DEFAULT_BATCH_SIZE, actor: "system",
                 clock: -> { Time.now.utc })
    @sidecar = sidecar
    @batch_size = batch_size
    @actor = actor
    @clock = clock
  end

  # Dev-gated entry: take the dedicated bootstrap advisory lock (singleton across replicas), then run.
  # Released in ensure. Returns the completed MirrorBootstrapRun.
  def run
    conn = ActiveRecord::Base.connection
    conn.execute("SELECT pg_advisory_lock(#{Mirror::BOOTSTRAP_LOCK_ID})")
    begin
      run_locked
    ensure
      conn.execute("SELECT pg_advisory_unlock(#{Mirror::BOOTSTRAP_LOCK_ID})")
    end
  end

  # The orchestration (UNIT-TESTED). Aborts loudly on any failure, marking the run row 'failed'.
  def run_locked
    guard_no_running_run!
    pause_draining!
    assert_empty_space!
    a_start = snapshot_a_start
    run = MirrorBootstrapRun.create!(a_start: a_start, started_at: now, actor: @actor, status: "running")
    begin
      swept = sweep(run)
      complete!(run, a_start, swept)
      run
    rescue StandardError => e
      fail_run!(run, "#{e.class}: #{e.message}")
      raise
    end
  end

  private

  # Single-run guard: a crashed run leaves status='running' (not completed_at), so this blocks a
  # concurrent/overlapping start; an operator marks a dead run 'aborted' to clear it (the partial
  # index on status='running' makes this cheap).
  def guard_no_running_run!
    raise AlreadyRunning, "a bootstrap run is already in progress (status='running')" if MirrorBootstrapRun.where(status: "running").exists?
  end

  # Pause the forward drain BEFORE sweeping so it cannot apply forward deltas into the fresh Space
  # while the sweep bulk-loads (the locked "worker paused until completion" model). On a re-bootstrap
  # draining_enabled is still true from the prior completion; flip it false under the singleton lock.
  # NOTE the operator must ALSO stop the drain-worker process (the §1 maintenance window) -- flipping
  # the flag idles future iterations but cannot abort an in-flight one.
  def pause_draining!
    MirrorOutbox.transaction do
      state = MirrorState.lock.first
      state.update!(draining_enabled: false) if state&.draining_enabled
    end
  end

  # Option A: bootstrap requires a FRESH (empty) Space -- /bulk_load is not idempotent, so a re-run
  # must start from a wiped sidecar (restart it first). Refuse to load into a non-empty (or
  # unverifiable) Space: a missing/non-integer atom_count is a contract break, not "empty".
  def assert_empty_space!
    count = @sidecar.space_stats["atom_count"]
    raise NonEmptySpace, "space_stats returned no integer atom_count: #{count.inspect}" unless count.is_a?(Integer)
    raise NonEmptySpace, "sidecar Space is not empty (atom_count=#{count}); restart the sidecar before bootstrap" unless count.zero?
  end

  # The cutoff between sweep coverage and forward coverage (matches the integrate hook's draft filter).
  def snapshot_a_start
    Card::Action.where("draft IS NOT TRUE").maximum(:id) || 0
  end

  def sweep(run)
    swept = 0
    Card.where(trash: [true, false]).find_in_batches(batch_size: @batch_size) do |batch|
      atoms = batch.flat_map { |card| CardAtomEncoder.encode_card_snapshot(card) }
      @sidecar.bulk_load(atoms)                      # raises BulkLoadError -> abort (run marked failed)
      run.update!(last_card_id_swept: batch.last.id) # progress/observability only (Option A)
      swept += batch.size
    end
    swept
  end

  # Completion (single transaction). The MirrorState SELECT FOR UPDATE serializes against the
  # integrate-job INSERT discipline (which reads bootstrap_a_start under the same lock), so the
  # cutover is atomic. Marks pre-A_start queued rows superseded; flips draining on; closes the run.
  def complete!(run, a_start, swept)
    MirrorOutbox.transaction do
      state = MirrorState.lock.first
      MirrorOutbox.where(status: "queued").where("action_id <= ?", a_start)
                  .update_all(status: "superseded_by_bootstrap")
      state.update!(bootstrap_a_start: a_start, last_drained_action_id: a_start, draining_enabled: true)
      run.update!(status: "completed", completed_at: now, cards_swept: swept)
    end
  end

  def fail_run!(run, message)
    run.update!(status: "failed", completed_at: now, actor: @actor)
    log_failure(run, message)
  rescue StandardError
    nil # never mask the original error with a bookkeeping failure
  end

  def log_failure(run, message)
    return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
    Rails.logger.error("[atomspace_mirror] bootstrap run #{run.id rescue nil} failed: #{message}")
  end

  def now = @clock.call
end
