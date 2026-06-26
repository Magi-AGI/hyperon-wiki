# frozen_string_literal: true

# Binds the AtomSpace read client (Lane C, L9). This MUST be an app-level initializer:
# Decko does NOT load new files placed under mod/*/config/initializers (verified on the dev
# box 2026-06-11 for both routes and this binding), so it cannot live in mod/mcp_api.
# mod lib is not autoloaded either, so require the port explicitly.
require_relative "../../mod/mcp_api/lib/atomspace/read_client"

# FAIL-CLOSED: bind FakeReadClient ONLY in test/development, or on demand via
# ATOMSPACE_READ_CLIENT=fake (e.g. a dev-server smoke test). In production with nothing bound,
# Atomspace::ReadClient.for raises ServiceUnavailable and the controller returns 503 -- never
# fake/empty data.
if Rails.env.test? || Rails.env.development? || ENV["ATOMSPACE_READ_CLIENT"] == "fake"
  require_relative "../../mod/mcp_api/lib/atomspace/fake_read_client"
  Atomspace::ReadClient.bind!(Atomspace::FakeReadClient)
end

# TODO(Lane B): in production, bind the real client here once the sidecar read-IPC verb exists:
#   require_relative "../../mod/mcp_api/lib/atomspace/sidecar_read_client"  # (when added)
#   Atomspace::ReadClient.bind!(Atomspace::SidecarReadClient) unless Rails.env.test?
# ReadConsistencyPort (L7) is wired separately by Lane A's mod/atomspace_mirror engine.
