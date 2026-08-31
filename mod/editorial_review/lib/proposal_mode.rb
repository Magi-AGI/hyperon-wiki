# frozen_string_literal: true

# ProposalMode — WS6 CP006C fail-closed gate for the merge workbench.
#
# WHAT THIS IS. The proposal mode is SIDECAR metadata, stored in
# `<Parent>+proposal+mode`, alongside `+base` and `+provenance`. It is NOT an
# in-body marker. Deployed verification established that the workbench builds
# its payload from the raw `+proposal` body (`proposal: card.db_content.to_s`)
# and that nothing parses or strips anything out of it — so a `Proposal mode:`
# line written into the body would be merge payload that lands in the parent
# article on apply. Requiring an in-body marker would therefore force routing
# metadata into the merge payload, which is the exact hazard the requirement was
# meant to prevent. Nothing here reads the proposal body.
#
# WHY FAIL CLOSED. This workbench treats the `+proposal` body as a candidate
# WHOLE-PARENT REPLACEMENT: `BlockMerge` compares base x current x proposal and
# the apply gate writes `parent.content` from the assembled draft. That is only
# a truthful operation for a proposal whose body really is the complete corrected
# parent body. A proposal with no recorded mode has not been characterized, so
# merging it would be a guess. `full-replacement` is consequently the ONLY mode
# this workbench may act on today.
#
# `manual-review-packet` and `diff` are recognized as valid labels in the wider
# taxonomy, but they are NOT mergeable here:
#   - a manual review packet is reviewer prose, not replacement content;
#   - a diff-shaped payload would be merged as literal diff syntax, because no
#     deployed workbench code parses one.
# Recognizing them and refusing them (with a precise reason) is deliberately
# different from treating them as unknown: it lets the UI say WHY.
#
# PURITY. Everything except `.for_proposal` is dependency-free (no Card, Rails
# or Decko), so the classification and the blocked-screen HTML are unit-testable
# without a database — see spec/mod/editorial_review/proposal_mode_spec.rb.
# `.for_proposal` is the single Card-aware lookup shared by all three
# enforcement points (workbench view, merge-draft seed, apply gate) so the
# sidecar path is defined in exactly one place.
require "cgi"

module ProposalMode
  module_function

  # Right-hand name part of the sidecar: `<Parent>+proposal+mode`.
  SIDECAR_RIGHT_NAME = "mode"

  FULL_REPLACEMENT = "full-replacement"
  MANUAL_REVIEW_PACKET = "manual-review-packet"
  DIFF = "diff"

  # Labels this codebase recognizes at all.
  KNOWN_MODES = [FULL_REPLACEMENT, MANUAL_REVIEW_PACKET, DIFF].freeze

  # Labels the CURRENT whole-parent-replacement workbench may act on. Widening
  # this list is a behavioral change that needs its own review: it would mean
  # the workbench had learned to handle a payload shape it cannot handle today.
  MERGEABLE_MODES = [FULL_REPLACEMENT].freeze

  # `<Parent>+proposal` -> `<Parent>+proposal+mode`.
  def sidecar_name(proposal_name)
    "#{proposal_name}+#{SIDECAR_RIGHT_NAME}"
  end

  # Stored card content -> comparable token.
  #
  # Strips only the surrounding whitespace Decko may store around a short text
  # value (trailing newline, stray padding). It deliberately does NOT downcase.
  # The agreed contract is that the sidecar contains exactly `full-replacement`,
  # and the sidecar is an assertion about mergeability: coercing `Full-Replacement`
  # into that assertion would be inventing agreement the author did not express.
  # A non-canonical spelling therefore falls through to :unknown and fails closed,
  # which is recoverable in one edit, whereas wrongly merging is not.
  def normalize(raw)
    raw.to_s.strip
  end

  # The single source of truth. Returns:
  #   mode      - the normalized label, or nil when absent
  #   known     - whether the label is in KNOWN_MODES
  #   mergeable - whether THIS workbench may act on it
  #   reason    - :ok | :missing | :unknown | :unsupported_by_workbench
  #   message   - operator-facing explanation, nil when mergeable
  def classify(raw)
    value = normalize(raw)

    return result(nil, false, false, :missing) if value.empty?
    return result(value, false, false, :unknown) unless KNOWN_MODES.include?(value)
    return result(value, true, false, :unsupported_by_workbench) unless MERGEABLE_MODES.include?(value)

    result(value, true, true, :ok)
  end

  def result(mode, known, mergeable, reason)
    { mode: mode, known: known, mergeable: mergeable, reason: reason,
      message: message_for(mode, reason) }
  end

  def message_for(mode, reason)
    case reason
    when :ok then nil
    when :missing
      "This proposal has no #{SIDECAR_RIGHT_NAME} sidecar. The merge workbench can only " \
        "act on a proposal whose `+#{SIDECAR_RIGHT_NAME}` sidecar contains exactly " \
        "`#{FULL_REPLACEMENT}`, because merging replaces the parent body wholesale. " \
        "Until the proposal has been characterized and that sidecar set, it is not mergeable."
    when :unsupported_by_workbench
      "This proposal is recorded as `#{mode}`, which this merge workbench cannot apply. " \
        "It replaces the parent body wholesale, so it only supports `#{FULL_REPLACEMENT}`. " \
        "A `#{MANUAL_REVIEW_PACKET}` must be reconciled by hand, and a `#{DIFF}` payload " \
        "would be merged as literal diff text because nothing here parses one."
    else
      "This proposal's `+#{SIDECAR_RIGHT_NAME}` sidecar holds an unrecognized value. " \
        "The merge workbench only acts on `#{FULL_REPLACEMENT}`; recognized labels are " \
        "#{KNOWN_MODES.join(', ')}. Labels are case-sensitive and lowercase — " \
        "surrounding whitespace is ignored, but a different spelling is not the agreed token."
    end
  end

  def mergeable?(raw)
    classify(raw)[:mergeable]
  end

  def rejection_message(raw)
    classify(raw)[:message]
  end

  # Fail-closed workbench screen. Deliberately emits NO merge affordances: no
  # `ws6-mw-data` island, no hunk rows, no polish/assemble/reset/apply controls.
  # The client JS keys off those, so a blocked proposal cannot be assembled or
  # applied from the UI at all. Values are escaped because both the mode value
  # and the card name are untrusted card content.
  def blocked_notice_html(raw, proposal_name: nil)
    info = classify(raw)
    shown = proposal_name ? " for <strong>#{CGI.escapeHTML(proposal_name.to_s)}</strong>" : ""
    recorded = info[:mode] ? %( Recorded value: <code>#{CGI.escapeHTML(info[:mode])}</code>.) : ""

    %(<div class="alert alert-warning ws6-mode-blocked" role="alert">) +
      %(<strong>Not mergeable#{shown}.</strong> ) +
      CGI.escapeHTML(info[:message].to_s) + recorded +
      %(</div>)
  end

  # Card-aware convenience shared by the workbench view, the merge-draft seed
  # and the apply gate, so the sidecar lookup path exists in exactly one place.
  # A nil proposal classifies as :missing — fail closed, never raise.
  def for_proposal(proposal)
    return classify(nil) unless proposal

    classify(Card.fetch(sidecar_name(proposal.name))&.db_content)
  end
end
