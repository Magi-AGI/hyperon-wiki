# Set module for +ai draft child cards.
# When an ai draft is created or updated, auto-tag the parent with "needs review".

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

# Event: when an ai draft is merged into the parent card.
# Triggered by saving with merge_draft param.
event :merge_ai_draft, :finalize, on: :update,
      when: proc { |_c| Env.params[:merge_draft] == "true" } do
  parent = left
  return unless parent

  parent.content = content
  parent.save!

  add_subcard "#{parent.name}+approved by", content: Auth.current.name, type_id: Card::PhraseID
  add_subcard "#{parent.name}+approved at", content: Time.current.to_date.to_s, type_id: Card::DateID

  self.content = ""
end

format :html do
  view :merge_button do
    return "" unless card.ok?(:update) && card.content.present?

    parent = card.left
    return "" unless parent

    link_to_card parent.name, "Merge into #{h parent.name}",
                 path: { action: :update, card: { content: card.content },
                         merge_draft: "true" },
                 class: "btn btn-primary btn-sm"
  end

  view :core do
    if card.content.present?
      banner = wrap_with(:div, class: "alert alert-info mb-3") do
        [
          "<strong>AI Draft</strong> &mdash; Proposed changes pending review.",
          (" " + render_merge_button if card.ok?(:update))
        ].compact.join
      end
      banner.to_s + super.to_s
    else
      wrap_with(:div, class: "text-muted") { "<em>No AI draft pending.</em>" }
    end
  end
end
