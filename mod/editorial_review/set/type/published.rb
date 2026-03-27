# Set module for Published card type.
# Displays approval seal (banner for 7 days, then subtle badge)
# and optional expert endorsement.

APPROVAL_BANNER_DAYS = 7

format :html do
  view :core, cache: :never do
    seal = render_approval_indicator
    if seal.present?
      output [seal, super()]
    else
      super()
    end
  end

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

# Event: when an expert endorses a Published card.
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
