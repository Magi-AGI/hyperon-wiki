# frozen_string_literal: true

require_relative "card_atom_encoder"
require_relative "mirror_outbox_writer"

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

  # ================================ APPLY LAYER (Part 2a, impure) ================================
  # The three operator entry points realize Card 17178 Task 1's `Reconciler.run!` plus the hook-lag
  # and drain-lag rakes. Each builds a Runner with injected collaborators (real defaults) and
  # delegates: the Runner resolves the Section 3 SQL predicates, calls the pure planner above, then
  # turns the plan into IDEMPOTENT mirror_outbox writes + a mirror_reconcile_runs audit row. The
  # transaction / coalescing / relink logic is unit-tested with stub models; the live SQL resolvers
  # and the rakes are dev-gated.
  def run!(detection_run_id, force: false, **deps)
    Runner.new(**deps).run_sweep!(detection_run_id, force: force)
  end

  def remediate_hook_lag!(**deps)
    Runner.new(**deps).remediate_hook_lag!
  end

  def requeue_failed!(**deps)
    Runner.new(**deps).requeue_failed!
  end

  # Drift signals fed to plan_sweep (duck-types the L5 DriftReconciler::Diff: arrays of card ids).
  DriftSignals = Struct.new(:pg_only, :space_only, :mismatch, keyword_init: true)

  # The stateful executor. Collaborators are injected (nil -> a real default resolved lazily, so the
  # standalone planner specs that only `require` this file never touch a model constant). Mirrors the
  # DriftReconciler injection style.
  class Runner
    def initialize(outbox: nil, reconcile_run_model: nil, card_lookup: nil, action_lookup: nil,
                   sidecar: nil, clock: nil, actor: "operator", alerter: nil, encoder: nil,
                   pre_state_fn: nil, gap_source: nil, later_card_action_fn: nil,
                   later_delivered_decko_fn: nil, in_flight_fn: nil, failed_rows_source: nil,
                   sample_limit: 50)
      @outbox = outbox || (defined?(MirrorOutbox) ? MirrorOutbox : nil)
      @reconcile_run_model = reconcile_run_model || (defined?(MirrorReconcileRun) ? MirrorReconcileRun : nil)
      @card_lookup = card_lookup || ->(id) { Card.where(id: id).first }
      @action_lookup = action_lookup || ->(id) { Card::Action.find_by(id: id) }
      @sidecar = sidecar || (defined?(SidecarClient) ? SidecarClient.new : nil)
      @clock = clock || -> { Time.now.utc }
      @actor = actor
      @alerter = alerter
      @encoder = encoder || CardAtomEncoder
      @pre_state_fn = pre_state_fn || ->(action) { MirrorOutboxWriter.derive_pre_state(action) }
      @sample_limit = sample_limit
      # Live SQL predicate resolvers (dev-gated; defaults reference DriftMonitor-style queries).
      @gap_source = gap_source || method(:default_gap_source)
      @later_card_action_fn = later_card_action_fn || method(:default_later_card_action?)
      @later_delivered_decko_fn = later_delivered_decko_fn || method(:default_later_delivered_decko?)
      @in_flight_fn = in_flight_fn || method(:default_in_flight?)
      @failed_rows_source = failed_rows_source || method(:default_failed_rows)
    end

    # --- entry: sweep remediation (consumes an L5 Mechanism 3 detection run) ---
    def run_sweep!(detection_run_id, force: false)
      detection = @reconcile_run_model.find(detection_run_id)
      unless force || detection.stable == true
        return record_aborted(detection_run_id,
                              "L5 detection run #{detection_run_id} is not stable (non-quiescent window); " \
                              "re-run the sweep when quiescent or pass force: true")
      end

      run = start_run("sweep", detection_run_id: detection_run_id)
      diff = signals_from(detection)
      warn_if_sample_truncated(detection, diff)
      actions = Reconciler.plan_sweep(diff: diff, run_id: run.id, in_flight: @in_flight_fn)
      audit = execute(actions)
      finish_run(run, actions, audit, detection_run_id: detection_run_id)
    end

    # --- entry: hook-lag remediation (Mechanism 1b coverage-gap) ---
    def remediate_hook_lag!
      run = start_run("hook_lag")
      gaps = enriched_gaps
      actions = Reconciler.plan_hook_lag(gaps: gaps, run_id: run.id)
      audit = execute(actions)
      finish_run(run, actions, audit)
    end

    # --- entry: drain-lag reset (failed rows) ---
    def requeue_failed!
      run = start_run("requeue")
      superseded = ->(row) { @outbox.superseded_by_later_or_reconcile?(row) }
      actions = Reconciler.plan_requeue(rows: @failed_rows_source.call, superseded: superseded)
      audit = execute(actions)
      finish_run(run, actions, audit)
    end

    # ============================ action execution ============================
    # Returns the collected quarantine audit (atom JSON), accumulated across Quarantine actions.
    def execute(actions)
      audit = []
      # AwaitingWithReconcile coalesces per (card_id, run_id): one reconcile event, many awaiting rows.
      awaiting, rest = actions.partition { |a| a.is_a?(Reconciler::AwaitingWithReconcile) }
      awaiting.group_by { |a| [a.card_id, a.run_id] }.each do |(card_id, run_id), group|
        exec_awaiting_group(card_id, run_id, group.map(&:action_id))
      end
      rest.each { |action| exec_one(action, audit) }
      audit
    end

    def exec_one(action, audit)
      case action
      when Reconciler::ReplayQueued      then exec_replay_queued(action.card_id, action.action_id)
      when Reconciler::SupersededByLater then insert_superseded_by_later(action.card_id, action.action_id)
      when Reconciler::ReconcileCreate   then exec_reconcile_create(action.card_id, action.run_id, action.reason)
      when Reconciler::Quarantine        then audit.concat(exec_quarantine(action.card_id))
      when Reconciler::SkipInFlight      then alert(:mirror_reconcile_skip, action.card_id, action.reason)
      when Reconciler::RequeueReset      then update_row(action.row_id, status: "queued", attempts: 0, error: nil)
      when Reconciler::RequeueSupersede  then update_row(action.row_id, status: "superseded_by_later")
      when Reconciler::RequeueHold       then alert(:mirror_reconcile_hold, action.row_id, action.reason)
      end
    end

    # Tail replay: reconstruct the canonical forward payload from the historical action (Codex: never
    # snapshot-only -- the drain validator requires a matching DeckoProvenance). auth is nulled (the
    # request-time Card::Auth.serialize snapshot is not persisted on a historical action; actor_id is
    # still real). A corrupt-encode raises EncodingError -> a terminal 'failed' row so check_event_ready
    # returns event_failed, not a staleness timeout (mirrors MirrorOutboxWriter).
    def exec_replay_queued(card_id, action_id)
      action = @action_lookup.call(action_id)
      unless action
        return alert(:mirror_reconcile_action_pruned, card_id,
                     "card_actions row #{action_id} not found; cannot reconstruct replay payload")
      end
      begin
        atoms = @encoder.encode(action, pre_state: @pre_state_fn.call(action),
                                        auth: { current_id: nil, as_id: nil }, request_context: {})
        insert_decko_action(card_id, action_id, status: "queued", payload: { "atoms" => atoms })
      rescue CardAtomEncoder::EncodingError => e
        insert_decko_action(card_id, action_id, status: "failed", payload: nil, error: e.message)
      end
    end

    # Case (b): fresh current-state reconcile + linked awaiting rows, single transaction, reconcile
    # FIRST (Invariant 13). Orphan-prevention (Codex): precompute the NEW awaitings + the relink
    # orphans BEFORE the txn; if BOTH are empty, skip entirely (never insert a dangling reconcile).
    def exec_awaiting_group(card_id, run_id, action_ids)
      reconcile_event_id = reconcile_event_id(card_id, run_id)
      new_ids = action_ids - existing_decko_action_ids(action_ids)
      orphans = orphan_failed_ids(card_id)
      return if new_ids.empty? && orphans.empty?

      @outbox.transaction do
        insert_reconcile_event(card_id, reconcile_event_id)                      # idempotent, FIRST
        new_ids.each do |n|
          insert_decko_action(card_id, n, status: "awaiting_reconcile", payload: nil,
                                          source_reconcile_event_id: reconcile_event_id)
        end
        relink_orphans(card_id, orphans, reconcile_event_id)
      end
    end

    # Sweep pg_only / mismatch: fresh current-state reconcile + relink any same-card orphans. No new
    # awaiting row (a full-card overwrite is not tied to a specific action id).
    def exec_reconcile_create(card_id, run_id, _reason)
      reconcile_event_id = reconcile_event_id(card_id, run_id)
      orphans = orphan_failed_ids(card_id)
      @outbox.transaction do
        insert_reconcile_event(card_id, reconcile_event_id)
        relink_orphans(card_id, orphans, reconcile_event_id)
      end
    end

    def exec_quarantine(card_id)
      Array(@sidecar.quarantine_card_scoped_atoms(card_id))
    rescue StandardError => e
      # B3 not yet live (fail-closed) or a transient admin error: record + alert, do not crash the run.
      alert(:mirror_reconcile_quarantine_unavailable, card_id, e.message)
      []
    end

    # ============================ idempotent outbox writers ============================
    def insert_reconcile_event(card_id, event_id)
      card = @card_lookup.call(card_id)
      return alert(:mirror_reconcile_card_missing, card_id, "card #{card_id} absent; cannot snapshot") unless card

      payload = { "atoms" => @encoder.encode_reconcile_snapshot(card, event_id: event_id,
                                                                       actor_id: nil, acted_at: @clock.call) }
      create_row(event_kind: "reconcile", event_id: event_id, action_id: nil, card_id: card_id,
                 status: "queued", payload: payload)
    end

    def insert_decko_action(card_id, action_id, status:, payload:, source_reconcile_event_id: nil, error: nil)
      create_row(event_kind: "decko_action", event_id: "decko:action:#{action_id}", action_id: action_id,
                 card_id: card_id, status: status, payload: payload,
                 source_reconcile_event_id: source_reconcile_event_id, error: error)
    end

    def insert_superseded_by_later(card_id, action_id)
      insert_decko_action(card_id, action_id, status: "superseded_by_later", payload: nil)
    end

    # ON CONFLICT DO NOTHING: a duplicate event_id / (decko_action, action_id) from a re-run, a retry,
    # or coalescing is an idempotent no-op (the unique indexes enforce it).
    def create_row(**attrs)
      @outbox.create!(**attrs.compact)
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def update_row(row_id, **attrs)
      @outbox.where(id: row_id).update_all(attrs)
    end

    # Relink PROVEN reconcile-orphans (Codex Fix 1): same-card, nil-payload, FAILED decko_action rows
    # whose source_reconcile_event_id points to a same-card reconcile that is itself FAILED. Clears the
    # stale failure metadata (error/attempts) so the relinked awaiting row reads clean in reports.
    def relink_orphans(card_id, orphan_ids, reconcile_event_id)
      return if orphan_ids.empty?

      @outbox.where(id: orphan_ids).update_all(
        status: "awaiting_reconcile", source_reconcile_event_id: reconcile_event_id, error: nil, attempts: 0
      )
    end

    def orphan_failed_ids(card_id)
      failed_reconciles = @outbox.where(event_kind: "reconcile", card_id: card_id, status: "failed").select(:event_id)
      @outbox.where(event_kind: "decko_action", status: "failed", card_id: card_id, payload: nil)
             .where(source_reconcile_event_id: failed_reconciles)
             .pluck(:id)
    end

    def existing_decko_action_ids(action_ids)
      return [] if action_ids.empty?

      @outbox.where(event_kind: "decko_action", action_id: action_ids).pluck(:action_id)
    end

    # ============================ run bookkeeping ============================
    def start_run(kind, detection_run_id: nil)
      now = @clock.call
      @reconcile_run_model.create!(started_at: now, actor: @actor, status: "running", stable: false,
                                   report_path: JSON.generate(kind: kind, detection_run_id: detection_run_id))
    end

    def finish_run(run, actions, audit, detection_run_id: nil)
      remediated = actions.count { |a| remediating?(a) }
      run.update!(completed_at: @clock.call, status: "completed", remediated: remediated,
                  report_path: JSON.generate(detection_run_id: detection_run_id,
                                             actions: summarize(actions),
                                             quarantine_audit_sample: audit.first(@sample_limit)))
      run
    end

    def record_aborted(detection_run_id, reason)
      now = @clock.call
      @reconcile_run_model.create!(started_at: now, completed_at: now, actor: @actor, status: "aborted",
                                   stable: false, remediated: 0,
                                   report_path: JSON.generate(detection_run_id: detection_run_id, aborted: reason))
    end

    # A SkipInFlight / RequeueHold is a decision NOT to write -- it is not a remediation.
    def remediating?(action)
      !action.is_a?(Reconciler::SkipInFlight) && !action.is_a?(Reconciler::RequeueHold)
    end

    def summarize(actions)
      actions.group_by { |a| a.class.name.split("::").last }.transform_values(&:size)
    end

    def signals_from(detection)
      report = JSON.parse(detection.report_path.to_s) rescue {}
      DriftSignals.new(pg_only: Array(report["pg_only_sample"]), space_only: Array(report["space_only_sample"]),
                       mismatch: Array(report["mismatch_sample"]))
    end

    # The L5 report stores only the first sample_limit ids; remediation is therefore sample-bounded.
    # When the recorded drift count exceeds the sample, log so the operator runs another sweep+remediate
    # cycle (the repair is idempotent, so iterating converges).
    def warn_if_sample_truncated(detection, diff)
      {
        "pg_only" => [detection.drift_pg_only.to_i, diff.pg_only.size],
        "space_only" => [detection.drift_space_only.to_i, diff.space_only.size],
        "mismatch" => [detection.drift_mismatch.to_i, diff.mismatch.size]
      }.each do |cls, (count, sampled)|
        next unless count > sampled

        alert(:mirror_reconcile_sample_truncated, cls,
              "#{cls} drift=#{count} but only #{sampled} sampled in the L5 report; re-run sweep+remediate to converge")
      end
    end

    def enriched_gaps
      @gap_source.call.map do |row|
        c = row.fetch(:card_id)
        n = row.fetch(:action_id)
        { card_id: c, action_id: n,
          later_card_action: @later_card_action_fn.call(c, n),
          later_delivered_decko: @later_delivered_decko_fn.call(c, n) }
      end
    end

    def reconcile_event_id(card_id, run_id)
      "reconcile:card:#{card_id}:#{run_id}"
    end

    def alert(signal, context, message)
      return @alerter.call(signal, context, message) if @alerter

      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn("[atomspace_mirror] #{signal} #{context}: #{message}")
      end
      nil
    end

    # ============================ live SQL predicate defaults (dev-gated) ============================
    def a_start
      (defined?(MirrorState) ? MirrorState.first&.bootstrap_a_start : nil).to_i
    end

    def conn
      ActiveRecord::Base.connection
    end

    # Mechanism 1b coverage-gap rows WITH card_id (Section 3 needs card_id, not left_id). Lowest gaps
    # first, sample-bounded. Mirrors DriftMonitor.coverage_gap_sample_sql + the ca.card_id column.
    def default_gap_source
      a = a_start
      n = @sample_limit.to_i
      sql = <<~SQL
        SELECT ca.card_id, ca.id AS action_id
          FROM card_actions ca
          LEFT JOIN mirror_outbox mo
            ON mo.event_kind = 'decko_action' AND mo.action_id = ca.id
         WHERE ca.id > #{a} AND ca.draft IS NOT TRUE AND mo.action_id IS NULL
         ORDER BY ca.id ASC
         LIMIT #{n}
      SQL
      conn.exec_query(sql).map { |r| { card_id: r["card_id"].to_i, action_id: r["action_id"].to_i } }
    end

    def default_later_card_action?(card_id, action_id)
      conn.select_value(<<~SQL).to_i.positive?
        SELECT COUNT(*) FROM card_actions
         WHERE card_id = #{card_id.to_i} AND id > #{action_id.to_i} AND draft IS NOT TRUE
      SQL
    end

    def default_later_delivered_decko?(card_id, action_id)
      conn.select_value(<<~SQL).to_i.positive?
        SELECT COUNT(*) FROM mirror_outbox
         WHERE event_kind = 'decko_action' AND status = 'delivered'
           AND card_id = #{card_id.to_i} AND action_id > #{action_id.to_i}
      SQL
    end

    def default_in_flight?(card_id)
      conn.select_value(<<~SQL).to_i.positive?
        SELECT COUNT(*) FROM mirror_outbox
         WHERE card_id = #{card_id.to_i} AND event_kind = 'decko_action'
           AND status IN ('queued', 'awaiting_reconcile')
      SQL
    end

    def default_failed_rows
      @outbox.where(status: "failed").to_a
    end
  end
end
