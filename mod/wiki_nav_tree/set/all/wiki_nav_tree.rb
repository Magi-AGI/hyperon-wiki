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
#
# Focus Mode (Ben's request):
#   Append ?nav_root=CardName to any URL to focus the tree on that card's subtree.
#   A "⊙" icon appears next to each item to set focus; a banner with "✕ clear" resets it.

format :html do
  view :wiki_nav_tree, cache: :never do
    wrap_with :nav, class: "wiki-nav-tree small", "aria-label": "Wiki outline" do
      focus_banner + render_wiki_nav_list(nav_tree_seed_cards, tier: :root)
    end
  end

  # Loaded into a slot via slotter; +card+ is the parent whose children we list.
  view :wiki_nav_tree_branch, cache: :never do
    render_wiki_nav_list(nav_child_cards(card), tier: :branch)
  end

  # ── Focus Mode ─────────────────────────────────────────────────────────────

  def focus_banner
    root = nav_root_param
    return "" if root.blank?

    clear_path = current_path_without(:nav_root)
    wrap_with(:div, class: "wiki-nav-focus-banner small border-bottom pb-1 mb-1") do
      "Focused: #{root} #{link_to("✕ clear", clear_path, class: "text-muted")}"
    end
  end

  # The active nav root: URL param takes priority, then env var.
  def nav_root_param
    Env.params[:nav_root].presence || ENV["WIKI_NAV_ROOT"].to_s.strip.presence
  rescue
    nil
  end

  # Reconstruct current URL without the nav_root param.
  def current_path_without(key)
    params = (Env.params || {}).reject { |k, _| k.to_s == key.to_s }
    base = params[:mark].presence || "/"
    rest = params.reject { |k, _| k.to_s == "mark" }
    rest.empty? ? base : "#{base}?#{rest.to_query}"
  rescue
    "/"
  end

  # Small ⊙ link that focuses the tree on a given card.
  def focus_mode_link(child)
    return "" if nav_root_param == child.name

    link_to(
      "⊙",
      "?nav_root=#{ERB::Util.url_encode(child.name)}",
      class: "wiki-nav-focus-btn text-muted text-decoration-none ms-1",
      title: "Focus tree on #{child.name.to_name.tag.tr("_", " ")}",
      "aria-label": "Focus navigation on #{child.name}"
    )
  end

  # ── Active-ancestor detection ───────────────────────────────────────────────

  # Returns true if +child+ is an ancestor of the page currently being viewed.
  # Used to pre-expand the tree along the active path on page load.
  def nav_ancestor_of_current?(child)
    current_page_ancestors.include?(child.name.to_name.key)
  rescue
    false
  end

  # Returns true if +child+ IS the page currently being viewed.
  def current_page?(child)
    main = (Env.params[:mark] || Env.params[:id]).to_s.strip
    return false if main.blank?
    child.name.to_name.key == main.to_name.key
  rescue
    false
  end

  # Set of ancestor name-keys for the current page (memoised per render).
  # e.g. viewing "Hyperon+Architecture+Atomspace" → {"hyperon", "hyperon+architecture"}
  def current_page_ancestors
    @current_page_ancestors ||= begin
      main = (Env.params[:mark] || Env.params[:id]).to_s.strip
      return Set.new if main.blank?
      # part_names returns all ancestor compound names (not including the card itself)
      main.to_name.part_names[0..-2].map { |n| n.to_name.key }.to_set
    rescue
      Set.new
    end
  end

  # ── List rendering ──────────────────────────────────────────────────────────

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
    is_ancestor = nav_ancestor_of_current?(child)
    is_current  = current_page?(child)

    expand = nil
    nest   = nil

    if likely_has_nav_children?(child)
      target_id = wiki_nav_dom_id(child)

      if is_ancestor || is_current
        # Pre-expand: render children inline so the active path is visible on load.
        expand = link_to_card(
          child.name, "▾",
          path: { view: :wiki_nav_tree_branch },
          slotter: true,
          class: "wiki-nav-expand wiki-nav-expand--open text-muted text-decoration-none ms-1",
          "data-slot-selector" => "##{target_id}",
          role: "button",
          "aria-label": "Collapse pages under #{child.name}"
        )
        nest = content_tag(:div, id: target_id, class: "wiki-nav-children ms-1") do
          render_wiki_nav_list(nav_child_cards(child), tier: :branch).html_safe
        end
      else
        # Lazy: children load on click via slotter.
        expand = link_to_card(
          child.name, "▸",
          path: { view: :wiki_nav_tree_branch },
          slotter: true,
          class: "wiki-nav-expand text-muted text-decoration-none ms-1",
          "data-slot-selector" => "##{target_id}",
          role: "button",
          "aria-label": "Show pages under #{child.name}"
        )
        nest = content_tag(:div, "", id: target_id, class: "wiki-nav-children ms-1")
      end
    end

    label = child.name.to_name.tag.to_s.tr("_", " ")
    item_class = ["wiki-nav-item py-1"]
    item_class << "wiki-nav-item--current fw-semibold" if is_current

    content_tag(:li, class: item_class.join(" ")) do
      safe_join([
        link_to_card(child.name, label, known: true),
        expand,
        focus_mode_link(child),
        nest
      ].compact, " ")
    end
  end

  # ── Data helpers ────────────────────────────────────────────────────────────

  def nav_tree_seed_cards
    parent = nav_tree_parent_card
    parent ? nav_child_cards(parent) : nav_root_cards
  end

  def nav_tree_parent_card
    name = nav_root_param
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
