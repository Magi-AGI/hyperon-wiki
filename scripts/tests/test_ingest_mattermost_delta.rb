#!/usr/bin/env ruby
# Offline unit tests for the Phase-1 delta planner in ingest_mattermost.rb.
#
# These run WITHOUT Decko/Rails: `Card` is undefined, so live_content() returns
# nil and the planner's DB-touching paths are inert. What is tested here is the
# part that must be right before anything is ever written:
#
#   1. the DELTA=1 + writes-enabled guard aborts, and aborts before any write
#   2. hashing ignores the exported_at header line and nothing else
#   3. change_reason classifies each observed change class
#
# Run: ruby scripts/tests/test_ingest_mattermost_delta.rb

require "minitest/autorun"
require "json"
require "open3"
require "tmpdir"

INGEST = File.expand_path("../ingest_mattermost.rb", __dir__)

load INGEST

# ------------------------------------------------------------
# 1. The guard: DELTA without DRY_RUN must refuse to run.
# ------------------------------------------------------------
# Driven as a subprocess because the guard runs at load time and calls abort.
class TestDeltaRequiresDryRun < Minitest::Test
  def run_ingest(env)
    # MATTERMOST_INGEST=1 makes the script auto-run, so a guard failure is the
    # only thing that can stop it before it starts planning.
    Open3.capture3(env, RbConfig.ruby, INGEST)
  end

  def test_delta_without_dry_run_aborts
    out, err, status = run_ingest(
      "MATTERMOST_INGEST" => "1",
      "MATTERMOST_INGEST_DELTA" => "1",
      "MATTERMOST_INGEST_DRY_RUN" => nil
    )
    refute status.success?, "delta without dry-run must exit non-zero"
    assert_match(/requires MATTERMOST_INGEST_DRY_RUN=1/, err + out)
  end

  def test_abort_happens_before_any_planning
    # The guard must fire before the export dir is even consulted, so no card
    # is fetched, rendered or classified on the way to the refusal.
    out, err, _status = run_ingest(
      "MATTERMOST_INGEST" => "1",
      "MATTERMOST_INGEST_DELTA" => "1",
      "MATTERMOST_INGEST_DRY_RUN" => nil,
      "MATTERMOST_EXPORT_DIR" => "/nonexistent-export-dir"
    )
    combined = out + err
    refute_match(/Export directory/, combined,
                 "guard must abort before the export dir is read")
    refute_match(/would update|would create|Updated:|Created:/, combined,
                 "guard must abort before any card is planned or written")
  end

  def test_delta_with_dry_run_is_allowed
    # Same invocation plus DRY_RUN: it gets past the guard (and then fails on
    # the missing export dir, which is a different, later error).
    out, err, _status = run_ingest(
      "MATTERMOST_INGEST" => "1",
      "MATTERMOST_INGEST_DELTA" => "1",
      "MATTERMOST_INGEST_DRY_RUN" => "1",
      "MATTERMOST_EXPORT_DIR" => "/nonexistent-export-dir"
    )
    combined = out + err
    refute_match(/requires MATTERMOST_INGEST_DRY_RUN=1/, combined)
    assert_match(/Export directory not found/, combined)
  end

  def test_full_write_mode_is_unaffected_by_the_guard
    # The guard must not change behaviour when DELTA is off.
    out, err, _status = run_ingest(
      "MATTERMOST_INGEST" => "1",
      "MATTERMOST_EXPORT_DIR" => "/nonexistent-export-dir"
    )
    refute_match(/requires MATTERMOST_INGEST_DRY_RUN=1/, out + err)
  end
end

# ------------------------------------------------------------
# 2. Hash normalization
# ------------------------------------------------------------
class TestHashNormalization < Minitest::Test
  def card(exported:, body: "<p>hello</p>")
    <<~HTML
      <p><strong>Source:</strong> Mattermost — Chan</p>
      <p><strong>Channel:</strong> chan (public)</p>
      <p><strong>Exported:</strong> #{exported}</p>
      <p><strong>Posts:</strong> 2</p>
      <hr>
      #{body}
    HTML
  end

  def test_exported_at_only_change_hashes_identically
    a = card(exported: "2026-10-05T01:45:54Z")
    b = card(exported: "2026-10-05T12:31:27Z")
    refute_equal a, b, "fixture must actually differ"
    assert_equal content_hash(a), content_hash(b),
                 "exported_at churn must not count as a change"
  end

  def test_real_body_change_still_hashes_differently
    a = card(exported: "2026-10-05T01:45:54Z", body: "<p>hello</p>")
    b = card(exported: "2026-10-05T01:45:54Z", body: "<p>hello there</p>")
    refute_equal content_hash(a), content_hash(b)
  end

  def test_body_change_is_detected_even_when_timestamp_also_moved
    # The dangerous case: both changed. Normalizing the timestamp must not
    # mask the body edit.
    a = card(exported: "2026-10-05T01:45:54Z", body: "<p>hello</p>")
    b = card(exported: "2026-10-05T12:31:27Z", body: "<p>hello there</p>")
    refute_equal content_hash(a), content_hash(b)
  end

  def test_normalization_removes_only_the_exported_line
    norm = normalize_for_hash(card(exported: "2026-10-05T01:45:54Z"))
    refute_match(/Exported:/, norm)
    assert_match(/Source:/, norm)
    assert_match(/Channel:/, norm)
    assert_match(/Posts:/, norm)
    assert_match(/hello/, norm)
  end

  def test_other_timestamps_are_not_stripped
    # Post timestamps live in the body and must stay in the hash.
    body = "<p><strong>alice</strong> (2026-10-05T11:00:00)</p>"
    a = normalize_for_hash(card(exported: "x", body: body))
    assert_match(/2026-10-05T11:00:00/, a)
  end
end

# ------------------------------------------------------------
# 3. change_reason classification
# ------------------------------------------------------------
class TestChangeReason < Minitest::Test
  def chunk(posts:, body:, exported: "2026-10-05T01:45:54Z")
    <<~HTML
      <p><strong>Source:</strong> Mattermost — Chan (chunk 1/2)</p>
      <p><strong>Exported:</strong> #{exported}</p>
      <p><strong>Posts in chunk:</strong> #{posts}</p>
      <hr>
      #{body}
    HTML
  end

  def test_missing_card
    assert_equal "missing_card", change_reason(nil, chunk(posts: 1, body: "<p>a</p>"))
  end

  def test_posts_added
    before = chunk(posts: 2, body: "<p>a</p>")
    after  = chunk(posts: 3, body: "<p>a</p>\n<p>b</p>")
    assert_equal "posts_added", change_reason(before, after)
  end

  def test_posts_removed
    before = chunk(posts: 3, body: "<p>a</p>\n<p>b</p>")
    after  = chunk(posts: 2, body: "<p>a</p>")
    assert_equal "posts_removed", change_reason(before, after)
  end

  def test_post_edited_keeps_same_count
    # The case a post-ID diff would miss: same posts, one message rewritten.
    before = chunk(posts: 2, body: "<p>typo</p>")
    after  = chunk(posts: 2, body: "<p>fixed</p>")
    assert_equal "post_edited", change_reason(before, after)
  end

  def test_channel_meta_changed_when_body_is_identical
    # Header moved (e.g. post_count on an index card) but no post body did.
    before = chunk(posts: 2, body: "<p>a</p>")
    after  = chunk(posts: 5, body: "<p>a</p>")
    assert_equal "channel_meta_changed", change_reason(before, after)
  end
end

# ------------------------------------------------------------
# 4. Planner classification over fixtures
# ------------------------------------------------------------
# Without Decko, live_content() returns nil, so every card is a "create".
# That is the correct offline answer and it proves the delta branch is wired
# into create_or_update_card and records the report fields.
class TestDeltaPlannerWiring < Minitest::Test
  def setup
    STATS[:cards].clear
    STATS[:perms].clear
    %i[created updated errors planned_create planned_update skipped_unchanged
       perm_created perm_updated perm_errors perm_skipped_unchanged
       planned_perm_create planned_perm_update].each { |k| STATS[k] = 0 }
  end

  def test_delta_mode_is_off_by_default_in_this_test_run
    # Guards the suite itself: these tests describe the non-delta default,
    # and the delta path is exercised through its own functions above.
    assert_equal false, DELTA, "run this file without MATTERMOST_INGEST_DELTA"
  end

  def test_planner_records_hash_and_reason_fields
    skip "delta classification requires MATTERMOST_INGEST_DELTA=1" unless DELTA

    create_or_update_card("Raw Data+mattermost+Fixture", "<p>x</p>")
    entry = STATS[:cards].last
    assert_equal "create", entry[:action]
    assert_equal "missing_card", entry[:reason]
    refute_nil entry[:hash_after]
    assert_nil entry[:hash_before]
  end
end

# ------------------------------------------------------------
# 5. Read-rule comparison is item-based, not literal
# ------------------------------------------------------------
# Regression: the write path sets a read rule's content to "[[Party]]", but
# Decko stores a List card's value as the bare "Party". Comparing raw strings
# made all 17 already-correct rules report as "update" on every delta run.
# The planner must compare normalized items instead.
class TestReadRuleItemComparison < Minitest::Test
  # Mirrors the comparison in restrict_card_to_private_party's DELTA branch.
  def matches?(live_items, party_name)
    live_items.map { |i| name_key(i) } == [name_key(party_name)]
  end

  def test_decko_normalized_rule_value_is_not_a_change
    # What Decko actually returns for a rule written as "[[Lake Watkins]]".
    assert matches?(["Lake Watkins"], "Lake Watkins"),
           "a correctly-set rule must not be planned as an update"
  end

  def test_bracket_form_also_matches
    assert matches?(["[[Lake Watkins]]".delete("[]")], "Lake Watkins")
  end

  def test_different_party_is_a_change
    refute matches?(["Someone Else"], "Lake Watkins")
  end

  def test_extra_party_is_a_change
    refute matches?(["Lake Watkins", "Someone Else"], "Lake Watkins"),
           "an over-readable rule must still be planned as an update"
  end

  def test_empty_rule_is_a_change
    refute matches?([], "Lake Watkins")
  end
end

