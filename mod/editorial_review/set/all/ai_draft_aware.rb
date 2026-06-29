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
    proposal = Card.fetch("#{card.name}+proposal")
    has_ai       = ai_draft && ai_draft.content.present?
    has_proposal = proposal && proposal.db_content.present?
    # WS6 discoverability (#2): surface the entry point whenever EITHER an +AI
    # draft OR a +proposal exists. A proposal created directly via the API (no
    # +AI draft) previously left the parent page with no link into the workbench.
    return "" unless has_ai || has_proposal

    review_link = has_ai &&
                  link_to_card(ai_draft.name, "Review AI Draft &rarr;",
                               class: "btn btn-outline-info btn-sm me-2")

    # WS6 Phase 8.1 (Option A): "Merge AI Draft -> Parent" must NOT overwrite the
    # parent directly. It routes through the verifying 3-way merge workbench /
    # apply gate instead (the WS6 mutual-exclusion invariant: the only path that
    # writes a parent is apply_merge_draft). Gated on card.ok?(:update) — the same
    # editorial capability as the apply gate. When an active +proposal exists, go
    # straight to the workbench (covers API-created proposals); otherwise POST the
    # capability-gated legacy bridge (creates the proposal from the +AI draft).
    merge_button =
      if card.ok?(:update)
        if has_proposal
          merged = Card.fetch("#{proposal.name}+merge audit")&.db_content.present?
          label = merged ? "View merged proposal &rarr;" : "Review &amp; merge proposal &rarr;"
          %(<a href="#{MergeWorkbench.workbench_url(proposal.name)}" ) +
            %(class="btn btn-primary btn-sm">#{label}</a>)
        elsif has_ai
          prop_name = "#{card.name}+proposal"
          token = (form_authenticity_token rescue "")
          success_url = MergeWorkbench.workbench_url(prop_name)
          %(<form method="post" action="/card/update" style="display:inline">) +
            %(<input type="hidden" name="authenticity_token" value="#{h token}">) +
            %(<input type="hidden" name="card[name]" value="#{h prop_name}">) +
            %(<input type="hidden" name="card[type]" value="#{h card.type_name}">) +
            %(<input type="hidden" name="legacy_bridge_from" value="#{h ai_draft.name}">) +
            %(<input type="hidden" name="proposal_source" value="legacy_bridge">) +
            %(<input type="hidden" name="success" value="#{h success_url}">) +
            %(<button type="submit" class="btn btn-primary btn-sm">) +
            %(Merge AI Draft &rarr; Parent</button></form>)
        end
      end

    wrap_with(:div, class: "mb-3") do
      [review_link, merge_button].select { |x| x.is_a?(String) && x.present? }.join(" ")
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

  # Renders the card's +author / +contributor / +editor pointers as a compact
  # attribution block (one labeled, comma-separated row of person links each)
  # at the top of the page.
  #
  # WHY here (same rationale as view :page_tags above): Draft / Published
  # cardtypes have no `+*type+*structure` rule, so this is invoked via
  # `render_page_attribution` from the Draft `view :core` (set/type/draft.rb)
  # and the Published core (Abstract::EditoriallyReviewed). IndexSubtopic /
  # IndexSection / History cards invoke it via `{{_self|page_attribution}}`
  # in their structure rules (where view :core dispatch is bypassed), which is
  # why the definition lives in set/all (universally resolvable for inclusion).
  #
  # Person names are rendered as links so each resolves to the Contributor
  # card (which can later hold a sign-in account). Wrapped in
  # `.wiki-page-attribution`; the Skin (sandra ui styles) styles it small/grey
  # and tightens spacing. Returns "" when the card has none of the three
  # pointers populated, so attribution-less cards render no extra UI.
  view :page_attribution, cache: :never do
    rows = [%w[author Authors], %w[contributor Contributors], %w[editor Editors]].filter_map do |field, label|
      pointer = Card.fetch("#{card.name}+#{field}")
      next unless pointer && pointer.type_id == Card::PointerID && pointer.item_names.present?

      links = pointer.item_names.map { |item_name| link_to_card item_name }.join(", ")
      %(<div class="wiki-attr-row"><span class="wiki-attr-label">#{label}:</span> #{links}</div>)
    end
    return "" if rows.empty?

    wrap_with(:div, class: "wiki-page-attribution") do
      rows.join
    end
  end
end
