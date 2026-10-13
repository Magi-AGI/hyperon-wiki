#!/usr/bin/env ruby
# Offline unit tests for the Phase-3 report-only classification in
# ingest_mattermost.rb: orphan labelling, chunk shrink/orphan reporting, and
# the name-binding manifest.
#
# These run WITHOUT Decko/Rails. `Card` is undefined, so the DB-touching
# entry points (find_orphans, chunk_count_changes) short-circuit to []. What
# is exercised here are the pure functions underneath them, which take the
# live and planned name lists explicitly:
#
#   classify_orphans(orphans, planned_names, channels)
#   chunk_changes(channels, live_names, planned_names)
#   name_binding_manifest(channels, live_names, classified_orphans)
#   orphan_summary(classified)
#
# The fixtures are the real shapes observed on the live deck in the Phase 2
# validation of export sync_20261005_123127: PLN has 7 live chunk cards but
# only 5 planned, and the 20 reported orphans are a mix of stranded chunks,
# pre-fix nested-name artifacts, and genuinely gone channels.
#
# Run: ruby scripts/tests/test_ingest_mattermost_phase3.rb

require "minitest/autorun"
require "json"

INGEST = File.expand_path("../ingest_mattermost.rb", __dir__)

load INGEST

PARENT = "Raw Data+mattermost"

# ------------------------------------------------------------
# Fixture helpers
# ------------------------------------------------------------

def channel(display, card_name = nil, id: nil, slug: nil, type: "O",
            label_reason: "display_name")
  {
    id: id || "id-#{display.downcase.gsub(/[^a-z0-9]+/, '')}",
    slug: slug || display.downcase.gsub(/[^a-z0-9]+/, "-"),
    display: display,
    card_name: card_name || "#{PARENT}+#{display}",
    type: type,
    label_reason: label_reason
  }
end

def orphan(name)
  { name: name, key: name_key(name) }
end

# A live card name.
#
# NOTE ON NAME FORM. The real deck stores this branch as "RawData+mattermost"
# while PARENT_CARD is "Raw Data+mattermost"; under Decko both resolve to the
# key "raw_datum+mattermost", which is why the planner compares keys and never
# raw strings. Offline, `Cardname` is absent and name_key() falls back to a
# documented approximation that cannot know "RawData" and "Raw Data" are the
# same word, so these fixtures use the PARENT_CARD form. The stored-form
# equivalence is asserted separately in TestStoredNameFormEquivalence, which
# skips unless Decko is loaded.
def live(name)
  orphan("#{PARENT}+#{name}")
end

# A planned card list as STATS[:cards] would hold it.
def planned(*names)
  names.map { |n| "#{PARENT}+#{n}" }
end

# ------------------------------------------------------------
# 1. The PLN shrink case: 7 live chunks, 5 planned.
# ------------------------------------------------------------
class TestChunkShrink < Minitest::Test
  def setup
    @channels = [channel("PLN", id: "dzw5ajh3ojyyzdb6cku5gic59r")]
    # Index card + chunk-1..5 is what the current export plans.
    @planned = planned("PLN", *(1..5).map { |i| "PLN+chunk-#{i}" })
    # chunk-1..7 exist live, from an earlier, larger export.
    @live = ["#{PARENT}+PLN"] + (1..7).map { |i| "#{PARENT}+PLN+chunk-#{i}" }
    STATS[:cards] = @planned.map { |n| { name: n, action: "skip-unchanged" } }
  end

  def teardown
    STATS[:cards] = []
  end

  def changes
    chunk_changes(@channels, @live, @planned)
  end

  def test_shrink_is_reported_once_for_the_channel
    assert_equal 1, changes.length
  end

  def test_counts_and_direction
    c = changes.first
    assert_equal 7, c[:live_chunks]
    assert_equal 5, c[:planned_chunks]
    assert_equal(-2, c[:delta])
    assert_equal "shrink", c[:direction]
  end

  def test_stale_chunk_cards_are_named_not_just_counted
    # The whole point of Phase 3: the report must say WHICH cards strand.
    c = changes.first
    assert_equal ["#{PARENT}+PLN+chunk-6", "#{PARENT}+PLN+chunk-7"],
                 c[:stale_chunk_cards]
    assert_empty c[:new_chunk_cards]
  end

  def test_chunk_indexes_are_reported
    c = changes.first
    assert_equal (1..7).to_a, c[:live_chunk_indexes]
    assert_equal (1..5).to_a, c[:planned_chunk_indexes]
  end

  def test_an_unchanged_channel_is_not_reported
    unchanged = planned("PLN", *(1..7).map { |i| "PLN+chunk-#{i}" })
    STATS[:cards] = unchanged.map { |n| { name: n, action: "skip-unchanged" } }
    assert_empty chunk_changes(@channels, @live, unchanged)
  end

  def test_growth_is_reported_without_stale_cards
    grown = planned("PLN", *(1..9).map { |i| "PLN+chunk-#{i}" })
    STATS[:cards] = grown.map { |n| { name: n, action: "update" } }
    c = chunk_changes(@channels, @live, grown).first
    assert_equal "grow", c[:direction]
    assert_equal 2, c[:delta]
    assert_empty c[:stale_chunk_cards]
    assert_equal ["#{PARENT}+PLN+chunk-8", "#{PARENT}+PLN+chunk-9"],
                 c[:new_chunk_cards]
  end

  def test_resegmentation_reports_both_sides
    # Chunk boundaries moved: 1..7 live, but the plan skips 6 and adds 8.
    reseg = planned("PLN", *[1, 2, 3, 4, 5, 7, 8].map { |i| "PLN+chunk-#{i}" })
    STATS[:cards] = reseg.map { |n| { name: n, action: "update" } }
    c = chunk_changes(@channels, @live, reseg).first
    assert_equal "resegmented", c[:direction]
    assert_equal ["#{PARENT}+PLN+chunk-6"], c[:stale_chunk_cards]
    assert_equal ["#{PARENT}+PLN+chunk-8"], c[:new_chunk_cards]
  end

  def test_gap_in_live_numbering_does_not_hide_the_shrink
    # Phase 1 counted live chunks with a take_while from 1, so a missing
    # chunk-1 reported "0 live chunks" and the shrink vanished from the
    # report. Regression guard for exactly that.
    gappy = ["#{PARENT}+PLN"] + [2, 3, 4, 5, 6, 7].map { |i| "#{PARENT}+PLN+chunk-#{i}" }
    c = chunk_changes(@channels, gappy, @planned).first
    refute_nil c, "a gap in live chunk numbering must not hide the shrink"
    assert_equal 6, c[:live_chunks]
    assert_equal ["#{PARENT}+PLN+chunk-6", "#{PARENT}+PLN+chunk-7"],
                 c[:stale_chunk_cards]
    assert_equal [1], c[:live_index_gaps]
  end

  def test_index_already_consistent_is_flagged
    # The live index card matching the plan means the stale chunks are
    # ALREADY unreferenced in the deck - a delta write neither causes nor
    # repairs that. The distinction matters when deciding remediation.
    c = changes.first
    assert c[:index_already_consistent]
    assert_match(/ALREADY stranded/, c[:note])
  end

  def test_index_rewrite_is_flagged_when_the_index_card_changes
    STATS[:cards] = @planned.map do |n|
      { name: n, action: (n == "#{PARENT}+PLN" ? "update" : "skip-unchanged") }
    end
    c = changes.first
    refute c[:index_already_consistent]
    assert_match(/index card will be rewritten/, c[:note])
  end

  def test_chunk_shrink_reporting_never_implies_deletion
    c = changes.first
    refute_match(/delete|trash|remov/i, c[:note])
  end
end

# ------------------------------------------------------------
# 2. Orphan classification
# ------------------------------------------------------------
class TestOrphanClassification < Minitest::Test
  def teardown
    STATS[:cards] = []
  end

  def classify(orphans, planned_names, channels)
    classify_orphans(orphans, planned_names, channels)
  end

  def one(orphans, planned_names, channels)
    classify(orphans, planned_names, channels).first
  end

  def test_stale_chunk_is_identified_as_the_shrink_case
    e = one([live("PLN+chunk-7")],
            planned("PLN", *(1..5).map { |i| "PLN+chunk-#{i}" }),
            [channel("PLN")])
    assert_equal "stale_chunk", e[:classification]
    assert_equal 7, e[:chunk_index]
    assert_match(/only 5 chunk/, e[:detail])
    assert_match(/high-water/, e[:detail])
  end

  def test_stale_chunk_records_its_base_card
    e = one([live("PLN+chunk-6")],
            planned("PLN", "PLN+chunk-1"),
            [channel("PLN")])
    assert_equal "stale_chunk", e[:classification]
    assert_equal name_key("#{PARENT}+PLN"), name_key(e[:base_card])
  end

  def test_superseded_by_rename_for_a_pre_fix_nested_channel
    # "LLM+PLN" used to be filed as two name parts; sanitize_name_part now
    # collapses "+" to "-", so the content lives at "LLM-PLN".
    e = one([live("LLM+PLN")], planned("LLM-PLN"),
            [channel("LLM+PLN", "#{PARENT}+LLM-PLN")])
    assert_equal "superseded_by_rename", e[:classification]
    assert_equal "#{PARENT}+LLM-PLN", e[:superseded_by]
  end

  def test_superseded_by_rename_carries_the_chunk_index
    e = one([live("LLM+PLN+chunk-2")], planned("LLM-PLN", "LLM-PLN+chunk-2"),
            [channel("LLM+PLN", "#{PARENT}+LLM-PLN")])
    assert_equal "superseded_by_rename", e[:classification]
    assert_equal "#{PARENT}+LLM-PLN+chunk-2", e[:superseded_by]
    assert_equal 2, e[:chunk_index]
  end

  def test_nesting_stub_is_distinguished_from_a_vanished_channel
    # "RawData+mattermost+LLM" exists only because the pre-fix ingest nested
    # "LLM+PLN" under it. It is structure, not a lost channel.
    classified = classify(
      [live("LLM"), live("LLM+PLN"), live("LLM+PLN+chunk-1")],
      planned("LLM-PLN", "LLM-PLN+chunk-1"),
      [channel("LLM+PLN", "#{PARENT}+LLM-PLN")]
    )
    stub = classified.find { |e| e[:name] == "#{PARENT}+LLM" }
    assert_equal "nesting_stub", stub[:classification]
    assert_equal 2, classified.count { |e| e[:classification] == "superseded_by_rename" }
  end

  def test_relabeled_channel_when_a_duplicate_display_name_was_disambiguated
    # Two channels both display as "test", so each card name gained a slug
    # suffix. The bare "test" card from an earlier run is now unreferenced.
    e = one([live("test")],
            planned("test (test)", "test (test-jan1)"),
            [channel("test", "#{PARENT}+test (test)", slug: "test",
                     label_reason: "display_name_and_slug"),
             channel("test", "#{PARENT}+test (test-jan1)", slug: "test-jan1",
                     label_reason: "display_name_and_slug")])
    assert_equal "relabeled_channel", e[:classification]
    assert_match(/now filed as/, e[:detail])
  end

  def test_vanished_channel_when_nothing_in_the_export_maps_to_it
    e = one([live("BioPerformance")], planned("PLN"), [channel("PLN")])
    assert_equal "vanished_channel", e[:classification]
    assert_nil e[:chunk_index]
  end

  def test_vanished_channel_chunk_is_tied_to_its_orphaned_channel
    classified = classify(
      [live("invoicing-currency-rate"), live("invoicing-currency-rate+chunk-1")],
      planned("PLN"), [channel("PLN")]
    )
    chunk = classified.find { |e| e[:chunk_index] == 1 }
    assert_equal "vanished_channel_chunk", chunk[:classification]
    assert_match(/orphaned channel card/, chunk[:detail])
  end

  def test_a_planned_chunk_reported_as_orphan_is_surfaced_not_swallowed
    # Contradictory input: the card is both planned and reported orphan.
    # It must be labelled loudly rather than silently called stale.
    e = one([live("PLN+chunk-2")],
            planned("PLN", "PLN+chunk-1", "PLN+chunk-2"),
            [channel("PLN")])
    assert_equal "unexpected_planned_chunk", e[:classification]
    assert_equal 1, orphan_summary([e])[:unexpected]
  end

  def test_every_orphan_gets_a_classification_and_detail
    orphans = [live("PLN+chunk-7"), live("LLM+PLN"), live("LLM"),
               live("BioPerformance"), live("test")]
    classified = classify(orphans, planned("PLN", "PLN+chunk-1", "LLM-PLN"),
                          [channel("PLN"), channel("LLM+PLN", "#{PARENT}+LLM-PLN")])
    assert_equal orphans.length, classified.length
    classified.each do |e|
      refute_nil e[:classification], "#{e[:name]} was left unclassified"
      refute_empty e[:detail].to_s, "#{e[:name]} has no detail"
    end
  end

  def test_classification_preserves_the_original_name_and_key
    o = live("PLN+chunk-7")
    e = one([o], planned("PLN"), [channel("PLN")])
    assert_equal o[:name], e[:name]
    assert_equal o[:key], e[:key]
  end
end

# ------------------------------------------------------------
# 3. orphan_summary
# ------------------------------------------------------------
class TestOrphanSummary < Minitest::Test
  # The 20-orphan shape observed live on export sync_20261005_123127.
  def live_fixture
    [live("Qwestor"), live("test"), live("AGI settle accounts AGI Society"),
     live("LLM"), live("Virtual robotics"), live("invoicing-currency-rate"),
     live("BioPerformance"), live("OmegaClaw news and updates"),
     live("OpenBGI Slack Bot Creation Sprint"), live("SophiaVerse Team"),
     live("PLN+chunk-7"), live("PLN+chunk-6"), live("Qwestor+PLN"),
     live("invoicing-currency-rate+chunk-1"),
     live("invoicing-currency-rate+chunk-2"),
     live("invoicing-currency-rate+chunk-3"),
     live("LLM+PLN"),
     live("Virtual robotics+experiential learning state of the union"),
     live("LLM+PLN+chunk-1"), live("LLM+PLN+chunk-2")]
  end

  def planned_fixture
    planned("PLN", *(1..5).map { |i| "PLN+chunk-#{i}" },
            "LLM-PLN", "LLM-PLN+chunk-1", "LLM-PLN+chunk-2",
            "Qwestor - PLN",
            "Virtual robotics - experiential learning state of the union",
            "test (test)", "test (test-jan1)")
  end

  def channels_fixture
    [channel("PLN"),
     channel("LLM+PLN", "#{PARENT}+LLM-PLN"),
     channel("Qwestor + PLN", "#{PARENT}+Qwestor - PLN"),
     channel("Virtual robotics + experiential learning state of the union",
             "#{PARENT}+Virtual robotics - experiential learning state of the union"),
     channel("test", "#{PARENT}+test (test)", slug: "test",
             label_reason: "display_name_and_slug"),
     channel("test", "#{PARENT}+test (test-jan1)", slug: "test-jan1",
             label_reason: "display_name_and_slug")]
  end

  def summary
    orphan_summary(classify_orphans(live_fixture, planned_fixture, channels_fixture))
  end

  def test_total_matches_the_input
    assert_equal 20, summary[:total]
  end

  def test_the_two_pln_chunks_are_the_only_stale_chunks
    s = summary
    assert_equal ["#{PARENT}+PLN+chunk-6", "#{PARENT}+PLN+chunk-7"],
                 s[:stale_chunks]
    assert_equal 2, s[:needs_attention]
  end

  def test_no_unexpected_classifications_on_real_data
    assert_equal 0, summary[:unexpected]
  end

  def test_classifications_partition_the_orphans
    by = summary[:by_classification]
    assert_equal 20, by.values.sum
    assert_equal 2, by["stale_chunk"]
    # LLM+PLN, its 2 chunks, Qwestor+PLN, Virtual robotics+experiential...
    assert_equal 5, by["superseded_by_rename"]
  end

  def test_rename_artifacts_are_not_counted_as_needing_attention
    # 20 orphans, but only the 2 stale chunks are a decision. That reduction
    # is the deliverable of Phase 3.
    s = summary
    assert_equal 2, s[:needs_attention]
    assert_operator s[:needs_attention], :<, s[:total]
  end
end

# ------------------------------------------------------------
# 4. Name-binding manifest
# ------------------------------------------------------------
class TestNameBindingManifest < Minitest::Test
  def test_a_bound_channel_is_marked_bound
    m = name_binding_manifest([channel("PLN")], ["#{PARENT}+PLN"], []).first
    assert m[:live_present]
    assert_equal "bound", m[:binding]
  end

  def test_a_channel_with_no_live_card_is_marked_new
    m = name_binding_manifest([channel("Brand New")], ["#{PARENT}+PLN"], []).first
    refute m[:live_present]
    assert_equal "new_card", m[:binding]
    assert m[:notable]
  end

  def test_binding_is_decided_by_key_not_by_string
    # Decko keys are case- and punctuation-insensitive, so a live card whose
    # stored string differs from the planned string must still bind.
    m = name_binding_manifest([channel("PLN")], ["#{PARENT}+pln"], []).first
    assert m[:live_present], "binding must compare keys, not raw strings"
  end

  def test_manifest_records_what_a_renamed_channel_supersedes
    classified = classify_orphans([live("LLM+PLN")], planned("LLM-PLN"),
                                  [channel("LLM+PLN", "#{PARENT}+LLM-PLN")])
    m = name_binding_manifest([channel("LLM+PLN", "#{PARENT}+LLM-PLN")],
                              ["#{PARENT}+LLM-PLN"], classified).first
    assert_equal ["#{PARENT}+LLM+PLN"], m[:supersedes_live_cards]
    assert m[:notable]
  end

  def test_manifest_records_a_shadowing_live_card_for_a_relabeled_channel
    channels = [channel("test", "#{PARENT}+test (test)", slug: "test",
                        label_reason: "display_name_and_slug")]
    classified = classify_orphans([live("test")], planned("test (test)"), channels)
    m = name_binding_manifest(channels, ["#{PARENT}+test (test)"], classified).first
    assert_equal ["#{PARENT}+test"], m[:shadowed_by_live_cards]
    assert m[:notable]
  end

  def test_an_ordinary_bound_channel_is_not_notable
    m = name_binding_manifest([channel("PLN")], ["#{PARENT}+PLN"], []).first
    refute m[:notable], "a plain bound channel should not demand review"
  end

  def test_manifest_covers_every_channel
    channels = [channel("PLN"), channel("LLM+PLN", "#{PARENT}+LLM-PLN"),
                channel("Brand New")]
    m = name_binding_manifest(channels, ["#{PARENT}+PLN"], [])
    assert_equal 3, m.length
    assert_equal channels.map { |c| c[:card_name] }.sort,
                 m.map { |e| e[:planned_card_name] }.sort
  end
end

# ------------------------------------------------------------
# 5. Report-only guarantees
# ------------------------------------------------------------
class TestReportOnlyGuarantees < Minitest::Test
  def test_no_delete_or_trash_call_exists_anywhere_in_the_script
    src = File.read(INGEST)
    # Nothing in this script may delete, trash or rename a card in any mode.
    refute_match(/\.delete\b|\.destroy\b|\.trash\s*=|Card\.delete|\.rename\b/, src,
                 "ingest_mattermost.rb must contain no deletion/rename calls")
  end

  def test_classifiers_are_pure_and_need_no_card_constant
    refute defined?(Card), "these tests must run without Decko loaded"
    # Each pure classifier runs to completion with no DB present.
    assert_equal 1, classify_orphans([live("PLN+chunk-7")], planned("PLN"),
                                     [channel("PLN")]).length
    assert_equal 1, chunk_changes([channel("PLN")],
                                  ["#{PARENT}+PLN+chunk-1"], planned("PLN")).length
    assert_equal 1, name_binding_manifest([channel("PLN")], [], []).length
  end

  def test_db_entry_points_are_inert_without_decko
    # find_orphans / chunk_count_changes / find_name_binding_conflicts guard
    # on defined?(Card), so they are safe to call offline.
    assert_empty find_orphans([channel("PLN")])
    assert_empty chunk_count_changes([channel("PLN")])
    assert_empty find_name_binding_conflicts([channel("PLN")])
  end

  def test_write_readiness_note_states_no_write_path
    src = File.read(INGEST)
    assert_match(/write_path_implemented: false/, src)
  end
end

# ------------------------------------------------------------
# 6. Chunk-name parsing helpers
# ------------------------------------------------------------
class TestChunkNameParsing < Minitest::Test
  def test_display_and_key_chunk_forms_are_both_recognised
    assert_equal [["PLN"], 6], split_chunk_parts(%w[PLN chunk-6])
    assert_equal [["PLN"], 6], split_chunk_parts(%w[PLN chunk_6])
  end

  def test_a_channel_named_like_a_chunk_is_not_mistaken_for_one
    # A single-part name can never be a chunk: there is no base card to
    # attach it to.
    assert_equal [["chunk-6"], nil], split_chunk_parts(["chunk-6"])
  end

  def test_multi_digit_chunk_indexes_parse
    assert_equal [["PLN"], 12], split_chunk_parts(%w[PLN chunk-12])
  end

  def test_a_non_numeric_chunk_suffix_is_not_a_chunk
    assert_equal [%w[PLN chunk-six], nil], split_chunk_parts(%w[PLN chunk-six])
  end

  def test_chunk_index_by_base_groups_by_card_key
    idx = chunk_index_by_base(["#{PARENT}+PLN+chunk-1", "#{PARENT}+PLN+chunk_2",
                               "#{PARENT}+PLN+chunk-7", "#{PARENT}+PLN"])
    assert_equal 1, idx.keys.length, "display and key chunk forms must share one base"
    assert_equal [1, 2, 7], idx.values.first.to_a.sort
  end

  def test_superseding_name_collapses_only_nested_names
    assert_nil superseding_name("#{PARENT}+PLN")
    assert_equal "#{PARENT}+LLM-PLN", superseding_name("#{PARENT}+LLM+PLN")
  end
end

# ------------------------------------------------------------
# 7. Stored vs planned name form (requires Decko)
# ------------------------------------------------------------
# The live deck stores this branch as "RawData+mattermost+..." while
# PARENT_CARD is "Raw Data+mattermost". Under Decko both normalize to the key
# "raw_datum+mattermost" - that equivalence is the reason the planner compares
# keys and never raw strings, and it is what made the Phase 2 report classify
# 1,204 cards as unchanged instead of reporting every card as both an orphan
# and a create.
#
# It cannot be asserted offline: without `Cardname`, name_key() falls back to a
# documented approximation that has no inflector, so "RawData" and "Raw Data"
# differ. These tests therefore skip unless run under `decko runner`.
class TestStoredNameFormEquivalence < Minitest::Test
  def setup
    skip "requires Decko (Cardname) for real key normalization" unless defined?(Cardname)
  end

  def test_stored_and_planned_parent_forms_share_a_key
    assert_equal name_key("Raw Data+mattermost"), name_key("RawData+mattermost")
  end

  def test_a_stored_form_chunk_orphan_is_still_classified_as_stale
    e = classify_orphans([orphan("RawData+mattermost+PLN+chunk-7")],
                         planned("PLN", *(1..5).map { |i| "PLN+chunk-#{i}" }),
                         [channel("PLN")]).first
    assert_equal "stale_chunk", e[:classification]
    assert_equal 7, e[:chunk_index]
  end

  def test_a_stored_form_live_card_binds_the_channel
    m = name_binding_manifest([channel("PLN")], ["RawData+mattermost+PLN"], []).first
    assert m[:live_present]
    assert_equal "bound", m[:binding]
  end

  def test_chunk_shrink_is_detected_across_name_forms
    live_names = (1..7).map { |i| "RawData+mattermost+PLN+chunk-#{i}" }
    plan = planned("PLN", *(1..5).map { |i| "PLN+chunk-#{i}" })
    STATS[:cards] = plan.map { |n| { name: n, action: "skip-unchanged" } }
    c = chunk_changes([channel("PLN")], live_names, plan).first
    refute_nil c, "stored-form live chunks must still match the planned base"
    assert_equal 7, c[:live_chunks]
    assert_equal 5, c[:planned_chunks]
  ensure
    STATS[:cards] = []
  end
end
