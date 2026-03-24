# frozen_string_literal: true

require "kramdown"
require "reverse_markdown"

module McpApi
  class MarkdownConverter
    class << self
      # Convert Markdown to Decko-safe HTML
      # Preserves wiki links [[Card+Name|Label]]
      def markdown_to_html(markdown)
        return "" if markdown.nil? || markdown.empty?

        # Step 1: Protect wiki links by temporarily replacing them
        # Use HTML comment format which won't be escaped by markdown processors
        wiki_links = {}
        protected_markdown = markdown.gsub(/\[\[(.*?)\]\]/) do |match|
          key = "WIKILINK#{wiki_links.size}ENDWIKI"
          wiki_links[key] = match
          key
        end

        # Step 2: Convert Markdown to HTML using kramdown
        doc = Kramdown::Document.new(protected_markdown, kramdown_options)
        html = doc.to_html

        # Step 3: Restore wiki links (before sanitization)
        wiki_links.each do |key, link|
          html.gsub!(key, link)
        end

        # Step 4: Basic sanitization (remove script/style tags)
        sanitize_html(html)
      end

      # Convert HTML to Markdown
      # Preserves wiki links [[Card+Name|Label]]
      def html_to_markdown(html)
        return "" if html.nil? || html.empty?

        # Step 1: Protect wiki links
        wiki_links = {}
        protected_html = html.gsub(/\[\[(.*?)\]\]/) do |match|
          key = "WIKILINK#{wiki_links.size}ENDWIKI"
          wiki_links[key] = match
          key
        end

        # Step 2: Convert HTML to Markdown
        markdown = ReverseMarkdown.convert(
          protected_html,
          reverse_markdown_options
        )

        # Step 3: Restore wiki links
        wiki_links.each do |key, link|
          markdown.gsub!(key, link)
        end

        markdown
      end

      private

      def kramdown_options
        {
          input: "kramdown", # Use standard kramdown (GFM requires kramdown-parser-gfm gem)
          hard_wrap: false,
          auto_ids: false, # Don't generate IDs for headers
          entity_output: :as_char,
          syntax_highlighter: nil, # Disable syntax highlighting for simplicity
          gfm_quirks: [:paragraph_end] # Enable some GFM-like behavior
        }
      end

      def reverse_markdown_options
        {
          unknown_tags: :pass_through,
          github_flavored: true
        }
      end

      def sanitize_html(html)
        # Use Rails' built-in sanitization for comprehensive XSS prevention
        # Allows safe HTML tags and attributes, strips script tags, javascript: URLs,
        # inline event handlers, and other XSS vectors
        ActionController::Base.helpers.sanitize(html, tags: allowed_tags, attributes: allowed_attributes)
      end

      def allowed_tags
        # Decko-safe HTML tags
        %w[
          p br div span h1 h2 h3 h4 h5 h6
          ul ol li dl dt dd
          strong em b i u s strike del ins
          a img
          blockquote pre code
          table thead tbody tr th td
          hr
        ]
      end

      def allowed_attributes
        # Decko-safe HTML attributes (no javascript: URLs or event handlers)
        %w[
          href src alt title
          class id
          colspan rowspan
          width height
        ]
      end
    end
  end
end
