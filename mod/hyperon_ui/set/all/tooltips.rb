# frozen_string_literal: true

# Compact tooltip render used by the client-side hover-popover (Phase 1 of
# the Term Tooltips Plan). Served at `/<CardName>?view=tooltip&format=html`.
#
# Body source order (curated only — no weak first-paragraph auto-summaries):
#   1. `+definition` subcard (preferred; doubles as the glossary entry body)
#   2. `+description` subcard (Sandra IndexSubtopic intro paragraph)
# If neither exists the view renders empty and the JS shows no tooltip (I-5).
#
# The term line shows the leaf of a compound name (e.g. "PeTTa" rather than
# "MeTTa Programming Language+PeTTa"). Decko inclusion/link syntax and HTML
# tags are stripped via Nokogiri; result truncated to ~200 chars. cache: :never
# for V1 so edits to a +definition land immediately.

format :html do
  view :tooltip, cache: :never do
    text = tooltip_body_text
    return "" if text.blank?

    wrap_with(:div, class: "wiki-tooltip-body") do
      tag.p(tooltip_term, class: "wiki-tooltip-term") +
        tag.p(text, class: "wiki-tooltip-text")
    end
  end

  private

  # Leaf segment of the (possibly compound) card name.
  def tooltip_term
    card.name.parts.last
  rescue StandardError
    card.name.to_s.split("+").last
  end

  # Plain-text tooltip body (<= ~200 chars, single-line) or nil. Curated
  # subcards only: +definition first, then +description.
  def tooltip_body_text
    raw = curated_definition_content
    return nil if raw.nil? || raw.empty?

    # Strip Decko inclusions/links ({{...}}, [[...]]) before HTML parsing;
    # curated content is stored unrendered.
    stripped = raw.gsub(/\{\{[^}]*\}\}/, " ").gsub(/\[\[[^\]]*\]\]/, " ")
    text = Nokogiri::HTML.fragment(stripped).text.gsub(/\s+/, " ").strip
    return nil if text.empty?

    text.length > 200 ? text[0, 200].rstrip + "…" : text
  end

  # First non-blank curated definition subcard content, or nil.
  def curated_definition_content
    %w[definition description].each do |field|
      sub = Card.fetch("#{card.name}+#{field}")
      return sub.content if sub && sub.content.present?
    end
    nil
  end
end
