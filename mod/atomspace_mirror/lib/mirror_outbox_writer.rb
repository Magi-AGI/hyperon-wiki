# frozen_string_literal: true

require_relative "card_atom_encoder"

# Level 2 -- outbox writer (the business logic behind the integrate_with_delay hook). Encodes the
# action and INSERTs a single mirror_outbox row under the Section 1 (Rider C v2) INSERT discipline.
# Unit-testable in isolation; the Decko set hook (set/all/atomspace_mirror.rb) is a one-line
# delegation passing `action = current_action` + `auth = Card::Auth.serialize`.
#
# RUNTIME MODEL (L2b dev-validated 2026-06-21): on this deck Cardio.config.delaying is false, so the
# integrate_with_delay hook runs INLINE in the saving request -- `action` (Decko's current_action)
# exposes correct AS-OF-THIS-ACTION state, so there is no delayed-worker post-state hazard and no
# snapshot reconstruction is needed. (If delaying is ever enabled, revisit: `action.card` could then
# reflect a later edit -- see L2 card 17170.)
#
# `action` CONTRACT: a Card::Action exposing #card (+ #references_out), #card_changes, #act,
# #id/#card_id/#draft/#action_type/#super_action_id, AND #previous_value(field) (used to derive
# pre_state). auth = Card::Auth.serialize ({current_id:, as_id:}). request_context = the Source-6
# agent fields from Card::Env.params ({} until an MCP write path stashes them -- Open Questions #18).
module MirrorOutboxWriter
  module_function

  # Exact set of the mirror's OWN cards (by codename) whose saves must NOT be mirrored -- e.g. the
  # mod/asset/system cards Decko creates for this mod. This is an EXACT codename set, NOT a
  # "mirror_*" key prefix: an ordinary user card whose key merely starts with "mirror_" IS mirrored.
  # Seeded with the mod card; the full membership is finalized once the installed mod's cards are
  # known on dev (L2b).
  SELF_CARD_CODENAMES = %w[mod_atomspace_mirror].freeze

  # MASTER ACTIVATION GATE (deploy safety). The integrate hook calls `write` only when this is true;
  # it is OFF unless ATOMSPACE_MIRRORING_ENABLED is explicitly "true". So the mod can be SHIPPED to a
  # server (code present, hook loaded) while the mirror is still dormant -- no mirror_state table
  # required, no outbox writes, zero added work on a card save -- and a save can NEVER break because
  # the mirror isn't migrated/bootstrapped yet. Activation is a deliberate op: migrate the mirror
  # tables, bootstrap the corpus, start the sidecar + drain worker, THEN set the env and restart.
  def enabled?
    ENV["ATOMSPACE_MIRRORING_ENABLED"].to_s.strip.casecmp?("true")
  end

  def write(action, pre_state: nil, auth:, request_context: {})
    # Validate the auth contract LOUDLY here -- an L2b wiring bug must not be swallowed into a
    # 'failed' row by the encode rescue below (that rescue is only for genuine encode/data corruption).
    unless auth.is_a?(Hash) && auth.key?(:current_id) && auth.key?(:as_id)
      raise ArgumentError, "auth: must be a Hash with :current_id and :as_id keys"
    end
    return if mirror_own_card?(action.card)
    return if action.draft

    # Derive pre_state + encode OUTSIDE the state lock (keeps the singleton lock short). BOTH run in
    # the same rescue: a corrupt card_changes.field raises CardAtomEncoder::EncodingError from
    # field_name (in derive_pre_state OR encode) -> a terminal 'failed' row, never a dropped event.
    # Unexpected bugs (NoMethodError etc.) still propagate loudly. Callers may inject pre_state
    # (bootstrap/reconcile); the inline hook passes none -> derived from the action here.
    atoms = nil
    encode_error = nil
    begin
      effective_pre_state = pre_state || derive_pre_state(action)
      atoms = CardAtomEncoder.encode(action, pre_state: effective_pre_state, auth: auth, request_context: request_context)
    rescue CardAtomEncoder::EncodingError => e
      encode_error = e
    end

    MirrorOutbox.transaction do
      state = MirrorState.lock.first # SELECT FOR UPDATE; atomic vs bootstrap completion
      if superseded_by_bootstrap?(state, action)
        # Sweep already covered this card: terminal-advance REGARDLESS of encode outcome. A corrupt
        # encode must NOT override this -> superseded_by_bootstrap (payload best-effort). (Codex blocker.)
        insert_row(event_id: event_id(action), action_id: action.id, card_id: action.card_id,
                   status: "superseded_by_bootstrap", payload: (atoms && { "atoms" => atoms }))
      elsif encode_error
        # Corrupt input -> terminal 'failed' so check_event_ready returns event_failed instead of a
        # never-inserted row that times out as staleness.
        insert_row(event_id: event_id(action), action_id: action.id, card_id: action.card_id,
                   status: "failed", payload: nil, error: encode_error.message)
      else
        insert_row(event_id: event_id(action), action_id: action.id, card_id: action.card_id,
                   status: "queued", payload: { "atoms" => atoms })
      end
    end
  end

  # pre-action field values for the encoder's provenance `changes`. Each card_changes.field is
  # normalized through the SAME locked mapping the encoder uses -- CardAtomEncoder.field_name, which
  # accepts the Decko name string OR the raw integer TRACKED_FIELDS index (the source archive
  # documents the integer form) -- so a numeric field never crashes the write path; a corrupt field
  # raises EncodingError here, inside write's rescue, -> a terminal 'failed' row. The prior value is
  # read via Card::Action#previous_value (card.last_change_on field, before: self; nil on :create).
  def derive_pre_state(action)
    Array(action.card_changes).each_with_object({}) do |ch, h|
      field = CardAtomEncoder.field_name(ch.field)
      h[field] = action.previous_value(field.to_sym)
    end
  end

  def mirror_own_card?(card)
    cn = card.codename
    cn.present? && SELF_CARD_CODENAMES.include?(cn.to_s)
  end

  # action.id <= the persisted bootstrap anchor => the sweep already covered this card (Section 1).
  def superseded_by_bootstrap?(state, action)
    !state.bootstrap_a_start.nil? && action.id <= state.bootstrap_a_start
  end

  # RecordNotUnique is rescued NARROWLY around the INSERT only -- idempotent no-op on a duplicate
  # event_id / (action_id, decko_action) from replay, retry, or concurrent integrate-jobs. It must
  # not wrap the encoder or the state lock (which would mask unrelated failures).
  def insert_row(**attrs)
    MirrorOutbox.create!(event_kind: "decko_action", **attrs)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def event_id(action)
    "decko:action:#{action.id}"
  end
end
