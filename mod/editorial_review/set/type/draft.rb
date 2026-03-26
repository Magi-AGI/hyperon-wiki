# Set module for Draft card type.
# Adds a draft banner and "Approve & Publish" button for signed-in users.
# Auto-tags new Draft cards with "needs review".

format :html do
  view :core do
    output [render_draft_banner, super()]
  end

  view :draft_banner do
    wrap_with :div, class: "alert alert-warning d-flex justify-content-between align-items-center mb-3" do
      [
        wrap_with(:span) do
          "<strong>Draft</strong> &mdash; This content has not been approved for publication."
        end,
        (render_approve_button if card.ok?(:update))
      ].compact.join
    end
  end

  view :approve_button do
    link_to_card card.name, "Approve &amp; Publish",
                 path: { action: :update, card: { type: "Published" },
                         trigger: :approve_draft },
                 class: "btn btn-success btn-sm"
  end
end

# Event: auto-tag new Draft cards with "needs review"
event :tag_draft_needs_review, :integrate, on: :create do
  tag_card_name = "#{name}+tag"
  tag_card = Card.fetch(tag_card_name) || Card.create!(name: tag_card_name, type_id: Card::PointerID)
  unless tag_card.item_names.include?("needs review")
    tag_card.add_item "needs review"
    tag_card.save!
  end
end

# NOTE: The approval event (type change Draft→Published) is in
# set/all/editorial_events.rb because type-specific sets don't see
# cross-type transitions.
