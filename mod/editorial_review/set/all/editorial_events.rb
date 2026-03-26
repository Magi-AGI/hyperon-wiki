# Editorial workflow events that apply to all cards.
# These need to be on set/all because type-specific sets don't see
# cross-type transitions (a Draft set event won't fire when the card
# becomes Published, because the card is no longer in the Draft set).

DRAFT_TYPE_NAME = "Draft".freeze
PUBLISHED_TYPE_NAME = "Published".freeze

# Event: when any card's type changes to Published, stamp approval metadata.
event :on_publish_card, :integrate, on: :update, changed: :type_id do
  new_type = Card.fetch(type_id)&.name
  next unless new_type == PUBLISHED_TYPE_NAME

  # Record who approved and when
  Card::Auth.as_bot do
    approved_by = Card.fetch("#{name}+approved by", new: {})
    approved_by.type_id = Card::PhraseID
    approved_by.content = Auth.current.name
    approved_by.save!

    approved_at = Card.fetch("#{name}+approved at", new: {})
    approved_at.type_id = Card::DateID
    approved_at.content = Time.current.to_date.to_s
    approved_at.save!

    # Update tags
    tag_card = Card.fetch("#{name}+tag", new: { type_id: Card::PointerID })
    tag_card.add_item "human approved" unless tag_card.item_names.include?("human approved")
    tag_card.drop_item "needs review" if tag_card.item_names.include?("needs review")
    tag_card.save!
  end
end
