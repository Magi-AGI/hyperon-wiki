# frozen_string_literal: true

# Level 4 bootstrap entry: `rake atomspace_mirror:bootstrap` (a.k.a. `decko atomspace_mirror:bootstrap`).
# Thin wrapper over Bootstrap#run (the runner owns the advisory lock + single-run guard + sweep +
# completion). Operator runbook: ensure a FRESH (empty) sidecar Space first (Option A) -- restart the
# sidecar before running; a failed run is marked 'failed' and must be re-run from scratch.
namespace :atomspace_mirror do
  desc "First-time bootstrap: sweep all cards into the Hyperon Space (Section 1 / Level 4)."
  task bootstrap: :environment do
    run = Bootstrap.new.run
    puts "[atomspace_mirror] bootstrap completed: run=#{run.id} a_start=#{run.a_start} " \
         "cards_swept=#{run.cards_swept} last_card_id_swept=#{run.last_card_id_swept}"
  end

  # ---- Level 8 forward-drain worker (Section 10). Long-running; systemd ExecStart. ----
  # Supervised entry point for the singleton drain loop. Owns NO drain logic of its own -- it just
  # boots Decko, builds the existing DrainWorker, and runs #drain_loop (which takes the per-iteration
  # Mirror::DRAIN_LOCK_ID advisory lock, so a second instance blocks rather than double-drains). It is
  # SAFE to start before bootstrap: drain_one_iteration idles while mirror_state.draining_enabled is
  # false, so the service simply waits until bootstrap flips draining on. SIGINT/SIGTERM request a
  # graceful stop (the loop exits after finishing and releasing the current iteration's lock).
  desc "Run the singleton forward-drain worker loop (Level 8 / Section 10). Long-running; systemd ExecStart."
  task drain: :environment do
    $stdout.sync = true
    worker = DrainWorker.new
    %w[INT TERM].each { |sig| Signal.trap(sig) { worker.stop } }
    puts "[atomspace_mirror] drain worker starting (pid=#{Process.pid})"
    worker.drain_loop
    puts "[atomspace_mirror] drain worker stopped (pid=#{Process.pid})"
  end

  desc "Drift sweep: full-projection SHA256 reconciliation, PG vs Space (Section 2 / Level 5, Mech 3, report-only)."
  task drift_sweep: :environment do
    run = DriftReconciler.new.run!
    puts "[atomspace_mirror] drift sweep run=#{run.id} stable=#{run.stable} " \
         "pg_only=#{run.drift_pg_only} space_only=#{run.drift_space_only} mismatch=#{run.drift_mismatch}"
  end

  # ---- Level 5 drift stream monitors (Section 2 cadences). Long-running; systemd ExecStart. ----
  # Report-only. Wires the three stream monitors (hook-tail-lag / coverage-gap / drain-lag) + the
  # missed-run watchdog onto a Rufus::Scheduler via the existing DriftSchedule.install, then blocks on
  # the scheduler. Emits structured JSON to Rails.logger by default (deployment-time metric/alert
  # adapters plug in via DriftRunner's emitter). This is DISTINCT from drift_sweep (Mechanism 3, the
  # O(n) full-projection sweep), which stays a cron/timer job per the deployment runbook.
  desc "Run the L5 drift stream monitors on their Section-2 cadences (report-only). Long-running; systemd ExecStart."
  task drift_schedule: :environment do
    require_relative "../../config/initializers/drift_schedule"
    $stdout.sync = true
    scheduler = DriftSchedule.install
    %w[INT TERM].each { |sig| Signal.trap(sig) { scheduler.shutdown } }
    puts "[atomspace_mirror] drift schedule started (pid=#{Process.pid})"
    scheduler.join
    puts "[atomspace_mirror] drift schedule stopped (pid=#{Process.pid})"
  end

  # ---- Level 6 reconciliation / repair (Section 3). Operator-initiated; off-hours. ----
  desc "Remediate an L5 drift detection run (Section 3 / Level 6). Args: [detection_run_id]; FORCE=1 overrides an unstable run."
  task :reconcile, [:detection_run_id] => :environment do |_t, args|
    id = Integer(args[:detection_run_id] || ENV["DETECTION_RUN_ID"])
    run = Reconciler.run!(id, force: ENV["FORCE"] == "1")
    puts "[atomspace_mirror] reconcile run=#{run.id} status=#{run.status} remediated=#{run.remediated}"
  end

  desc "Hook-lag remediation: replay / supersede / hold Mechanism 1b coverage gaps (Section 3 / Level 6)."
  task remediate_hook_lag: :environment do
    run = Reconciler.remediate_hook_lag!
    puts "[atomspace_mirror] hook-lag remediation run=#{run.id} remediated=#{run.remediated}"
  end

  desc "Drain-lag reset: requeue / supersede / hold failed mirror_outbox rows (Section 3 / Level 6, helper-gated)."
  task requeue_failed: :environment do
    run = Reconciler.requeue_failed!
    puts "[atomspace_mirror] requeue_failed run=#{run.id} remediated=#{run.remediated}"
  end
end
