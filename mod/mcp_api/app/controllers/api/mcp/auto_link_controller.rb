# frozen_string_literal: true

module Api
  module Mcp
    class AutoLinkController < BaseController
      before_action :require_gm_or_admin

      # POST /api/mcp/auto_link
      # Analyze card content and suggest or apply wiki links
      def create
        card_name = params[:card_name]
        mode = params[:mode] || "suggest"
        dry_run = params[:dry_run] != false && params[:dry_run] != "false"

        unless card_name.present?
          return render json: { error: "card_name is required" }, status: :bad_request
        end

        unless %w[suggest apply].include?(mode)
          return render json: { error: "mode must be 'suggest' or 'apply'" }, status: :bad_request
        end

        card = Card.fetch(card_name)
        unless card
          return render json: { error: "Card not found: #{card_name}" }, status: :not_found
        end

        # Extract options
        options = {
          scope: params[:scope] || derive_scope(card_name),
          min_term_length: (params[:min_term_length] || 3).to_i,
          include_types: params[:include_types],
          case_sensitive: params[:case_sensitive] == true || params[:case_sensitive] == "true"
        }

        # Build term index for the scope
        term_index = build_term_index(options[:scope], options)

        # Scan content for potential links
        suggestions = scan_for_links(card, term_index, options)

        if mode == "suggest" || dry_run
          render json: {
            card_name: card_name,
            scope: options[:scope],
            mode: mode,
            dry_run: dry_run,
            suggestions: suggestions,
            preview: dry_run ? generate_preview(card.content, suggestions) : nil,
            stats: {
              terms_in_index: term_index.size,
              suggestions_found: suggestions.size,
              unique_cards_referenced: suggestions.map { |s| s[:matching_card] }.uniq.size
            }
          }
        else
          # Apply the links
          new_content = apply_links(card.content, suggestions)

          Card::Auth.as(current_account.name) do
            card.update!(content: new_content)
          end

          render json: {
            card_name: card_name,
            scope: options[:scope],
            mode: mode,
            dry_run: false,
            applied: suggestions.size,
            new_content: new_content,
            stats: {
              terms_in_index: term_index.size,
              links_applied: suggestions.size,
              unique_cards_referenced: suggestions.map { |s| s[:matching_card] }.uniq.size
            }
          }
        end
      rescue StandardError => e
        Rails.logger.error "AutoLink error: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
        render json: { error: e.message }, status: :internal_server_error
      end

      private

      # Derive scope from card name (top 2 left parts)
      def derive_scope(card_name)
        parts = card_name.split("+")
        return card_name if parts.size <= 2
        parts.first(2).join("+")
      end

      # Build a term index from cards within the scope
      def build_term_index(scope, options)
        index = {}

        # Get cards and build index
        Card::Auth.as(current_account.name) do
          cards = if scope.present?
                    # Decko stores compound card names via left_id/right_id relationships,
                    # not in the name column. We need to find all descendants recursively.
                    scope_card = Card.fetch(scope)
                    return index unless scope_card

                    # Use recursive left_id traversal to find all descendants
                    scope_prefix = "#{scope}+"
                    find_all_descendants(scope_card).map(&:name)
                  else
                    Card.search(limit: 2000, return: :name)
                  end

          cards.each do |name|
            next if name == scope  # Skip the scope card itself

            # Filter by type if specified
            if options[:include_types].present?
              card = Card.fetch(name)
              next unless card && options[:include_types].include?(card.type_name)
            end

            # Extract indexable parts from the name
            indexable_parts = extract_indexable_parts(name, scope)

            indexable_parts.each do |part|
              next if part.length < options[:min_term_length]
              next if stopword?(part)

              key = options[:case_sensitive] ? part : part.downcase
              index[key] ||= []
              index[key] << { term: part, full_name: name }
            end
          end
        end

        # Deduplicate entries - keep only the shortest full_name for each term
        index.each do |key, matches|
          index[key] = matches.uniq { |m| m[:full_name] }
        end

        index
      end

      # Extract parts of the name that should be indexed
      def extract_indexable_parts(card_name, scope)
        parts = card_name.split("+")
        scope_parts = scope.to_s.split("+")

        # Remove scope prefix parts
        remaining = parts.drop(scope_parts.size)

        # Return individual parts, excluding system/meta parts
        result = []
        remaining.each do |part|
          # Skip system parts that shouldn't be linked
          next if part.match?(/^(GM|AI|Player|legacy|roots|tags|TOC|Summary)$/i)
          # Skip parts that are just numbers or very short
          next if part.match?(/^\d+$/)
          result << part
        end

        result.uniq
      end

      # Scan card content for potential links
      def scan_for_links(card, term_index, options)
        content = card.content.to_s
        suggestions = []

        # Skip if content is empty
        return suggestions if content.blank?

        # Remove HTML tags for text analysis but track positions
        text_content = strip_html_preserve_positions(content)

        # Extract existing links to skip
        existing_links = extract_existing_links(content)

        return suggestions if term_index.empty?

        # Scan content for each term in the index
        term_index.each do |key, matches|
          term = matches.first[:term]

          # Build pattern - word boundary matching
          pattern = options[:case_sensitive] ? /\b#{Regexp.escape(term)}\b/ : /\b#{Regexp.escape(term)}\b/i

          # Find all occurrences
          content.scan(pattern) do
            match_data = Regexp.last_match
            position = match_data.begin(0)
            matched_text = match_data[0]

            # Skip if this position is inside an existing link
            next if inside_existing_link?(position, existing_links)

            # Skip if inside HTML tag
            next if inside_html_tag?(content, position)

            # Skip if this is a self-reference
            next if matches.any? { |m| m[:full_name] == card.name }

            # Find the best matching card
            best_match = find_best_match(matches, matched_text)

            # Extract context around the match
            context = extract_context(content, position, matched_text.length)

            suggestions << {
              term: matched_text,
              matching_card: best_match[:full_name],
              position: position,
              context: context,
              display_name: best_match[:term]
            }
          end
        end

        # Remove duplicates and sort by position
        suggestions.uniq { |s| [s[:position], s[:term].downcase] }
                   .sort_by { |s| s[:position] }
      end

      # Strip HTML tags but this is simplified - just for analysis
      def strip_html_preserve_positions(content)
        content.gsub(/<[^>]+>/, ' ')
      end

      # Check if position is inside an HTML tag
      def inside_html_tag?(content, position)
        # Look backwards for < or >
        before = content[0...position]
        last_open = before.rindex('<')
        last_close = before.rindex('>')

        # If there's an open tag after the last close, we're inside a tag
        return false if last_open.nil?
        return false if last_close && last_close > last_open
        true
      end

      # Extract existing wiki links from content
      def extract_existing_links(content)
        links = []
        content.scan(/\[\[([^\]]+)\]\]/) do
          match_data = Regexp.last_match
          links << {
            start: match_data.begin(0),
            end: match_data.end(0),
            text: match_data[1]
          }
        end
        links
      end

      # Check if a position is inside an existing link
      def inside_existing_link?(position, existing_links)
        existing_links.any? { |link| position >= link[:start] && position < link[:end] }
      end

      # Find the best matching card for a term
      def find_best_match(matches, matched_text)
        # Prefer exact case match
        exact = matches.find { |m| m[:term] == matched_text }
        return exact if exact

        # Otherwise return the one with the shortest full name (most specific)
        matches.min_by { |m| m[:full_name].length }
      end

      # Extract context around a match
      def extract_context(content, position, match_length, context_size = 50)
        context_start = [position - context_size, 0].max
        context_end = [position + match_length + context_size, content.length].min
        context = content[context_start...context_end]

        # Clean up HTML in context for readability
        context = context.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip

        prefix = context_start > 0 ? "..." : ""
        suffix = context_end < content.length ? "..." : ""
        "#{prefix}#{context}#{suffix}"
      end

      # Generate a preview of the content with links applied
      def generate_preview(content, suggestions)
        return content if suggestions.empty?

        # Apply links in reverse position order to maintain positions
        result = content.dup
        suggestions.sort_by { |s| -s[:position] }.each do |suggestion|
          term = suggestion[:term]
          position = suggestion[:position]
          matching_card = suggestion[:matching_card]

          # Create the link - use display text if term differs from card name's last part
          card_display = matching_card.split("+").last
          if card_display.downcase == term.downcase
            link = "[[#{matching_card}]]"
          else
            link = "[[#{matching_card}|#{term}]]"
          end

          result[position, term.length] = link
        end

        result
      end

      # Apply links to content
      def apply_links(content, suggestions)
        generate_preview(content, suggestions)
      end

      # Stopwords - common words that should never be linked
      STOPWORDS = Set.new(%w[
        a an the
        and or but nor yet so for
        of in on at to from by with as
        is are was were be been being am
        have has had do does did
        will would shall should can could may might must
        i you he she it we they me him her us them
        my your his its our their mine yours hers ours theirs
        this that these those
        what which who whom whose when where why how
        all any both each few more most other some such
        no not only own same than too very just
        also still even again already always never often sometimes
        about above across after against along among around
        before behind below beneath beside between beyond
        down during except inside into near off onto
        out outside over past since through throughout
        under until up upon within without
        here there everywhere nowhere somewhere anywhere
        today tomorrow yesterday now then soon later
        one two three four five six seven eight nine ten
        first second third last next
        new old good bad great small large long short
        many much little few several
        said says say told tell tells
        know knows knew known think thinks thought
        see sees saw seen look looks looked
        come comes came want wants wanted
        get gets got give gives gave
        make makes made take takes took
        go goes went find finds found
        use uses used seem seems seemed
        become becomes became keep keeps kept
        let lets leave leaves left begin begins began
        part parts thing things time times way ways
        day days year years world people
        however therefore moreover furthermore nevertheless
        although though while whereas because since unless
        like also well back even still
      ]).freeze

      # Recursively find all descendant cards by following left_id
      def find_all_descendants(parent_card, max_depth: 10)
        return [] unless parent_card
        
        descendants = []
        to_process = [parent_card]
        processed_ids = Set.new([parent_card.id])
        depth = 0
        
        while to_process.any? && depth < max_depth
          current_batch = to_process
          to_process = []
          depth += 1
          
          current_batch.each do |card|
            children = Card.where(left_id: card.id).where(trash: false).to_a
            children.each do |child|
              next if processed_ids.include?(child.id)
              processed_ids.add(child.id)
              descendants << child
              to_process << child
            end
          end
        end
        
        descendants
      end

      def stopword?(term)
        STOPWORDS.include?(term.downcase)
      end

      def require_gm_or_admin
        unless %w[gm admin].include?(current_role)
          render json: { error: "GM or Admin role required" }, status: :forbidden
        end
      end
    end
  end
end
