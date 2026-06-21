# frozen_string_literal: true

# Level 1 -- pure encoder. Converts one Decko card action into the ordered atom-event list for a
# single mirror_outbox row's payload. No model writes; reads the action's already-loaded card +
# associations (references_out, card_changes) and the injected pre_state / request_context.
# Referentially transparent: same (action, pre_state, request_context) -> identical output.
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
#   card_changes    : Card::Change -- #field (TRACKED_FIELDS name string), #value (new value)
#   pre_state       : Hash{field_name => old_value} for the changes array; {} when unavailable
#   request_context : Hash of Source-6 agent fields; {} outside an MCP request (those encode as
#                     JSON null per the frozen contract)
module CardAtomEncoder
  module_function

  SOURCE = "decko"
  EVENT_SCHEMA_VERSION = "decko-spaceevent-v1"
  STAGE = "integrate_with_delay"

  def encode(action, pre_state: {}, request_context: {})
    return [] if action.draft

    card = action.card
    [decko_card(card),
     *decko_references(card),
     decko_provenance(action, card, pre_state || {}, request_context || {})]
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
      ["Trash",     !card.trash.nil? && card.trash ? true : false],
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
        ["IsPresent",  r.is_present ? true : false]
      ]
    end
  end

  def decko_provenance(action, card, pre_state, ctx)
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
      ["auth_current_id",      ctx[:auth_current_id]],   # JSON null when absent (canonical |null)
      ["auth_as_id",           ctx[:auth_as_id]],
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
      field = ch.field.to_s
      { "field" => field, "old" => pre_state[field], "new" => ch.value }
    end
  end

  # --- helpers ---

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
