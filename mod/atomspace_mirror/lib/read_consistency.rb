# frozen_string_literal: true

require_relative "mirror_outbox"

# Read-your-writes readiness (Level 7 / Card 17120 Section 4).
#
# check_event_ready inspects the per-event mirror_outbox row and returns a readiness symbol with NO
# watermark arithmetic. CANONICAL algorithm: Card 17120 Section 4 (card 17378), mirrored in the
# Level 7 card (17180) and this file -- keep all three in sync.
#
# It dispatches by event_kind FIRST so a corrupt event_kind / status / action_id combination always
# fails closed (:integrity_error) rather than surfacing a false :ready / :not_yet proof.
#
# Returns one of: :ready | :not_yet | :not_yet_inserted | :failed | :integrity_error
module ReadConsistency
  module_function

  def check_event_ready(event_id)
    row = MirrorOutbox.find_by(event_id: event_id)
    # Phase 4: mirror_outbox is NOT pruned (Open Q#7); a missing row means not-yet-inserted.
    return :not_yet_inserted unless row

    case row.event_kind
    when "decko_action"
      return :integrity_error if row.action_id.nil? # OQ#12 structural invariant

      case row.status
      when "delivered"               then :ready
      when "superseded_by_bootstrap" then :ready # structurally proven by Section 1
      when "superseded_by_reconcile"
        return :integrity_error if row.source_reconcile_event_id.blank?

        reconcile = MirrorOutbox.find_by(event_id: row.source_reconcile_event_id)
        return :integrity_error unless reconcile &&
                                       reconcile.event_kind == "reconcile" &&
                                       reconcile.card_id == row.card_id &&
                                       reconcile.action_id.nil? # OQ#12 invariant

        reconcile_ready(reconcile.status)
      when "superseded_by_later"
        MirrorOutbox.superseded_by_later_or_reconcile?(row) ? :ready : :not_yet
      when "queued", "awaiting_reconcile" then :not_yet
      when "failed"                       then :failed
      else                                :integrity_error # unknown decko_action status fails closed
      end
    when "reconcile"
      return :integrity_error unless row.action_id.nil? # OQ#12 structural invariant

      reconcile_ready(row.status)
    else
      :integrity_error # unknown event_kind fails closed
    end
  end

  # Reconcile rows are only ever queued | delivered | failed; anything else is corrupt. Shared by
  # the primary-reconcile branch and the linked-reconcile proof.
  def reconcile_ready(status)
    case status
    when "delivered" then :ready
    when "failed"    then :failed # OQ#10: fail fast, do not hang to the RYW timeout
    when "queued"    then :not_yet
    else                  :integrity_error
    end
  end
end
