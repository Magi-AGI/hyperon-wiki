# Set module for Draft card type.
# Adds a draft banner and "Approve & Publish" button for signed-in users.

format :html do
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
    link_to "Approve &amp; Publish",
            path(action: :update, card: { type: "Published", trigger: :approve_draft }),
            class: "btn btn-success btn-sm",
            method: :put,
            data: { confirm: "Publish this card? It will become visible to all users." }
  end

  view :content_with_banner do
    output [render_draft_banner, _render_core]
  end
end

# Event: when a Draft is approved (type changed to Published),
# stamp the approval metadata and update tags.
event :on_approve_draft, :finalize, on: :update, changed: :type_id,
      when: proc { |c| c.type_code == :published } do
  # Record who approved and when
  add_subcard "#{name}+approved by", content: Auth.current.name, type_id: Card::PhraseID
  add_subcard "#{name}+approved at", content: Time.current.to_date.to_s, type_id: Card::DateID

  # Add "human approved" tag
  tag_card = fetch(:tag, new: { type_id: Card::PointerID })
  existing = tag_card.item_names
  tag_card.add_item "human approved" unless existing.include?("human approved")

  # Remove "needs review" tag if present
  tag_card.drop_item "needs review" if existing.include?("needs review")

  add_subcard tag_card
end
