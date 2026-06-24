# frozen_string_literal: true

module Api
  module Mcp
    # Controller for running safe, limited queries against the wiki
    class QueryController < BaseController
      # POST /api/mcp/run_query
      # Run a safe CQL (Card Query Language) query with enforced limits
      def run
        query_params = params[:query] || {}
        limit = [(params[:limit] || 50).to_i, 100].min
        offset = (params[:offset] || 0).to_i

        # Validate query parameters
        return render_error("validation_error", "Query cannot be empty") if query_params.empty?

        # Build safe query with enforced constraints
        safe_query = build_safe_query(query_params, limit, offset)

        # T7: reject queries that produced no real filter (e.g. unrecognized keys,
        # or raw CQL strings like "name ~ 'x'"). Without this guard the query
        # degrades to Card.search(limit/offset) and silently returns EVERY card.
        filter_keys = safe_query.keys.map(&:to_s) & %w[name type content updated_at created_at and]
        if filter_keys.empty?
          return render_error(
            "validation_error",
            "Query must include at least one recognized filter (name, type, content, " \
            "updated_at, or created_at). Raw CQL strings are not supported; pass e.g. {\"name\": \"synthesis\"}."
          )
        end

        # T7: optional ordering (sort=name|created|updated, dir=asc|desc).
        apply_sort!(safe_query, params[:sort], params[:dir])

        # Execute query
        results = execute_safe_query(safe_query, limit, offset)
        total = count_query_results(safe_query)

        render json: {
          results: results.map { |c| card_summary_json(c) },
          total: total,
          limit: limit,
          offset: offset,
          next_offset: (offset + limit < total ? offset + limit : nil),
          query: safe_query
        }
      rescue StandardError => e
        render_error("query_error", "Query failed", { error: e.message })
      end

      private

      # T7: map a friendly sort/dir to Decko's Card.search ordering.
      def apply_sort!(safe_query, sort, dir)
        column = { "name" => "name", "created" => "create", "created_at" => "create",
                   "updated" => "update", "updated_at" => "update" }[sort.to_s]
        return unless column

        safe_query[:sort] = column
        safe_query[:dir] = (dir.to_s == "asc" ? "asc" : "desc")
      end

      def build_safe_query(query_params, limit, offset)
        safe_query = {}

        # Allow only safe query operations
        allowed_keys = %w[name type content updated_at created_at]

        query_params.each do |key, value|
          next unless allowed_keys.include?(key.to_s)

          case key.to_s
          when "name"
            # Support match operations for name
            if value.is_a?(Array) && value.first == "match"
              safe_query[:name] = value
            elsif value.is_a?(String)
              safe_query[:name] = ["match", value]
            end
          when "type"
            # Exact type match only
            safe_query[:type] = value
          when "content"
            # Support match operations for content
            if value.is_a?(Array) && value.first == "match"
              safe_query[:content] = value
            elsif value.is_a?(String)
              safe_query[:content] = ["match", value]
            end
          when "updated_at", "created_at"
            # Support date range queries (>, >=, <, <=, between)
            add_date_condition(safe_query, key.to_sym, value)
          end
        end

        # Add pagination
        safe_query[:limit] = limit
        safe_query[:offset] = offset

        safe_query
      end

      # Translate a friendly date filter into a Decko CQL condition.
      #
      # Decko CQL only honors the keyword operators "gt"/"lt" with a STRING
      # date value. A raw [">=", date] is parsed as an IN-list (the bug this
      # fixes) and a Time object is rejected outright ("Invalid value type:
      # Time"). So we fold the comparison operators onto gt/lt and pass a
      # normalized date string. ">=" / "<=" collapse to "gt" / "lt" at the
      # given instant (CQL has no inclusive operator); at day granularity this
      # behaves as "on or after / on or before" for practical purposes.
      # "between" is expressed as an :and of a lower (gt) and upper (lt) bound.
      def add_date_condition(safe_query, field, value)
        return unless value.is_a?(Array) && value.length >= 2

        operator = value[0].to_s
        if operator == "between" && value.length >= 3
          (safe_query[:and] ||= []) << { field => ["gt", normalize_date(value[1])] }
          safe_query[:and] << { field => ["lt", normalize_date(value[2])] }
          return
        end

        cql_op = { ">" => "gt", ">=" => "gt", "gt" => "gt",
                   "<" => "lt", "<=" => "lt", "lt" => "lt" }[operator]
        return unless cql_op

        safe_query[field] = [cql_op, normalize_date(value[1])]
      end

      # Normalize a date/time value to a UTC timestamp string PostgreSQL and
      # Decko's CQL both accept. Falls back to the raw string if unparseable.
      def normalize_date(raw)
        Time.parse(raw.to_s).utc.strftime("%Y-%m-%d %H:%M:%S")
      rescue ArgumentError, TypeError
        raw.to_s
      end

      def execute_safe_query(query, limit, offset)
        # Execute query through Decko's search with proper auth context
        cards = Card::Auth.as(current_account.name) do
          Card.search(query)
        end

        # Filter by Decko's native permission system
        # This respects +*read rules and their inheritance to child cards.
        # DEPRECATED: Previously used name-based filtering (+GM, +AI patterns).
        cards.select do |card|
          !card.trash && Card::Auth.as(current_account.name) { card.ok?(:read) }
        end
      end

      def count_query_results(query)
        # Count total results (without limit/offset)
        count_query = query.dup
        count_query.delete(:limit)
        count_query.delete(:offset)
        count_query.delete(:sort)
        count_query.delete(:dir)
        count_query[:return] = "count"

        Card::Auth.as(current_account.name) do
          Card.search(count_query)
        end
      rescue StandardError
        0
      end

      def card_summary_json(card)
        {
          name: card.name,
          id: card.id,
          type: card.type_name,
          updated_at: card.updated_at.iso8601
        }
      end
    end
  end
end
