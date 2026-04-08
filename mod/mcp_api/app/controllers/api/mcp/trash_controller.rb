# frozen_string_literal: true

module Api
  module Mcp
    class TrashController < BaseController
      before_action :check_admin_role!

      # GET /api/mcp/trash
      # List deleted cards in trash
      def index
        limit = [(params[:limit] || 50).to_i, 100].min
        offset = (params[:offset] || 0).to_i

        cards = Card::Auth.as(current_account.name) do
          Card.where(trash: true)
              .order(updated_at: :desc)
              .offset(offset)
              .limit(limit)
        end

        total = Card.where(trash: true).count

        render json: {
          cards: cards.map { |card| trash_card_json(card) },
          total: total,
          limit: limit,
          offset: offset,
          next_offset: (offset + limit < total ? offset + limit : nil)
        }
      end

      private

      def check_admin_role!
        return if current_role == "admin"

        render_forbidden("Only admin role can access trash")
      end

      def trash_card_json(card)
        # Find the delete action for this card
        delete_action = Card::Action.where(card_id: card.id, action_type: 2)
                                    .order(id: :desc)
                                    .includes(:act)
                                    .first

        {
          name: card.name,
          type: card.type_name,
          deleted_at: delete_action&.act&.acted_at&.iso8601 || card.updated_at&.iso8601,
          deleted_by: delete_action&.act&.actor&.name
        }.compact
      end
    end
  end
end
