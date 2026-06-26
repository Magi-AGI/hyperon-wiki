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

  desc "Drift sweep: full-projection SHA256 reconciliation, PG vs Space (Section 2 / Level 5, Mech 3, report-only)."
  task drift_sweep: :environment do
    run = DriftReconciler.new.run!
    puts "[atomspace_mirror] drift sweep run=#{run.id} stable=#{run.stable} " \
         "pg_only=#{run.drift_pg_only} space_only=#{run.drift_space_only} mismatch=#{run.drift_mismatch}"
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
