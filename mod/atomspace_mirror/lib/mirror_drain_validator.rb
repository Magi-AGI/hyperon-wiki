# frozen_string_literal: true

# Level 8 drain -- structural + identity preflight (OQ#15 + the Codex 2026-06-22 row<->payload
# identity check). Runs in-memory BEFORE any IPC: a row that fails validation is terminalized as
# 'failed' (with an L10 alert) and NEVER forwarded to the sidecar. Without the identity check a
# corrupt row whose columns describe event A but whose payload encodes event B could apply the wrong
# event/card and then mark the wrong outbox row delivered -- the sidecar only checks payload-internal
# consistency, not consistency with the outbox row. Pure: no DB, no network.
module MirrorDrainValidator
  module_function

  EVENT_KINDS = %w[decko_action reconcile].freeze
  ATOM_KINDS  = %w[DeckoCard DeckoReference DeckoProvenance].freeze

  class InvalidRow < StandardError; end

  # @param row     responds to #event_kind, #card_id, #action_id, #event_id (the mirror_outbox row)
  # @param payload the parsed outbox payload Hash: {"atoms" => [{"atom"=>.., "fields"=>[[name,val],..]}, ..]}
  # @raise InvalidRow with a reason on any structural OR row<->payload-identity violation
  # @return true when valid
  def validate!(row, payload)
    validate_row_shape!(row)
    atoms = payload_atoms!(payload)

    cards = atoms.select { |a| kind(a) == "DeckoCard" }
    provs = atoms.select { |a| kind(a) == "DeckoProvenance" }
    refs  = atoms.select { |a| kind(a) == "DeckoReference" }

    unknown = atoms.map { |a| kind(a) }.uniq - ATOM_KINDS
    raise InvalidRow, "unknown atom kind(s): #{unknown.inspect}" unless unknown.empty?
    raise InvalidRow, "expected exactly one DeckoCard, got #{cards.size}" unless cards.size == 1
    raise InvalidRow, "expected exactly one DeckoProvenance, got #{provs.size}" unless provs.size == 1

    validate_identity!(row, cards.first, provs.first, refs)
    true
  end

  # --- row shape (OQ#15) ---
  def validate_row_shape!(row)
    unless EVENT_KINDS.include?(row.event_kind)
      raise InvalidRow, "event_kind #{row.event_kind.inspect} not in #{EVENT_KINDS}"
    end
    raise InvalidRow, "card_id is required (integer), got #{row.card_id.inspect}" unless int?(row.card_id)
    if row.event_kind == "decko_action"
      raise InvalidRow, "decko_action requires a non-nil integer action_id, got #{row.action_id.inspect}" unless int?(row.action_id)
    elsif !row.action_id.nil?
      raise InvalidRow, "reconcile requires a nil action_id, got #{row.action_id.inspect}"
    end
  end

  # --- row <-> payload identity (Codex blocker) ---
  def validate_identity!(row, card, prov, refs)
    card_id = field(card, "Id")
    raise InvalidRow, "DeckoCard.Id #{card_id.inspect} != row.card_id #{row.card_id.inspect}" unless card_id == row.card_id

    event_id = field(prov, "event_id")
    raise InvalidRow, "DeckoProvenance.event_id #{event_id.inspect} != row.event_id #{row.event_id.inspect}" unless event_id == row.event_id

    action_id = field(prov, "action_id")
    raise InvalidRow, "DeckoProvenance.action_id #{action_id.inspect} != row.action_id #{row.action_id.inspect}" unless action_id == row.action_id

    refs.each do |r|
      referer = field(r, "RefererId")
      raise InvalidRow, "DeckoReference.RefererId #{referer.inspect} != row.card_id #{row.card_id.inspect}" unless referer == row.card_id
    end
  end

  # --- helpers ---
  def payload_atoms!(payload)
    atoms = payload.is_a?(Hash) ? payload["atoms"] : nil
    raise InvalidRow, "payload missing 'atoms' array" unless atoms.is_a?(Array)
    raise InvalidRow, "payload 'atoms' is empty" if atoms.empty?
    atoms
  end

  def kind(atom)
    atom.is_a?(Hash) ? atom["atom"] : nil
  end

  def field(atom, name)
    return nil unless atom.is_a?(Hash) && atom["fields"].is_a?(Array)
    pair = atom["fields"].find { |p| p.is_a?(Array) && p.size == 2 && p[0] == name }
    pair && pair[1]
  end

  def int?(value)
    value.is_a?(Integer)
  end
end
