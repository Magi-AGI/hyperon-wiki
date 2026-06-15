# frozen_string_literal: true

# Decko mod entry point. Decko auto-requires lib/card/mod/<modname>.rb for mods that ship Ruby
# under lib/ (cf. mod/mcp_api/lib/card/mod/mcp_api.rb). This is the hook that loads the engine's
# code at app boot -- Decko does NOT autoload mod lib/, so the require chain is explicit.
#
# The Engine puts the mod's db/migrate on the application migration path so `decko update` /
# `rake db:migrate` actually run the schema migration (Decko does not auto-discover mod db/migrate;
# verified on dev 2026-06-15).
require_relative "../../atomspace_mirror/engine"
require_relative "../../atomspace_mirror"

module Card
  module Mod
    module AtomspaceMirror
      # AtomSpace Mirror engine (Lane A): write-through mirror from Decko/Postgres to the Hyperon
      # Space (Phase 4). Slice 1 = schema + models + §10 helper + L7 read-consistency.
    end
  end
end
