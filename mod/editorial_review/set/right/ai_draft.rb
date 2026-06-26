# Set module for +ai draft child cards.
# When an ai draft is created or updated, auto-tag the parent with "needs review".
#
# WS6 Phase 6 — MUTUAL EXCLUSION: the blunt "merge into parent" overwrite has been
# REMOVED. There used to be an `event :merge_ai_draft` (triggered by a
# ?merge_draft=true post) that copied the draft straight onto the parent, plus a
# `merge_button` that fired it. Both are gone. Removing the EVENT — not just the
# button — is deliberate: a direct ?merge_draft=true post is no longer a usable
# bypass. The ONLY authorized path to write a draft back to a parent is now the
# verifying 3-way merge workbench + apply gate (set/right/proposal.rb +
# set/right/merge_draft.rb), which checks permission, optimistic lock, and content
# hashes in one transaction. The +AI -> +proposal bridge lands in Phase 7.

event :tag_parent_needs_review, :integrate, on: :save do
  parent = left
  return unless parent
  return if content.blank?

  tag_card_name = "#{parent.name}+tag"
  tag_card = Card.fetch(tag_card_name) || Card.create!(name: tag_card_name, type_id: Card::PointerID)
  unless tag_card.item_names.include?("needs review")
    tag_card.add_item "needs review"
    tag_card.save!
  end
end

format :html do
  view :core do
    if card.content.present?
      banner = wrap_with(:div, class: "alert alert-info mb-3") do
        "<strong>AI Draft</strong> &mdash; proposed changes pending review. " \
          "Merging into the parent now goes through the verifying merge workbench " \
          "on the parent's <code>+proposal</code> (no direct overwrite)."
      end
      output [banner, super()]
    else
      wrap_with(:div, class: "text-muted") { "<em>No AI draft pending.</em>" }
    end
  end
end
