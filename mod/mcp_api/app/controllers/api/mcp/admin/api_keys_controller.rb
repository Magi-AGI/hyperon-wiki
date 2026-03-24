# frozen_string_literal: true

require_relative "../../../../../lib/mcp/api_key_manager"

module Api
  module Mcp
    module Admin
      # Admin controller for managing MCP API keys via web interface
      # Requires admin authentication
      class ApiKeysController < BaseController
        before_action :require_admin_role
        before_action :set_api_key, only: [:show, :update, :destroy]

        # GET /api/mcp/admin/api_keys
        # List all API keys
        def index
          keys = ::Mcp::ApiKeyManager.all_active
          key_data = keys.map do |key_card|
            metadata = ::Mcp::ApiKeyManager.get_metadata(key_card)
            usage = ::Mcp::ApiKeyManager.usage_info(key_card)

            {
              id: key_card.id,
              name: metadata["name"],
              key_prefix: metadata["key_prefix"],
              allowed_roles: metadata["allowed_roles"],
              status: usage[:status],
              rate_limit_per_hour: metadata["rate_limit_per_hour"],
              last_used_at: usage[:last_used],
              created_at: metadata["created_at"],
              created_by: metadata["created_by"],
              expires_at: metadata["expires_at"],
              masked_key: "#{metadata['key_prefix']}***"
            }
          end

          # Count statuses
          active_count = key_data.count { |k| k[:status] == "active" }
          expired_count = key_data.count { |k| k[:status] == "expired" }
          inactive_count = key_data.count { |k| k[:status] == "inactive" }

          render json: {
            keys: key_data,
            summary: {
              total: key_data.count,
              active: active_count,
              expired: expired_count,
              inactive: inactive_count
            }
          }
        end

        # GET /api/mcp/admin/api_keys/:id
        # Show specific API key details
        def show
          metadata = ::Mcp::ApiKeyManager.get_metadata(@key_card)
          usage = ::Mcp::ApiKeyManager.usage_info(@key_card)

          render json: {
            id: @key_card.id,
            name: metadata["name"],
            key_prefix: metadata["key_prefix"],
            allowed_roles: metadata["allowed_roles"],
            status: usage[:status],
            active: metadata["active"],
            expired: usage[:status] == "expired",
            rate_limit_per_hour: metadata["rate_limit_per_hour"],
            last_used_at: usage[:last_used],
            created_at: metadata["created_at"],
            created_by: metadata["created_by"],
            contact_email: metadata["contact_email"],
            description: metadata["description"],
            expires_at: metadata["expires_at"],
            days_until_expiration: calculate_days_until_expiration(metadata["expires_at"]),
            usage_info: usage,
            masked_key: "#{metadata['key_prefix']}***"
          }
        end

        # POST /api/mcp/admin/api_keys
        # Generate a new API key
        def create
          result = ::Mcp::ApiKeyManager.generate(
            name: params[:name] || "Key #{Time.current.to_i}",
            roles: Array(params[:roles]).presence || ["user"],
            rate_limit: params[:rate_limit]&.to_i || 1000,
            expires_in: params[:expires_in_days] ? params[:expires_in_days].to_i.days : nil,
            created_by: current_admin_name,
            contact_email: params[:contact_email],
            description: params[:description]
          )

          metadata = ::Mcp::ApiKeyManager.get_metadata(result[:card])

          render json: {
            message: "API key generated successfully",
            key: {
              id: result[:card].id,
              name: metadata["name"],
              allowed_roles: metadata["allowed_roles"],
              api_key: result[:api_key],  # Only time this is returned!
              key_prefix: metadata["key_prefix"],
              rate_limit_per_hour: metadata["rate_limit_per_hour"],
              expires_at: metadata["expires_at"],
              created_at: metadata["created_at"]
            },
            warning: "Store this API key securely - it will never be shown again!"
          }, status: :created
        rescue ArgumentError => e
          render json: {
            error: "validation_error",
            message: e.message
          }, status: :unprocessable_entity
        end

        # PATCH /api/mcp/admin/api_keys/:id
        # Update API key settings
        def update
          metadata = ::Mcp::ApiKeyManager.get_metadata(@key_card)

          # Update metadata fields
          metadata["rate_limit_per_hour"] = params[:rate_limit_per_hour].to_i if params[:rate_limit_per_hour]
          metadata["active"] = params[:active] if params.key?(:active)
          metadata["description"] = params[:description] if params.key?(:description)
          metadata["contact_email"] = params[:contact_email] if params.key?(:contact_email)

          if params.key?(:expires_at)
            metadata["expires_at"] = parse_expiration(params[:expires_at])&.iso8601
          end

          # Save updated metadata
          Card::Auth.as_bot do
            metadata_card = Card.fetch("#{@key_card.name}+metadata")
            metadata_card.update!(content: metadata.to_json)
          end

          usage = ::Mcp::ApiKeyManager.usage_info(@key_card)

          render json: {
            message: "API key updated successfully",
            key: {
              id: @key_card.id,
              name: metadata["name"],
              status: usage[:status],
              active: metadata["active"],
              rate_limit_per_hour: metadata["rate_limit_per_hour"],
              expires_at: metadata["expires_at"],
              description: metadata["description"],
              contact_email: metadata["contact_email"]
            }
          }
        rescue StandardError => e
          render json: {
            error: "update_error",
            message: e.message
          }, status: :unprocessable_entity
        end

        # DELETE /api/mcp/admin/api_keys/:id
        # Delete an API key (hard delete the Card)
        def destroy
          metadata = ::Mcp::ApiKeyManager.get_metadata(@key_card)
          key_name = metadata["name"]
          key_prefix = metadata["key_prefix"]

          Card::Auth.as_bot do
            @key_card.delete!
          end

          render json: {
            message: "API key deleted successfully",
            deleted_key: {
              id: @key_card.id,
              name: key_name,
              key_prefix: key_prefix
            }
          }
        end

        # POST /api/mcp/admin/api_keys/:id/deactivate
        # Deactivate an API key
        def deactivate
          set_api_key
          ::Mcp::ApiKeyManager.deactivate!(@key_card)
          metadata = ::Mcp::ApiKeyManager.get_metadata(@key_card)
          usage = ::Mcp::ApiKeyManager.usage_info(@key_card)

          render json: {
            message: "API key deactivated",
            key: {
              id: @key_card.id,
              name: metadata["name"],
              status: usage[:status],
              active: metadata["active"]
            }
          }
        end

        # POST /api/mcp/admin/api_keys/:id/activate
        # Activate an API key
        def activate
          set_api_key
          ::Mcp::ApiKeyManager.activate!(@key_card)
          metadata = ::Mcp::ApiKeyManager.get_metadata(@key_card)
          usage = ::Mcp::ApiKeyManager.usage_info(@key_card)

          render json: {
            message: "API key activated",
            key: {
              id: @key_card.id,
              name: metadata["name"],
              status: usage[:status],
              active: metadata["active"]
            }
          }
        end

        private

        def set_api_key
          Card::Auth.as_bot do
            @key_card = Card.fetch(params[:id].to_i)
            unless @key_card&.type_name == "MCP API Key"
              return render json: {
                error: "not_found",
                message: "API key not found"
              }, status: :not_found
            end
          end
        rescue Card::Error::NotFound
          render json: {
            error: "not_found",
            message: "API key not found"
          }, status: :not_found
        end

        def require_admin_role
          unless current_role == "admin"
            render_forbidden("This endpoint requires admin role", { required_role: "admin", current_role: current_role })
          end
        end

        def current_admin_name
          # Return the current MCP account name (from JWT)
          current_account&.name || "admin"
        end

        def parse_expiration(value)
          return nil if value.blank? || value == "null" || value == "never"

          if value.is_a?(String) && value.match?(/^\d+$/)
            # Number of days from now
            Time.current + value.to_i.days
          elsif value.is_a?(String)
            # ISO8601 timestamp
            Time.zone.parse(value)
          else
            value
          end
        end

        def calculate_days_until_expiration(expires_at)
          return nil if expires_at.blank?

          expiry_time = Time.parse(expires_at)
          days = ((expiry_time - Time.current) / 1.day).ceil
          days.positive? ? days : 0
        rescue StandardError
          nil
        end
      end
    end
  end
end
