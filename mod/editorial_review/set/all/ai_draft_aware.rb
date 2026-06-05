# Set module — provides the `view :ai_draft_link` to every card so it can
# be invoked via inclusion (`{{_self|ai_draft_link}}`) from cardtype
# structure rules (`+*type+*structure`).
#
# WHY here and not in Abstract::EditoriallyReviewed: structure rules for
# cardtypes like IndexSubtopic / IndexSection replace the body rendering
# at a level that bypasses the cardtype's `view :core` dispatch, which
# means views defined inside an `include_set`-ed abstract module aren't
# resolvable for inclusion-style invocation. Putting the definition in
# `set/all` registers the view universally, making it findable.
#
# WHEN the +AI / +ai draft child has no content the view returns "",
# so cards without an AI proposal render no extra UI.
#
# WHO renders it:
#   - Published cards: via `Abstract::EditoriallyReviewed#view :core`
#     which calls `render_ai_draft_link` and integrates the result.
#   - IndexSubtopic / IndexSection cards: via `{{_self|ai_draft_link}}`
#     in their respective `+*type+*structure` rules.
#   - Any other card: not currently invoked, but available if needed.

format :html do
  view :ai_draft_link, cache: :never do
    ai_draft = Card.fetch("#{card.name}+AI") || Card.fetch("#{card.name}+ai draft")
    return "" unless ai_draft && ai_draft.content.present?

    review_link = link_to_card ai_draft.name, "Review AI Draft &rarr;",
                               class: "btn btn-outline-info btn-sm me-2"

    merge_button = if card.ok?(:update)
                     link_to_card card.name, "Merge AI Draft &rarr; Parent",
                                  path: { action: :update,
                                          card: { content: ai_draft.content },
                                          merge_draft: "true" },
                                  class: "btn btn-primary btn-sm"
                   end

    wrap_with(:div, class: "mb-3") do
      [review_link, merge_button].compact.join(" ")
    end
  end

  # Renders the card's +tag pointer as a pill row at the top of the page.
  #
  # WHY here: Draft / Published cardtypes have no `+*type+*structure` rule
  # (unlike IndexSubtopic / IndexSection, whose structures render `{{+tag}}`),
  # so a Draft/Published card viewed on its own URL would show no tags. This
  # view is invoked via `render_page_tags` from the Draft `view :core`
  # (set/type/draft.rb) and the Published core (Abstract::EditoriallyReviewed)
  # so those pages get the same top-of-page tag pills as the index pages.
  #
  # Wrapped in `.wiki-page-tags`, which the Skin (sandra ui styles) styles into
  # the same rounded grey/blue pills as the index-page tag slots. Returns ""
  # when the card has no +tag pointer or it is empty.
  view :page_tags, cache: :never do
    tag_card = Card.fetch("#{card.name}+tag")
    return "" unless tag_card && tag_card.type_id == Card::PointerID
    return "" if tag_card.item_names.blank?

    wrap_with(:div, class: "wiki-page-tags") do
      nest(tag_card, view: :content)
    end
  end
end
