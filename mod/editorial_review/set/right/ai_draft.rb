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
      parent = card.left
      proposal = parent && Card.fetch("#{parent.name}+proposal")
      # Entry point (Phase 7.3): when a +proposal exists, link to its workbench
      # via the centralized layout=none builder. When it doesn't, the Phase 7.2
      # legacy bridge will offer "Open as proposal" here instead.
      link =
        if proposal&.db_content.present?
          %( <a href="#{MergeWorkbench.workbench_url(proposal.name)}" ) +
            %(class="btn btn-primary btn-sm">Review &amp; merge in the workbench &rarr;</a>)
        else
          ""
        end
      banner = wrap_with(:div, class: "alert alert-info mb-3") do
        "<strong>AI Draft</strong> &mdash; proposed changes pending review. " \
          "Merging into the parent goes through the verifying merge workbench " \
          "(no direct overwrite).#{link}"
      end
      output [banner, super()]
    else
      wrap_with(:div, class: "text-muted") { "<em>No AI draft pending.</em>" }
    end
  end
end
