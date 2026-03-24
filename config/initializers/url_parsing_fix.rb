# frozen_string_literal: true

# Fix for URL parsing that stops at em-dashes and ellipses
#
# This initializer loads the URI extensions that allow URLs containing
# em-dashes (—) and ellipses (…) to be properly parsed and linked in
# richtext cards.
#
# TESTING:
# After applying this fix, URLs like these should be fully linked:
# - https://example.com—test
# - https://example.com/path…more
# - https://example.com/page—with-dash/end
#
# TO TEST AFTER UPDATES:
# 1. Create a richtext card with test URLs containing em-dashes and ellipses
# 2. Verify the entire URL (up to the actual trailing punctuation) is clickable
# 3. Check logs if issues occur
#
# VERSION: Decko 0.19.1 (as of 2025-11-06)

Rails.application.config.after_initialize do
  require_relative '../../mod/url_fixes/lib/card/content/chunk/uri_extensions'
  # HTML linkifier (RichText rendering path)
  begin
    require_relative '../../mod/url_fixes/lib/url_linkifier'
    require_relative '../../mod/url_fixes/lib/html_format_url_fix'
  rescue LoadError => e
    Rails.logger.warn "[URLFIX] Linkifier load failed: #{e.message}"
  end

  if defined?(Card::Content::Chunk::Uri)
    Card::Content::Chunk::Uri.prepend(UriExtensions)
    Rails.logger.info "=== UriExtensions module prepended to Card::Content::Chunk::Uri"
  end

  # Prepend HtmlFormat patch so RichText HTML output is post-processed
  if defined?(Card::Format::HtmlFormat) && defined?(HtmlFormatUrlFix)
    Card::Format::HtmlFormat.prepend(HtmlFormatUrlFix)
    Rails.logger.info "[URLFIX] HtmlFormatUrlFix prepended to Card::Format::HtmlFormat"
  end
end
