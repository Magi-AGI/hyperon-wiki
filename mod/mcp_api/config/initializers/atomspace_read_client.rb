# frozen_string_literal: true

# FAIL-CLOSED binding. FakeReadClient is bound ONLY in test/development so production never
# serves fake/empty AtomSpace data (Codex Finding 1). In production the SidecarReadClient is
# bound once Lane B's read-IPC verb lands; until then ReadClient.for raises ServiceUnavailable
# and the controller returns 503.
if Rails.env.test? || Rails.env.development?
  require_dependency "atomspace/fake_read_client"
  Atomspace::ReadClient.bind!(Atomspace::FakeReadClient)
  # ReadConsistencyPort is left unwired by default; specs inject a stub per example.
end
