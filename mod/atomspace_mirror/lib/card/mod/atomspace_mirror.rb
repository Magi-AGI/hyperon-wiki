# frozen_string_literal: true

# Decko mod entry point. Decko auto-requires lib/card/mod/<modname>.rb for mods that ship Ruby
# under lib/ (cf. mod/mcp_api/lib/card/mod/mcp_api.rb). This is the hook that actually loads the
# engine's code at app boot -- Decko does NOT autoload mod lib/, so the require chain is explicit.
#
# No Rails::Engine is declared: Slice 1 ships no app/ directory (the L9 read controller lives in
# mod/mcp_api, Lane C). An engine for app/controllers autoload can be added if/when this mod grows
# a controller.
require_relative "../../atomspace_mirror"

module Card
  module Mod
    module AtomspaceMirror
      # AtomSpace Mirror engine (Lane A): write-through mirror from Decko/Postgres to the Hyperon
      # Space (Phase 4). Slice 1 = schema + models + §10 helper + L7 read-consistency.
    end
  end
end
