# Set module for Draft card type.
# Adds a draft banner and "Approve & Publish" button for signed-in users.
# Auto-tags new Draft cards with "needs review".

format :html do
  # Override core view to prepend the draft banner
  view :core do
    banner = render_draft_banner
    output [banner, super()]
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
    link_to "Approve &amp; Publish",
            path(action: :update, card: { type: "Published", trigger: :approve_draft }),
            class: "btn btn-success btn-sm",
            method: :put,
            data: { confirm: "Publish this card? It will become visible to all users." }
  end
end

# Event: auto-tag new Draft cards with "needs review"
event :tag_draft_needs_review, :integrate, on: :create do
  tag_card = fetch(:tag, new: { type_id: Card::PointerID })
  tag_card.add_item "needs review" unless tag_card.item_names.include?("needs review")
  tag_card.save!
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
