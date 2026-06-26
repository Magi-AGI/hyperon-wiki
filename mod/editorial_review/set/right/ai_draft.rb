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
      # Entry point: when a +proposal exists, link to its workbench (Phase 7.3).
      # When none exists, offer the Phase 7.2 legacy bridge ("Open as proposal"),
      # but only to a user who may create the proposal (admin/editor) — never a
      # silent or anonymous promotion.
      action =
        if proposal&.db_content.present?
          %( <a href="#{MergeWorkbench.workbench_url(proposal.name)}" ) +
            %(class="btn btn-primary btn-sm">Review &amp; merge in the workbench &rarr;</a>)
        elsif parent && ai_draft_can_bridge?(parent)
          ai_draft_bridge_form(parent)
        else
          ""
        end
      banner = wrap_with(:div, class: "alert alert-info mb-3") do
        "<strong>AI Draft</strong> &mdash; proposed changes pending review. " \
          "Merging into the parent goes through the verifying merge workbench " \
          "(no direct overwrite).#{action}"
      end
      output [banner, super()]
    else
      wrap_with(:div, class: "text-muted") { "<em>No AI draft pending.</em>" }
    end
  end

  # Admin/editor gate: may the current user create the parent's +proposal?
  def ai_draft_can_bridge?(parent)
    Card.new(name: "#{parent.name}+proposal", type_id: parent.type_id).ok?(:create)
  rescue StandardError
    false
  end

  # Phase 7.2 "Open as proposal" — a plain authenticated form POST that creates
  # <parent>+proposal seeded from THIS +AI draft (legacy_bridge_from); the
  # proposal set estimates the base from the draft's creation time and marks it
  # low-confidence, and `success` redirects into the merge workbench (layout=none).
  def ai_draft_bridge_form(parent)
    prop_name = "#{parent.name}+proposal"
    token = (form_authenticity_token rescue "")
    success_url = MergeWorkbench.workbench_url(prop_name)
    %(<form method="post" action="/card/update" style="display:inline">) +
      %(<input type="hidden" name="authenticity_token" value="#{h token}">) +
      %(<input type="hidden" name="card[name]" value="#{h prop_name}">) +
      %(<input type="hidden" name="card[type]" value="#{h parent.type_name}">) +
      %(<input type="hidden" name="legacy_bridge_from" value="#{h card.name}">) +
      %(<input type="hidden" name="proposal_source" value="legacy_bridge">) +
      %(<input type="hidden" name="success" value="#{h success_url}">) +
      %( <button type="submit" class="btn btn-warning btn-sm" ) +
      %(title="Creates an estimated-base review proposal and opens the merge workbench">) +
      %(Open as proposal (review &amp; merge) &rarr;</button></form>)
  end
end
