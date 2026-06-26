# frozen_string_literal: true

require "json"
require "digest"

# Level 5 / Mechanism 3 -- the canonical per-card projection serializer (Lane A side, the ANCHOR
# implementation). The Lane B sidecar implements a byte-identical serializer in Python; a SHARED
# golden-vector fixture (spec/atomspace_mirror/golden_projection_vectors.json, copied verbatim into
# the sidecar repo) is asserted by BOTH suites so the two languages can never silently diverge.
#
# A "projection" is one card's drift-relevant state: the DeckoCard atom + all its DeckoReference
# atoms (provenance EXCLUDED -- it varies per event and would corrupt drift detection). Input is the
# CardAtomEncoder.encode_card_snapshot(card) output (already provenance-free, field values already in
# JSON-primitive form: Integer | String | true/false | nil | {"sym" => "..."}).
#
# Canonical byte format (LOCKED 2026-06-24, Card 17374; deterministic minimal-whitespace JSON over
# ORDERED arrays -- NOT S-expressions, which are unsafe for Content's arbitrary whitespace/newlines):
#
#   [["DeckoCard",     [["Id",N],["Name","X"],["Codename",{"sym":"Y"}], ...]],
#    ["DeckoReference", [["RefererId",N], ...]],
#    ...]
#
#   * DeckoCard first, then DeckoReference atoms.
#   * Field order = the exact encoder field order (NOT sorted).
#   * Reference total-order sort key (must be TOTAL so Ruby + Python cannot diverge on ties, Codex):
#       (RefType, resolved_flag, RefereeId_or_0, RefereeKey, canonical_reference_json)
#     resolved_flag = RefereeId is an Integer ? 0 : 1 (resolved refs sort first); the trailing
#     canonical-json of the reference itself is the ultimate deterministic tie-breaker.
#   * Bytes: JSON.generate (no insignificant whitespace, order preserved, raw UTF-8). The Python side
#     uses json.dumps(obj, separators=(",",":"), ensure_ascii=False).encode("utf-8") -- identical.
#   * Hash: SHA256 hexdigest of those UTF-8 bytes.
module CanonicalProjection
  module_function

  CARD_KIND = "DeckoCard"
  REF_KIND  = "DeckoReference"

  # atoms: the encode_card_snapshot list. Returns the canonical UTF-8 byte string.
  def serialize(atoms)
    JSON.generate(structure(atoms))
  end

  def sha256(atoms)
    Digest::SHA256.hexdigest(serialize(atoms))
  end

  # The ordered [[kind, fields], ...] structure JSON is generated from. Split out for golden tests.
  def structure(atoms)
    cards = atoms.select { |a| a["atom"] == CARD_KIND }
    # EXACTLY one (not "at least one") -- a multi-card projection is corruption, never hashed clean.
    raise ArgumentError, "projection requires exactly one DeckoCard, got #{cards.size}" unless cards.size == 1

    refs = atoms.select { |a| a["atom"] == REF_KIND }.sort_by { |r| ref_sort_key(r) }
    [[CARD_KIND, cards.first["fields"]], *refs.map { |r| [REF_KIND, r["fields"]] }]
  end

  # Total deterministic ordering key for one DeckoReference atom.
  def ref_sort_key(ref)
    ref_type    = field_value(ref, "RefType")     # {"sym"=>code} -> code; coerced to string below
    referee_id  = field_value(ref, "RefereeId")   # Integer when resolved, {"sym"=>"Unresolved"} when not
    referee_key = field_value(ref, "RefereeKey")  # String
    resolved = referee_id.is_a?(Integer)
    [
      symbol_or_string(ref_type),
      resolved ? 0 : 1,
      resolved ? referee_id : 0,
      referee_key.to_s,
      JSON.generate([REF_KIND, ref["fields"]])    # ultimate tie-breaker
    ]
  end

  # --- helpers ---

  def field_value(atom, name)
    pair = Array(atom["fields"]).find { |fname, _| fname == name }
    pair && pair[1]
  end

  # A field value is either a {"sym"=>x} hash (MeTTa symbol) or a JSON primitive; reduce to a
  # comparable string for the sort key.
  def symbol_or_string(value)
    value.is_a?(Hash) ? value["sym"].to_s : value.to_s
  end
end
