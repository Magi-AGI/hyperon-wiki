# Editorial workflow events that apply to all cards.
# These need to be on set/all because type-specific sets don't see
# cross-type transitions (a Draft set event won't fire when the card
# becomes Published, because the card is no longer in the Draft set).

DRAFT_TYPE_NAME = "Draft".freeze
PUBLISHED_TYPE_NAME = "Published".freeze

# Event: when any card's type changes to Published, stamp approval metadata.
event :on_publish_card, :finalize, on: :update, changed: :type_id do
  new_type = Card.fetch(type_id)&.name
  return unless new_type == PUBLISHED_TYPE_NAME

  # Record who approved and when
  add_subcard "#{name}+approved by", content: Auth.current.name, type_id: Card::PhraseID
  add_subcard "#{name}+approved at", content: Time.current.to_date.to_s, type_id: Card::DateID

  # Update tags
  tag_card_name = "#{name}+tag"
  tag_card = Card.fetch(tag_card_name) || Card.new(name: tag_card_name, type_id: Card::PointerID)
  tag_card.add_item "human approved" unless tag_card.item_names.include?("human approved")
  tag_card.drop_item "needs review" if tag_card.item_names.include?("needs review")
  add_subcard tag_card
end
