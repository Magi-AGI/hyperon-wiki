# frozen_string_literal: true

require "time" # Time#iso8601 (stdlib; autoloaded under Decko/ActiveSupport but not standalone)

# Level 1 -- pure encoder. Converts one Decko card action into the ordered atom-event list for a
# single mirror_outbox row's payload. No model writes; reads the action's already-loaded card +
# associations (references_out, card_changes) and the injected pre_state / auth / request_context.
# Referentially transparent: same inputs -> identical output.
#
# Output wire format is FROZEN in Card 17161 (L1 "Slice 2 outbox payload wire format", 2026-06-21);
# atom shapes per Canonical Encodings. V1 only -- Content is the raw db_content string, NO cardtype
# dispatch (Section 7).
#
# Input contract (verified against Decko card-1.110.0 on dev 2026-06-15):
#   action          : Card::Action -- #id, #action_type (:create|:update|:delete), #draft,
#                     #super_action_id, #card_id, #act, #card_changes, #card
#   action.act      : Card::Act    -- #id, #actor_id, #acted_at, #ip_address
#   action.card     : Card         -- the 14 source attributes; #references_out (Card::Reference)
#   card_changes    : Card::Change -- #field (TRACKED_FIELDS name OR integer index), #value (new)
#   pre_state       : Hash{field_name => old_value} for the changes array (string or symbol keys);
#                     {} when unavailable
#   auth            : Hash{current_id:, as_id:} -- Source-5 dual-actor snapshot captured at action
#                     time by L2 (Card::Auth.serialize.current_id / .as_id); {} -> JSON null
#   request_context : Hash of the 4 Source-6 agent fields; {} outside an MCP request (-> JSON null)
module CardAtomEncoder
  module_function

  SOURCE = "decko"
  EVENT_SCHEMA_VERSION = "decko-spaceevent-v1"
  STAGE = "integrate_with_delay"

  # Raised for genuine corrupt action DATA (e.g. an unknown card_changes.field). The L2 writer
  # catches THIS narrowly to emit a terminal 'failed' outbox row; unexpected errors (NoMethodError
  # etc.) propagate loudly. auth-contract violations stay ArgumentError (a caller bug, not data).
  class EncodingError < StandardError; end

  # Decko card_changes.field is an integer index into this list (Card::Change#field maps it to the
  # name); the encoder accepts either the integer index or the name string.
  TRACKED_FIELDS = %w[name type_id db_content trash left_id right_id].freeze

  def encode(action, pre_state: {}, auth:, request_context: {})
    # auth is MANDATORY (Source-5 dual-actor audit data): callers must pass the Card::Auth.serialize
    # snapshot, or { current_id: nil, as_id: nil } when genuinely unavailable. Omission must be
    # explicit, never a silent null -- so no default, and the keys must be present.
    unless auth.is_a?(Hash) && auth.key?(:current_id) && auth.key?(:as_id)
      raise ArgumentError, "auth: must be a Hash with :current_id and :as_id keys"
    end
    return [] if action.draft

    card = action.card
    [decko_card(card),
     *decko_references(card),
     decko_provenance(action, card, pre_state || {}, auth || {}, request_context || {})]
  end

  def decko_card(card)
    atom "DeckoCard", [
      ["Id",        card.id],
      ["Name",      card.name],
      ["Key",       card.key],
      ["Codename",  card.codename.present? ? sym(card.codename) : sym("NoCodename")],
      ["TypeId",    card.type_id],
      ["TypeName",  card.type_name],
      ["LeftId",    card.left_id || sym("NoLeft")],
      ["RightId",   card.right_id || sym("NoRight")],
      ["Content",   card.db_content],
      ["Trash",     card.trash ? true : false],
      ["CreatedAt", iso(card.created_at)],
      ["UpdatedAt", iso(card.updated_at)],
      ["CreatorId", card.creator_id],
      ["UpdaterId", card.updater_id]
    ]
  end

  def decko_references(card)
    Array(card.references_out).map do |r|
      atom "DeckoReference", [
        ["RefererId",  r.referer_id],
        ["RefereeKey", r.referee_key],
        ["RefereeId",  r.referee_id || sym("Unresolved")],
        ["RefType",    sym(r.ref_type)],
        # IsPresent = does the reference resolve to an existing card. The card_references
        # is_present column is DEAD in card-1.110.0 (0/574 rows populated on dev, 2026-06-21 L2b),
        # so it is derived from referee_id (the resolved target id; nil => a wanted/unresolved link).
        ["IsPresent",  !r.referee_id.nil?]
      ]
    end
  end

  def decko_provenance(action, card, pre_state, auth, ctx)
    ip = action.act.ip_address
    atom "DeckoProvenance", [
      ["source",               SOURCE],
      ["event_schema_version", EVENT_SCHEMA_VERSION],
      ["event_id",             "decko:action:#{action.id}"],
      ["action_id",            action.id],
      ["act_id",               action.act.id],
      ["super_action_id",      action.super_action_id || sym("NoSuper")],
      ["action",               sym(action.action_type.to_s)],
      ["draft",                action.draft ? true : false],
      ["card_id",              action.card_id],
      ["card_key",             card.key],
      ["actor_id",             action.act.actor_id],
      ["auth_current_id",      auth[:current_id]],   # Source-5 dual-actor (Card::Auth.serialize),
      ["auth_as_id",           auth[:as_id]],        # captured at action time by L2; JSON null if absent
      ["acted_at",             iso(action.act.acted_at)],
      ["ip_address",           filled?(ip) ? ip : sym("NoIP")],
      ["stage",                STAGE],
      ["changes",              changes(action, pre_state)],
      ["agent_session_id",     ctx[:agent_session_id]],
      ["agent_kind",           ctx[:agent_kind] ? sym(ctx[:agent_kind].to_s) : nil],
      ["origin_system",        ctx[:origin_system] ? sym(ctx[:origin_system].to_s) : nil],
      ["origin_request_id",    ctx[:origin_request_id]]
    ]
  end

  def changes(action, pre_state)
    Array(action.card_changes).map do |ch|
      field = field_name(ch.field)
      { "field" => field, "old" => pre_lookup(pre_state, field), "new" => ch.value }
    end
  end

  # --- helpers ---

  # Card::Change#field may be the name string or the raw integer index -- normalize to a name and
  # validate it against the locked TRACKED_FIELDS set. A corrupt/unknown field (out-of-range index
  # OR an unexpected name) raises rather than encoding a bogus change -- this surfaces any new Decko
  # tracked field for a deliberate contract update instead of leaking it silently (Codex 2026-06-21).
  def field_name(raw)
    name = raw.is_a?(Integer) && (0...TRACKED_FIELDS.size).cover?(raw) ? TRACKED_FIELDS[raw] : raw.to_s
    return name if TRACKED_FIELDS.include?(name)

    raise EncodingError, "unknown/corrupt card_changes.field #{raw.inspect} (not in TRACKED_FIELDS)"
  end

  # pre_state old-value lookup, tolerant of string or symbol keys (distinguishes absent from nil).
  def pre_lookup(pre_state, field)
    return nil unless pre_state
    return pre_state[field] if pre_state.key?(field)

    pre_state[field.to_sym]
  end

  def atom(kind, fields)
    { "atom" => kind, "fields" => fields }
  end

  # A MeTTa symbol / sentinel (vs a string value). The Lane B sidecar renders {"sym" => x} as a
  # MeTTa symbol and native JSON values as MeTTa literals.
  def sym(name)
    { "sym" => name.to_s }
  end

  def iso(time)
    time&.utc&.iso8601
  end

  def filled?(val)
    !(val.nil? || val.to_s.strip.empty?)
  end
end
