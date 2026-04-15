# frozen_string_literal: true

# Right-sidebar views: breadcrumbs and page table of contents.
# Both are composed into view :page_sidebar (defined in layouts.rb).

format :html do
  # Renders Bootstrap breadcrumbs from the compound name hierarchy.
  # "Hyperon+Architecture+Atomspace" → Hyperon > Architecture > Atomspace
  # Simple (top-level) cards return blank — no breadcrumb needed.
  view :breadcrumbs, cache: :never do
    parts = card.name.to_name.part_names
    return "" if parts.size <= 1

    crumbs = parts.map.with_index do |part_name, i|
      label = part_name.to_name.tag.to_s.tr("_", " ")
      if i == parts.size - 1
        tag.li(label, class: "breadcrumb-item active", "aria-current": "page")
      else
        tag.li(link_to_card(part_name, label, known: true), class: "breadcrumb-item")
      end
    end

    tag.nav("aria-label": "breadcrumb", class: "wiki-breadcrumbs mb-3") do
      tag.ol(crumbs.join.html_safe, class: "breadcrumb small")
    end
  end

  # Renders a table of contents by parsing h2/h3/h4 headings from the card's
  # rendered content via Nokogiri (already available in Decko).
  #
  # Headings without id attributes get a generated slug so anchor links work.
  # The heading ids are NOT injected back into the page — a Phase 3 enhancement
  # would add a content post-processor to stamp ids during rendering.
  view :page_toc, cache: :never do
    html = render(:core)
    doc = Nokogiri::HTML::DocumentFragment.parse(html)
    headings = doc.css("h2, h3, h4")
    return "" if headings.empty?

    items = headings.map do |h|
      id = h[:id].presence || slugify(h.text)
      level = h.name[1].to_i - 1 # h2→1, h3→2, h4→3
      tag.li(link_to(h.text.strip, href: "##{id}"),
             class: "toc-#{h.name} ps-#{level * 2}")
    end

    wrap_with(:nav, class: "wiki-toc mb-3", "aria-label": "Page contents") do
      tag.p("Contents", class: "wiki-toc-heading text-muted small text-uppercase mb-1 fw-semibold") +
        tag.ul(items.join.html_safe, class: "list-unstyled")
    end
  end

  private

  def slugify(text)
    text.to_s.strip.downcase.gsub(/[^a-z0-9\-]+/, "-").gsub(/^-+|-+$/, "")
  end
end
