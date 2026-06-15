# frozen_string_literal: true

# Lane A / AtomSpace Mirror engine -- Slice 1 schema.
# Locked contract: Card 17120 Section 1 (Bootstrap) + Section 3 (Reconciliation), with the
# 2026-06-14 amendments OQ#9 (mirror_state singleton) and OQ#12 (mirror_outbox action_id CHECKs).
class CreateAtomspaceMirrorTables < ActiveRecord::Migration[7.0]
  def change
    # -- mirror_state: a single control row; singleton enforced at the DB layer ----------------
    create_table :mirror_state do |t|
      t.bigint   :last_drained_action_id        # diagnostic / lag cursor only (NOT a drain cursor)
      t.bigint   :bootstrap_a_start             # persisted bootstrap anchor (Rider C v2)
      t.boolean  :draining_enabled, null: false, default: false
      t.boolean  :singleton_guard,  null: false, default: true
      t.timestamps
    end
    add_index :mirror_state, :singleton_guard, unique: true
    # UNIQUE on a boolean alone is NOT a singleton (Postgres allows one true + one false row);
    # the CHECK forces guard = TRUE so the table can hold at most one row.
    add_check_constraint :mirror_state, "singleton_guard = true", name: "mirror_state_singleton_true"

    # -- mirror_outbox: the durable mirror event queue -----------------------------------------
    create_table :mirror_outbox do |t|
      t.string   :event_id,                  null: false                       # primary idempotency key
      t.string   :event_kind,                null: false, default: "decko_action" # decko_action | reconcile
      t.bigint   :action_id,                 null: true                        # NULL for reconcile events
      t.bigint   :card_id,                   null: false
      t.string   :status,                    null: false, default: "queued"
      # queued | delivered | failed | superseded_by_bootstrap | superseded_by_later
      # | awaiting_reconcile | superseded_by_reconcile
      t.string   :source_reconcile_event_id, null: true                        # awaiting_reconcile -> reconcile event
      t.integer  :attempts,                  null: false, default: 0
      t.datetime :last_attempt_at
      t.text     :error
      t.json     :payload
      t.timestamps
    end
    add_index :mirror_outbox, :event_id, unique: true
    add_index :mirror_outbox, :action_id, where: "action_id IS NOT NULL"
    add_index :mirror_outbox, :action_id, unique: true,
              where: "event_kind = 'decko_action'", name: "mirror_outbox_decko_action_unique"
    add_index :mirror_outbox, %i[card_id action_id]
    add_index :mirror_outbox, %i[event_kind status action_id]
    add_index :mirror_outbox, :source_reconcile_event_id, where: "source_reconcile_event_id IS NOT NULL"
    # OQ#12 structural integrity. Implication form constrains ONLY the two Phase 4 event kinds;
    # a future event_kind is unconstrained by both.
    add_check_constraint :mirror_outbox, "event_kind <> 'decko_action' OR action_id IS NOT NULL",
                         name: "mirror_outbox_decko_action_id_present"
    add_check_constraint :mirror_outbox, "event_kind <> 'reconcile' OR action_id IS NULL",
                         name: "mirror_outbox_reconcile_action_id_null"

    # -- mirror_bootstrap_runs: one row per backfill sweep -------------------------------------
    create_table :mirror_bootstrap_runs do |t|
      t.bigint   :a_start, null: false
      t.bigint   :last_card_id_swept
      t.datetime :started_at
      t.datetime :completed_at
      t.string   :actor
      t.integer  :cards_swept, default: 0
    end

    # -- mirror_reconcile_runs: one row per drift-reconciliation run ---------------------------
    create_table :mirror_reconcile_runs do |t|
      t.datetime :started_at
      t.datetime :completed_at
      t.string   :actor                                   # operator id
      t.string   :status                                  # running | completed | aborted
      t.integer  :drift_pg_only,    default: 0
      t.integer  :drift_space_only, default: 0
      t.integer  :drift_mismatch,   default: 0
      t.integer  :remediated,       default: 0
      t.text     :report_path
    end

    # Seed the single mirror_state row (the singleton_guard UNIQUE + CHECK keep it the only row).
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          INSERT INTO mirror_state
            (last_drained_action_id, draining_enabled, singleton_guard, created_at, updated_at)
          VALUES (NULL, false, true, NOW(), NOW())
        SQL
      end
    end
  end
end
