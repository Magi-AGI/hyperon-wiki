# frozen_string_literal: true

# Compact tooltip render used by the client-side hover-popover (Phase 1 of
# the Term Tooltips Plan). Served at `/<CardName>?view=tooltip&format=html`.
#
# Body source order:
#   1. `+description` subcard if present (preferred — short, curated)
#   2. The card's raw `content` (stored body), stripped to plain text
#
# We read `card.content` directly rather than rendering the :core view so we
# don't pick up Draft-banner chrome or other view wrappers. Inclusions and
# inline HTML are stripped via Nokogiri text(); result is truncated to ~200
# chars with an ellipsis. Cache mode is :never for V1 so edits land instantly.

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
    raw = (desc&.content || card.content).to_s
    return nil if raw.empty?

    # Strip Decko inclusions/links ({{...}}, [[...]]) before HTML parsing —
    # card.content is stored unrendered, so these would otherwise leak as
    # literal text through Nokogiri's text() pass.
    stripped = raw.gsub(/\{\{[^}]*\}\}/, " ").gsub(/\[\[[^\]]*\]\]/, " ")
    text = Nokogiri::HTML.fragment(stripped).text.gsub(/\s+/, " ").strip
    return nil if text.empty?

    text.length > 200 ? text[0, 200].rstrip + "…" : text
  end
end
