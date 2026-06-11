# frozen_string_literal: true

# FAIL-CLOSED binding. FakeReadClient is bound ONLY in test/development so production never
# serves fake/empty AtomSpace data (Codex Finding 1). In production the SidecarReadClient is
# bound once Lane B's read-IPC verb lands; until then ReadClient.for raises ServiceUnavailable
# and the controller returns 503.
if Rails.env.test? || Rails.env.development? || ENV["ATOMSPACE_READ_CLIENT"] == "fake"
  require_relative "../../lib/atomspace/fake_read_client"
  Atomspace::ReadClient.bind!(Atomspace::FakeReadClient)
  # Fake is bound in test/dev, or on demand via ATOMSPACE_READ_CLIENT=fake (e.g. a dev-server
  # smoke test) -- NEVER in production by default (fail-closed). ReadConsistencyPort stays
  # unwired; specs/dev inject a stub.
end
