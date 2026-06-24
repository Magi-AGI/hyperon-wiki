# frozen_string_literal: true

# Set: <Parent>+proposal — the WS6 structured edit-proposal convention.
#
# WHY a new convention (not +AI): `+AI` has historically been a catch-all for
# ANY AI-generated content (notes, summaries, ad-hoc suggestions). The merge
# workbench needs an unambiguous trigger — "this card IS a proposed replacement
# for its parent's content, with a known base and a merge lifecycle." `+proposal`
# is that trigger, and is author-neutral (humans can open peer-review proposals
# too). `+AI` is left untouched. See docs/ws6-merge-editor-design.md §3.5/§4.1.
#
# WHAT this file is: Phase 1, the MODEL layer only. It (1) aligns the proposal's
# content format to its parent so later diffs compare like with like, and
# (2) stamps the base revision + writes verifiable provenance at AUTHORING time.
# The merge workbench view and the verifying merge-apply path land in later
# phases; the legacy blunt overwrite (set/right/ai_draft.rb) stays live until
# Phase 6 replaces it, so there is never a window with no merge path.

# ProposalProvenance (mod/editorial_review/lib/proposal_provenance.rb) is
# autoloaded from the mod's lib dir — do NOT require_relative it here; Decko's
# set loader evaluates this file without a stable __FILE__, so a relative
# require raises and silently drops the whole set (events never register).

# Inert plain-text cardtype for the JSON sidecars (+provenance; later +merge
# audit). We read its stored db_content back verbatim and never rely on its
# rendered form, so Decko's RichText URL chunk-processor never touches it.
# NOTE (dev-runtime check): confirm "Plain Text" is the right inert core type
# in this Decko 0.20 deck; if not, this is the single constant to change.
PROPOSAL_META_TYPE = "Plain Text"

# Content cardtypes a proposal may mirror (so 3-way diffs are apples-to-apples).
# Compared by type NAME (robust) rather than codename ids. Non-content parent
# types (e.g. Published/Draft, themselves HTML-backed) are left alone — a
# proposal created against them stays its authored type and the diff engine keys
# off the recorded parent_type/proposal_type instead.
PROPOSAL_CONTENT_TYPES = %w[RichText Markdown].freeze

# (1) Align proposal content format to its parent's, before the card is stored.
event :align_proposal_type, :prepare_to_validate, on: :create do
  parent = left
  next unless parent
  next if type_id == parent.type_id
  next unless PROPOSAL_CONTENT_TYPES.include?(parent.type_name)

  self.type_id = parent.type_id
end

# (2) Stamp base + write provenance at authoring time. Idempotent; honours a
#     generator-supplied base override (never overwrites it).
#
# STAGE = :finalize (not :integrate): :integrate runs after-commit and is
# deferred/suppressed on the MCP-API and runner create paths (the AI-generator
# path), so an :integrate stamp would never run for AI-authored proposals.
# :finalize runs inside the save transaction, so the proposal + base +
# provenance commit atomically (no orphaned unstamped proposals). The metadata
# cards' right names (+base/+provenance) are not "proposal", so writing them
# here does not re-trigger this set.
event :stamp_proposal_base, :finalize, on: :create do
  parent = left
  next unless parent

  base_name = "#{name}+base"
  prov_name = "#{name}+provenance"
  next if Card.fetch(prov_name)&.db_content.present? # already stamped

  # Capture the REAL actor before switching to the bot for the metadata writes.
  actor = Card::Auth.current
  override_reason = Env.params[:proposal_base_override_reason].presence

  existing_base = Card.fetch(base_name)
  if existing_base&.db_content.present?
    # A generator/human pre-stamped a read-time (or deliberately chosen) base.
    # A read-time stamp is NOT an override; override is reserved for an explicit
    # manual non-current base selection (carries a required reason).
    base_act_id = existing_base.db_content.to_i
    stamp_source = override_reason ? "manual_override" : "generator_read_time"
  else
    latest = Card::Action.where(card_id: parent.id)
                         .where(draft: [false, nil]).order(id: :desc).first
    base_act_id = latest&.act&.id
    stamp_source = "server_current"
  end

  # Durable reconstruction key: the PARENT's Card::Action at that act. An Act can
  # span several cards' actions, so resolve the parent's action explicitly rather
  # than assuming act_id maps to one content revision (Codex #1).
  base_action_id =
    if base_act_id
      Card::Action.joins(:act)
                  .where(card_id: parent.id, card_acts: { id: base_act_id })
                  .order(id: :desc).first&.id
    end

  record = ProposalProvenance.build_record(
    parent_id: parent.id, parent_name: parent.name,
    parent_type: parent.type_name, proposal_type: type_name,
    base_act_id: base_act_id, base_action_id: base_action_id,
    base_hash: ProposalProvenance.content_hash(parent.db_content),
    proposal_hash: ProposalProvenance.content_hash(db_content),
    actor_id: actor&.id, actor_name: actor&.name,
    source: Env.params[:proposal_source].presence || "unknown",
    stamp_source: stamp_source,
    override: stamp_source == "manual_override",
    override_reason: override_reason,
    stamped_at: Time.now.utc.iso8601
  )

  Card::Auth.as_bot do
    if base_act_id && existing_base&.db_content.blank?
      Card.create!(name: base_name, type: "Number", content: base_act_id.to_s)
    end
    Card.create!(name: prov_name, type: PROPOSAL_META_TYPE,
                 content: ProposalProvenance.to_json_compact(record))
  end
end

# (3) Keep proposal_hash/proposal_type current so legitimate post-authoring edits
#     to the proposal don't trip Phase 6's integrity check. Base fields preserved.
event :refresh_proposal_hash, :finalize, on: :update, changed: :db_content do
  prov_name = "#{name}+provenance"
  prov = Card.fetch(prov_name)
  next unless prov&.db_content.present?

  record = ProposalProvenance.parse(prov.db_content)
  record["proposal_hash"] = ProposalProvenance.content_hash(db_content)
  record["proposal_type"] = type_name
  record["proposal_hash_updated_at"] = Time.now.utc.iso8601

  Card::Auth.as_bot { prov.update!(content: ProposalProvenance.to_json_compact(record)) }
end
