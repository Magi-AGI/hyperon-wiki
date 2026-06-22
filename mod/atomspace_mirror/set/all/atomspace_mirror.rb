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
  action = current_action
  if action
    # pre_state = each changed field's value as of the PRIOR action, so the encoder's provenance
    # `changes` carry real old->new (locked contract). Card::Action#previous_value is Decko's
    # authoritative source (card.last_change_on field, before: self; nil on :create), so this does
    # not depend on dirty-tracking timing. Built here (the only Decko-coupled file) to keep the
    # writer/encoder pure + standalone-testable.
    pre_state = action.card_changes.each_with_object({}) do |ch, h|
      h[ch.field] = action.previous_value(ch.field.to_sym)
    end
    ::MirrorOutboxWriter.write(action, pre_state: pre_state, auth: ::Card::Auth.serialize)
  end
end
