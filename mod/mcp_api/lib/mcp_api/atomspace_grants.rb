# frozen_string_literal: true

require_relative "../mcp/user_authenticator"

module McpApi
  # Decides which principals receive the AtomSpace scopes (the dedicated AtomSpace toolset /
  # L9 read API + the card-scoped B3 admin quarantine surface) at token-mint time.
  #
  # == POLICY REV5 (owner decision) -- supersedes REV4
  #
  # OWNER DIRECTION (recorded verbatim in intent): admins and `Raw Data Analyst` principals are
  # TRUSTED WITH FULL AtomSpace BACKEND ACCESS. The near-term goal is a working two-way
  # Decko card <-> AtomSpace atom migration path for the demo; granular separation between read,
  # write, and admin AtomSpace scopes is DEPRIORITIZED relative to getting that path functional.
  # Scope plumbing is retained (three distinct scope strings, each independently checked at the
  # surface) so the separation can be re-tightened later without a re-architecture -- but policy
  # today hands all three to the same two principal classes.
  #
  # Scopes minted:
  #
  #   mcp:atomspace:read   -- L9 card-scoped + aggregate reads
  #   mcp:atomspace:write  -- (forward-looking) card -> atom mutation surface
  #   mcp:atomspace:admin  -- card-scoped B3 quarantine (DESTRUCTIVE; removes atoms from the Space)
  #
  # Grant matrix:
  #
  #   1. ADMIN principals            -> read + write + admin (policy-granted, no ENV entry needed)
  #   2. `Raw Data Analyst` principals -> read + write + admin (policy-granted, no ENV entry needed)
  #   3. ENV ATOMSPACE_READ_GRANTS   -> read ONLY. The allowlist stays a READ escape hatch for
  #      service accounts / API keys / one-off manual grants; it never confers write or admin.
  #      Comma-separated principal ids matching the JWT `sub` (e.g. "user:Administrator,key:9f3c").
  #   4. API-key principals          -> allowlist only (NOTHING auto-granted). See #scopes_for.
  #
  # What REV5 changes vs REV4: REV4 minted read alone and left quarantine behind a generic
  # `mcp:admin` scope that this module never minted -- making quarantine a permanent 403. REV5
  # mints the NAMESPACED `mcp:atomspace:admin` instead, so the card-scoped B3 quarantine surface is
  # reachable by exactly the principals the owner designated, and the generic `mcp:admin` scope is
  # no longer involved in the AtomSpace surface at all.
  #
  # What REV5 does NOT change:
  #
  #   * The generic `mcp:admin` scope is still NEVER minted here. AtomSpace authority is namespaced.
  #   * API-key principals are still auto-granted NOTHING -- allowlist only (read only).
  #   * Card-scoped READ responses are still filtered per-atom through Decko read rules
  #     (AtomspaceReadFilter -> Card::Auth.as + card.ok?(:read)). This module widens who may CALL
  #     the L9 surface; it does not widen what any caller may SEE. Admins pass that filter via
  #     Decko's own admin bypass; a Raw Data Analyst sees exactly what their +*read rules allow.
  #   * Role/admin lookup failures FAIL CLOSED (deny scope, never 500 the auth endpoint).
  #
  # ACCEPTED RISK (owner-directed, REV5): a `Raw Data Analyst` who is NOT a Decko admin now holds
  # mcp:atomspace:admin, so they can quarantine atoms scoped to a card whose content their +*read
  # rules would hide. That is the explicit demo-velocity tradeoff above, not an oversight. Tighten
  # by splitting the quarantine grant off #policy_granted_user? when granularity is re-prioritized.
  module AtomspaceGrants
    READ_SCOPE  = "mcp:atomspace:read"
    WRITE_SCOPE = "mcp:atomspace:write"
    ADMIN_SCOPE = "mcp:atomspace:admin"

    # Full backend access, in a stable order (token `scope` claim is a space-joined string).
    FULL_SCOPES = [READ_SCOPE, WRITE_SCOPE, ADMIN_SCOPE].freeze

    # Retained for pre-REV5 callers that referenced the single read scope constant.
    SCOPE = READ_SCOPE

    # Decko role granted full AtomSpace scopes by policy. Matched with case + separator folding
    # (see #normalize_role) because the role card may be titled "Raw Data Analyst",
    # "Raw-Data-Analyst", "raw_data_analyst", etc.
    RAW_DATA_ANALYST_ROLE = "Raw Data Analyst"

    module_function

    # Scopes to embed in a freshly minted token.
    #
    # Policy (admin / Raw Data Analyst) is evaluated BEFORE the ENV allowlist so an allowlisted
    # admin is not silently downgraded to read-only by the narrower match.
    #
    # @param principal_id [String] the JWT `sub` ("user:<name>" or "key:<id>")
    # @param user_card [Card, nil] the AUTHENTICATED Decko user card when the principal is a
    #   human. Deliberately nil for API-key principals: an API key's role is CALLER-SUPPLIED and
    #   only checked against the key card's own `allowed_roles` metadata
    #   (Mcp::ApiKeyManager.role_allowed?), while the legacy ENV MCP_API_KEY is permitted every
    #   role unconditionally (AuthController#allowed_role_for_key? returns true). A token
    #   claiming role "admin" from an API key is therefore self-asserted, not evidence of an
    #   admin principal -- so a leaked key must not silently acquire the raw-data surface, let
    #   alone the destructive quarantine surface. Keys that legitimately need reads get an
    #   explicit "key:<id>" entry in ATOMSPACE_READ_GRANTS.
    # @return [Array<String>]
    def scopes_for(principal_id, user_card: nil)
      return FULL_SCOPES.dup if policy_granted_user?(user_card)
      return [READ_SCOPE] if granted?(principal_id)

      []
    end

    # Explicit ENV allowlist match. READ scope only -- never write, never admin.
    def granted?(principal_id)
      principal_id && list.include?(principal_id.to_s)
    end

    # REV5 role-derived FULL grant for human principals (admin or Raw Data Analyst).
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
