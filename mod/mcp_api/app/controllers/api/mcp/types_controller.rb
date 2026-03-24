# frozen_string_literal: true

module Api
  module Mcp
    class TypesController < BaseController
      # GET /api/mcp/types
      # List all card types
      def index
        types = fetch_all_types

        render json: {
          types: types.map { |t| type_json(t, include_description: false) }
        }
      end

      # GET /api/mcp/types/:name
      # Get specific type by name
      def show
        type_name = params[:name]
        type_card = find_type_by_name(type_name)

        unless type_card
          return render_error(
            "not_found",
            "Type '#{type_name}' not found",
            {},
            status: :not_found
          )
        end

        render json: type_json(type_card, include_description: true)
      end

      private

      def fetch_all_types
        # Cache types for 1 hour (configurable via ENV)
        cache_key = "mcp_api:types:all"
        cache_ttl = (ENV["MCP_TYPES_CACHE_TTL"] || 3600).to_i

        Rails.cache.fetch(cache_key, expires_in: cache_ttl) do
          Card::Auth.as(current_account.name) do
            Card.search(type: "Cardtype").sort_by(&:name)
          end
        end
      end

      def find_type_by_name(name)
        Card::Auth.as(current_account.name) do
          # Try exact match first
          type_card = Card.fetch(name)
          return type_card if type_card&.type_id == Card::CardtypeID

          # Try case-insensitive search
          Card.search(
            type: "Cardtype",
            name: ["match", name]
          ).first
        end
      end

      def type_json(type_card, include_description: false)
        result = {
          name: type_card.name,
          id: type_card.id,
          codename: type_card.codename,
          common: common_type?(type_card.name)
        }

        if include_description
          result[:description] = type_description(type_card)
        end

        result
      end

      def common_type?(type_name)
        # Common types used frequently in the wiki
        %w[
          RichText
          Phrase
          PlainText
          Pointer
          User
          EmailTemplate
        ].include?(type_name)
      end

      def type_description(type_card)
        # Try to get description from type's content or help card
        help_card = Card::Auth.as(current_account.name) do
          Card.fetch("#{type_card.name}+*type+*help")
        end
        return help_card.content if help_card

        # Fallback descriptions
        case type_card.name
        when "RichText"
          "Rich HTML content with wiki links"
        when "Phrase"
          "Short text string"
        when "PlainText"
          "Plain text without formatting"
        when "Pointer"
          "References to other cards"
        else
          "Card type: #{type_card.name}"
        end
      end
    end
  end
end
