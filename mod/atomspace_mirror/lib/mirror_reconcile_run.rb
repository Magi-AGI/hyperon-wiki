# frozen_string_literal: true

# One row per drift-reconciliation run (Card 17120 Section 3). Tracks per-class drift counts and
# the run lifecycle (running | completed | aborted).
class MirrorReconcileRun < ActiveRecord::Base
  self.table_name = "mirror_reconcile_runs"
end
