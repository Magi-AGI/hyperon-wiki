# frozen_string_literal: true

# Set: <Parent>+proposal+merge draft — WS6 Phase 5 polish artifact.
#
# The merge draft is the human-assembled-and-polished output of the merge
# workbench. It is a SEPARATE card from <Parent>+proposal (its `left`), so the
# original AI/human suggestion and its provenance hash stay IMMUTABLE — Phase 6
# verifies BOTH the original proposal hash (what was reviewed) and the merge-draft
# hash (what gets applied), plus the parent/base optimistic locks. Storing the
# polish here instead of overwriting +proposal is the audit-chain decision (Codex)
# in docs/ws6-merge-editor-phase5-tinymce-gate.md.
#
# This set: (1) mirrors the draft's content type to the proposal's so the standard
# ?view=edit dispatches the right native editor (RichText -> TinyMCE, Markdown ->
# Markdown editor — no asset duplication in the layout-free workbench), (2) stamps
# a +audit sidecar with the assembled hash + hunk selections + optimistic-lock
# anchors (parent_act_id, base_hash) for Phase 6, refreshing the hash as the human
# polishes, and (3) shows a merge-context + stale-base banner on the edit screen.
# NO parent writes here (those are Phase 6).
#
# merge_draft codename is registered in data/real.yml. ProposalProvenance
# autoloads from the mod lib dir — do NOT require_relative it (the set loader has
# no stable __FILE__; a relative require silently drops the whole set).

MERGE_DRAFT_META_TYPE = "Plain Text"

# Latest committed act id for a card (mirrors the Phase 1 base-stamp query).
def merge_draft_latest_act_id(card_id)
  Card::Action.where(card_id: card_id)
              .where(draft: [false, nil]).order(id: :desc).first&.act&.id
end

# Parse the workbench's {hunk_id => "current"|"proposal"|"base"} JSON into the
# symbol-side hash BlockMerge.assemble expects.
def parse_merge_selections(raw)
  return {} if raw.blank?

  parsed = (JSON.parse(raw) rescue {})
  return {} unless parsed.is_a?(Hash)

  parsed.each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_s.to_sym }
end

# Server-side re-assembly (Codex integrity rule): when seeded from the workbench
# (hunk_selections present), re-derive the authoritative content from the
# SELECTIONS — the client's assembled HTML is never trusted as the artifact
# (client assemble == BlockMerge.assemble is already proven). Also enforce the
# parent-drift gate. When hunk_selections is absent (e.g. the human later
# polishing in the native editor) this is a no-op and the human's content stands.
event :rederive_merge_draft, :prepare_to_validate, on: :save,
      when: proc { Env.params[:hunk_selections].present? } do
  proposal = left
  next unless proposal

  parent = proposal.left
  next unless parent

  # Drift gate: the reviewer assembled against a specific parent act; if the
  # parent moved since, reject so the audit can't claim a stale review basis.
  submitted = Env.params[:parent_act_id].presence&.to_i
  current_act = merge_draft_latest_act_id(parent.id)
  if submitted && current_act && submitted != current_act
    errors.add(:parent_act_id,
               "the parent changed since the merge workbench loaded " \
               "(was #{submitted}, now #{current_act}); reload the workbench and re-merge")
    next
  end

  fmt = proposal.type_name == "Markdown" ? :markdown : :html
  resolve = BaseResolver.resolve(proposal)
  base = if resolve[:mode] == :three_way && resolve[:base_content]
           resolve[:base_content]
         else
           parent.db_content
         end
  merged = BlockMerge.merge(base: base.to_s, current: parent.db_content.to_s,
                            proposal: proposal.db_content.to_s, format: fmt)
  begin
    self.content = BlockMerge.assemble(merged, parse_merge_selections(Env.params[:hunk_selections]))
  rescue StandardError => e
    errors.add(:content, "could not assemble merge draft from selections: #{e.message}")
  end
end

# (1) Mirror content type to the proposal so ?view=edit loads the right editor.
event :align_merge_draft_type, :prepare_to_validate, on: :create do
  proposal = left
  next unless proposal
  next if type_id == proposal.type_id

  self.type_id = proposal.type_id
end

# (2) Stamp/refresh the +audit sidecar (finalize, in-transaction so it commits
#     with the draft — :integrate would not fire on the MCP/runner/seed paths).
#     On create (seed from the workbench): full origin + locks. On later content
#     updates (the human polishing): refresh only the assembled hash + timestamp.
#     The original proposal's +provenance is never touched.
event :stamp_merge_draft_audit, :finalize, on: :save, changed: :db_content do
  proposal = left
  next unless proposal

  audit_name = "#{name}+audit"
  assembled_hash = ProposalProvenance.content_hash(db_content)
  existing = Card.fetch(audit_name)

  record =
    if existing&.db_content.present?
      rec = ProposalProvenance.parse(existing.db_content)
      rec["assembled_hash"] = assembled_hash
      rec["polished_at"] = Time.now.utc.iso8601
      rec
    else
      parent = proposal.left
      prov = Card.fetch("#{proposal.name}+provenance")
      prov_rec = prov&.db_content.present? ? ProposalProvenance.parse(prov.db_content) : {}
      parent_act_id = Env.params[:parent_act_id].presence&.to_i ||
                      (parent && merge_draft_latest_act_id(parent.id))
      {
        "schema" => "ws6-merge-draft-audit/1",
        "proposal_name" => proposal.name,
        "proposal_hash" => prov_rec["proposal_hash"],
        "parent_id" => parent&.id,
        "parent_name" => parent&.name,
        "parent_act_id" => parent_act_id,
        "base_act_id" => prov_rec["base_act_id"],
        "base_hash" => prov_rec["base_hash"],
        "assembled_hash" => assembled_hash,
        "hunk_selections" => Env.params[:hunk_selections].presence,
        "actor_name" => Card::Auth.current&.name,
        "source" => Env.params[:assemble_source].presence || "workbench",
        "assembled_at" => Time.now.utc.iso8601
      }
    end

  Card::Auth.as_bot do
    if existing
      existing.update!(content: ProposalProvenance.to_json_compact(record))
    else
      Card.create!(name: audit_name, type: MERGE_DRAFT_META_TYPE,
                   content: ProposalProvenance.to_json_compact(record))
    end
  end
end

format :html do
  # Merge-context + stale-base banner, prepended to the standard edit screen so
  # the reviewer knows they are polishing a MERGE DRAFT (not an ad-hoc edit) and
  # is warned if the parent drifted since the proposal was authored.
  view :edit do
    output [render_merge_draft_banner, super()]
  end

  view :merge_draft_banner do
    proposal = card.left
    return "" unless proposal

    parent = proposal.left
    rows = ["<strong>Polishing a merge draft</strong> for " \
            "#{parent ? h(parent.name) : 'its parent'} — changes here do not touch the " \
            "original proposal or the parent (apply happens in the review step)."]

    stale = merge_draft_stale_warning(proposal, parent)
    rows << stale if stale

    link = proposal ? %( <a href="/#{proposal.name}?view=merge_workbench&layout=none">Back to merge workbench</a>) : ""
    cls = stale ? "alert alert-warning" : "alert alert-info"
    wrap_with(:div, class: "#{cls} mb-3") { rows.join("<br>") + link }
  end

  # Returns a warning string if the parent moved past the proposal's stamped base.
  def merge_draft_stale_warning(proposal, parent)
    return nil unless parent

    prov = Card.fetch("#{proposal.name}+provenance")
    return nil unless prov&.db_content.present?

    base_act_id = ProposalProvenance.parse(prov.db_content)["base_act_id"]
    return nil unless base_act_id

    # Inline (not the set-module helper): format methods run on the format object,
    # which does not mix in the card-set's top-level defs.
    current = Card::Action.where(card_id: parent.id)
                          .where(draft: [false, nil]).order(id: :desc).first&.act&.id
    return nil if current.nil? || current == base_act_id

    "&#9888; The parent has changed since this proposal was authored " \
      "(base act #{base_act_id} &rarr; current #{current}). Re-check the merge before applying."
  end
end
