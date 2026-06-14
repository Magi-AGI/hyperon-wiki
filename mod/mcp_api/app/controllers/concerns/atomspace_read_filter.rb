# frozen_string_literal: true

# Strict MULTI-CARD default-deny read filter (Invariant 9, 2026-06-09 clarification).
# An atom is returned only if its associated_card_ids list is non-empty, nil-free, and
# EVERY id resolves to a card the account can read. References require BOTH referer and
# (resolved) referee readable; an unresolved referee is excluded from the list, so the
# atom is returned iff the referer is readable.
module AtomspaceReadFilter
  extend ActiveSupport::Concern

  private

  def filter_by_read_auth(atoms, account)
    Card::Auth.as(account.name) do
      atoms.select do |atom|
        ids = atom.associated_card_ids
        next false if ids.empty? || ids.any?(&:nil?)

        ids.all? { |cid| (card = Card.fetch(cid)) ? card.ok?(:read) : false }
      end
    end
  end
end
