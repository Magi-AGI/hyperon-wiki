# frozen_string_literal: true

require_relative "../../lib/drift_runner"

# Level 5 schedule wiring (Section 2 cadences). Registers the three Slice-5a stream monitors + the
# missed-run watchdog with a Rufus::Scheduler.
#
# IMPORTANT (dev-gated, hard-won): Decko does NOT auto-load a mod's config/initializers/*.rb on boot
# (verified on dev for routes AND the read-client binding). So this file does NOT start anything at
# require time -- it exposes `DriftSchedule.install(...)` which an operator / deck-level initializer
# calls explicitly. Like the L8 drain worker, the drift monitors are a background process launched in
# a gated session, never auto-started inside web request processes. REPORT-ONLY in Phase 4.
module DriftSchedule
  module_function

  # Wire the three monitors at their Section-2 cadences + a heartbeat watchdog. Returns the scheduler
  # (caller owns its lifecycle: keep the process alive, .shutdown on stop). Injectable for tests.
  def install(scheduler: default_scheduler, runner: DriftRunner.new)
    scheduler.every("#{DriftRunner::CADENCE['hook_tail_lag']}s", overlap: false) { runner.run_hook_tail_lag }
    scheduler.every("#{DriftRunner::CADENCE['coverage_gap']}s", overlap: false) { runner.run_coverage_gap }
    scheduler.every("#{DriftRunner::CADENCE['drain_lag']}s",    overlap: false) { runner.run_drain_lag }
    # Watchdog at the tightest cadence so a stalled scheduler thread is caught within ~one interval.
    scheduler.every("#{DriftRunner::CADENCE['hook_tail_lag']}s", overlap: false) { runner.check_heartbeats }
    scheduler
  end

  # Rufus is an optional dependency: loaded lazily so requiring this file never hard-fails a deck that
  # doesn't have the gem. install raises a clear error if it's genuinely missing at launch time.
  def default_scheduler
    require "rufus-scheduler"
    Rufus::Scheduler.new
  rescue LoadError
    raise LoadError, "rufus-scheduler is required to run the L5 drift schedule; add it to the deck " \
                     "Gemfile or pass an explicit scheduler: to DriftSchedule.install"
  end
end
