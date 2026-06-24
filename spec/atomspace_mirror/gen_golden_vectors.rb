# frozen_string_literal: true
#
# Generates the SHARED golden-vector fixture from the Ruby ANCHOR (CanonicalProjection). Run once
# whenever the canonical format legitimately changes:
#   ruby spec/atomspace_mirror/gen_golden_vectors.rb
# Writes spec/atomspace_mirror/golden_projection_vectors.json (asserted by BOTH the Ruby spec and the
# Python sidecar test -- copy the file verbatim into the sidecar repo). Each vector pins a typed
# projection input -> exact canonical bytes -> exact sha256, so the two language serializers can never
# silently diverge.

require_relative "../../mod/atomspace_mirror/lib/canonical_projection"

def card(fields)
  { "atom" => "DeckoCard", "fields" => fields }
end

def ref(fields)
  { "atom" => "DeckoReference", "fields" => fields }
end

def sym(s)
  { "sym" => s }
end

# A realistic DeckoCard field list (encoder order), parameterized on the parts that matter for parity.
def card_fields(id:, name:, content:, codename:, left:, right:, trash:)
  [
    ["Id", id], ["Name", name], ["Key", name.downcase.gsub(/\s+/, "_")],
    ["Codename", codename], ["TypeId", 1], ["TypeName", "Basic"],
    ["LeftId", left], ["RightId", right], ["Content", content], ["Trash", trash],
    ["CreatedAt", "2026-06-24T00:00:00Z"], ["UpdatedAt", "2026-06-24T01:00:00Z"],
    ["CreatorId", 7], ["UpdaterId", 7]
  ]
end

def ref_fields(referer:, key:, referee:, type:, present:)
  [["RefererId", referer], ["RefereeKey", key], ["RefereeId", referee],
   ["RefType", sym(type)], ["IsPresent", present]]
end

vectors = {}

# 1. minimal card, no references, plain ascii
vectors["minimal_no_refs"] = [
  card(card_fields(id: 100, name: "Alpha", content: "hello", codename: sym("NoCodename"),
                   left: sym("NoLeft"), right: sym("NoRight"), trash: false))
]

# 2. symbols + booleans + a real codename + references that MUST be reordered by the total sort key
#    (given out of canonical order on purpose; includes a resolved + an unresolved ref of same type)
vectors["symbols_and_sorted_refs"] = [
  card(card_fields(id: 200, name: "Beta Card", content: "body", codename: sym("beta_code"),
                   left: 5, right: sym("NoRight"), trash: true)),
  ref(ref_fields(referer: 200, key: "zzz_target", referee: 900, type: "L", present: true)),
  ref(ref_fields(referer: 200, key: "aaa_target", referee: nil,  type: "L", present: false)), # unresolved -> Unresolved sym
  ref(ref_fields(referer: 200, key: "mmm_target", referee: 300, type: "I", present: true)),
  ref(ref_fields(referer: 200, key: "bbb_target", referee: 150, type: "L", present: true))
]
# fix the unresolved RefereeId to the sentinel symbol (encoder uses sym("Unresolved"))
vectors["symbols_and_sorted_refs"][2]["fields"][2][1] = sym("Unresolved")

# 3. unicode, newlines, quotes, backslash in Content + Name (the S-expr-killer case)
vectors["unicode_and_control_chars"] = [
  card(card_fields(id: 300, name: %(Quote "x" \\ slash), content: "line1\nline2\té— end",
                   codename: sym("NoCodename"), left: sym("NoLeft"), right: sym("NoRight"), trash: false)),
  ref(ref_fields(referer: 300, key: "uni_ref", referee: 301, type: "P", present: true))
]

out = vectors.map do |name, atoms|
  bytes = CanonicalProjection.serialize(atoms)
  {
    "name" => name,
    "input" => atoms,
    "expected_bytes" => bytes,
    "expected_sha256" => CanonicalProjection.sha256(atoms)
  }
end

path = File.expand_path("golden_projection_vectors.json", __dir__)
File.write(path, JSON.pretty_generate({ "version" => 1, "vectors" => out }) + "\n")
puts "wrote #{out.size} vectors -> #{path}"
out.each { |v| puts "  #{v['name']}: sha256=#{v['expected_sha256'][0, 16]}... bytes=#{v['expected_bytes'].bytesize}" }
