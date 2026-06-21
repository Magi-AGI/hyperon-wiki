# Shared editorial-review behavior for cards in a "published" state.
# Includes the approval seal (banner for 7 days, then subtle badge) and
# optional expert endorsement.
#
# Included from set/type/published.rb and set/type/index_published.rb so
# Index-track cards share the same review/approval surface as the regular
# Published track.

APPROVAL_BANNER_DAYS = 7

format :html do
  view :core, cache: :never do
    seal = render_approval_indicator
    ai_link = render_ai_draft_link
    tags = render_page_tags
    attribution = render_page_attribution
    output([seal, ai_link, tags, attribution, super()].compact.reject(&:blank?))
  end

  # NOTE: the implementation of view :ai_draft_link lives in
  # `mod/editorial_review/set/all/ai_draft_aware.rb` (universal scope)
  # so it can be invoked both from view :core above (via render_ai_draft_link
  # for Published cards, where view :core dispatch works) and from
  # `{{_self|ai_draft_link}}` inclusion in IndexSubtopic / IndexSection
  # structure rules (where the cardtype's view :core dispatch is bypassed
  # by the structure-rule rendering and inclusion-style lookup needs the
  # view to be visible from set/all).

  # Choose banner vs badge based on approval recency
  view :approval_indicator, cache: :never do
    approver = Card.fetch("#{card.name}+approved by")&.content
    approved_at_str = Card.fetch("#{card.name}+approved at")&.content

    return "" unless approver

    approved_at = begin
      Date.parse(approved_at_str)
    rescue StandardError
      nil
    end

    recent = approved_at && (Date.today - approved_at) <= APPROVAL_BANNER_DAYS

    expert_html = render_expert_indicator

    if recent
      wrap_with :div, class: "alert alert-success d-flex justify-content-between align-items-center mb-3" do
        [
          wrap_with(:span) do
            "<strong>Human Approved</strong> &mdash; by #{h approver} on #{h approved_at_str}"
          end,
          expert_html
        ].compact.join
      end
    else
      wrap_with :div, class: "text-muted small mb-2" do
        [
          "Approved by #{h approver} on #{h approved_at_str}",
          expert_html.present? ? " &middot; #{expert_html}" : nil
        ].compact.join
      end
    end
  end

  view :expert_indicator, cache: :never do
    expert = Card.fetch("#{card.name}+expert approved by")&.content

    if expert
      expert_at = Card.fetch("#{card.name}+expert approved at")&.content || "unknown date"
      wrap_with(:span, class: "badge bg-warning text-dark") do
        "Expert Approved by #{h expert} on #{h expert_at}"
      end
    elsif user_is_expert?
      link_to_card card.name, "Expert Approve",
                   path: { action: :update, trigger: :expert_approve },
                   class: "btn btn-warning btn-sm"
    else
      ""
    end
  end

  def user_is_expert?
    Card::Auth.current_roles.include?("Expert")
  rescue StandardError
    false
  end
end

# Event: when an expert endorses a reviewed card.
event :on_expert_approve, :integrate, on: :update,
      when: proc { |_c| Env.params[:trigger] == "expert_approve" } do
  Card::Auth.as_bot do
    expert_by = Card.fetch("#{name}+expert approved by", new: {})
    expert_by.type_id = Card::PhraseID
    expert_by.content = Auth.current.name
    expert_by.save!

    expert_at = Card.fetch("#{name}+expert approved at", new: {})
    expert_at.type_id = Card::DateID
    expert_at.content = Time.current.to_date.to_s
    expert_at.save!

    tag_card = Card.fetch("#{name}+tag", new: { type_id: Card::PointerID })
    tag_card.add_item "expert approved" unless tag_card.item_names.include?("expert approved")
    tag_card.save!
  end
end
