# Set module for Published card type.
# Displays approval seal and optional expert endorsement.

format :html do
  # Override core view to prepend the approval seal
  view :core do
    seal = render_approval_seal
    if seal.present?
      output [seal, super()]
    else
      super()
    end
  end

  view :approval_seal do
    approver = Card.fetch("#{card.name}+approved by")&.content
    approved_at = Card.fetch("#{card.name}+approved at")&.content

    return "" unless approver

    date_display = approved_at || "unknown date"

    wrap_with :div, class: "alert alert-success d-flex justify-content-between align-items-center mb-3" do
      [
        wrap_with(:span) do
          "<strong>Human Approved</strong> &mdash; by #{h approver} on #{h date_display}"
        end,
        render_expert_seal_or_button
      ].compact.join
    end
  end

  view :expert_seal_or_button do
    expert = Card.fetch("#{card.name}+expert approved by")&.content

    if expert
      expert_at = Card.fetch("#{card.name}+expert approved at")&.content || "unknown date"
      wrap_with(:span, class: "badge bg-warning text-dark ms-2") do
        "Expert Approved by #{h expert} on #{h expert_at}"
      end
    elsif user_is_expert?
      link_to "Expert Approve",
              card.path(action: :update, trigger: :expert_approve),
              class: "btn btn-warning btn-sm ms-2",
              method: :put,
              data: { confirm: "Add your expert endorsement to this card?" }
    else
      ""
    end
  end

  def user_is_expert?
    Auth.current&.fetch(:roles)&.item_names&.include?("Expert")
  rescue StandardError
    false
  end
end

# Event: when an expert endorses a Published card.
event :on_expert_approve, :finalize, on: :update,
      when: proc { |_c| Env.params[:trigger] == "expert_approve" } do
  add_subcard "#{name}+expert approved by", content: Auth.current.name, type_id: Card::PhraseID
  add_subcard "#{name}+expert approved at", content: Time.current.to_date.to_s, type_id: Card::DateID

  # Add "expert approved" tag
  tag_card = fetch(:tag, new: { type_id: Card::PointerID })
  tag_card.add_item "expert approved" unless tag_card.item_names.include?("expert approved")
  add_subcard tag_card
end
