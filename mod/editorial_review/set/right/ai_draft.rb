# Set module for +ai draft child cards.
# When an ai draft is created or updated, auto-tag the parent with "needs review".

event :tag_parent_needs_review, :integrate, on: :save do
  parent = left
  return unless parent

  # Only tag if the ai draft has content
  return if content.blank?

  # Add "needs review" tag to parent
  tag_card = parent.fetch(:tag, new: { type_id: Card::PointerID })
  unless tag_card.item_names.include?("needs review")
    tag_card.add_item "needs review"
    tag_card.save!
  end
end

# Event: when an ai draft is merged into the parent card.
# Triggered by saving with merge_draft param.
event :merge_ai_draft, :finalize, on: :update,
      when: proc { |c| Env.params[:merge_draft] == "true" } do
  parent = left
  return unless parent

  # Copy draft content into parent's main content
  parent.content = content
  parent.save!

  # Record approval metadata on parent
  add_subcard "#{parent.name}+approved by", content: Auth.current.name, type_id: Card::PhraseID
  add_subcard "#{parent.name}+approved at", content: Time.current.to_date.to_s, type_id: Card::DateID

  # Clear the draft content after merge
  self.content = ""
end

format :html do
  view :merge_button do
    return "" unless card.ok?(:update) && card.content.present?

    parent = card.left
    return "" unless parent

    link_to "Merge into #{h parent.name}",
            path(action: :update, card: { content: card.content }, merge_draft: "true"),
            class: "btn btn-primary btn-sm",
            method: :put,
            data: { confirm: "Merge this AI draft into the published article?" }
  end

  view :core do
    if card.content.present?
      output [
        wrap_with(:div, class: "alert alert-info mb-3") do
          [
            "<strong>AI Draft</strong> &mdash; Proposed changes pending review.",
            (" " + render_merge_button if card.ok?(:update))
          ].compact.join
        end,
        super()
      ]
    else
      wrap_with(:div, class: "text-muted") { "<em>No AI draft pending.</em>" }
    end
  end
end
