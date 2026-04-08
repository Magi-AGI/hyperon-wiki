# frozen_string_literal: true

module Mcp
  # Centralized role management that integrates with Decko's role system.
  #
  # == Permission Architecture
  #
  # Permissions are handled by Decko's native +*read rules, NOT by role checks:
  #
  # 1. Decko permissions (+*read rules) control who can see what content
  # 2. Child cards automatically inherit parent permissions via permission_propagation mod
  # 3. MCP roles (admin, gm, user) are used for:
  #    - Token authentication and role validation
  #    - Admin-only operations (delete, rename, trash)
  #    - NOT for content visibility filtering (use +*read rules instead)
  #
  # == Setting Up GM-Only Content
  #
  # To restrict content to GM/admin users:
  # 1. Create the parent card (e.g., "Games+MyGame+GM Content")
  # 2. Create +*self+*read rule: "Games+MyGame+GM Content+*self+*read"
  # 3. Set content to: "[[Game Master]]\n[[Administrator]]"
  # 4. All child cards will automatically inherit this restriction
  #
  # == Migration from Name-Based Filtering
  #
  # Previously, content with +GM or +AI in the name was filtered by role.
  # This is now DEPRECATED. Cards should have proper +*read rules set instead.
  # The can_view_gm_content? method is retained for auth level calculations
  # but is no longer used for content filtering.
  class Roles
    # Legacy MCP role names for backwards compatibility
    ADMIN = "admin"
    GM = "gm"
    USER = "user"

    # Map Decko role names to MCP role names
    # Keys are Decko role names (case-insensitive), values are MCP role names
    DECKO_TO_MCP_MAP = {
      "administrator" => ADMIN,
      "admin" => ADMIN,
      "game master" => GM,
      "gm" => GM
    }.freeze

    # Roles that have elevated privileges in the MCP system.
    # DEPRECATED: This was used for name-based content filtering (+GM, +AI patterns).
    # Content visibility should now be controlled by Decko's +*read rules instead.
    # Retained for backwards compatibility in role level calculations.
    GM_CONTENT_ROLES = [ADMIN, GM, "game master", "administrator", "magi team"].freeze

    class << self
      # Check if a role name is valid (exists in Decko)
      #
      # @param role [String] Role name to check
      # @return [Boolean] True if role exists in Decko or is a legacy MCP role
      def valid?(role)
        return true if legacy_mcp_role?(role)
        decko_role_exists?(role)
      end

      # Get all valid role names from Decko
      #
      # @return [Array<String>] List of all role names
      def all
        @all_roles ||= fetch_decko_roles
      end

      # Clear cached roles (call when roles are added/removed in Decko)
      def clear_cache!
        @all_roles = nil
      end

      # Check if this is a legacy MCP role (admin, gm, user)
      #
      # @param role [String] Role name
      # @return [Boolean]
      def legacy_mcp_role?(role)
        [ADMIN, GM, USER].include?(role&.downcase)
      end

      # Normalize a Decko role name to MCP role name
      # Returns the original role if no mapping exists
      #
      # @param decko_role [String] Decko role name
      # @return [String] MCP role name
      def normalize(decko_role)
        return USER if decko_role.nil?
        DECKO_TO_MCP_MAP[decko_role.downcase] || decko_role.downcase
      end

      # Get the highest-privilege role from a list of roles
      # Uses Decko's permission system to determine hierarchy
      #
      # @param roles [Array<String>] List of role names
      # @return [String] Highest-privilege role
      def highest_role(roles)
        return USER if roles.empty?

        # Check for admin first
        return ADMIN if roles.any? { |r| normalize(r) == ADMIN }

        # Check for GM
        return GM if roles.any? { |r| normalize(r) == GM }

        # Return the first non-system role, or USER as default
        custom_role = roles.find { |r| !system_role?(r) }
        custom_role ? normalize(custom_role) : USER
      end

      # DEPRECATED: Check if a role has elevated privileges.
      #
      # Previously used to filter content based on +GM/+AI naming conventions.
      # Content visibility should now be controlled by Decko's +*read rules instead.
      # This method is retained for backwards compatibility in role level calculations.
      #
      # @param role [String] Role name
      # @return [Boolean] True if role has elevated privileges
      # @deprecated Use Decko's +*read rules for content visibility instead
      def can_view_gm_content?(role)
        return true if role.nil? # Nil role defers to Decko permissions
        GM_CONTENT_ROLES.include?(role.downcase)
      end

      # Get role hierarchy level for comparison
      # Higher number = more privileges
      #
      # @param role [String] Role name
      # @return [Integer] Hierarchy level (0 = unknown, 1 = user, 2 = gm, 3 = admin)
      def level(role)
        case normalize(role)
        when ADMIN then 3
        when GM then 2
        when USER then 1
        else
          # Custom roles default to user level unless they're in GM_CONTENT_ROLES
          can_view_gm_content?(role) ? 2 : 1
        end
      end

      # Check if user can request a specific role
      # User can request any role at or below their highest privilege level
      #
      # @param user_roles [Array<String>] User's Decko roles
      # @param requested_role [String] Role being requested
      # @return [Boolean] True if user can use this role
      def can_assume_role?(user_roles, requested_role)
        return false unless valid?(requested_role)

        user_level = level(highest_role(user_roles))
        requested_level = level(requested_role)

        requested_level <= user_level
      end

      private

      # Check if a role exists in Decko
      def decko_role_exists?(role_name)
        all.any? { |r| r.downcase == role_name.downcase }
      end

      # Fetch all roles from Decko
      def fetch_decko_roles
        Card::Auth.as_bot do
          # Get all cards of type Role
          role_type_id = Card.fetch("Role")&.id
          return [ADMIN, GM, USER] unless role_type_id

          roles = Card.where(type_id: role_type_id, trash: false).pluck(:name)
          roles.presence || [ADMIN, GM, USER]
        end
      rescue StandardError => e
        Rails.logger.error("Failed to fetch Decko roles: #{e.message}")
        [ADMIN, GM, USER] # Fallback to legacy roles
      end

      # Check if this is a Decko system role (Anyone, Anyone Signed In, etc.)
      def system_role?(role)
        %w[anyone anyone\ signed\ in].include?(role.downcase)
      end
    end
  end
end
