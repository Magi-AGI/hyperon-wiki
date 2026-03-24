# frozen_string_literal: true

# Fix for Decko URL parsing that stops at special punctuation
#
# ISSUE: URLs in richtext cards get cut short when they contain:
#        - Em-dashes (—)
#        - En-dashes (–)
#        - Ellipses (…)
#        Example: "https://example.com–test" only links "https://example.com"
#
# ROOT CAUSE: Ruby's URI::DEFAULT_PARSER.make_regexp stops at these characters
#             because they're not valid URI characters. The existing trailing
#             punctuation handler only checks single ASCII characters.
#
# SOLUTION: Extend the interpret method to detect and strip multi-character
#           punctuation (em-dashes, ellipses) after the URI match.
#
# APPROACH: Instead of modifying the regex (which would be complex), we
#           post-process the matched chunk to look ahead and capture valid
#           URI characters that appear after the initial match but before
#           actual trailing punctuation.

module UriExtensions
  # Extended punctuation patterns that should be treated as trailing
  EXTENDED_TRAILING_PUNCTUATION = [
    "—",  # Em-dash (U+2014)
    "–",  # En-dash (U+2013)
    "…",  # Horizontal ellipsis (U+2026)
    "...", # Three periods
  ].freeze

  # Characters that are valid in URIs but might appear after em-dash/ellipsis
  # This helps us determine where the URL actually ends
  URI_VALID_CHARS = /[A-Za-z0-9\-._~:\/\?#\[\]@!$&'()*+,;=%]/

  def interpret(match_start, content)
    # Call original interpret to get the base URI match
    super

    # Now look ahead from where the original match ended to see if there's
    # more URI content after an em-dash or ellipsis
    extend_past_special_chars(content)

    self
  end

  private

  def extend_past_special_chars(content)
    # Safety check - if @text_range is nil, we can't extend
    return unless @text_range

    # Get the current end position of our match
    current_end = @text_range.end

    # Look at what comes immediately after our current match
    remaining = content[current_end..-1] || ""

    # Check if it starts with an extended punctuation character
    EXTENDED_TRAILING_PUNCTUATION.each do |punct|
      next unless remaining.start_with?(punct)

      # Found one - now see if there's more URI content after it
      after_punct = remaining[punct.length..-1]

      # Extract any valid URI characters that follow
      if (match = after_punct.match(/\A(#{URI_VALID_CHARS}+)/))
        extended_content = punct + match[1]

        # Check if this extended content ends with simple trailing punctuation
        # that we should strip off
        if extended_content =~ /([,.!?:;]+)\z/
          trailing = Regexp.last_match(1)
          extended_content = extended_content[0...-trailing.length]
          @trailing_punctuation = trailing
        end

        # Update our text and range to include the extended content
        @text += extended_content
        @text_range = (@text_range.begin...(@text_range.end + extended_content.length))
      else
        # The punct is truly trailing punctuation, not part of URL
        @trailing_punctuation = punct
      end

      break # Only process the first matching punctuation
    end
  end
end
