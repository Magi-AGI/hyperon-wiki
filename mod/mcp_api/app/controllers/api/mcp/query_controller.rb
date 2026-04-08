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
            # Support date range queries
            safe_query[key.to_sym] = parse_date_query(value)
          end
        end

        # Add pagination
        safe_query[:limit] = limit
        safe_query[:offset] = offset

        safe_query
      end

      def parse_date_query(value)
        # Support array format: [">=", "2025-01-01"] or ["between", "2025-01-01", "2025-12-31"]
        if value.is_a?(Array)
          operator = value[0]
          case operator
          when ">=", ">", "<=", "<"
            [operator, Time.parse(value[1])]
          when "between"
            ["between", Time.parse(value[1]), Time.parse(value[2])]
          else
            value
          end
        elsif value.is_a?(String)
          # Single date string means exact match
          Time.parse(value)
        else
          value
        end
      rescue ArgumentError
        value # Return as-is if parsing fails
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
