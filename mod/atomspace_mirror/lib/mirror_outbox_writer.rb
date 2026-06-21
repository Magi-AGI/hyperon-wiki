# frozen_string_literal: true

require_relative "card_atom_encoder"

# Level 2 -- outbox writer (the business logic behind the integrate_with_delay hook). Encodes the
# action and INSERTs a single mirror_outbox row under the Section 1 (Rider C v2) INSERT discipline.
# Unit-testable in isolation; the Decko set hook (set/all/atomspace_mirror.rb) is a one-line
# delegation, and L2b gathers the inputs across the delayed-job process boundary (see below).
#
# POST-STATE CONTRACT (Codex 2026-06-21): `action` MUST expose `action.card` + `references_out` AS
# OF this action (the post-action snapshot), NOT current card state. integrate_with_delay runs in a
# delayed worker, possibly after later edits to the same card have committed; encoding current state
# under an older action_id would corrupt provenance and confuse supersession. L2b is responsible for
# supplying the post-action snapshot (or reconstructing it from Card::Action history) and proving it
# with a delayed-two-updates test before the hook is installed. This writer never re-reads current
# state -- it encodes exactly what `action` exposes.
#
# L2b also gathers (across the process boundary): pre_state (from action history), auth
# (Card::Auth.serialize captured at save time), request_context (Source-6 fields stashed in
# Card::Env.params at save time). See Open Questions #16 (mod-install) for the hook-load gating.
module MirrorOutboxWriter
  module_function

  # Exact set of the mirror's OWN cards (by codename) whose saves must NOT be mirrored -- e.g. the
  # mod/asset/system cards Decko creates for this mod. This is an EXACT codename set, NOT a
  # "mirror_*" key prefix: an ordinary user card whose key merely starts with "mirror_" IS mirrored.
  # Seeded with the mod card; the full membership is finalized once the installed mod's cards are
  # known on dev (L2b).
  SELF_CARD_CODENAMES = %w[mod_atomspace_mirror].freeze

  def write(action, pre_state: {}, auth:, request_context: {})
    # Validate the auth contract LOUDLY here -- an L2b wiring bug must not be swallowed into a
    # 'failed' row by the encode rescue below (that rescue is only for genuine encode/data corruption).
    unless auth.is_a?(Hash) && auth.key?(:current_id) && auth.key?(:as_id)
      raise ArgumentError, "auth: must be a Hash with :current_id and :as_id keys"
    end
    return if mirror_own_card?(action.card)
    return if action.draft

    # Encode OUTSIDE the state lock (keeps the singleton lock short). Catch ONLY a genuine encoder
    # data-corruption error -> a 'failed' row; unexpected bugs (NoMethodError etc.) propagate loudly.
    atoms = nil
    encode_error = nil
    begin
      atoms = CardAtomEncoder.encode(action, pre_state: pre_state, auth: auth, request_context: request_context)
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
