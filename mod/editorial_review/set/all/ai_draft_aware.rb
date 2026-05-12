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
end
