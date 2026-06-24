# frozen_string_literal: true
#
# L5 / Mechanism 3 canonical projection serializer (Lane A anchor). Asserts the Ruby serializer
# against the SHARED golden-vector fixture (the identical file is asserted by the sidecar's Python
# test). If this and the Python test both pass, the two serializers are byte-for-byte identical.

require "json"
require_relative "../../mod/atomspace_mirror/lib/canonical_projection"

RSpec.describe CanonicalProjection do
  GOLDEN = JSON.parse(File.read(File.expand_path("golden_projection_vectors.json", __dir__)))

  describe "golden vectors (shared Ruby<->Python parity fixture)" do
    GOLDEN["vectors"].each do |vec|
      it "#{vec['name']}: bytes + sha256 match the locked fixture" do
        expect(CanonicalProjection.serialize(vec["input"])).to eq(vec["expected_bytes"])
        expect(CanonicalProjection.sha256(vec["input"])).to eq(vec["expected_sha256"])
      end
    end

    it "covers symbols, booleans, unresolved refs, and unicode/control chars" do
      names = GOLDEN["vectors"].map { |v| v["name"] }
      expect(names).to include("symbols_and_sorted_refs", "unicode_and_control_chars")
    end
  end

  describe ".structure" do
    it "puts DeckoCard first, then references in total-sort order" do
      atoms = GOLDEN["vectors"].find { |v| v["name"] == "symbols_and_sorted_refs" }["input"]
      st = CanonicalProjection.structure(atoms)
      expect(st.first[0]).to eq("DeckoCard")
      ref_keys = st.drop(1).map { |_kind, fields| fields.find { |n, _| n == "RefereeKey" }[1] }
      # I-type first, then L-type resolved by RefereeId asc, then L-type unresolved last
      expect(ref_keys).to eq(%w[mmm_target bbb_target zzz_target aaa_target])
    end

    it "raises on zero OR multiple DeckoCards (exactly one, never 'at least one')" do
      expect { CanonicalProjection.structure([{ "atom" => "DeckoReference", "fields" => [] }]) }
        .to raise_error(ArgumentError, /exactly one DeckoCard/)
      two = [{ "atom" => "DeckoCard", "fields" => [["Id", 1]] }, { "atom" => "DeckoCard", "fields" => [["Id", 1]] }]
      expect { CanonicalProjection.structure(two) }.to raise_error(ArgumentError, /exactly one DeckoCard, got 2/)
    end
  end

  describe ".ref_sort_key" do
    it "resolved references sort before unresolved of the same type" do
      resolved = { "atom" => "DeckoReference",
                   "fields" => [["RefereeId", 5], ["RefType", { "sym" => "L" }], ["RefereeKey", "k"]] }
      unresolved = { "atom" => "DeckoReference",
                     "fields" => [["RefereeId", { "sym" => "Unresolved" }], ["RefType", { "sym" => "L" }], ["RefereeKey", "k"]] }
      expect(CanonicalProjection.ref_sort_key(resolved)[1]).to eq(0)
      expect(CanonicalProjection.ref_sort_key(unresolved)[1]).to eq(1)
    end
  end
end
