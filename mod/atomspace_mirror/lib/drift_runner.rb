# frozen_string_literal: true

require "json"
require_relative "drift_monitor"

# Level 5 runtime shell around the pure DriftMonitor mechanisms. Owns the cross-run state the pure
# functions can't (the 1b consecutive-nonzero streak; per-mechanism last-run timestamps for the
# missed-run watchdog) and the side effects (structured JSON emit to L10; error capture so a failing
# monitor never crashes the scheduler thread).
#
# REPORT-ONLY: like DriftMonitor, this never mutates a mirror model and never remediates.
#
# Phase-4 caveat: the streak + last-run registry are IN-PROCESS (reset on restart). Acceptable while
# the monitors are co-located with the single drain host; Phase 5 moves them to a persistent store.
#
# Dependencies are injected for testability:
#   emitter          : call(Hash) -- L10 sink; default logs one JSON line at INFO (warn on "alert").
#   clock            : -> Time    -- UTC now.
#   a_start_provider : -> Integer -- mirror_state.bootstrap_a_start.
#   conn             : the AR connection passed through to the pure mechanisms.
class DriftRunner
  # Default minute-ish cadences (seconds), used by the schedule + the missed-run watchdog. A run is
  # "skipped" if its last success is older than SKIP_FACTOR x its cadence.
  CADENCE = { "hook_tail_lag" => 30, "coverage_gap" => 300, "drain_lag" => 60 }.freeze
  SKIP_FACTOR = 2

  def initialize(emitter: nil, clock: -> { Time.now.utc },
                 a_start_provider: -> { default_a_start }, conn: nil)
    @emitter = emitter
    @clock = clock
    @a_start_provider = a_start_provider
    @conn = conn
    @coverage_gap_streak = 0
    @last_success = {}   # mechanism_name => Time (UTC); drives the missed-run watchdog
    @started_at = @clock.call  # baseline so a never-yet-due mechanism isn't falsely "skipped" at boot
  end

  def run_hook_tail_lag
    run("hook_tail_lag") { DriftMonitor.hook_tail_lag(a_start, **conn_opt) }
  end

  def run_coverage_gap
    run("coverage_gap") do
      report = DriftMonitor.coverage_gap(a_start, prior_nonzero_runs: @coverage_gap_streak, **conn_opt)
      @coverage_gap_streak = report[:consecutive_nonzero_runs]
      report
    end
  end

  def run_drain_lag
    run("drain_lag") { DriftMonitor.drain_lag(a_start, **conn_opt) }
  end

  def run_all
    [run_hook_tail_lag, run_coverage_gap, run_drain_lag]
  end

  # Missed-run watchdog (Section 2 / L5 acceptance: a missed run is observable). Emits one
  # `mechanism_run_skipped` per mechanism whose most recent success is older than SKIP_FACTOR x
  # cadence. A mechanism that has NEVER succeeded is measured from the runner's start time, NOT
  # treated as instantly skipped -- otherwise a fresh scheduler would page for every mechanism before
  # its first scheduled opportunity (e.g. coverage_gap's first run is 300s out, but the watchdog ticks
  # every 30s) (Codex 2026-06-24). Schedule on its own tick. Returns the skipped mechanism names.
  def check_heartbeats(now: @clock.call)
    CADENCE.filter_map do |name, cadence|
      last = @last_success[name]
      baseline = last || @started_at   # never-run -> measure staleness from boot, not from epoch
      next unless (now - baseline) > cadence * SKIP_FACTOR

      emit(mechanism: name, signal: "mechanism_run_skipped", status: "alert",
           last_success: last&.iso8601,                 # nil if it has never succeeded
           age_seconds: (now - baseline).round(1),
           cadence_seconds: cadence, ts: now.iso8601)
      name
    end
  end

  private

  # Wrap one mechanism: time it, stamp it, emit it, record the success heartbeat. A raised error is
  # caught and emitted as a structured `error` report (NOT re-raised) so one bad query can't take down
  # the scheduler -- the emitted signal is the observable, per the L10 contract.
  def run(name)
    started = @clock.call
    report = yield
    finished = @clock.call
    report = report.merge(ts: finished.iso8601, duration_ms: ((finished - started) * 1000.0).round(1))
    @last_success[name] = finished
    emit(report)
    report
  rescue StandardError => e
    emit(mechanism: name, status: "error", error: "#{e.class}: #{e.message}", ts: @clock.call.iso8601)
    nil
  end

  def a_start
    @a_start_provider.call.to_i
  end

  # Only pass conn: through when one was injected, so the pure mechanisms keep their
  # ActiveRecord::Base.connection default in production.
  def conn_opt
    @conn ? { conn: @conn } : {}
  end

  def default_a_start
    defined?(MirrorState) ? MirrorState.first&.bootstrap_a_start.to_i : 0
  end

  # Default L10 sink: one JSON line. "alert"/"error" -> warn; everything else -> info. A real L10
  # adapter (metrics/alerting) is injected as `emitter` in production wiring.
  def emit(report)
    return @emitter.call(report) if @emitter

    line = "[atomspace_mirror][drift] #{JSON.generate(report)}"
    return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

    %w[alert error].include?(report[:status]) ? Rails.logger.warn(line) : Rails.logger.info(line)
  end
end
