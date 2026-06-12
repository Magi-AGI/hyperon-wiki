# frozen_string_literal: true

module McpApi
  # Explicit allowlist of principals granted the mcp:atomspace:read scope (the dedicated
  # AtomSpace read toolset / L9 read API). DELIBERATELY explicit -- NOT derived from role or
  # admin (Codex guardrail): possessing mcp:admin does not imply AtomSpace read access.
  #
  # Configured via ENV ATOMSPACE_READ_GRANTS as a comma-separated list of principal ids that
  # match the JWT `sub` (e.g. "user:Administrator,key:9f3c..."). Empty by default => nobody
  # is granted, and the L9 gate denies everyone (fail-closed). Phase 5+ may move this to a
  # per-account card attribute; the interface (granted?/scopes_for) stays the same.
  module AtomspaceGrants
    SCOPE = "mcp:atomspace:read"

    module_function

    def granted?(principal_id)
      principal_id && list.include?(principal_id.to_s)
    end

    def scopes_for(principal_id)
      granted?(principal_id) ? [SCOPE] : []
    end

    def list
      (ENV["ATOMSPACE_READ_GRANTS"] || "").split(",").map(&:strip).reject(&:empty?)
    end
  end
end
