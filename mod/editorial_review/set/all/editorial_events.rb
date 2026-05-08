# Editorial workflow events that apply to all cards.
# These need to be on set/all because type-specific sets don't see
# cross-type transitions (a Draft set event won't fire when the card
# becomes Published, because the card is no longer in the Draft set).

DRAFT_TYPE_NAME = "Draft".freeze
PUBLISHED_TYPE_NAMES = ["Published", "IndexPublished", "IndexSection"].freeze

# Event: when any card's type changes to a publication target, stamp approval
# metadata. Published, IndexPublished, and IndexSection all count as
# publication. IndexPublished is the curated subtopic cardtype for the
# Hyperon Prime Index; IndexSection is the corresponding section-landing
# cardtype. All three share editorial behavior with each other via
# Abstract::EditoriallyReviewed.
#
# Idempotent: if the card already has +approved by content, skip the stamp
# entirely. This protects approval metadata when a card moves between
# publication-equivalent cardtypes (e.g., Published <-> IndexPublished); only
# the first Draft -> publication transition records the approval.
event :on_publish_card, :integrate, on: :update, changed: :type_id do
  new_type = Card.fetch(type_id)&.name
  next unless PUBLISHED_TYPE_NAMES.include?(new_type)

  existing_approver = Card.fetch("#{name}+approved by")&.content
  next if existing_approver.present?

  # First-time approval — record who approved and when
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
