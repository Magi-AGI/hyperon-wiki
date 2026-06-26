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
  current_hash = ProposalProvenance.content_hash(db_content)
  existing = Card.fetch(audit_name)

  # Two-hash audit (Codex). A (re)assembly is signalled by hunk_selections in the
  # params (the workbench seed / explicit Reset & re-merge); a native editor save
  # (polishing) has none.
  #   - (Re)assembly: assembled_hash AND polished_hash both = the freshly
  #     server-assembled content; (re)records origin (selections/parent_act_id).
  #     Reset legitimately produces a NEW assembled_hash (a new authoritative
  #     assembly), so it is rebuilt here — NOT preserved from a prior seed.
  #   - Native polish save: refresh polished_hash ONLY; assembled_hash stays the
  #     immutable origin so we keep proving selections -> assembled content.
  # Phase 6 applies against polished_hash.
  reassembling = Env.params[:hunk_selections].present?
  record =
    if existing&.db_content.present? && !reassembling
      rec = ProposalProvenance.parse(existing.db_content)
      rec["polished_hash"] = current_hash
      rec["polished_at"] = Time.now.utc.iso8601
      rec
    else
      parent = proposal.left
      prov = Card.fetch("#{proposal.name}+provenance")
      prov_rec = prov&.db_content.present? ? ProposalProvenance.parse(prov.db_content) : {}
      parent_act_id = Env.params[:parent_act_id].presence&.to_i ||
                      (parent && merge_draft_latest_act_id(parent.id))
      {
        "schema" => "ws6-merge-draft-audit/2",
        "proposal_name" => proposal.name,
        "proposal_hash" => prov_rec["proposal_hash"],
        "parent_id" => parent&.id,
        "parent_name" => parent&.name,
        "parent_act_id" => parent_act_id,
        "base_act_id" => prov_rec["base_act_id"],
        "base_hash" => prov_rec["base_hash"],
        "assembled_hash" => current_hash,
        "polished_hash" => current_hash,
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

# ---------------------------------------------------------------------------
# PHASE 6 — verifying merge-apply (the governance gate from the Khellar call).
# Triggered by the apply_to_parent param on a merge-draft save. Runs a four-fold
# gate INSIDE the save transaction; if any check fails it adds an error and the
# whole act rolls back — never a partial parent write. Replaces the blunt
# merge_ai_draft overwrite. Spec: docs/ws6-merge-editor-phase6-apply-gate.md.
event :apply_merge_draft, :finalize, on: :update,
      when: proc { Env.params[:apply_to_parent] == "true" } do
  proposal = left
  next merge_apply_reject("merge draft has no proposal") unless proposal

  parent = proposal.left
  next merge_apply_reject("proposal has no parent card") unless parent

  audit = Card.fetch("#{name}+audit")
  rec = audit&.db_content.present? ? ProposalProvenance.parse(audit.db_content) : nil
  next merge_apply_reject("no merge-draft audit found; cannot verify before applying") unless rec

  # Idempotency: a completed apply leaves a +merge audit. Refuse to re-apply.
  if Card.fetch("#{proposal.name}+merge audit")&.db_content.present?
    next merge_apply_reject("this proposal has already been merged (409)")
  end

  # (1) Permission — on the PARENT, for the acting user (not the draft/proposal).
  actor = Card::Auth.current
  next merge_apply_reject("you do not have permission to update #{parent.name}") unless parent.ok?(:update)

  # (2) Optimistic lock — parent must not have moved since the reviewer assembled.
  current_act = merge_draft_latest_act_id(parent.id)
  if rec["parent_act_id"] && current_act && rec["parent_act_id"].to_i != current_act.to_i
    next merge_apply_reject(
      "the parent changed since this merge was reviewed (act #{rec['parent_act_id']} -> #{current_act}); " \
      "re-open the merge workbench and re-merge before applying"
    )
  end

  # (3) Draft integrity — what we are about to write must equal what was last
  #     polished + saved (polished_hash), so no DB tampering slips through.
  if rec["polished_hash"] && ProposalProvenance.content_hash(db_content) != rec["polished_hash"]
    next merge_apply_reject("the merge draft changed since it was last saved; reload the draft and re-apply")
  end

  # (4) Identity — the applier is the polishing author or holds parent-update
  #     clearance (gate 1 already proved the latter). Recorded in the audit.
  identity_note = rec["actor_name"].present? && actor&.name != rec["actor_name"] ? "applied-by-other" : "applied-by-author"

  # --- all gates pass: apply within this transaction ---
  pre_act = current_act
  merged_content = db_content
  # Nested parent write (proven merge_ai_draft pattern). Actor has :update (gate 1).
  parent.content = merged_content
  parent.save!
  post_act = merge_draft_latest_act_id(parent.id)

  apply_record = {
    "schema" => "ws6-merge-apply/1",
    "proposal_name" => proposal.name,
    "merged_by_id" => actor&.id,
    "merged_by_name" => actor&.name,
    "identity" => identity_note,
    "parent_id" => parent.id,
    "parent_name" => parent.name,
    "parent_pre_merge_act_id" => pre_act,
    "parent_post_merge_act_id" => post_act,
    "hunk_selections" => rec["hunk_selections"],
    "original_base_act_id" => rec["base_act_id"],
    "original_proposal_hash" => rec["proposal_hash"],
    "assembled_hash" => rec["assembled_hash"],
    "polished_hash" => rec["polished_hash"],
    "merged_at" => Time.now.utc.iso8601
  }

  Card::Auth.as_bot do
    Card.create!(name: "#{proposal.name}+merge audit", type: MERGE_DRAFT_META_TYPE,
                 content: ProposalProvenance.to_json_compact(apply_record))
    merge_apply_lifecycle(proposal)
  end

  # Mark the draft applied (archive-don't-delete) — also gives THIS act a real
  # change so it commits; an apply that left the draft byte-identical would be a
  # no-op update and roll back the nested parent write.
  add_subcard "#{name}+applied", content: Time.now.utc.iso8601
end

# Abort helper: record the reason so Decko rolls the act back (no parent write).
def merge_apply_reject(message)
  errors.add(:apply_to_parent, message)
  nil
end

# Lifecycle transition on a successful apply: tag the proposal "merged" and drop
# the "ai generated" tag if present. Archive-don't-delete.
def merge_apply_lifecycle(proposal)
  tag_name = "#{proposal.name}+tag"
  tag = Card.fetch(tag_name) || Card.create!(name: tag_name, type_id: Card::PointerID)
  tag.drop_item("ai generated") if tag.item_names.include?("ai generated")
  tag.add_item("merged") unless tag.item_names.include?("merged")
  tag.save!
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
