# frozen_string_literal: true

require "securerandom"
require "digest"
require "json"

module Mcp
  # Card-based API key management for MCP API
  # Stores API keys as Cards instead of ActiveRecord models
  #
  # Structure:
  #   MCP API Keys (container card)
  #   ├── admin_key (type: MCP API Key)
  #   │   ├── +key_hash (SHA256 of the key)
  #   │   ├── +metadata (JSON with name, roles, limits, etc.)
  #   │   └── +last_used_at (timestamp)
  #   └── user_key (type: MCP API Key)
  #       └── ...
  class ApiKeyManager
    CONTAINER_NAME = "MCP API Keys"
    TYPE_NAME = "MCP API Key"
    VALID_ROLES = %w[user gm admin].freeze

    class << self
      # Generate a new API key
      #
      # @param name [String] Human-readable name (becomes card name slug)
      # @param roles [Array<String>] Allowed roles
      # @param rate_limit [Integer] Requests per hour
      # @param expires_in [ActiveSupport::Duration, nil] Expiration duration
      # @param created_by [String, nil] Admin who created the key
      # @param contact_email [String, nil] Key holder's email
      # @param description [String, nil] Additional notes
      # @return [Hash] { card: Card, api_key: String }
      def generate(name:, roles: ["user"], rate_limit: 1000, expires_in: nil,
                   created_by: nil, contact_email: nil, description: nil)
        # Generate cryptographically secure random key
        api_key = SecureRandom.hex(32) # 64 hex chars
        key_hash = Digest::SHA256.hexdigest(api_key)
        key_prefix = api_key[0..7]

        # Create slug-safe card name from human name
        card_name = "#{CONTAINER_NAME}+#{name.parameterize}"

        # Prepare metadata
        metadata = {
          name: name,
          description: description,
          allowed_roles: Array(roles),
          rate_limit_per_hour: rate_limit,
          expires_at: expires_in ? (Time.current + expires_in).iso8601 : nil,
          created_by: created_by,
          created_at: Time.current.iso8601,
          contact_email: contact_email,
          active: true,
          key_prefix: key_prefix
        }

        # Validate roles
        invalid_roles = Array(roles) - VALID_ROLES
        if invalid_roles.any?
          raise ArgumentError, "Invalid roles: #{invalid_roles.join(', ')}. Valid: #{VALID_ROLES.join(', ')}"
        end

        # Create the API key card with subcards
        Card::Auth.as_bot do
          # Ensure container exists
          ensure_container_exists!

          # Create key card
          key_card = Card.create!(
            name: card_name,
            type: TYPE_NAME,
            content: "API Key: #{name}"
          )

          # Create subcards for data storage
          Card.create!(name: "#{card_name}+key_hash", content: key_hash)
          Card.create!(name: "#{card_name}+metadata", content: metadata.to_json)
          Card.create!(name: "#{card_name}+last_used_at", content: "")

          { card: key_card, api_key: api_key }
        end
      end

      # Find an API key by plaintext value
      #
      # @param api_key [String] The plaintext API key
      # @return [Card, nil] The key card if found and valid
      def find_by_key(api_key)
        return nil if api_key.blank?

        key_hash = Digest::SHA256.hexdigest(api_key)

        Card::Auth.as_bot do
          # Search for cards with matching key_hash subcard
          results = Card.search(
            type: TYPE_NAME,
            right_plus: ["key_hash", { content: key_hash }]
          )

          key_card = results.first
          return nil unless key_card

          # Check if key is active and not expired
          return nil unless valid_for_use?(key_card)

          key_card
        end
      end

      # Authenticate with an API key (find and touch last_used_at)
      #
      # @param api_key [String] The plaintext API key
      # @return [Card, nil] The key card if authenticated
      def authenticate(api_key)
        key_card = find_by_key(api_key)
        return nil unless key_card

        # Update last_used_at
        touch_last_used!(key_card)

        key_card
      end

      # Check if a role is allowed for this key card
      #
      # @param key_card [Card] The key card
      # @param role [String, Symbol] The role to check
      # @return [Boolean] True if role is allowed
      def role_allowed?(key_card, role)
        metadata = get_metadata(key_card)
        return false unless metadata

        Array(metadata["allowed_roles"]).include?(role.to_s)
      end

      # Get metadata hash from key card
      #
      # @param key_card [Card] The key card
      # @return [Hash, nil] Metadata hash
      def get_metadata(key_card)
        Card::Auth.as_bot do
          metadata_card = Card.fetch("#{key_card.name}+metadata")
          return nil unless metadata_card

          JSON.parse(metadata_card.content)
        rescue JSON::ParserError
          nil
        end
      end

      # Check if key is currently valid (active and not expired)
      #
      # @param key_card [Card] The key card
      # @return [Boolean] True if valid
      def valid_for_use?(key_card)
        metadata = get_metadata(key_card)
        return false unless metadata
        return false unless metadata["active"]

        # Check expiration
        if metadata["expires_at"]
          expires_at = Time.parse(metadata["expires_at"])
          return false if expires_at <= Time.current
        end

        true
      end

      # Update last_used_at timestamp
      #
      # @param key_card [Card] The key card
      def touch_last_used!(key_card)
        Card::Auth.as_bot do
          last_used_card = Card.fetch("#{key_card.name}+last_used_at")
          if last_used_card
            last_used_card.update!(content: Time.current.iso8601)
          end
        end
      rescue StandardError => e
        Rails.logger.warn("Failed to update last_used_at for #{key_card.name}: #{e.message}")
      end

      # Deactivate a key (soft delete)
      #
      # @param key_card [Card] The key card
      def deactivate!(key_card)
        Card::Auth.as_bot do
          metadata = get_metadata(key_card)
          return unless metadata

          metadata["active"] = false
          metadata_card = Card.fetch("#{key_card.name}+metadata")
          metadata_card.update!(content: metadata.to_json) if metadata_card
        end
      end

      # Reactivate a key
      #
      # @param key_card [Card] The key card
      def activate!(key_card)
        Card::Auth.as_bot do
          metadata = get_metadata(key_card)
          return unless metadata

          metadata["active"] = true
          metadata_card = Card.fetch("#{key_card.name}+metadata")
          metadata_card.update!(content: metadata.to_json) if metadata_card
        end
      end

      # Get all active API keys
      #
      # @return [Array<Card>] Active key cards
      def all_active
        Card::Auth.as_bot do
          Card.search(type: TYPE_NAME).select { |card| valid_for_use?(card) }
        end
      end

      # Get usage info for a key
      #
      # @param key_card [Card] The key card
      # @return [Hash] Usage information
      def usage_info(key_card)
        metadata = get_metadata(key_card)
        return {} unless metadata

        last_used_card = Card.fetch("#{key_card.name}+last_used_at")
        last_used_at = last_used_card&.content.present? ? Time.parse(last_used_card.content) : nil

        {
          name: metadata["name"],
          last_used: last_used_at&.iso8601,
          days_since_last_use: last_used_at ? ((Time.current - last_used_at) / 1.day).floor : nil,
          status: key_status(key_card),
          expires_at: metadata["expires_at"],
          active: metadata["active"],
          allowed_roles: metadata["allowed_roles"]
        }
      end

      private

      # Get human-readable status
      def key_status(key_card)
        metadata = get_metadata(key_card)
        return "unknown" unless metadata
        return "inactive" unless metadata["active"]

        if metadata["expires_at"]
          expires_at = Time.parse(metadata["expires_at"])
          return "expired" if expires_at <= Time.current
        end

        "active"
      end

      # Ensure container card exists
      def ensure_container_exists!
        unless Card.exists?(CONTAINER_NAME)
          Card.create!(
            name: CONTAINER_NAME,
            type: "Basic",
            content: "Container for MCP API keys"
          )
        end

        # Ensure type exists
        unless Card.exists?(TYPE_NAME)
          Card.create!(
            name: TYPE_NAME,
            type: "Cardtype",
            content: "API Key for MCP authentication"
          )
        end
      end
    end
  end
end
