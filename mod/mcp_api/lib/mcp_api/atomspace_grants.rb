# frozen_string_literal: true

require_relative "../mcp/user_authenticator"

module McpApi
  # Decides which principals receive the mcp:atomspace:read scope (the dedicated AtomSpace read
  # toolset / L9 read API) at token-mint time.
  #
  # == POLICY REV4 (owner decision) -- supersedes REV3
  #
  # The AtomSpace mirror IS the raw-data surface, so read scope follows the two principal classes
  # that are already entitled to raw data inside Decko, plus an explicit escape hatch:
  #
  #   1. ADMIN principals. Decko administrators already bypass card read rules, so withholding
  #      the mirror's read scope from them protected nothing while making the L9 surface
  #      unusable for the operators it exists for.
  #   2. `Raw Data Analyst` principals -- the Decko role designed for full raw-data access, which
  #      is precisely what AtomSpace access represents.
  #   3. EXPLICIT allowlist via ENV ATOMSPACE_READ_GRANTS (comma-separated principal ids matching
  #      the JWT `sub`, e.g. "user:Administrator,key:9f3c..."). Retained for service accounts,
  #      API keys, and one-off manual grants.
  #
  # REV3 was "explicit allowlist only; NOT derived from role or admin". That guardrail is
  # retired for admin / Raw Data Analyst. Two things it protected are NOT retired:
  #
  #   * mcp:admin remains a SEPARATE scope. Read scope never implies it, so the quarantine
  #     endpoints (which require mcp:atomspace:read AND mcp:admin) stay admin-only: a Raw Data
  #     Analyst gets reads, never quarantine.
  #   * API-key principals are auto-granted NOTHING -- allowlist only. See #scopes_for.
  #
  # Card-scoped responses are still filtered per-atom through Decko read rules
  # (AtomspaceReadFilter -> Card::Auth.as + card.ok?(:read)). This module widens who may CALL
  # the L9 surface; it does not widen what any caller may SEE. Admins pass that filter anyway
  # via Decko's own admin bypass; a Raw Data Analyst sees exactly the cards their +*read rules
  # already allow.
  module AtomspaceGrants
    SCOPE = "mcp:atomspace:read"

    # Decko role granted AtomSpace read scope by policy. Matched with case + separator folding
    # (see #normalize_role) because the role card may be titled "Raw Data Analyst",
    # "Raw-Data-Analyst", "raw_data_analyst", etc.
    RAW_DATA_ANALYST_ROLE = "Raw Data Analyst"

    module_function

    # Scopes to embed in a freshly minted token.
    #
    # @param principal_id [String] the JWT `sub` ("user:<name>" or "key:<id>")
    # @param user_card [Card, nil] the AUTHENTICATED Decko user card when the principal is a
    #   human. Deliberately nil for API-key principals: an API key's role is CALLER-SUPPLIED and
    #   only checked against the key card's own `allowed_roles` metadata
    #   (Mcp::ApiKeyManager.role_allowed?), while the legacy ENV MCP_API_KEY is permitted every
    #   role unconditionally (AuthController#allowed_role_for_key? returns true). A token
    #   claiming role "admin" from an API key is therefore self-asserted, not evidence of an
    #   admin principal -- so a leaked key must not silently acquire the raw-data surface. Keys
    #   that legitimately need it get an explicit "key:<id>" entry in ATOMSPACE_READ_GRANTS.
    # @return [Array<String>]
    def scopes_for(principal_id, user_card: nil)
      return [SCOPE] if granted?(principal_id)
      return [SCOPE] if policy_granted_user?(user_card)

      []
    end

    # Explicit ENV allowlist match.
    def granted?(principal_id)
      principal_id && list.include?(principal_id.to_s)
    end

    # REV4 role-derived grant for human principals.
    def policy_granted_user?(user_card)
      return false unless user_card

      admin_principal?(user_card) || raw_data_analyst?(user_card)
    end

    # Same admin determination the role detector uses (Mcp::UserAuthenticator.determine_role),
    # so token scope and token role can never disagree about who is an admin.
    def admin_principal?(user_card)
      ::Mcp::UserAuthenticator.check_admin_status(user_card)
    rescue StandardError => e
      warn_grant_failure("admin", user_card, e)
      false
    end

    def raw_data_analyst?(user_card)
      target = normalize_role(RAW_DATA_ANALYST_ROLE)
      ::Mcp::UserAuthenticator.get_user_roles(user_card).any? { |r| normalize_role(r) == target }
    rescue StandardError => e
      warn_grant_failure("raw_data_analyst", user_card, e)
      false
    end

    def list
      (ENV["ATOMSPACE_READ_GRANTS"] || "").split(",").map(&:strip).reject(&:empty?)
    end

    # Fold case and separators: Decko name keys treat space and hyphen as equivalent, so role
    # cards can legitimately be named with either.
    def normalize_role(role)
      role.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end

    # Fail closed and leave a trace: a role/admin lookup blowing up must deny scope, not 500 the
    # auth endpoint (a denied grant is a 403 on the L9 surface, which is triageable).
    def warn_grant_failure(kind, user_card, error)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      principal = user_card.respond_to?(:name) ? user_card.name : user_card.class.name
      Rails.logger.warn("AtomspaceGrants: #{kind} check failed for #{principal}: #{error.message}")
    end
  end
end
