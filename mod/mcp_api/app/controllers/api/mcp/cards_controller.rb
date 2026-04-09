# frozen_string_literal: true

require "base64"
require "tempfile"
require_relative "../../../../lib/mcp/roles"

module Api
  module Mcp
    class CardsController < BaseController
      before_action :set_card, only: [:show, :update, :destroy, :rename, :children, :referers, :nested_in, :nests, :links, :linked_by, :history, :revision, :restore, :search_content, :outline, :file_url]
      before_action :set_card_if_exists, only: [:upload]
      before_action :check_admin_role!, only: [:destroy, :rename]

      # GET /api/mcp/cards
      # Search/list cards with filters
      def index
        limit = [(params[:limit] || 50).to_i, 100].min
        offset = (params[:offset] || 0).to_i
        include_virtual = params[:include_virtual] == "true" || params[:include_virtual] == true

        if params[:updated_since] || params[:updated_before]
          # Use SQL-level pagination for date range queries.
          # Decko CQL does not support updated_at filtering, so the old approach
          # loaded ALL matching cards into memory to filter by date in Ruby.
          # With ~10K cards, this caused 776MB+ memory bloat and 14s+ GC pauses.
          cards, total = execute_date_range_search(limit, offset)
        else
          query = build_search_query
          cards = execute_search(query, limit, offset, include_virtual: include_virtual)
          if @name_filter_words && @name_filter_words.any?
            total = cards.size
          else
            total = count_search_results(query, include_virtual: include_virtual)
          end
        end

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
      # Pass rendered=true to get fully rendered HTML with all inclusions resolved
      def show
        return render_forbidden_content unless can_view_card?(@card)

        if params[:rendered] == "true" || params[:rendered] == true
          # Use as_bot for rendering since we already verified can_view_card?
          # above. The user account may lack permission on nested subcards that
          # are included via {{...}} nests, but bot can resolve all inclusions.
          rendered_content = Card::Auth.as_bot do
            @card.format(:html).render(:core)
          end
          render json: card_full_json(@card, rendered_content: rendered_content)
        else
          render json: card_full_json(@card)
        end
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
        return render_forbidden_content unless can_modify_card?(@card)

        Card::Auth.as(current_account.name) do
          if params[:patch]
            apply_patch(@card, params[:patch])
          else
            content = prepare_content(params[:content], params[:markdown_content])
            @card.content = content if content

            # Handle type change
            if params[:type]
              type_card = find_type_by_name(params[:type])
              return render_error("not_found", "Type '#{params[:type]}' not found") unless type_card

              @card.type_id = type_card.id
            end

            @card.save!
          end
        end

        render json: card_full_json(@card) unless performed?
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

      # PUT /api/mcp/cards/:name/rename
      # Rename card (admin only)
      def rename
        new_name = params[:new_name]
        return render_error("validation_error", "Missing new_name parameter") unless new_name

        # update_referers defaults to true (update all references when renaming)
        # Set to false to skip updating referers
        update_referers = params[:update_referers].nil? ? true : params[:update_referers]

        old_name = @card.name

        Card::Auth.as(current_account.name) do
          @card.name = new_name
          # If update_referers is false, skip updating referer content
          @card.skip = :update_referer_content unless update_referers
          @card.save!
        end

        render json: {
          status: "renamed",
          old_name: old_name,
          new_name: @card.name,
          updated_referers: update_referers,
          card: card_full_json(@card)
        }, status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render_error("validation_error", "Rename failed", { errors: e.record.errors.full_messages })
      rescue StandardError => e
        render_error("rename_failed", "Could not rename card", { error: e.message })
      end

      # GET /api/mcp/cards/:name/children
      # List children cards
      def children
        return render_forbidden_content unless can_view_card?(@card)

        limit = [(params[:limit] || 50).to_i, 100].min
        offset = (params[:offset] || 0).to_i
        include_virtual = params[:include_virtual] == "true" || params[:include_virtual] == true
        depth = (params[:depth] || 1).to_i
        include_virtual = params[:include_virtual] == "true" || params[:include_virtual] == true

        children_cards = fetch_children(@card, depth: depth).select { |c| can_view_card?(c) }
        children_cards = children_cards.reject { |c| detect_virtual_card(c) } unless include_virtual

        # Apply pagination
        total = children_cards.size
        paginated_children = children_cards.drop(offset).take(limit)

        next_off = offset + limit < total ? offset + limit : nil

        render json: {
          parent: @card.name,
          children: paginated_children.map { |c| card_full_json(c) },
          child_count: total,
          depth: depth,
          limit: limit,
          offset: offset,
          next_offset: next_off,
          truncated: paginated_children.size < total - offset
        }
      end

      # GET /api/mcp/cards/:name/referers
      # List cards that reference/link to this card
      def referers
        return render_forbidden_content unless can_view_card?(@card)

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
        return render_forbidden_content unless can_view_card?(@card)

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
        return render_forbidden_content unless can_view_card?(@card)

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
        return render_forbidden_content unless can_view_card?(@card)

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
        return render_forbidden_content unless can_view_card?(@card)

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

      # GET /api/mcp/cards/:name/history
      # Get revision history for a card
      def history
        return render_forbidden_content unless can_view_card?(@card)

        limit = [(params[:limit] || 20).to_i, 100].min

        # Get actions for this card, ordered by most recent first
        actions = Card::Auth.as(current_account.name) do
          Card::Action.where(card_id: @card.id)
                      .where(draft: [false, nil])
                      .order(id: :desc)
                      .limit(limit)
                      .includes(:act)
        end

        total = Card::Action.where(card_id: @card.id).where(draft: [false, nil]).count

        render json: {
          card: @card.name,
          revisions: actions.map { |action| action_summary_json(action) },
          total: total,
          in_trash: @card.trash
        }
      end

      # GET /api/mcp/cards/:name/history/:act_id
      # Get content from a specific revision
      def revision
        return render_forbidden_content unless can_view_card?(@card)

        act_id = params[:act_id].to_i

        # Find the action for this card at this act
        action = Card::Auth.as(current_account.name) do
          Card::Action.joins(:act)
                      .where(card_id: @card.id, card_acts: { id: act_id })
                      .first
        end

        unless action
          return render_error("not_found", "Revision not found",
                              { card: @card.name, act_id: act_id }, status: :not_found)
        end

        render json: revision_json(action)
      end

      # POST /api/mcp/cards/:name/restore
      # Restore card to previous state or from trash
      def restore
        check_admin_role!
        return unless response_body.nil? # check_admin_role! may have rendered

        from_trash = params[:from_trash] == true || params[:from_trash] == "true"
        act_id = params[:act_id]&.to_i

        unless from_trash || act_id
          return render_error("validation_error",
                              "Must specify either act_id or from_trash: true")
        end

        Card::Auth.as(current_account.name) do
          if from_trash
            restore_from_trash
          else
            restore_to_revision(act_id)
          end
        end
      end


      # GET /api/mcp/cards/:name/search_content
      # Search within a card's raw content and return matching excerpts
      def search_content
        return render_forbidden_content unless can_view_card?(@card)

        query = params[:query]
        return render_error("validation_error", "Missing query parameter") unless query

        context_chars = (params[:context_chars] || 100).to_i
        content = @card.content || ""

        matches = []
        search_pos = 0
        while (idx = content.index(query, search_pos))
          start_pos = [idx - context_chars, 0].max
          end_pos = [idx + query.length + context_chars, content.length].min
          matches << {
            position: idx,
            context: content[start_pos...end_pos],
            context_start: start_pos,
            match_offset_in_context: idx - start_pos
          }
          search_pos = idx + query.length
        end

        render json: {
          card: @card.name,
          query: query,
          match_count: matches.size,
          content_length: content.length,
          matches: matches
        }
      end

      # GET /api/mcp/cards/:name/outline
      # Return the heading structure of a card without full content
      def outline
        return render_forbidden_content unless can_view_card?(@card)

        content = @card.content || ""
        headings = extract_headings(content)

        render json: {
          card: @card.name,
          type: @card.type_name,
          content_length: content.length,
          headings: headings
        }
      end

      # POST /api/mcp/cards/:name/upload
      # Upload a file or image to create or update a File/Image card
      def upload
        type_name = params[:type]
        unless type_name && %w[File Image].include?(type_name)
          return render_error("validation_error", "type must be 'File' or 'Image'")
        end

        # Handle base64 file data
        if params[:file_data]
          filename = params[:filename]
          return render_error("validation_error", "filename is required with file_data") unless filename

          begin
            file_content = Base64.strict_decode64(params[:file_data])
          rescue ArgumentError => e
            return render_error("validation_error", "Invalid base64 encoding: #{e.message}")
          end

          # Write to tempfile with correct extension
          ext = File.extname(filename)
          tempfile = Tempfile.new(["mcp_upload", ext])
          tempfile.binmode
          tempfile.write(file_content)
          tempfile.rewind

          attachment_param = type_name == "Image" ? :image : :file
        elsif params[:remote_url]
          # Download file ourselves with explicit timeout instead of using
          # CarrierWave's remote_*_url which hangs due to SSRF protection
          require "net/http"
          uri = URI.parse(params[:remote_url])
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == "https")
          http.open_timeout = 10
          http.read_timeout = 30
          response = http.get(uri.request_uri)

          unless response.is_a?(Net::HTTPSuccess)
            return render_error("validation_error", "Failed to download from URL: HTTP #{response.code}")
          end

          filename = File.basename(uri.path)
          ext = File.extname(filename)
          ext = ".dat" if ext.empty?
          tempfile = Tempfile.new(["mcp_remote", ext])
          tempfile.binmode
          tempfile.write(response.body)
          tempfile.rewind

          attachment_param = type_name == "Image" ? :image : :file
        else
          return render_error("validation_error", "Either file_data or remote_url is required")
        end

        card_name = params[:name]

        Card::Auth.as(current_account.name) do
          if @card
            # Update existing card
            return render_forbidden_content unless can_modify_card?(@card)

            attrs = { attachment_param => tempfile }
            @card.update!(attrs)
            @card.acts.last&.actions&.last&.update(comment: filename) if filename
          else
            # Create new card
            type_card = find_type_by_name(type_name)
            return render_error("not_found", "Type '#{type_name}' not found") unless type_card

            attrs = { name: card_name, type_id: type_card.id, attachment_param => tempfile }

            @card = Card.create!(attrs)
            @card.acts.last&.actions&.last&.update(comment: filename) if filename
          end
        end

        result = card_full_json(@card)
        # Add file-specific metadata
        result[:file_url] = file_url_for(@card)
        result[:original_filename] = filename || File.basename(params[:remote_url].to_s)
        if type_name == "Image"
          result[:image_urls] = image_urls_for(@card)
        end

        render json: result, status: @card.id ? :ok : :created
      rescue ActiveRecord::RecordInvalid => e
        render_error("validation_error", "Upload failed: #{e.message}", { errors: e.record&.errors&.full_messages })
      ensure
        tempfile&.close
        tempfile&.unlink
      end

      # GET /api/mcp/cards/:name/file_url
      # Get the download URL for a File or Image card
      def file_url
        unless %w[File Image].include?(@card.type_name)
          return render_error("validation_error", "Card '#{@card.name}' is not a File or Image card (type: #{@card.type_name})")
        end

        result = {
          name: @card.name,
          type: @card.type_name,
          file_url: file_url_for(@card),
          original_filename: @card.acts.last&.actions&.last&.comment
        }

        if @card.type_name == "Image"
          result[:image_urls] = image_urls_for(@card)
        end

        render json: result
      end

      private

      def set_card
        name = params[:name]
        # Look in trash when restoring from trash
        look_in_trash = action_name == "restore" &&
                        (params[:from_trash] == true || params[:from_trash] == "true")
        
        # First check if card exists at all (as bot to bypass permissions)
        card_exists = Card::Auth.as_bot do
          Card.exists?(name) || (look_in_trash && Card.where(name: name, trash: true).exists?)
        end

        unless card_exists
          return render_error("not_found", "Card '#{name}' not found", {}, status: :not_found)
        end

        # Now fetch with user's permissions
        @card = Card::Auth.as(current_account.name) do
          Card.fetch(name, look_in_trash: look_in_trash)
        end

        # If card exists but fetch returned nil, it's a permission issue
        unless @card
          render_error(
            "permission_denied",
            "You do not have permission to access '#{name}'",
            { hint: "This card exists but requires elevated permissions to view." },
            status: :forbidden
          )
        end
      end

      def set_card_if_exists
        name = params[:name]
        @card = Card::Auth.as(current_account.name) do
          Card.fetch(name.tr("_", " "))
        end
        # @card may be nil for new cards — that's ok
      end

      def file_url_for(card)
        attachment = card.type_name == "Image" ? card.image : card.file
        return nil unless attachment&.file
        attachment.url
      end

      def image_urls_for(card)
        return {} unless card.type_name == "Image" && card.image&.file
        sizes = {}
        %w[icon small medium large original].each do |size|
          version = size == "original" ? card.image : card.image.send(size)
          sizes[size] = version&.url if version
        end
        sizes
      rescue StandardError
        {}
      end

      def check_admin_role!
        unless current_role == "admin"
          render_forbidden("Only admin role can delete cards")
        end
      end

      def can_view_card?(card)
        # Filter out trashed/deleted cards
        return false if card.trash

        # Use Decko's built-in permission system exclusively.
        # This respects +*read rules set on cards and their inheritance.
        #
        # Permission inheritance works via the permission_propagation mod:
        # - Child cards inherit parent +*read rules automatically
        # - New cards under restricted parents get correct permissions on create
        # - Permission changes propagate to all descendant cards
        #
        # DEPRECATED: Previously we also filtered by card name patterns (+GM, +AI).
        # Cards requiring GM access should have proper +*read rules set instead.
        # The name-based filtering has been removed for consistency.
        Card::Auth.as(current_account.name) do
          card.ok?(:read)
        end
      end

      def can_modify_card?(card)
        return false if card.trash

        Card::Auth.as(current_account.name) do
          card.ok?(:update)
        end
      end

      def render_forbidden_content
        # Used when Decko's native permissions deny access
        render_forbidden(
          "You do not have permission to access this content",
          { card: @card.name, hint: "Check card permissions (+*read rules) or contact an admin." }
        )
      end

# SQL-based search for date range queries.
# Uses ActiveRecord directly instead of Decko CQL to get proper
# SQL-level LIMIT/OFFSET/WHERE/COUNT. This prevents loading all
# matching cards into Ruby memory for post-filtering.
def execute_date_range_search(limit, offset)
  Card::Auth.as(current_account.name) do
    scope = Card.where(trash: false)

    if params[:updated_since]
      scope = scope.where("cards.updated_at >= ?", Time.parse(params[:updated_since]))
    end
    if params[:updated_before]
      scope = scope.where("cards.updated_at < ?", Time.parse(params[:updated_before]))
    end

    if params[:type]
      type_card = Card.fetch(params[:type])
      scope = scope.where(type_id: type_card.id) if type_card
    end

    if params[:q]
      escaped = sanitize_sql_like_param(params[:q])
      search_in = params[:search_in] || "name"
      case search_in
      when "content"
        scope = scope.where("cards.db_content LIKE ?", "%#{escaped}%")
      when "both"
        scope = scope.where("cards.name LIKE ? OR cards.db_content LIKE ?",
                            "%#{escaped}%", "%#{escaped}%")
      else
        scope = scope.where("cards.name LIKE ?", "%#{escaped}%")
      end
    end

    if params[:prefix]
      escaped = sanitize_sql_like_param(params[:prefix])
      scope = scope.where("cards.name LIKE ?", "#{escaped}%")
    end

    if params[:not_name]
      pattern = params[:not_name].gsub("*", "%")
      scope = scope.where("cards.name NOT LIKE ?", pattern)
    end

    # Filter by permissions
    scope = scope.order(updated_at: :desc)
    total = scope.count
    cards = scope.limit(limit).offset(offset).to_a

    # Post-filter by view permissions (must happen after SQL pagination)
    cards = cards.select { |c| can_view_card?(c) }

    [cards, total]
  end
end

# Sanitize user input for SQL LIKE patterns
def sanitize_sql_like_param(value)
  # Use Rails built-in sanitizer for LIKE wildcards
  ActiveRecord::Base.sanitize_sql_like(value)
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
              part: params[:q],
              content: ["match", params[:q]]
            }
          else  # "name" or any other value defaults to name search
            # For multi-word searches, search broadly then filter by full name
            search_words = params[:q].to_s.split(/\s+/).reject(&:empty?)
            if search_words.size > 1
              @name_filter_words = search_words
              # Search for ALL words to find deeply nested cards
              all_conditions = []
              search_words.each do |word|
                all_conditions += build_single_word_conditions(word)
              end
              name_conditions = all_conditions.uniq { |c| c.to_s }
            else
              name_conditions = build_hybrid_name_conditions(params[:q])
            end
            if name_conditions.size == 1
              query.merge!(name_conditions.first)
            else
              query[:any] = name_conditions
            end
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


      # Build hybrid search conditions for compound card name search
# This enables substring matching by:
# 1. Searching simple cards with "match" (works for substring on name column)
# 2. Finding compound cards that have matching simple cards as parts
# For multi-word searches like "Tharaneth roots", ALL words must match
def build_hybrid_name_conditions(search_term)
  # Split search term into words for multi-word searches
  words = search_term.to_s.split(/\s+/).reject(&:empty?)
  
  if words.size <= 1
    # Single word - use simple approach
    build_single_word_conditions(words.first || search_term)
  else
    # Multi-word search - each word must match (AND logic)
    build_multi_word_conditions(words)
  end
end

# Build conditions for a single search word
def build_single_word_conditions(word)
  conditions = []

  # 1. Direct name match (SQL LIKE on name column)
  conditions << { name: ["match", word] }

  # 2. Find simple cards matching the word, then add part conditions
  begin
    matching_simple_cards = Card::Auth.as(current_account.name) do
      Card.search(
        name: ["match", word],
        limit: 50,
        return: :name
      )
    end

    matching_simple_cards.each do |card_name|
      conditions << { part: card_name }
    end
  rescue => e
    Rails.logger.warn "Hybrid name search failed for word: #{e.message}"
  end

  # 3. Left-part match for compound card prefix search
  # e.g., searching "opencog-ml" finds "RawData+opencog-ml+thread1"
  # where "opencog-ml" is the right part of the left compound "RawData+opencog-ml"
  conditions << { left: { name: ["match", word] } }
  conditions << { right: { name: ["match", word] } }

  conditions
end

# Build conditions for multi-word search using AND logic
# "Tharaneth roots" finds cards matching BOTH "Tharaneth" AND "roots"
def build_multi_word_conditions(words)
  # Build conditions for each word
  word_conditions = words.map do |word|
    single = build_single_word_conditions(word)
    # Wrap in "any" if multiple conditions, otherwise use directly
    single.size == 1 ? single.first : { any: single }
  end

  # Return AND condition requiring ALL words to match
  [{ and: word_conditions }]
end


def execute_search(query, limit, offset, include_virtual: false)
  # Fetch more cards than needed to account for post-filtering
  # We'll filter then apply offset/limit
  fetch_limit = [limit * 10, 1000].max  # Fetch enough to handle filtering

  cards = Card::Auth.as(current_account.name) do
    Card.search(query.merge(limit: fetch_limit))
  end

  # Apply date range post-filter if needed
  if @filter_date_range
    cards = cards.select do |c|
      in_range = true
      in_range = false if @filter_date_range[:since] && c.updated_at < @filter_date_range[:since]
      in_range = false if @filter_date_range[:before] && c.updated_at > @filter_date_range[:before]
      in_range
    end
  end

  # Filter out trashed/deleted cards (all roles)
  cards = cards.reject { |c| c.trash }

  # Filter by name words if multi-word search
  if @name_filter_words && @name_filter_words.any?
    cards = cards.select do |c|
      card_name_lower = c.name.to_s.downcase
      @name_filter_words.all? { |word| card_name_lower.include?(word.downcase) }
    end
  end

  # Use Decko's native permission system to filter cards
  # This respects +*read rules and their inheritance to child cards.
  # DEPRECATED: Previously used name-based filtering (+GM, +AI patterns).
  # Cards requiring restricted access should have proper +*read rules set.
  cards = cards.select { |c| can_view_card?(c) }

  # Filter out virtual cards unless explicitly requested
  unless include_virtual
    cards = cards.reject { |c| detect_virtual_card(c) }
  end

  # NOW apply offset and limit to filtered results
  cards.drop(offset).take(limit)
end

      def count_search_results(query, include_virtual: true)
  Card::Auth.as(current_account.name) do
    cards = Card.search(query.merge(limit: 10000))

    cards = cards.reject { |c| c.trash }

    # Use Decko's native permission system to filter cards
    # This respects +*read rules and their inheritance to child cards.
    cards = cards.select { |c| can_view_card?(c) }
    
    unless include_virtual
      cards = cards.reject { |c| detect_virtual_card(c) }
    end
    
    if @filter_date_range
      cards = cards.select do |c|
        in_range = true
        in_range = in_range && (c.updated_at >= @filter_date_range[:since]) if @filter_date_range[:since]
        in_range = in_range && (c.updated_at <= @filter_date_range[:before]) if @filter_date_range[:before]
        in_range
      end
    end
    
    cards.size
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
        when "append"
          apply_append(card, patch_params)
        when "prepend"
          apply_prepend(card, patch_params)
        when "find_replace"
          apply_find_replace(card, patch_params)
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

      def apply_append(card, patch_params)
        content = patch_params[:content]
        return render_error("validation_error", "Missing content for append") unless content

        separator = patch_params[:separator] || ""
        card.content = (card.content || "") + separator + content
        card.save!
      end

      def apply_prepend(card, patch_params)
        content = patch_params[:content]
        return render_error("validation_error", "Missing content for prepend") unless content

        separator = patch_params[:separator] || ""
        card.content = content + separator + (card.content || "")
        card.save!
      end

      def apply_find_replace(card, patch_params)
        find_text = patch_params[:find]
        replace_text = patch_params[:replace]
        return render_error("validation_error", "Missing 'find' parameter") unless find_text
        return render_error("validation_error", "Missing 'replace' parameter") unless replace_text.is_a?(String)

        occurrence = patch_params[:occurrence] || "first"
        content = card.content || ""

        unless content.include?(find_text)
          return render_error("validation_error", "Text not found in card content",
                              { find: find_text, card: card.name })
        end

        card.content = case occurrence
                        when "all"
                          content.gsub(find_text, replace_text)
                        when "last"
                          idx = content.rindex(find_text)
                          content[0...idx] + replace_text + content[(idx + find_text.length)..]
                        else # "first"
                          content.sub(find_text, replace_text)
                        end
        card.save!
      end

      # Extract heading structure from card content (HTML and Markdown)
      def extract_headings(content)
        headings = []
        pos = 0

        # Scan for HTML headings: <h1>...</h1> through <h6>...</h6>
        content.scan(/<h(\d)[^>]*>(.*?)<\/h\1>/im) do |level, text|
          match_pos = content.index($~.to_s, pos)
          headings << {
            level: level.to_i,
            text: text.strip.gsub(/<[^>]+>/, ""), # strip inner HTML tags
            position: match_pos,
            format: "html"
          }
          pos = match_pos + 1 if match_pos
        end

        # Scan for Markdown headings: # through ######
        content.scan(/^(\#{1,6})\s+(.+)$/m) do |hashes, text|
          match_pos = content.index($~.to_s)
          headings << {
            level: hashes.length,
            text: text.strip,
            position: match_pos,
            format: "markdown"
          }
        end

        # Sort by position in document
        headings.sort_by { |h| h[:position] || 0 }
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

      # Format an action for the history list
      def action_summary_json(action)
        action_type_names = { 0 => "create", 1 => "update", 2 => "delete" }
        {
          act_id: action.act.id,
          action: action_type_names[action.action_type] || action.action_type.to_s,
          actor: action.act.actor&.name,
          acted_at: action.act.acted_at&.iso8601,
          changes: action.all_changes.map { |c| c.field.to_s },
          comment: action.comment
        }.compact
      end

      # Format a single revision with full content snapshot
      def revision_json(action)
        snapshot = build_snapshot_at_action(action)

        {
          card: @card.name,
          act_id: action.act.id,
          acted_at: action.act.acted_at&.iso8601,
          actor: action.act.actor&.name,
          snapshot: snapshot
        }
      end

      # Build what the card looked like at a given action
      def build_snapshot_at_action(action)
        snapshot = {
          name: action.value(:name) || @card.name,
          type: nil,
          content: action.value(:db_content) || action.value(:content)
        }

        # Get type - convert type_id to type name
        type_id = action.value(:type_id)
        if type_id
          type_card = Card.fetch(type_id.to_i)
          snapshot[:type] = type_card&.name
        else
          snapshot[:type] = @card.type_name
        end

        # If content was not changed in this action, we need to look back
        if snapshot[:content].nil?
          prev_content_action = Card::Action.where(card_id: @card.id)
                                            .where("id <= ?", action.id)
                                            .order(id: :desc)
                                            .find { |a| a.value(:db_content) || a.value(:content) }
          snapshot[:content] = prev_content_action&.value(:db_content) ||
                               prev_content_action&.value(:content) ||
                               @card.content
        end

        snapshot
      end

      def restore_from_trash
        unless @card.trash
          return render_error("validation_error", "Card is not in trash",
                              { card: @card.name })
        end

        @card.trash = false
        @card.save!

        render json: {
          success: true,
          card: @card.name,
          message: "Card restored from trash"
        }
      rescue StandardError => e
        render_error("restore_failed", "Could not restore card", { error: e.message })
      end

      def restore_to_revision(act_id)
        action = Card::Action.joins(:act)
                             .where(card_id: @card.id, card_acts: { id: act_id })
                             .first

        unless action
          return render_error("not_found", "Revision not found",
                              { card: @card.name, act_id: act_id }, status: :not_found)
        end

        snapshot = build_snapshot_at_action(action)
        @card.content = snapshot[:content] if snapshot[:content]
        @card.save!

        render json: {
          success: true,
          card: @card.name,
          restored_from: {
            act_id: act_id,
            acted_at: action.act.acted_at&.iso8601
          },
          message: "Card restored to revision from #{action.act.acted_at}"
        }
      rescue StandardError => e
        render_error("restore_failed", "Could not restore card", { error: e.message })
      end


      def card_summary_json(card)
        {
          name: card.name,
          id: card.id,
          type: card.type_name,
          updated_at: card.updated_at.iso8601
        }
      end

      def card_full_json(card, rendered_content: nil)
        # Detect virtual cards: simple name (no +), empty ancestors, empty/minimal content
        # Virtual cards are junction cards that exist primarily for naming, with actual
        # content in compound child cards (e.g., "Trallox" vs "Games+...+Trallox")
        is_virtual = detect_virtual_card(card)

        json = {
          name: card.name,
          id: card.id,
          type: card.type_name,
          codename: card.codename,
          content: rendered_content || card.content,
          updated_at: card.updated_at.iso8601,
          created_at: card.created_at.iso8601,
          virtual_card: is_virtual,
          rendered: !rendered_content.nil?
        }
        
        # Include ancestor information if available (helps detect virtual cards client-side)
        if card.respond_to?(:ancestors) && card.ancestors.present?
          json[:ancestors] = card.ancestors.map { |a| { name: a.name, id: a.id } }
        end
        
        json
      end
      
      # Detect if a card is a virtual/junction card
      # Virtual cards typically have:
      # 1. Simple name (no + signs indicating compound structure)
      # 2. No ancestors (not part of a hierarchy)
      # 3. Empty or minimal content (actual content is in compound child cards)
      def detect_virtual_card(card)
        # Child cards (with left_id) are never virtual, even if they have simple names
        # This is because Decko stores child cards with just the tail name
        is_child = card.respond_to?(:left_id) && card.left_id.present?
        return false if is_child

        simple_name = !card.name.include?("+")
        no_ancestors = !card.respond_to?(:ancestors) || card.ancestors.blank?
        minimal_content = card.content.blank? || card.content.strip.length < 10
        
        simple_name && no_ancestors && minimal_content
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
