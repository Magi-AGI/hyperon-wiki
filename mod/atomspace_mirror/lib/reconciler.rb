# frozen_string_literal: true

# Level 6 -- the PURE reconcile DECISION CORE (Card 17178 + Section 3 / card 17376). Given drift
# signals whose SQL predicates the caller has already resolved, it returns an ordered list of typed
# remediation ACTIONS. It decides WHAT to repair and HOW, but performs NO IO -- the Part 2 apply layer
# (rakes + DB writes + sidecar B3) executes the actions, the L8 DrainWorker delivers the resulting
# outbox rows, and the existing two-phase release advances the linked awaiting rows. Pure +
# referentially transparent, so the entire branch logic is unit-tested with plain Ruby hashes -- no
# Decko boot, DB, or sidecar.
#
# Remediation primitives map to drift classes exactly per Section 3:
#   hook-lag (Mechanism 1b gap (C,N)) -> Tail replay | Case (a) superseded_by_later | Case (b) fresh
#                                        reconcile + linked awaiting row
#   sweep pg_only / mismatch          -> fresh reconcile (skipped when a same-card forward row is in flight)
#   sweep space_only (orphan)         -> quarantine (Part 2 sidecar B3 admin)
#   drain-lag failed rows             -> helper-gated supersede / hold / reset
#
# Two design points the reviewers locked (2026-06-26):
#  * Hook-lag Case (b) ALWAYS synthesizes a FRESH current-state reconcile (never reuses a pre-existing
#    delivered reconcile as proof): a fresh snapshot covers the gap action by construction, and the
#    read-your-writes gate proves readiness through the explicit source_reconcile_event_id linkage,
#    not insertion order -- so there is no temporal false-readiness window.
#  * A nil-payload `failed` row (a reconcile-orphan whose linked reconcile terminal-failed) is NEVER
#    reset to queued (it would fail payload validation immediately). It HOLDs until either the
#    supersession helper proves it covered, or a fresh same-card reconcile relinks it (Part 2 apply).
module Reconciler
  module_function

  # --- typed remediation actions (value objects; the apply layer pattern-matches on class) ---
  ReplayQueued          = Struct.new(:card_id, :action_id, keyword_init: true)          # decko:action:N queued (reconstructed payload)
  SupersededByLater     = Struct.new(:card_id, :action_id, keyword_init: true)          # decko:action:N superseded_by_later (nil payload)
  AwaitingWithReconcile = Struct.new(:card_id, :action_id, :run_id, keyword_init: true) # Case (b): fresh reconcile + linked awaiting
  ReconcileCreate       = Struct.new(:card_id, :run_id, :reason, keyword_init: true)    # sweep pg_only/mismatch -> fresh reconcile
  Quarantine            = Struct.new(:card_id, keyword_init: true)                      # sweep space_only orphan
  SkipInFlight          = Struct.new(:card_id, :reason, keyword_init: true)             # same-card forward/repair row already in flight
  RequeueReset          = Struct.new(:row_id, keyword_init: true)                       # failed -> queued (redrivable payload)
  RequeueSupersede      = Struct.new(:row_id, keyword_init: true)                       # failed -> superseded_by_later (helper proved)
  RequeueHold           = Struct.new(:row_id, :reason, keyword_init: true)              # failed nil-payload, no proof -> leave + alert

  # ============================ hook-lag (Mechanism 1b coverage-gap) ============================
  # Each gap is a Hash the apply layer pre-resolves from card_actions + mirror_outbox (Section 3 SQL):
  #   { card_id:, action_id:, later_card_action:, later_delivered_decko: }
  #   later_card_action     = a later NON-DRAFT card_action for the card exists (card_actions.id > N)
  #   later_delivered_decko = a later DELIVERED decko_action for the card exists (action_id > N)
  # NOT in-flight gated: a coverage gap IS a missing queue row, so it must always be repaired to keep
  # the historical audit stream continuous (Section 3 / reviewer ruling).
  def plan_hook_lag(gaps:, run_id:)
    gaps.map do |gap|
      c = gap.fetch(:card_id)
      n = gap.fetch(:action_id)
      if !gap.fetch(:later_card_action)
        # Tail: N is the latest non-draft action for C; current cards-table state IS post-N -> replay.
        ReplayQueued.new(card_id: c, action_id: n)
      elsif gap.fetch(:later_delivered_decko)
        # Case (a): a later action for C is already delivered+applied -> Space reflects post-N.
        # Helper branch (a) is action_id-ordered, so this proves ready even for a freshly-inserted row.
        SupersededByLater.new(card_id: c, action_id: n)
      else
        # Case (b): later card_actions exist but none delivered -> hold N under a FRESH reconcile.
        AwaitingWithReconcile.new(card_id: c, action_id: n, run_id: run_id)
      end
    end
  end

  # ================================ sweep (Mechanism 3 full-projection) ================================
  # diff responds to #pg_only / #space_only / #mismatch (the L5 DriftReconciler::Diff, or any duck-type
  # exposing those arrays of card ids). in_flight: ->(card_id) { Bool } -- true when a same-card queued
  # OR awaiting_reconcile row exists (the forward / pending-repair path will resolve it; remediating
  # again would double-write). space_only orphans are NEVER skipped (an orphan has no forward path) and
  # never in-flight gated.
  def plan_sweep(diff:, run_id:, in_flight:)
    actions = []
    diff.pg_only.each    { |c| actions << sweep_reconcile_or_skip(c, run_id, "pg_only",  in_flight) }
    diff.mismatch.each   { |c| actions << sweep_reconcile_or_skip(c, run_id, "mismatch", in_flight) }
    diff.space_only.each { |c| actions << Quarantine.new(card_id: c) }
    actions
  end

  def sweep_reconcile_or_skip(card_id, run_id, reason, in_flight)
    if in_flight.call(card_id)
      SkipInFlight.new(card_id: card_id, reason: "#{reason}: same-card queued/awaiting row in flight")
    else
      ReconcileCreate.new(card_id: card_id, run_id: run_id, reason: reason)
    end
  end

  # ================================ drain-lag (failed rows) ================================
  # rows: each responds to #id + #payload_present? (or a Hash {id:, payload_present:}). superseded:
  # ->(row) { Bool } == MirrorOutbox.superseded_by_later_or_reconcile?. Resolution order (Codex Option B
  # amendment, locked 2026-06-26):
  #   (1) the helper proves a later delivered decko_action/reconcile already covers C -> supersede;
  #   (2) a nil-payload row cannot be re-driven (a reconcile-orphan, or a corrupt-encode terminal) ->
  #       HOLD + alert -- resetting to queued would fail validate_payload! instantly; a fresh same-card
  #       reconcile relinks reconcile-orphans (Part 2 apply), clearing the watermark hole;
  #   (3) otherwise the payload is intact -> reset to queued for redelivery.
  def plan_requeue(rows:, superseded:)
    rows.map do |row|
      if superseded.call(row)
        RequeueSupersede.new(row_id: row_id(row))
      elsif !payload_present?(row)
        RequeueHold.new(row_id: row_id(row), reason: "nil payload; not redrivable (awaiting fresh-reconcile relink)")
      else
        RequeueReset.new(row_id: row_id(row))
      end
    end
  end

  # --- duck-type helpers (accept a model row or a plain Hash, for standalone unit tests) ---
  def row_id(row)
    row.respond_to?(:id) ? row.id : row.fetch(:id)
  end

  def payload_present?(row)
    return row.payload_present? if row.respond_to?(:payload_present?)

    row.fetch(:payload_present)
  end
end
