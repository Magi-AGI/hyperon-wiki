# frozen_string_literal: true

module Api
  module Mcp
    class CardsController < BaseController
      before_action :set_card, only: [:show, :update, :destroy, :children, :referers, :nested_in, :nests, :links, :linked_by]
      before_action :check_admin_role!, only: [:destroy]

      # GET /api/mcp/cards
      # Search/list cards with filters
      def index
        query = build_search_query
        limit = [(params[:limit] || 50).to_i, 100].min
        offset = (params[:offset] || 0).to_i

        cards = execute_search(query, limit, offset)
        total = count_search_results(query)

        render json: {
          cards: cards.map { |c| card_summary_json(c) },
          total: total,
          limit: limit,
          offset: offset,
          next_offset: (offset + limit < total ? offset + limit : nil)
        }
      end

      # GET /api/mcp/cards/:name
      # Get single card with full content
      def show
        return render_forbidden_gm_content unless can_view_card?(@card)

        render json: card_full_json(@card)
      end

      # POST /api/mcp/cards
      # Create new card
      def create
        name = params[:name]
        return render_error("validation_error", "Missing name") unless name

        type_name = params[:type]
        return render_error("validation_error", "Missing type") unless type_name

        type_card = find_type_by_name(type_name)
        return render_error("not_found", "Type '#{type_name}' not found") unless type_card

        content = prepare_content(params[:content], params[:markdown_content])

        # Create card with service account permissions
        card = Card::Auth.as(current_account.name) do
          Card.create!(
            name: name,
            type_id: type_card.id,
            content: content
          )
        end

        render json: card_full_json(card), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_error("validation_error", "Card validation failed", { errors: e.record.errors.full_messages })
      end

      # PATCH /api/mcp/cards/:name
      # Update existing card
      def update
        return render_forbidden_gm_content unless can_modify_card?(@card)

        Card::Auth.as(current_account.name) do
          if params[:patch]
            apply_patch(@card, params[:patch])
          else
            content = prepare_content(params[:content], params[:markdown_content])
            @card.content = content if content
            @card.save!
          end
        end

        render json: card_full_json(@card)
      rescue ActiveRecord::RecordInvalid => e
        render_error("validation_error", "Update failed", { errors: e.record.errors.full_messages })
      end

      # DELETE /api/mcp/cards/:name
      # Delete card (admin only)
      def destroy
        Card::Auth.as(current_account.name) do
          @card.delete!
        end

        render json: { status: "deleted", name: @card.name }, status: :ok
      rescue StandardError => e
        render_error("delete_failed", "Could not delete card", { error: e.message })
      end

      # GET /api/mcp/cards/:name/children
      # List children cards
      def children
        return render_forbidden_gm_content unless can_view_card?(@card)

        limit = [(params[:limit] || 50).to_i, 100].min
        offset = (params[:offset] || 0).to_i
        depth = (params[:depth] || 1).to_i

        children_cards = fetch_children(@card, depth: depth).select { |c| can_view_card?(c) }

        # Apply pagination
        total = children_cards.size
        paginated_children = children_cards.drop(offset).take(limit)

        render json: {
          parent: @card.name,
          children: paginated_children.map { |c| card_full_json(c) },
          child_count: total,
          depth: depth,
          limit: limit,
          offset: offset
        }
      end

      # GET /api/mcp/cards/:name/referers
      # List cards that reference/link to this card
      def referers
        return render_forbidden_gm_content unless can_view_card?(@card)

        referer_cards = fetch_referers(@card).select { |c| can_view_card?(c) }

        render json: {
          card: @card.name,
          referers: referer_cards.map { |c| card_summary_json(c) },
          referer_count: referer_cards.size
        }
      end

      # GET /api/mcp/cards/:name/nested_in
      # List cards that nest/include this card
      def nested_in
        return render_forbidden_gm_content unless can_view_card?(@card)

        nesting_cards = fetch_nested_in(@card).select { |c| can_view_card?(c) }

        render json: {
          card: @card.name,
          nested_in: nesting_cards.map { |c| card_summary_json(c) },
          nested_in_count: nesting_cards.size
        }
      end

      # GET /api/mcp/cards/:name/nests
      # List cards that this card nests/includes
      def nests
        return render_forbidden_gm_content unless can_view_card?(@card)

        nested_cards = fetch_nests(@card).select { |c| can_view_card?(c) }

        render json: {
          card: @card.name,
          nests: nested_cards.map { |c| card_summary_json(c) },
          nests_count: nested_cards.size
        }
      end

      # GET /api/mcp/cards/:name/links
      # List cards that this card links to
      def links
        return render_forbidden_gm_content unless can_view_card?(@card)

        linked_cards = fetch_links(@card).select { |c| can_view_card?(c) }

        render json: {
          card: @card.name,
          links: linked_cards.map { |c| card_summary_json(c) },
          links_count: linked_cards.size
        }
      end

      # GET /api/mcp/cards/:name/linked_by
      # List cards that link to this card
      def linked_by
        return render_forbidden_gm_content unless can_view_card?(@card)

        linking_cards = fetch_linked_by(@card).select { |c| can_view_card?(c) }

        render json: {
          card: @card.name,
          linked_by: linking_cards.map { |c| card_summary_json(c) },
          linked_by_count: linking_cards.size
        }
      end

      # POST /api/mcp/cards/batch
      # Batch create/update operations
      def batch
        ops = params[:ops] || []
        return render_error("validation_error", "Missing ops array") if ops.empty?
        return render_error("validation_error", "Too many operations", { max: 100 }) if ops.size > 100

        mode = params[:mode] || "per_item"
        results = []

        if mode == "transactional"
          Card.transaction do
            results = process_batch_ops(ops)
            raise ActiveRecord::Rollback if results.any? { |r| r[:status] == "error" }
          end
        else
          results = process_batch_ops(ops)
        end

        # Return 207 Multi-Status if mixed results
        status = results.all? { |r| r[:status] == "ok" } ? :ok : 207
        render json: { results: results }, status: status
      end

      private

      def set_card
        name = params[:name]
        @card = Card::Auth.as(current_account.name) do
          Card.fetch(name)
        end

        unless @card
          render_error("not_found", "Card '#{name}' not found", {}, status: :not_found)
        end
      end

      def check_admin_role!
        unless current_role == "admin"
          render_forbidden("Only admin role can delete cards")
        end
      end

      def can_view_card?(card)
        # User role cannot see GM or AI content
        return false if current_role == "user" && (card.name.include?("+GM") || card.name.include?("+AI"))

        true
      end

      def can_modify_card?(card)
        # Same rules as viewing for now
        can_view_card?(card)
      end

      def render_forbidden_gm_content
        render_forbidden(
          "Role '#{current_role}' cannot access GM content",
          { card: @card.name, required_role: "gm" }
        )
      end

      def build_search_query
        query = {}

        # Handle search_in parameter for name/content/both search
        if params[:q]
          search_in = params[:search_in] || "name"  # Default to name search for backward compatibility

          case search_in
          when "content"
            # Search in content only
            query[:content] = ["match", params[:q]]
          when "both"
            # Search in both name and content using OR condition
            query[:or] = {
              name: ["match", params[:q]],
              content: ["match", params[:q]]
            }
          else  # "name" or any other value defaults to name search
            # Search in name only (default, fastest)
            query[:name] = ["match", params[:q]]
          end
        end

        query[:name] = ["starts_with", params[:prefix]] if params[:prefix]
        query[:type] = params[:type] if params[:type]

        if params[:not_name]
          # Simple glob pattern support
          pattern = params[:not_name].gsub("*", "%")
          query[:not] = { name: ["like", pattern] }
        end

        # Handle date range queries
        # NOTE: Decko CQL does NOT support updated_at/created_at filtering at all
        # See: https://decko.org/CQL_Syntax - only id, name, type, content are queryable
        # We must fetch all cards matching other criteria and filter by date in Ruby
        if params[:updated_since] || params[:updated_before]
          @filter_date_range = {}
          @filter_date_range[:since] = Time.parse(params[:updated_since]) if params[:updated_since]
          @filter_date_range[:before] = Time.parse(params[:updated_before]) if params[:updated_before]
          # Sort by update descending to get recent cards first (helps with pagination)
          query[:sort] = "update"
          query[:dir] = "desc"
        end

        query
      end

      def execute_search(query, limit, offset)
        # Execute search with proper auth context
        cards = Card::Auth.as(current_account.name) do
          Card.search(query.merge(limit: limit, offset: offset))
        end

        # Apply date range post-filter if needed
        # Required because Decko CQL doesn't support updated_at filtering
        if @filter_date_range
          cards = cards.select do |c|
            in_range = true
            in_range = in_range && (c.updated_at >= @filter_date_range[:since]) if @filter_date_range[:since]
            in_range = in_range && (c.updated_at <= @filter_date_range[:before]) if @filter_date_range[:before]
            in_range
          end
        end

        # Filter out GM/AI content for user role
        if current_role == "user"
          cards.reject { |c| c.name.include?("+GM") || c.name.include?("+AI") }
        else
          cards
        end
      end

      def count_search_results(query)
        Card::Auth.as(current_account.name) do
          Card.search(query.merge(return: "count"))
        end
      end

      def find_type_by_name(name)
        Card::Auth.as(current_account.name) do
          type_card = Card.fetch(name)
          return type_card if type_card&.type_id == Card::CardtypeID

          Card.search(type: "Cardtype", name: ["match", name]).first
        end
      end

      def prepare_content(content, markdown_content)
        return content if content

        if markdown_content
          convert_markdown_to_html(markdown_content)
        end
      end

      def convert_markdown_to_html(markdown)
        # Simple Markdown-to-HTML conversion preserving [[...]] links
        # Phase 1: Basic conversion; Phase 2: Use proper markdown gem
        html = markdown.dup

        # Preserve wiki links by temporarily replacing them
        wiki_links = {}
        html.gsub!(/\[\[(.*?)\]\]/) do |match|
          key = "__WIKILINK_#{wiki_links.size}__"
          wiki_links[key] = match
          key
        end

        # Convert basic markdown
        html.gsub!(/^# (.+)$/, '<h1>\1</h1>')
        html.gsub!(/^## (.+)$/, '<h2>\1</h2>')
        html.gsub!(/^### (.+)$/, '<h3>\1</h3>')
        html.gsub!(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
        html.gsub!(/\*(.+?)\*/, '<em>\1</em>')
        html.gsub!(/^- (.+)$/, '<li>\1</li>')

        # Wrap paragraphs
        lines = html.split("\n").reject(&:empty?)
        html = lines.map { |line|
          line.match?(/^<[h\d|li]/) ? line : "<p>#{line}</p>"
        }.join("\n")

        # Restore wiki links
        wiki_links.each do |key, link|
          html.gsub!(key, link)
        end

        html
      end

      def apply_patch(card, patch_params)
        mode = patch_params[:mode]

        case mode
        when "replace_between"
          apply_replace_between(card, patch_params)
        else
          render_error("validation_error", "Unknown patch mode: #{mode}")
        end
      end

      def apply_replace_between(card, patch_params)
        start_marker = patch_params[:start_marker]
        end_marker = patch_params[:end_marker]
        replacement = patch_params[:replacement_html]
        end_inclusive = patch_params[:end_inclusive] != false

        content = card.content
        start_idx = content.index(start_marker)

        unless start_idx
          return render_error("validation_error", "Start marker not found", { marker: start_marker })
        end

        end_idx = content.index(end_marker, start_idx + start_marker.length)

        unless end_idx
          return render_error("validation_error", "End marker not found", { marker: end_marker })
        end

        # Adjust end index based on end_inclusive flag
        end_idx += end_marker.length if end_inclusive

        new_content = content[0...start_idx] + replacement + content[end_idx..-1]
        card.content = new_content
        card.save!
      end

      def process_batch_ops(ops)
        ops.map do |op|
          process_single_op(op)
        rescue StandardError => e
          {
            status: "error",
            name: op["name"],
            message: e.message
          }
        end
      end

      def process_single_op(op)
        action = op["action"]
        name = op["name"]

        case action
        when "create"
          process_create_op(op)
        when "update"
          process_update_op(op)
        else
          { status: "error", name: name, message: "Unknown action: #{action}" }
        end
      end

      def process_create_op(op)
        name = op["name"]
        type_name = op["type"]
        content = prepare_content(op["content"], op["markdown_content"])
        fetch_or_init = op["fetch_or_initialize"]

        type_card = find_type_by_name(type_name)
        return { status: "error", name: name, message: "Type not found: #{type_name}" } unless type_card

        Card::Auth.as(current_account.name) do
          if fetch_or_init
            card = Card.fetch(name, new: {})
            card.type_id = type_card.id
            card.content = content if content
            card.save!
          else
            card = Card.create!(name: name, type_id: type_card.id, content: content)
          end

          # Create children if specified
          create_children(card, op["children"]) if op["children"]

          { status: "ok", name: card.name, id: card.id }
        end
      rescue StandardError => e
        { status: "error", name: name, message: e.message }
      end

      def process_update_op(op)
        name = op["name"]
        card = Card.fetch(name)

        return { status: "error", name: name, message: "Card not found" } unless card

        Card::Auth.as(current_account.name) do
          if op["patch"]
            apply_patch(card, op["patch"])
          else
            content = prepare_content(op["content"], op["markdown_content"])
            card.content = content if content
            card.save!
          end

          { status: "ok", name: card.name, id: card.id }
        end
      rescue StandardError => e
        { status: "error", name: name, message: e.message }
      end

      def create_children(parent_card, children_specs)
        children_specs.each do |child_spec|
          child_name = child_spec["name"]

          # Prepend parent name if child name starts with *
          if child_name.start_with?("*")
            child_name = "#{parent_card.name}+#{child_name}"
          end

          type_name = child_spec["type"]
          type_card = find_type_by_name(type_name)
          next unless type_card

          content = prepare_content(child_spec["content"], child_spec["markdown_content"])

          Card.create!(
            name: child_name,
            type_id: type_card.id,
            content: content
          )
        end
      end

      def card_summary_json(card)
        {
          name: card.name,
          id: card.id,
          type: card.type_name,
          updated_at: card.updated_at.iso8601
        }
      end

      def card_full_json(card)
        {
          name: card.name,
          id: card.id,
          type: card.type_name,
          codename: card.codename,
          content: card.content,
          updated_at: card.updated_at.iso8601,
          created_at: card.created_at.iso8601
        }
      end

      # Fetch cards that reference/link to the given card
      def fetch_referers(card)
        # Use Decko's referers method if available, otherwise search for cards containing this card's name
        Card::Auth.as(current_account.name) do
          if card.respond_to?(:referers)
            card.referers
          else
            # Fallback: search for cards containing references to this card
            # Use regex to match complete link syntax and prevent false positives
            # Matches: [[CardName]] or [[CardName|Display Text]]
            # Does NOT match [[CardName Suffix]] (prevents "Apple" matching "Apple Pie")
            escaped_name = Regexp.escape(card.name)
            link_pattern = "\\[\\[#{escaped_name}(?:\\|[^\\]]+)?\\]\\]"
            Card.search(content: ["match", link_pattern], limit: 100)
          end
        end
      rescue StandardError
        []
      end

      # Fetch cards that nest/include the given card
      def fetch_nested_in(card)
        # Use Decko's nested_in or includees method if available
        Card::Auth.as(current_account.name) do
          if card.respond_to?(:nested_in)
            card.nested_in
          elsif card.respond_to?(:includees)
            card.includees
          else
            # Fallback: search for cards containing nest syntax {{cardname}}
            # Use regex to match complete nest syntax and prevent false positives
            # Matches: {{CardName}} exactly
            # Does NOT match {{CardName Suffix}} (prevents "Apple" matching "Apple Pie")
            escaped_name = Regexp.escape(card.name)
            nest_pattern = "\\{\\{#{escaped_name}\\}\\}"
            Card.search(content: ["match", nest_pattern], limit: 100)
          end
        end
      rescue StandardError
        []
      end

      # Fetch cards that this card nests/includes
      def fetch_nests(card)
        # Use Decko's nests or includes method if available
        if card.respond_to?(:nests)
          card.nests
        elsif card.respond_to?(:includes)
          card.includes
        else
          # Fallback: parse card content for {{...}} syntax
          content = card.content || ""
          nest_pattern = /\{\{([^}]+)\}\}/
          names = content.scan(nest_pattern).flatten.map(&:strip)
          names.map { |name| Card.fetch(name) }.compact
        end
      rescue StandardError
        []
      end

      # Fetch cards that this card links to
      def fetch_links(card)
        # Use Decko's links method if available
        if card.respond_to?(:links)
          card.links
        else
          # Fallback: parse card content for [[...]] syntax
          content = card.content || ""
          link_pattern = /\[\[([^\]]+)\]\]/
          names = content.scan(link_pattern).flatten.map(&:strip)
          names.map { |name| Card.fetch(name) }.compact
        end
      rescue StandardError
        []
      end

      # Fetch cards that link to this card
      def fetch_linked_by(card)
        # Same as referers for now
        fetch_referers(card)
      end

      # Fetch child cards using Decko's left_id relationship
      # In Decko, child cards have left_id pointing to parent card's id
      # E.g., "Parent+Child" has left_id = Parent.id
      def fetch_children(card, depth: 1)
        # Check for Decko built-in methods first
        if card.respond_to?(:children)
          return card.children
        elsif card.respond_to?(:parts)
          return card.parts
        elsif card.respond_to?(:items)
          return card.items
        end

        # Use left_id relationship to find children
        direct_children = Card::Auth.as(current_account.name) do
          Card.where("left_id = ?", card.id).to_a
        end

        # For depth > 1, recursively fetch descendants
        if depth > 1
          all_matches = []
          to_process = [card]
          current_depth = 0

          while current_depth < depth && to_process.any?
            current_level = to_process
            to_process = []
            current_depth += 1

            current_level.each do |parent|
              children = Card::Auth.as(current_account.name) do
                Card.where("left_id = ?", parent.id).to_a
              end
              all_matches.concat(children)
              to_process.concat(children) if current_depth < depth
            end
          end

          all_matches.uniq
        else
          direct_children
        end
      rescue StandardError => e
        Rails.logger.error "fetch_children error: #{e.class.name}: #{e.message}"
        []
      end

      # Fetch all descendants (unlimited depth)
      def fetch_all_descendants(card)
        fetch_children(card, depth: 999)
      end
    end
  end
end
