# frozen_string_literal: true

# Compact tooltip render used by the client-side hover-popover (Phase 1 of
# the Term Tooltips Plan). Served at `/<CardName>?view=tooltip&format=html`.
#
# Body source order:
#   1. `+description` subcard if present (preferred — short, curated)
#   2. The card's own rendered :core view, stripped to plain text, first ~200 chars
#
# Returns plain-text inside a small HTML envelope; no inclusions, no links.
# Cache mode is :never for V1 so editing a `+description` is immediately
# visible. Promote to :standard once the client cache contract is settled.

format :html do
  view :tooltip, cache: :never do
    text = tooltip_body_text
    return "" if text.blank?

    wrap_with(:div, class: "wiki-tooltip-body") do
      tag.p(card.name, class: "wiki-tooltip-term") +
        tag.p(text, class: "wiki-tooltip-text")
    end
  end

  private

  # Returns the plain-text tooltip body (≤ ~200 chars, single-line) or nil.
  def tooltip_body_text
    desc = Card.fetch([card.name, :description])
    rendered_html = if desc
                      desc.format(:html).render(:core).to_s
                    else
                      render(:core).to_s
                    end
    text = Nokogiri::HTML.fragment(rendered_html).text.gsub(/\s+/, " ").strip
    return nil if text.empty?

    text.length > 200 ? text[0, 200].rstrip + "…" : text
  end
end
