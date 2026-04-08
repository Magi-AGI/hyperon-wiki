# frozen_string_literal: true

# Math rendering support via KaTeX
#
# Injects KaTeX CSS/JS into page <head> and registers a decko.slot.ready
# callback to render math after AJAX card loads.
#
# Supports \(...\) for inline math and \[...\] for display math.
# Content authors (human or agent) write these delimiters directly in
# card content (RichText HTML or Markdown).
#
# For Markdown cards, Kramdown's built-in math parser converts $$...$$ to
# \[...\] (block) and \(...\) (inline) via its MathJax engine, so KaTeX
# picks those up automatically.
#
# VERSION: Decko 0.19.1

Rails.application.config.after_initialize do
  begin
    require_relative '../../mod/math_rendering/lib/math_rendering_head'
  rescue LoadError => e
    Rails.logger.warn "[MATH] MathRenderingHead load failed: #{e.message}"
  end

  if defined?(Card::Format::HtmlFormat) && defined?(MathRenderingHead)
    Card::Format::HtmlFormat.prepend(MathRenderingHead)
    Rails.logger.info "[MATH] MathRenderingHead prepended to Card::Format::HtmlFormat"
  end
end
