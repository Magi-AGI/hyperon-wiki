# frozen_string_literal: true

# HtmlFormatUrlFix
# Patches Decko's HtmlFormat render path to post-process the rendered
# RichText HTML and linkify URLs that include Unicode punctuation
# (en-dash, em-dash, ellipsis) by delegating to UrlLinkifier.

module HtmlFormatUrlFix
  def render_content(*args, **kwargs, &block)
    html = super
    if ENV['URLFIX_DEBUG'] == '1' && defined?(Rails)
      Rails.logger.info("[URLFIX] HtmlFormatUrlFix#render_content for card=#{respond_to?(:card) ? card&.name : 'n/a'}")
    end
    begin
      fixed = UrlLinkifier.linkify_html(html)
      fixed
    rescue StandardError => e
      Rails.logger.error("[URLFIX] HtmlFormatUrlFix error: #{e.class}: #{e.message}") if defined?(Rails)
      html
    end
  end

  def render_core(*args, **kwargs, &block)
    html = super
    if ENV['URLFIX_DEBUG'] == '1' && defined?(Rails)
      Rails.logger.info("[URLFIX] HtmlFormatUrlFix#render_core for card=#{respond_to?(:card) ? card&.name : 'n/a'}")
    end
    safe_linkify(html)
  end

  def render_view(*args, **kwargs, &block)
    html = super
    if ENV['URLFIX_DEBUG'] == '1' && defined?(Rails)
      Rails.logger.info("[URLFIX] HtmlFormatUrlFix#render_view for card=#{respond_to?(:card) ? card&.name : 'n/a'}")
    end
    safe_linkify(html)
  end

  private

  def safe_linkify(html)
    return html unless html.is_a?(String)
    # quick heuristic to avoid unnecessary parsing
    sniff = !!(html =~ /(https?:\/\/|www\.|\b(?:[a-z0-9-]+\.)+[a-z]{2,}(?=\/|\?|#))/i)
    return html unless sniff
    UrlLinkifier.linkify_html(html)
  rescue StandardError => e
    Rails.logger.error("[URLFIX] HtmlFormatUrlFix safe_linkify error: #{e.class}: #{e.message}") if defined?(Rails)
    html
  end
end
