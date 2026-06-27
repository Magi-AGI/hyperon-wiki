# frozen_string_literal: true

# BaseResolver — determines the 3-way merge BASE for a +proposal card and how
# much to trust it (WS6 three-tier confidence; docs/ws6-merge-editor-design.md
# §4.2). Pure tier logic lives in `classify`; DB I/O in `resolve`, which reuses
# the canonical RevisionSnapshot helper rather than forking revision logic.
#
# resolve(proposal) returns a structured result:
#   { tier:, mode:, base_content:, base_act_id:, base_action_id:, base_hash:,
#     base_hash_ok:, parent_id:, parent_name:, warning: }
# where tier ∈ :verified | :stale | :estimated | :unreliable and
#       mode ∈ :three_way | :two_way.
module BaseResolver
  module_function

  # Ambiguity window (seconds) for legacy timestamp inference: if the parent has
  # MORE THAN ONE committed revision within +/- this of the proposal's creation,
  # the base is ambiguous (read-modify-write race) -> unreliable -> 2-way.
  INFER_WINDOW = 120

  # Pure classification -> tier symbol.
  #   stamped       — proposal carries a +provenance base_action_id
  #   base_hash_ok  — reconstructed base content hashes to the recorded base_hash
  #   window_count  — # parent revisions within +/- INFER_WINDOW of creation
  # Stamped + hash mismatch is a HARD failure (:stale) — never silently 3-way a
  # wrong base. Unstamped is unambiguous (estimated) only with <= 1 nearby
  # revision; 2+ near the creation time => unreliable.
  def classify(stamped:, base_hash_ok:, window_count:)
    if stamped
      base_hash_ok ? :verified : :stale
    elsif window_count <= 1
      :estimated
    else
      :unreliable
    end
  end

  # Tiers that support a true 3-way merge; others degrade to 2-way.
  def three_way?(tier)
    %i[verified estimated].include?(tier)
  end

  # Read-only. Resolve the base + confidence for a +proposal card.
  def resolve(proposal)
    parent = proposal&.left
    return no_parent_result unless parent

    prov = parse_provenance(proposal)
    if prov && prov["base_action_id"]
      resolve_stamped(parent, prov)
    else
      resolve_inferred(parent, proposal)
    end
  end

  # --- internals ---

  def parse_provenance(proposal)
    prov_card = Card.fetch("#{proposal.name}+provenance")
    return nil unless prov_card && prov_card.db_content.present?

    ProposalProvenance.parse(prov_card.db_content)
  rescue StandardError
    nil
  end

  def resolve_stamped(parent, prov)
    action = Card::Action.find_by(id: prov["base_action_id"])
    content = action && RevisionSnapshot.content_at(parent.id, action)

    if action.nil? || content.nil?
      return build(:stale, parent: parent, prov: prov, base_content: nil, base_hash_ok: false,
                   warning: "stamped base action #{prov['base_action_id']} not found; cannot reconstruct base")
    end

    computed = ProposalProvenance.content_hash(content)
    ok = (computed == prov["base_hash"])
    tier = classify(stamped: true, base_hash_ok: ok, window_count: 0)

    warnings = []
    warnings << "base_hash mismatch: recorded #{prov['base_hash']} but base now reconstructs to #{computed}" unless ok
    if prov["parent_id"] && prov["parent_id"] != parent.id
      warnings << "parent id changed since authoring (#{prov['parent_id']} -> #{parent.id})"
    end

    # Legacy-bridge base is an ESTIMATE from a +AI draft's creation time — never
    # "verified" even when the reconstruction hashes clean (Phase 7.2). Downgrade
    # to estimated (still 3-way, but with the yellow caveat / one-click 2-way).
    if prov["stamp_source"] == "legacy_bridge" && tier == :verified
      tier = :estimated
      warnings << "base ESTIMATED from a legacy +AI draft's creation time; switch to 2-way if blocks look misaligned"
    end

    build(tier, parent: parent, prov: prov, base_content: (ok ? content : nil), base_hash_ok: ok,
          warning: warnings.empty? ? nil : warnings.join("; "))
  end

  def resolve_inferred(parent, proposal)
    time = proposal.created_at
    base_action = RevisionSnapshot.latest_action_at_or_before(parent.id, time)
    unless base_action
      return build(:unreliable, parent: parent, base_content: nil,
                   warning: "no parent revision at/before proposal creation; use 2-way (proposal vs current)")
    end

    window_count = RevisionSnapshot.actions_within(parent.id, time, INFER_WINDOW).count
    tier = classify(stamped: false, base_hash_ok: false, window_count: window_count)

    if tier == :estimated
      content = RevisionSnapshot.content_at(parent.id, base_action)
      build(:estimated, parent: parent, base_content: content,
            base_act_id: base_action.act&.id, base_action_id: base_action.id,
            base_hash: (content && ProposalProvenance.content_hash(content)),
            warning: "base ESTIMATED from proposal creation time; switch to 2-way if blocks look misaligned")
    else
      build(:unreliable, parent: parent, base_content: nil,
            warning: "ambiguous parent history near proposal creation (#{window_count} revisions within ±#{INFER_WINDOW}s); use 2-way")
    end
  end

  def build(tier, parent:, base_content:, prov: nil, base_hash_ok: nil,
            base_act_id: nil, base_action_id: nil, base_hash: nil, warning: nil)
    {
      tier: tier,
      mode: three_way?(tier) ? :three_way : :two_way,
      base_content: base_content,
      base_act_id: base_act_id || prov&.dig("base_act_id"),
      base_action_id: base_action_id || prov&.dig("base_action_id"),
      base_hash: base_hash || prov&.dig("base_hash"),
      base_hash_ok: base_hash_ok,
      parent_id: parent&.id,
      parent_name: parent&.name,
      warning: warning
    }
  end

  def no_parent_result
    { tier: :unreliable, mode: :two_way, base_content: nil, warning: "proposal has no parent" }
  end
end
