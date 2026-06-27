# frozen_string_literal: true

# RevisionSnapshot — canonical reconstruction of a card's content at a point in
# its Decko revision history. Centralized so WS6 (BaseResolver) and the MCP API
# do not fork subtly different revision logic; mirrors mcp_api's
# build_snapshot_at_action (Card::Action / Card::Act). All methods read-only.
module RevisionSnapshot
  module_function

  # Raw stored content of card_id as of `action` (a Card::Action). Decko records
  # db_content only on actions that changed content, so when this action did not
  # touch content we look back to the most recent one that did.
  def content_at(card_id, action)
    return nil unless action

    direct = action.value(:db_content) || action.value(:content)
    return direct unless direct.nil?

    prev = Card::Action.where(card_id: card_id)
                       .where("card_actions.id <= ?", action.id)
                       .order("card_actions.id DESC")
                       .find { |a| !(a.value(:db_content) || a.value(:content)).nil? }
    prev && (prev.value(:db_content) || prev.value(:content))
  end

  # The card's committed action within a given act (durable reconstruction
  # anchor — an Act can span several cards' actions, so resolve per card).
  def action_at_act(card_id, act_id)
    return nil unless act_id

    Card::Action.joins(:act)
                .where(card_id: card_id, card_acts: { id: act_id })
                .order("card_actions.id DESC").first
  end

  # The card's latest committed (non-draft) action with acted_at <= time.
  def latest_action_at_or_before(card_id, time)
    Card::Action.joins(:act)
                .where(card_id: card_id, draft: [false, nil])
                .where("card_acts.acted_at <= ?", time)
                .order("card_acts.acted_at DESC, card_actions.id DESC").first
  end

  # Committed actions of card_id with acted_at within +/- window seconds of time.
  def actions_within(card_id, time, window)
    Card::Action.joins(:act)
                .where(card_id: card_id, draft: [false, nil])
                .where("card_acts.acted_at BETWEEN ? AND ?", time - window, time + window)
                .order("card_acts.acted_at ASC")
  end
end
