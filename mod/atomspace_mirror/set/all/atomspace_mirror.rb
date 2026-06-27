# frozen_string_literal: true
#
# Level 2 -- the integrate_with_delay set hook: the only Decko-runtime entry point for the mirror.
# Fires once per committed create/update/delete and delegates to MirrorOutboxWriter.write, which
# encodes the action and INSERTs a single mirror_outbox row under the Section 1 INSERT discipline.
#
# RUNTIME MODEL (verified on the dev box 2026-06-21, L2b): this deck runs with
# Cardio.config.delaying = false (the card-mod-delayed_job default; the deck never enables it), so
# integrate_with_delay events run INLINE in the saving request -- NOT in a delayed worker. Therefore:
#   * `self` and `current_action` expose correct AS-OF-THIS-ACTION state (db_content, references_out,
#     trash), so the post-state hazard (a delayed job re-reading current state under an older
#     action_id) does not arise here and no historical-snapshot reconstruction is needed.
#   * Card::Auth.serialize and Card::Director.act are the live save-time values.
#   * Card::Env.params is the live request's params (empty outside a web request; Source-6 agent
#     context is therefore unavailable until the MCP write path stashes it -- passed as {} for V1).
# If delaying is ever enabled, this must be revisited (L2 card 17170 / OQ#16): `self`'s core
# attributes would then be the GlobalID-refetched CURRENT card and as-of-N state would have to be
# rebuilt from current_action + change history before encoding.
#
# CONSTANT RESOLUTION: inside a Decko set module bare constants resolve under Card::Set::All::* first
# (e.g. `File` => Card::Set::All::File -- a real gotcha, see L2b notes), so every top-level constant
# is referenced fully-qualified (::MirrorOutboxWriter, ::Card).
event :write_to_mirror_outbox, :integrate_with_delay, on: %i[create update delete] do
  # current_action is Decko's per-act Card::Action (correct as-of-this-action inline). The writer
  # derives pre_state from it (via Card::Action#previous_value, normalized through the locked
  # field_name mapping) so a corrupt/numeric card_changes.field becomes a terminal 'failed' row
  # rather than crashing the write path -- see MirrorOutboxWriter#derive_pre_state.
  # Deploy-safety gate: do NOTHING unless the mirror is explicitly activated
  # (ATOMSPACE_MIRRORING_ENABLED=true). Shipping the mod with the mirror dormant must never add work
  # to -- or break -- a card save (e.g. before the mirror tables are migrated). See
  # MirrorOutboxWriter.enabled?.
  next unless ::MirrorOutboxWriter.enabled?

  action = current_action
  ::MirrorOutboxWriter.write(action, auth: ::Card::Auth.serialize) if action
end
