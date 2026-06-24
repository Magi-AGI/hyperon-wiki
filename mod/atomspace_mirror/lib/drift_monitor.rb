# frozen_string_literal: true

require_relative "mirror"

# Level 5 -- Drift detection (Section 2 v4). PHASE 4 = REPORT-ONLY diagnostics; this module NEVER
# mutates a model and NEVER remediates (remediation is L6). Each mechanism is a PURE SQL builder + a
# thin runner that returns a structured Hash (JSON-ready for L10) carrying the metric, the threshold
# decision (:ok | :alert), and the inputs that produced it.
#
# Slice 5a covers the three stream-based, pure-Postgres monitors:
#   1a hook tail-lag   -- most-recent committed card_action vs most-recent outbox row
#   1b coverage-gap    -- interior card_actions absent from the outbox (sparse hook drops)
#   2  drain watermark -- contiguous terminal-status prefix vs outbox head (diagnostic; reuses Mirror)
# Mechanism 3 (full-projection SHA256, PG + sidecar extraction) is Slice 5b.
#
# a_start is mirror_state.bootstrap_a_start (Integer, .to_i coerced) -- the bootstrap pre-A_start tail
# is irrelevant to every query. The status enum lists are frozen constants (Mirror::*) -> no injection
# surface; a_start is our own integer, .to_i before interpolation.
#
# Every query takes an explicit `conn:` (defaults to ActiveRecord::Base.connection) so the SQL
# builders + threshold logic are unit-testable with a fake connection, no Decko/AR boot.
module DriftMonitor
  module_function

  # --- configurable thresholds (Section 2; defaults are the locked Phase-4 values) ---
  HOOK_LAG_ACTIONS  = 10    # 1a: alert if tail-lag > 10 actions ...
  HOOK_LAG_SECONDS  = 60    # 1a: ... OR oldest un-mirrored action older than 60s
  COVERAGE_GAP_RUNS = 2     # 1b: alert only if gap_count > 0 for N consecutive runs (transient is OK)
  DRAIN_LAG_ACTIONS = 50    # 2 : alert if drain lag > 50 actions ...
  DRAIN_LAG_SECONDS = 300   # 2 : ... OR oldest unapplied row older than 300s
  GAP_SAMPLE_LIMIT  = 10    # 1b: gap_action_ids[..10] for the report

  # ============================ Mechanism 1a: hook generation tail-lag ============================
  # Detects: tail-stalled hook, detached hook, encoder exceptions swallowing the most recent rows.
  def hook_tail_lag(a_start, conn: ActiveRecord::Base.connection,
                    actions_threshold: HOOK_LAG_ACTIONS, seconds_threshold: HOOK_LAG_SECONDS)
    a = a_start.to_i
    lag_actions = conn.select_value(hook_tail_lag_actions_sql(a)).to_i
    lag_seconds = conn.select_value(hook_tail_lag_seconds_sql(a)).to_f
    {
      mechanism: "hook_tail_lag",
      lag_actions: lag_actions,
      lag_seconds: lag_seconds.round(3),
      status: alert?(lag_actions > actions_threshold || lag_seconds > seconds_threshold),
      thresholds: { actions: actions_threshold, seconds: seconds_threshold },
      a_start: a
    }
  end

  # VERBATIM Section 2 / Card 17120 (action-count). Both subqueries scope to action_id > a_start and
  # COALESCE to a_start (a fresh post-bootstrap mirror with no forward events shows 0 lag, never a
  # NULL-arithmetic crash). event_kind = 'decko_action' scopes to the linear action stream; reconcile
  # rows are out-of-band and excluded. Both operands are in action-id space; subtraction is defined.
  def hook_tail_lag_actions_sql(a_start)
    a = a_start.to_i
    <<~SQL
      SELECT
        COALESCE(
          (SELECT MAX(id) FROM card_actions
            WHERE id > #{a} AND draft IS NOT TRUE),
          #{a}
        )
        -
        COALESCE(
          (SELECT MAX(action_id) FROM mirror_outbox
            WHERE action_id > #{a}
              AND event_kind = 'decko_action'),
          #{a}
        )
    SQL
  end

  # Seconds dimension for the Section 2 "> 60s" threshold. The count SQL above is the verbatim locked
  # metric; this time-lag query is the L5 *implementation* of the seconds metric (Section 2 specifies
  # the threshold but not the SQL). TAIL-ONLY by design (Codex 2026-06-24): the age of the oldest
  # committed, non-draft card_action that lies STRICTLY ABOVE the outbox tail head -- actions with
  # id > MAX(mirrored action_id). It must NOT count interior gaps (action 104 missing while 105 is
  # mirrored): that is 1b's job, and 1b has the consecutive-run debounce a transient interior gap is
  # supposed to get. Measuring interior gaps here would alert 1a after 60s and bypass that debounce,
  # collapsing the deliberate 1a/1b split. 0 when the tail is caught up (then lag_actions is also 0).
  # NOTE (dev-gated): card_actions -> card_acts join column is `card_act_id` in card-1.110.0; verify
  # in the dev validation run (the SQL builders are pure/unit-tested; live execution is dev-gated).
  def hook_tail_lag_seconds_sql(a_start)
    a = a_start.to_i
    <<~SQL
      SELECT COALESCE(EXTRACT(EPOCH FROM (now() - MIN(act.acted_at))), 0)
        FROM card_actions ca
        JOIN card_acts act ON act.id = ca.card_act_id
       WHERE ca.draft IS NOT TRUE
         AND ca.id > GREATEST(
           #{a},
           COALESCE(
             (SELECT MAX(action_id) FROM mirror_outbox
               WHERE event_kind = 'decko_action' AND action_id > #{a}),
             #{a})
         )
    SQL
  end

  # ================================ Mechanism 1b: coverage-gap ================================
  # 1a misses sparse interior gaps (action 104 missing while 105 is already in the outbox). 1b counts
  # them explicitly. `prior_nonzero_runs` carries the consecutive-nonzero streak from the caller
  # (Runner) so a single transient gap does NOT alert -- only `consecutive_runs` runs in a row do.
  def coverage_gap(a_start, conn: ActiveRecord::Base.connection, sample_limit: GAP_SAMPLE_LIMIT,
                   consecutive_runs: COVERAGE_GAP_RUNS, prior_nonzero_runs: 0)
    a = a_start.to_i
    gap_count = conn.select_value(coverage_gap_count_sql(a)).to_i
    gap_action_ids = gap_count.positive? ? conn.select_values(coverage_gap_sample_sql(a, sample_limit)).map(&:to_i) : []
    streak = gap_count.positive? ? prior_nonzero_runs.to_i + 1 : 0
    {
      mechanism: "coverage_gap",
      gap_count: gap_count,
      gap_action_ids: gap_action_ids,
      consecutive_nonzero_runs: streak,
      status: alert?(streak >= consecutive_runs),
      thresholds: { consecutive_runs: consecutive_runs },
      a_start: a
    }
  end

  # VERBATIM Section 2 / Card 17120: card_actions with no matching decko_action outbox row.
  def coverage_gap_count_sql(a_start)
    a = a_start.to_i
    <<~SQL
      SELECT COUNT(*) AS coverage_gap_count
        FROM card_actions ca
        LEFT JOIN mirror_outbox mo
          ON mo.event_kind = 'decko_action'
         AND mo.action_id  = ca.id
       WHERE ca.id > #{a}
         AND ca.draft IS NOT TRUE
         AND mo.action_id IS NULL
    SQL
  end

  # The lowest `sample_limit` gap action_ids, for the L6 hook-lag remediator to target. limit is
  # .to_i'd (our own integer, never user input).
  def coverage_gap_sample_sql(a_start, sample_limit)
    a = a_start.to_i
    n = sample_limit.to_i
    <<~SQL
      SELECT ca.id
        FROM card_actions ca
        LEFT JOIN mirror_outbox mo
          ON mo.event_kind = 'decko_action'
         AND mo.action_id  = ca.id
       WHERE ca.id > #{a}
         AND ca.draft IS NOT TRUE
         AND mo.action_id IS NULL
       ORDER BY ca.id ASC
       LIMIT #{n}
    SQL
  end

  # ========================= Mechanism 2: drain lag / contiguous watermark =========================
  # The watermark itself is the locked Section 2 SQL (Mirror.contiguous_watermark_sql -- single source
  # of truth, also the value the drain writes to mirror_state.last_drained_action_id). DIAGNOSTIC ONLY
  # (Rider C v2): never a drain cursor, never a read-your-writes primitive. drain_lag = outbox head -
  # watermark; seconds = age of the oldest unapplied (hole) row.
  def drain_lag(a_start, conn: ActiveRecord::Base.connection,
                actions_threshold: DRAIN_LAG_ACTIONS, seconds_threshold: DRAIN_LAG_SECONDS)
    a = a_start.to_i
    watermark = conn.select_value(Mirror.contiguous_watermark_sql(a)).to_i
    outbox_head = conn.select_value(max_decko_action_sql(a)).to_i
    lag_actions = outbox_head - watermark
    lag_seconds = conn.select_value(drain_lag_seconds_sql(a)).to_f
    {
      mechanism: "drain_lag",
      watermark: watermark,
      outbox_head: outbox_head,
      lag_actions: lag_actions,
      lag_seconds: lag_seconds.round(3),
      status: alert?(lag_actions > actions_threshold || lag_seconds > seconds_threshold),
      thresholds: { actions: actions_threshold, seconds: seconds_threshold },
      a_start: a
    }
  end

  # Outbox head = MAX decko_action action_id (> a_start), COALESCE to a_start (no rows -> 0 lag).
  def max_decko_action_sql(a_start)
    a = a_start.to_i
    <<~SQL
      SELECT COALESCE(
        (SELECT MAX(action_id) FROM mirror_outbox
          WHERE event_kind = 'decko_action' AND action_id > #{a}),
        #{a}
      )
    SQL
  end

  # Age of the oldest unapplied (non-terminal-advance) decko_action row above a_start: how long the
  # drain has been behind. NOT-IN the four terminal-advance statuses = a "hole" (queued / failed /
  # awaiting_reconcile). 0 when fully drained. Uses mirror_outbox.created_at (our table).
  def drain_lag_seconds_sql(a_start)
    a = a_start.to_i
    advance = Mirror::TERMINAL_ADVANCE_STATUSES.map { |s| "'#{s}'" }.join(", ")
    <<~SQL
      SELECT COALESCE(EXTRACT(EPOCH FROM (now() - MIN(created_at))), 0)
        FROM mirror_outbox
       WHERE event_kind = 'decko_action'
         AND action_id > #{a}
         AND status NOT IN (#{advance})
    SQL
  end

  # --- helpers ---

  def alert?(condition)
    condition ? "alert" : "ok"
  end
end
