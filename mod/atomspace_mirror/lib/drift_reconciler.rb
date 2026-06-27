# frozen_string_literal: true

require "set"
require "json"
require_relative "drift_monitor"
require_relative "card_atom_encoder"
require_relative "canonical_projection"
require_relative "sidecar_client"

# Level 5 / Mechanism 3 -- the full-projection drift sweep (Section 2, reviewer-locked 2026-06-24).
# REPORT-ONLY: detects divergence between Postgres and the Hyperon Space and records it in
# mirror_reconcile_runs; it NEVER remediates (remediation is L6). Set-reconciliation over two full
# {card_id => sha256} inventories:
#   * Postgres side: encode every card's snapshot (DeckoCard + sorted DeckoReferences, no provenance)
#     and hash it with the locked CanonicalProjection.
#   * Space side: the sidecar's GET /projection_index (byte-identical Python serializer).
# Diff -> cards_pg_only / cards_space_only / cards_mismatch.
#
# Consistency-window rule (Codex): the sweep is NOT atomic across PG + sidecar, so a card changing
# mid-sweep (PG updated, Space awaiting drain) can surface as false drift. We capture drain-lag +
# MAX(card_actions.id) at start AND end; the run is `stable` only if drain lag is 0 at both ends and
# no card_actions were committed during the sweep. When NOT stable, every flagged card is re-verified
# individually (re-fetch both sides) so transient divergences are dropped before reporting.
#
# Dependencies are injected for standalone testing (no Decko/DB/sidecar needed in unit tests).
class DriftReconciler
  Diff = Struct.new(:pg_only, :space_only, :mismatch, keyword_init: true)

  # The drift queries (/projection_index, /card_projection) are O(n) over the whole Space -- at the
  # production corpus (~9.6K cards / ~17K atoms) /projection_index measured ~7.4s, which exceeds the
  # SidecarClient default 5s read_timeout and times the sweep out (proven live on prod 2026-06-26). So
  # the drift sidecar gets a generous, env-tunable read_timeout (default 60s). This is a Phase-4
  # headroom fix; the O(n) projection cost is the Phase-5 trigger to move to a write-time/indexed hash.
  DRIFT_READ_TIMEOUT = Integer(ENV["ATOMSPACE_DRIFT_READ_TIMEOUT"] || "60")

  def initialize(sidecar: nil, clock: -> { Time.now.utc }, actor: "system",
                 sample_limit: 50, card_source: nil, card_lookup: nil, a_start_provider: nil,
                 drain_lag_fn: nil, max_action_fn: nil, reconcile_run_model: nil, pg_hash_fn: nil)
    @sidecar = sidecar || SidecarClient.new(read_timeout: DRIFT_READ_TIMEOUT)
    @clock = clock
    @actor = actor
    @sample_limit = sample_limit
    @card_source = card_source || -> { Card.where(trash: [true, false]) }
    @card_lookup = card_lookup || ->(id) { Card.where(id: id).first }
    @a_start_provider = a_start_provider || -> { MirrorState.first&.bootstrap_a_start.to_i }
    @drain_lag_fn = drain_lag_fn || ->(a) { DriftMonitor.drain_lag(a)[:lag_actions] }
    @max_action_fn = max_action_fn ||
                     -> { ActiveRecord::Base.connection.select_value("SELECT COALESCE(MAX(id), 0) FROM card_actions").to_i }
    @reconcile_run_model = reconcile_run_model || (defined?(MirrorReconcileRun) ? MirrorReconcileRun : nil)
    @pg_hash_fn = pg_hash_fn || ->(card) { CanonicalProjection.sha256(CardAtomEncoder.encode_card_snapshot(card)) }
  end

  # Run one sweep; record + return the mirror_reconcile_runs row. Report-only.
  def run!
    started = @clock.call
    a_start = @a_start_provider.call.to_i
    start_lag = @drain_lag_fn.call(a_start)
    start_max = @max_action_fn.call

    pg_index = build_pg_index
    space_index = @sidecar.projection_index               # {card_id(Integer) => sha256}
    diff = diff_indexes(pg_index, space_index)

    end_lag = @drain_lag_fn.call(a_start)
    end_max = @max_action_fn.call
    stable = start_lag.zero? && end_lag.zero? && start_max == end_max
    diff = reverify(diff, pg_index) unless stable

    record(diff, stable: stable, started: started,
           window: { start_action_id: start_max, end_action_id: end_max,
                     start_drain_lag: start_lag, end_drain_lag: end_lag })
  end

  # Postgres-side inventory: {card_id => canonical sha256} over every card the bootstrap would sweep.
  def build_pg_index
    index = {}
    @card_source.call.find_each { |card| index[card.id] = @pg_hash_fn.call(card) }
    index
  end

  def diff_indexes(pg_index, space_index)
    pg_ids = pg_index.keys.to_set
    space_ids = space_index.keys.to_set
    shared = pg_ids & space_ids
    Diff.new(
      pg_only: (pg_ids - space_ids).to_a.sort,
      space_only: (space_ids - pg_ids).to_a.sort,
      mismatch: shared.select { |id| pg_index[id] != space_index[id] }.sort
    )
  end

  # Per-card re-verification for a non-quiescent sweep. RE-FETCHES both sides for every flagged card
  # and REBUILDS the three buckets from current state -- NOT a mere filter: a card can change class
  # during the sweep (e.g. a pg_only card that drained mid-sweep but with a different hash must move to
  # mismatch, not be dropped) (Codex 2026-06-24). Transient states (now consistent, or gone from both)
  # fall out cleanly.
  def reverify(diff, _pg_index)
    ids = (diff.pg_only + diff.space_only + diff.mismatch).uniq
    pg_only = []
    space_only = []
    mismatch = []
    ids.each do |id|
      cp = @sidecar.card_projection(id)
      card = @card_lookup.call(id)
      in_space = cp["present"] ? true : false
      in_pg = !card.nil?
      if in_pg && !in_space
        pg_only << id
      elsif in_space && !in_pg
        space_only << id
      elsif in_pg && in_space
        mismatch << id if cp["sha256"] != @pg_hash_fn.call(card)
      end
      # both absent -> the card is gone from PG and Space; nothing to report.
    end
    Diff.new(pg_only: pg_only.sort, space_only: space_only.sort, mismatch: mismatch.sort)
  end

  private

  def record(diff, stable:, started:, window:)
    report = window.merge(
      stable: stable,
      pg_only_sample: diff.pg_only.first(@sample_limit),
      space_only_sample: diff.space_only.first(@sample_limit),
      mismatch_sample: diff.mismatch.first(@sample_limit)
    )
    @reconcile_run_model.create!(
      started_at: started, completed_at: @clock.call, actor: @actor,
      status: stable ? "completed" : "unstable", stable: stable,
      drift_pg_only: diff.pg_only.size, drift_space_only: diff.space_only.size,
      drift_mismatch: diff.mismatch.size, remediated: 0,
      report_path: JSON.generate(report)
    )
  end
end
