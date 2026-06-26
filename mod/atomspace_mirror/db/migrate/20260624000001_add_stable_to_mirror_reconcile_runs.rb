# frozen_string_literal: true

# L5 / Mechanism 3 (Slice 5b): the drift sweep records a consistency-window `stable` flag on each
# mirror_reconcile_runs row -- false when card writes/drain-lag occurred during the sweep (counts are
# then post-re-verification but the run is marked non-quiescent). The action-id window + drift sample
# ids ride along in the existing `report_path` text column as JSON.
class AddStableToMirrorReconcileRuns < ActiveRecord::Migration[7.0]
  def change
    add_column :mirror_reconcile_runs, :stable, :boolean
  end
end
