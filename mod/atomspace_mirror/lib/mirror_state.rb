# frozen_string_literal: true

# Singleton control row for the AtomSpace Mirror (Card 17120 Section 1).
#
# Exactly one row exists, enforced at the DB layer (singleton_guard UNIQUE + CHECK). Always read
# via .instance / .first / .lock.first -- never create additional rows.
class MirrorState < ActiveRecord::Base
  self.table_name = "mirror_state" # table is singular; Rails would otherwise expect "mirror_states"

  # The single control row.
  def self.instance
    first
  end
end
