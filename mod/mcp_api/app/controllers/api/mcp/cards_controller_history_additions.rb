# frozen_string_literal: true

# HISTORICAL REFERENCE FILE
# These methods have been merged into cards_controller.rb
# This file is kept for reference/documentation only.
# 
# Note: Method names updated to match current implementation
# (render_forbidden_content instead of render_forbidden_gm_content)

# Add to before_action line at the top:
#   before_action :set_card, only: [..., :history, :revision, :restore]

# Add these new action methods:

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

      private

      # Format an action for the history list
      def action_summary_json(action)
        {
          act_id: action.act.id,
          action: action.action_type.to_s,
          actor: action.act.actor&.name,
          acted_at: action.act.acted_at&.iso8601,
          changes: action.all_changes.map { |c| c.field.to_s },
          comment: action.comment
        }.compact
      end

      # Format a single revision with full content snapshot
      def revision_json(action)
        # Build the snapshot from the action's changes
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
        # Get the values set by this action
        # For fields not changed in this action, we need to look at previous actions

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

        # If content wasn't changed in this action, we need to look back
        if snapshot[:content].nil?
          # Find the most recent action that set content before this one
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
        # Find the action at that act
        action = Card::Action.joins(:act)
                             .where(card_id: @card.id, card_acts: { id: act_id })
                             .first

        unless action
          return render_error("not_found", "Revision not found",
                              { card: @card.name, act_id: act_id }, status: :not_found)
        end

        # Get the content at that revision
        snapshot = build_snapshot_at_action(action)

        # Update the card with the snapshot content
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
