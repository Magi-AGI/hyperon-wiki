# frozen_string_literal: true

# Lane A / AtomSpace Mirror -- Slice 4 (Bootstrap, L4).
#
# Adds a lifecycle `status` to mirror_bootstrap_runs so a FAILED/ABORTED run does not block the next
# fresh re-run (Codex 2026-06-23). The single-run guard checks for a row with status='running'
# (instead of `completed_at IS NULL`, which a crashed run would leave set forever). The partial index
# makes that guard query cheap. Statuses: running | completed | failed | aborted.
class AddStatusToMirrorBootstrapRuns < ActiveRecord::Migration[7.0]
  def change
    add_column :mirror_bootstrap_runs, :status, :string

    add_index :mirror_bootstrap_runs, :status,
              where: "status = 'running'",
              name: "index_mirror_bootstrap_runs_running"
  end
end
