# frozen_string_literal: true

# The durable mirror event queue (Card 17120 Section 1). Each row is a Decko action
# (event_kind = "decko_action") or a synthetic reconciliation event (event_kind = "reconcile")
# awaiting -- or having completed -- application to the Hyperon Space.
class MirrorOutbox < ActiveRecord::Base
  self.table_name = "mirror_outbox" # table is singular; Rails would otherwise expect "mirror_outboxes"

  # A row is "redrivable" only if it still carries a payload. The L6 drain-lag reset (Reconciler
  # plan_requeue / requeue_failed!) consults this: a nil-payload failed row (a reconcile-orphan or a
  # corrupt-encode terminal) must NOT be reset to queued -- it would fail validate_payload! instantly.
  def payload_present?
    !payload.nil?
  end

  # Shared supersession predicate (Card 17120 Section 10). Returns true when this row's payload
  # should NOT be applied because a later same-card delivered decko_action OR a later-inserted
  # delivered reconcile already reflects current/later state for the card.
  #
  # Used at three sites: the §10 drain apply guard, the §3 drain-lag reset rake, and the Level 7
  # check_event_ready superseded_by_later proof.
  #
  # Fail-safe to "not superseded" (false) for reconcile rows AND structurally-corrupt decko_action
  # rows with a nil action_id (action_id > NULL is SQL UNKNOWN, which would otherwise mis-evaluate
  # query (a)). NOTE (OQ#15): at the drain apply site "false" means "apply" -- the Slice 3 drain
  # worker must independently reject structurally-invalid rows; it must not treat this predicate's
  # false as "safe to apply".
  def self.superseded_by_later_or_reconcile?(row)
    return false unless row.event_kind == "decko_action" && row.action_id.present?

    # (a) Later same-card delivered decko_action (action_id ordering).
    later_decko_action_delivered =
      where(event_kind: "decko_action", card_id: row.card_id, status: "delivered")
        .where("action_id > ?", row.action_id)
        .exists?
    return true if later_decko_action_delivered

    # (b) Same-card delivered reconcile (structurally valid: action_id IS NULL) inserted after this row.
    where(event_kind: "reconcile", card_id: row.card_id, status: "delivered", action_id: nil)
      .where("id > ?", row.id)
      .exists?
  end
end
