# frozen_string_literal: true

# Right-side card names that are metadata/system fields, not content pages.
# Normalized to lowercase with spaces (underscores and mixed-case are handled
# at comparison time in ok_nav_card?).
NAV_BLOCKED_RIGHTS = [
  "tag", "tags", "content", "discussion",
  "approved by", "approved at",
  "expert approved by", "expert approved at",
  "table of contents"
].to_set.freeze

# Server-rendered hierarchical nav: compound-name children (left: parent) with
# lazy-loaded deeper levels via Decko slotters.
#
# Usage (e.g. in *sidebar or any card):
#   {{_|view:wiki_nav_tree}}
#
# Root-level display:
#   Only content cards that have compound children appear as top-level sections.
#   Content cards with no children are grouped under a collapsible "Other" item.
#   "Content" means: type is Draft/Published/RichText/Basic, no system codename, not a rule card.
#
# Env:
#   WIKI_NAV_ROOT — optional parent card name; tree shows its direct children first.
#                   If unset, lists content section cards filtered as above.
#   WIKI_NAV_CHILD_LIMIT — max children per parent (default 250).
#
# Focus Mode:
#   Append ?nav_root=CardName to any URL to focus the tree on that card's subtree.
#   A "⊙" icon appears next to each item to set focus; a banner with "✕ clear" resets it.

format :html do
  view :wiki_nav_tree, cache: :never do
    wrap_with :nav, class: "wiki-nav-tree small", "aria-label": "Wiki outline" do
      parent = nav_tree_parent_card
      if parent
        # Focus mode / WIKI_NAV_ROOT: show the focused card's children
        focus_banner + render_wiki_nav_list(nav_child_cards(parent), tier: :root)
      else
        # Normal mode: content section cards + collapsible Other
        focus_banner +
          wrap_with(:ul, class: "wiki-nav-branch wiki-nav-branch--root list-unstyled mb-0") do
            safe_join(nav_section_cards.map { |c| render_wiki_nav_row(c) }) +
              render_other_group
          end
      end
    end
  end

  # Loaded into a slot via slotter; +card+ is the parent whose children we list.
  view :wiki_nav_tree_branch, cache: :never do
    render_wiki_nav_list(nav_child_cards(card), tier: :branch)
  end

  # Loaded into the Other slot via slotter; returns all leaf content cards.
  view :wiki_nav_tree_leaves, cache: :never do
    leaves = nav_content_cards.reject { |c| card_ids_with_nav_children.include?(c.id) }
    render_wiki_nav_list(leaves, tier: :branch)
  end

  # ── Focus Mode ─────────────────────────────────────────────────────────────

  def focus_banner
    root = nav_root_param
    return "" if root.blank?

    clear_path = current_path_without(:nav_root)
    wrap_with(:div, class: "wiki-nav-focus-banner small border-bottom pb-1 mb-1") do
      "Focused: #{root} #{link_to("✕ clear", href: clear_path, class: "text-muted")}"
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
      href: "?nav_root=#{ERB::Util.url_encode(child.name)}",
      class: "wiki-nav-focus-btn text-muted text-decoration-none ms-1",
      title: "Focus tree on #{child.name.to_name.tag.tr("_", " ")}",
      "aria-label": "Focus navigation on #{child.name}"
    )
  end

  # ── Active-ancestor detection ───────────────────────────────────────────────

  # Returns true if +child+ is an ancestor of the page currently being viewed.
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

  # Renders an "Other" <li> that lazy-loads leaf content cards on click via slotter.
  def render_other_group
    leaves = nav_content_cards.reject { |c| card_ids_with_nav_children.include?(c.id) }
    return "" if leaves.blank?

    target_id = "wiki-nav-other-items"
    label = "Other (#{leaves.size})"

    content_tag(:li, class: "wiki-nav-item wiki-nav-other py-1") do
      expand = link_to_card(
        card.name, "▸ #{label}",
        path: { view: :wiki_nav_tree_leaves },
        slotter: true,
        class: "wiki-nav-other-toggle wiki-nav-expand text-muted text-decoration-none",
        "data-slot-selector" => "##{target_id}",
        role: "button",
        "aria-label": "Show #{label}"
      )
      nest = content_tag(:div, "", id: target_id, class: "wiki-nav-children ms-1")
      safe_join([expand, nest])
    end
  end

  # ── Data helpers ────────────────────────────────────────────────────────────

  def nav_tree_parent_card
    name = nav_root_param
    return if name.blank?
    Card.fetch name
  end

  # IDs of top-level cards that have at least one real compound child (memoised).
  # Excludes rule cards (right side starts with "*") and known metadata fields.
  def card_ids_with_nav_children
    @card_ids_with_nav_children ||=
      Card.joins("INNER JOIN cards right_c ON right_c.id = cards.right_id")
          .where(trash: false)
          .where.not(left_id: nil)
          .where.not("right_c.name LIKE ?", "*%")
          .where.not("LOWER(right_c.name) IN (?)", NAV_BLOCKED_RIGHTS.to_a)
          .pluck(:left_id)
          .compact.uniq.to_set
  end

  # Memoised list of all readable simple top-level content cards.
  # "Content" = type in [Draft, Published, RichText, Basic], no codename, not a rule card.
  def nav_content_cards
    @nav_content_cards ||= begin
      type_ids = Card.where(name: %w[Draft Published RichText]).pluck(:id)
      Card.where(trash: false, left_id: nil, right_id: nil, codename: nil)
          .where(type_id: type_ids)
          .where.not("cards.name LIKE ?", "*%")
          .order(:name)
          .to_a
          .select { |c| ok_nav_card?(c) && c.ok?(:read) }
    end
  end

  # Content cards that have compound children — these become top-level nav sections.
  def nav_section_cards
    ids = card_ids_with_nav_children
    nav_content_cards.select { |c| ids.include?(c.id) }
  end

  def nav_child_cards(parent)
    return [] unless parent&.real?

    q = { left: parent.name, sort: :name, limit: wiki_nav_child_limit }
    Card.search(q, "wiki_nav_children of #{parent.name}")
        .select { |c| ok_nav_card?(c) && c.ok?(:read) }
  end

  def likely_has_nav_children?(c)
    return false unless c&.real?

    Card.search(
      { left: c.name, limit: 1, return: :id },
      "wiki_nav_child check #{c.name}"
    ).present?
  end

  def ok_nav_card?(c)
    return false if c.blank? || !c.real?
    return false if c.trash
    return false if %w[Image File].include?(c.type_name)

    right = c.name.to_name.right
    return false if right.present? && right.start_with?("*")
    return false if right.present? && NAV_BLOCKED_RIGHTS.include?(right.to_s.downcase.tr("_", " ").strip)
    return false if c.name.simple? && c.name.start_with?("*")

    true
  end

  def wiki_nav_dom_id(card)
    "wiki-nav-ch-#{card.id}"
  end

  def wiki_nav_child_limit
    ENV.fetch("WIKI_NAV_CHILD_LIMIT", "250").to_i.clamp(10, 1000)
  end
end
