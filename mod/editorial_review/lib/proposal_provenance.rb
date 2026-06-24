# frozen_string_literal: true

# ProposalProvenance — pure helpers for the WS6 `+proposal` metadata contract.
#
# Deliberately dependency-free (no Card / Rails / Decko access) so the hashing
# and record-shaping logic is unit-testable WITHOUT a database. The `+proposal`
# set events (set/right/proposal.rb) supply the Card-derived values and persist
# the result; this module only computes content hashes and assembles/serializes
# the provenance record described in docs/ws6-merge-editor-design.md §4.1.
require "digest"
require "json"

module ProposalProvenance
  module_function

  SCHEMA_VERSION = 1
  HASH_ALGO = "sha256"

  # Stable, parser-independent fingerprint over RAW stored db_content (never
  # rendered HTML) so whitespace/markup normalization can't shift it. nil is
  # treated as "" so a missing-content card hashes deterministically.
  def content_hash(content)
    "#{HASH_ALGO}:#{Digest::SHA256.hexdigest(content.to_s)}"
  end

  # Assemble the authoring-time provenance record. All values are passed in by
  # the caller (the set event) to keep this pure. Returns an ordered Hash whose
  # key order JSON.generate preserves.
  def build_record(parent_id:, parent_name:, parent_type:, proposal_type:,
                   base_act_id:, base_action_id:, base_hash:, proposal_hash:,
                   actor_id:, actor_name:, source:, stamp_source:,
                   override:, override_reason:, stamped_at:)
    {
      schema_version: SCHEMA_VERSION,
      parent_id: parent_id,
      parent_name: parent_name,
      parent_type: parent_type,
      base_act_id: base_act_id,
      base_action_id: base_action_id,
      base_hash: base_hash,
      proposal_hash: proposal_hash,
      proposal_type: proposal_type,
      actor_id: actor_id,
      actor_name: actor_name,
      source: source,
      stamp_source: stamp_source,
      override: override,
      override_reason: override_reason,
      stamped_at: stamped_at
    }
  end

  # Compact (single-line) JSON — no newlines, so the value is inert in a plain
  # cardtype and safe from any line-oriented processing.
  def to_json_compact(record)
    JSON.generate(record)
  end

  def parse(json)
    JSON.parse(json)
  end
end
