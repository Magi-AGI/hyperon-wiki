# frozen_string_literal: true

# AtomSpace Mirror engine (Lane A) -- Slice 1 entry point.
#
# Requires the engine's models + the read-consistency module. Loaded explicitly because Decko does
# not autoload mod lib/. The integration glue -- an app-level initializer that requires this file
# and binds ReadConsistency into Lane C's Atomspace::ReadConsistencyPort -- is added when Lane A and
# Lane C combine (Lane C's port lives in mod/mcp_api, not on this branch).
require_relative "mirror_state"
require_relative "mirror_outbox"
require_relative "mirror_bootstrap_run"
require_relative "mirror_reconcile_run"
require_relative "read_consistency"
require_relative "card_atom_encoder"
require_relative "mirror_outbox_writer"
# Slice 3 (L8 drain): shared constants/watermark, the structural+identity preflight, and the IPC
# client. Required here so the deck initializer's `require "atomspace_mirror"` loads them at runtime
# (the specs require them directly, which does NOT prove runtime availability -- Codex 2026-06-22).
require_relative "mirror"
require_relative "mirror_drain_validator"
require_relative "sidecar_client"
require_relative "drain_worker"
