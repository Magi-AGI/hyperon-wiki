# frozen_string_literal: true

# One row per bootstrap backfill sweep (Card 17120 Section 1). Owns the run's a_start anchor and
# is resumable from last_card_id_swept on failure.
class MirrorBootstrapRun < ActiveRecord::Base
  self.table_name = "mirror_bootstrap_runs"
end
