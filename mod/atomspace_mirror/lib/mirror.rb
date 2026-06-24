# frozen_string_literal: true

# Level 8 drain shared constants + the Section 2 contiguous-watermark (diagnostic / lag cursor only).
module Mirror
  module_function

  # Postgres advisory-lock key for the singleton forward-drain worker. MUST be a signed 64-bit
  # integer: the original spec value 0xA705_BEEF_DEAD_F00D (= 12035235516659920909) exceeds max
  # signed int64 and makes pg_advisory_lock raise "bigint out of range", crash-looping the worker
  # (Gemini + Codex, verified 2026-06-22). 0x7705_BEEF_DEAD_F00D (= 8576471002839379981) fits and
  # keeps the recognizable suffix. This constant MUST match across the drain worker + any operator
  # task that takes the same lock.
  DRAIN_LOCK_ID = 0x7705_BEEF_DEAD_F00D

  # Distinct signed-int64 advisory-lock key for the singleton bootstrap sweep (separate from the
  # forward drain's lock, so a bootstrap and the drain don't block each other on the same key).
  BOOTSTRAP_LOCK_ID = 0x7705_BEEF_DEAD_B007

  # The four terminal-advance statuses: a row in any of these is "applied or safely skipped" and the
  # contiguous prefix may advance past it. Their complement (queued / failed / awaiting_reconcile) is
  # a "hole" that holds the watermark down. (Section 2 Mechanism 2 / Section 10.)
  TERMINAL_ADVANCE_STATUSES = %w[
    delivered superseded_by_bootstrap superseded_by_later superseded_by_reconcile
  ].freeze

  # Section 2 Mechanism 2: the highest decko_action action_id such that everything below it is in a
  # terminal-advance status (no holes). Diagnostic / lag metric, and the value the drain writes to
  # mirror_state.last_drained_action_id -- NOT a drain cursor (Rider C v2). Returns Integer >= a_start.
  def compute_contiguous_watermark(a_start)
    ActiveRecord::Base.connection.select_value(contiguous_watermark_sql(a_start)).to_i
  end

  # Pure SQL builder (no DB) -- unit-testable. a_start is our own integer (mirror_state.bootstrap_a_start
  # or 0), coerced with to_i; the status list is a frozen constant -> no injection surface.
  def contiguous_watermark_sql(a_start)
    a = a_start.to_i
    advance = TERMINAL_ADVANCE_STATUSES.map { |s| "'#{s}'" }.join(", ")
    <<~SQL
      SELECT GREATEST(
        COALESCE(
          (SELECT MIN(action_id) - 1 FROM mirror_outbox
             WHERE event_kind = 'decko_action'
               AND status NOT IN (#{advance})
               AND action_id > #{a}),
          (SELECT MAX(action_id) FROM mirror_outbox
             WHERE event_kind = 'decko_action'
               AND status IN (#{advance})
               AND action_id > #{a}),
          #{a}
        ),
        #{a}
      )
    SQL
  end
end
