# frozen_string_literal: true

# Server-rendered hierarchical nav: compound-name children (left: parent) with
# lazy-loaded deeper levels via Decko slotters.
#
# Usage (e.g. in *sidebar or any card):
#   {{_|view:wiki_nav_tree}}
#
# Env:
#   WIKI_NAV_ROOT — optional parent card name; tree shows its direct children first.
#                   If unset, lists top-level simple cards (left_id/right_id nil), filtered.
#   WIKI_NAV_ROOT_LIMIT — max root candidates when WIKI_NAV_ROOT unset (default 150).
#   WIKI_NAV_CHILD_LIMIT — max children per parent (default 250).

format :html do
  view :wiki_nav_tree, cache: :never do
    wrap_with :nav, class: "wiki-nav-tree small", "aria-label": "Wiki outline" do
      render_wiki_nav_list(nav_tree_seed_cards, tier: :root)
    end
  end

  # Loaded into a slot via slotter; +card+ is the parent whose children we list.
  view :wiki_nav_tree_branch, cache: :never do
    render_wiki_nav_list(nav_child_cards(card), tier: :branch)
  end

  def render_wiki_nav_list(cards, tier:)
    return "" if cards.blank?

    ul_class = ["wiki-nav-branch", "list-unstyled", "mb-0"]
    ul_class << "wiki-nav-branch--root" if tier == :root
    ul_class << "ps-2 border-start border-secondary-subtle" if tier == :branch

    wrap_with :ul, class: ul_class.join(" ") do
      safe_join(cards.map { |c| render_wiki_nav_row(c) })
    end
  end

  def render_wiki_nav_row(child)
    expand = nil
    nest = nil
    if likely_has_nav_children?(child)
      target_id = wiki_nav_dom_id(child)
      expand = link_to_card(
        child.name,
        "▸",
        path: { view: :wiki_nav_tree_branch },
        slotter: true,
        class: "wiki-nav-expand text-muted text-decoration-none ms-1",
        "data-slot-selector" => "##{target_id}",
        role: "button",
        "aria-label": "Show pages under #{child.name}"
      )
      nest = content_tag(:div, "", id: target_id, class: "wiki-nav-children ms-1")
    end

    label = child.name.tr("_", " ")
    content_tag(:li, class: "wiki-nav-item py-1") do
      safe_join(
        [
          link_to_card(child.name, label, known: true),
          expand,
          nest
        ].compact,
        " "
      )
    end
  end

  def nav_tree_seed_cards
    parent = nav_tree_parent_card
    parent ? nav_child_cards(parent) : nav_root_cards
  end

  def nav_tree_parent_card
    name = ENV["WIKI_NAV_ROOT"].to_s.strip
    return if name.blank?

    Card.fetch name
  end

  def nav_root_cards
    lim = wiki_nav_root_limit
    scope = Card.where(trash: false, left_id: nil, right_id: nil)
                .where.not("cards.name LIKE ?", "*%")
                .order(:name)
                .limit(lim)
    scope.to_a.select { |c| ok_nav_card?(c) && c.ok?(:read) }
  end

  def nav_child_cards(parent)
    return [] unless parent&.real?

    q = { left: parent.name, trash: false, sort: :name, limit: wiki_nav_child_limit }
    Card.search(q, "wiki_nav_children of #{parent.name}")
        .select { |c| ok_nav_card?(c) && c.ok?(:read) }
  end

  def likely_has_nav_children?(c)
    return false unless c&.real?

    Card.search(
      { left: c.name, trash: false, limit: 1, return: :id },
      "wiki_nav_child check #{c.name}"
    ).present?
  end

  def ok_nav_card?(c)
    return false if c.blank? || !c.real?
    return false if c.trash
    return false if %w[Image File].include?(c.type_name)

    right = c.name.to_name.right
    return false if right.present? && right.start_with?("*")
    return false if c.name.simple? && c.name.start_with?("*")

    true
  end

  def wiki_nav_dom_id(card)
    "wiki-nav-ch-#{card.id}"
  end

  def wiki_nav_root_limit
    ENV.fetch("WIKI_NAV_ROOT_LIMIT", "150").to_i.clamp(10, 500)
  end

  def wiki_nav_child_limit
    ENV.fetch("WIKI_NAV_CHILD_LIMIT", "250").to_i.clamp(10, 1000)
  end
end
