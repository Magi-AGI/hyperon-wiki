# frozen_string_literal: true

module Api
  module Mcp
    # Controller for async job operations (spoiler scans, bulk tasks)
    class JobsController < BaseController
      before_action :check_gm_or_admin!, only: [:spoiler_scan]

      # POST /api/mcp/jobs/spoiler-scan
      # Scan for spoiler terms leaking from GM/AI content to player content
      def spoiler_scan
        terms_card_name = params[:terms_card]
        results_card_name = params[:results_card]
        scope = params[:scope] || "player" # "player" or "ai"
        limit = [(params[:limit] || 500).to_i, 1000].min

        return render_error("validation_error", "Missing terms_card parameter") unless terms_card_name
        return render_error("validation_error", "Missing results_card parameter") unless results_card_name

        # Fetch the terms card with proper auth context
        terms_card = Card::Auth.as(current_account.name) do
          Card.fetch(terms_card_name)
        end
        return render_error("not_found", "Terms card '#{terms_card_name}' not found") unless terms_card

        # Extract spoiler terms from the terms card
        spoiler_terms = extract_spoiler_terms(terms_card)
        return render_error("validation_error", "No spoiler terms found in '#{terms_card_name}'") if spoiler_terms.empty?

        # Scan for spoilers
        matches = scan_for_spoilers(spoiler_terms, scope, limit)

        # Write results to results card
        write_results_to_card(results_card_name, spoiler_terms, matches, scope)

        render json: {
          status: "completed",
          matches: matches.size,
          results_card: results_card_name,
          scope: scope,
          terms_checked: spoiler_terms.size
        }
      rescue StandardError => e
        render_error("job_error", "Spoiler scan failed", { error: e.message })
      end

      private

      def check_gm_or_admin!
        unless current_role == "gm" || current_role == "admin"
          render_forbidden("Only GM or admin roles can run spoiler scans")
        end
      end

      def extract_spoiler_terms(terms_card)
        content = terms_card.content || ""
        terms = []

        # Extract terms from different formats:
        # 1. [[term]] wiki links
        content.scan(/\[\[([^\]]+)\]\]/) do |match|
          terms << match[0].strip
        end

        # 2. Bullet list items
        content.scan(/^[-*]\s*(.+)$/m) do |match|
          terms << match[0].strip
        end

        # 3. Line-separated terms
        if terms.empty?
          terms = content.split("\n").map(&:strip).reject(&:empty?)
        end

        # Remove HTML tags and normalize
        terms.map { |t| strip_html(t) }.reject(&:empty?).uniq
      end

      def strip_html(text)
        text.gsub(/<[^>]*>/, '').strip
      end

      def scan_for_spoilers(spoiler_terms, scope, limit)
        matches = []

        # Build search query based on scope
        scope_pattern = case scope
                        when "player"
                          # Exclude +GM and +AI cards
                          nil # We'll filter in code
                        when "ai"
                          # Only +AI cards
                          "+AI"
                        else
                          nil
                        end

        # Search for each spoiler term
        spoiler_terms.each do |term|
          # Search in card content with proper auth context
          query = { content: ["match", term], limit: limit }
          cards = Card::Auth.as(current_account.name) do
            Card.search(query)
          end

          # Filter based on scope
          filtered_cards = filter_cards_by_scope(cards, scope)

          filtered_cards.each do |card|
            # Skip cards the user cannot read (uses Decko's native +*read rules)
            next unless Card::Auth.as(current_account.name) { card.ok?(:read) }

            matches << {
              term: term,
              card_name: card.name,
              card_type: card.type_name,
              snippet: extract_snippet(card.content, term)
            }
          end
        end

        matches
      end

      def filter_cards_by_scope(cards, scope)
        # NOTE: This uses name patterns intentionally for CONTENT CATEGORIZATION, not permissions.
        # The spoiler scan is designed to detect leaks between content categories:
        # - "player" scope: Content intended for players (no +GM or +AI in name)
        # - "ai" scope: Content intended for AI processing (has +AI in name)
        # Actual permission checking is done separately via card.ok?(:read).
        case scope
        when "player"
          # Exclude GM and AI content (by naming convention)
          cards.reject { |c| c.name.include?("+GM") || c.name.include?("+AI") }
        when "ai"
          # Only AI content
          cards.select { |c| c.name.include?("+AI") }
        else
          cards
        end
      end

      def extract_snippet(content, term, context_chars = 100)
        return "" unless content

        # Find the term in content (case-insensitive)
        clean_content = strip_html(content)
        index = clean_content.downcase.index(term.downcase)
        return "" unless index

        # Extract context around the term
        start_pos = [index - context_chars, 0].max
        end_pos = [index + term.length + context_chars, clean_content.length].min

        snippet = clean_content[start_pos...end_pos]

        # Add ellipsis if truncated
        snippet = "...#{snippet}" if start_pos > 0
        snippet = "#{snippet}..." if end_pos < clean_content.length

        snippet
      end

      def write_results_to_card(results_card_name, spoiler_terms, matches, scope)
        # Build HTML results
        html = build_results_html(spoiler_terms, matches, scope)

        # Fetch or create the results card
        card = Card.fetch(results_card_name, new: {})

        # Update with service account permissions
        Card::Auth.as(current_account.name) do
          card.type_id = find_type_by_name("RichText")&.id || Card::BasicID
          card.content = html
          card.save!
        end
      end

      def build_results_html(spoiler_terms, matches, scope)
        parts = []
        parts << "<h2>Spoiler Scan Results</h2>"
        parts << "<p><strong>Scope:</strong> #{scope.capitalize} content</p>"
        parts << "<p><strong>Terms Checked:</strong> #{spoiler_terms.size}</p>"
        parts << "<p><strong>Matches Found:</strong> #{matches.size}</p>"
        parts << "<p><strong>Scan Date:</strong> #{Time.now.utc.strftime('%Y-%m-%d %H:%M:%S UTC')}</p>"
        parts << ""

        if matches.any?
          parts << "<h3>Detected Spoilers</h3>"
          parts << "<ul>"

          # Group by term
          matches.group_by { |m| m[:term] }.each do |term, term_matches|
            parts << "<li><strong>#{term}</strong> (#{term_matches.size} matches)"
            parts << "  <ul>"
            term_matches.each do |match|
              parts << "    <li>[[#{match[:card_name]}]] (#{match[:card_type]})"
              parts << "      <br/><em>#{match[:snippet]}</em>"
              parts << "    </li>"
            end
            parts << "  </ul>"
            parts << "</li>"
          end

          parts << "</ul>"
        else
          parts << "<p><em>No spoilers detected. All clear!</em></p>"
        end

        parts << ""
        parts << "<h3>Checked Terms</h3>"
        parts << "<ul>"
        spoiler_terms.each do |term|
          count = matches.count { |m| m[:term] == term }
          parts << "<li>#{term} (#{count} matches)</li>"
        end
        parts << "</ul>"

        parts.join("\n")
      end

      def find_type_by_name(name)
        Card::Auth.as(current_account.name) do
          type_card = Card.fetch(name)
          return type_card if type_card&.type_id == Card::CardtypeID

          Card.search(type: "Cardtype", name: ["match", name]).first
        end
      end
    end
  end
end
