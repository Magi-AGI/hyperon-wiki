#!/usr/bin/env ruby
# Offline unit tests for the guards, naming and delta planner in
# ingest_transcripts.rb.
#
# These run WITHOUT Decko/Rails: `Card` and `Cardname` are undefined, so
# live_content() returns nil, the DB-touching paths are inert, and name_key()
# uses its approximation fallback. What is tested here is the part that must be
# right before anything is ever written:
#
#   1. the load-time guard: loading this file must not run an ingest
#   2. the DELTA + writes-enabled guard aborts, and aborts before DB access
#   3. card naming: sanitization, the RawData/Raw Data spelling, collisions
#   4. hashing needs no normalization (no per-run export timestamp)
#   5. change_reason classifies each observed change class
#   6. chunk shrink / orphan classification is report-only and names cards
#
# Run: ruby scripts/tests/test_ingest_transcripts_delta.rb

require "minitest/autorun"
require "json"
require "open3"
require "tmpdir"

INGEST = File.expand_path("../ingest_transcripts.rb", __dir__)

# Loading the script must be side-effect free: run! is guarded by
# `$PROGRAM_NAME == __FILE__ || TRANSCRIPT_INGEST=1`, and neither holds here.
load INGEST

# Snapshot STATS the instant the load finishes. The load-time guard below has
# to assert on *this*, not on live STATS: STATS is a global that the planner
# tests in this same process legitimately mutate, so under a random seed that
# schedules a planner test first, reading live STATS would report another
# test's fixtures as a load-time side effect and fail for the wrong reason.
STATS_AFTER_LOAD = {
  cards: STATS[:cards].dup,
  created: STATS[:created], updated: STATS[:updated], errors: STATS[:errors]
}.freeze

# ------------------------------------------------------------
# 1. The load-time guard
# ------------------------------------------------------------
class TestLoadTimeGuard < Minitest::Test
  def test_loading_this_file_did_not_run_an_ingest
    # If the guard were `defined?(Card)` (or absent), merely loading the script
    # under Decko would ingest. The proof it did not run here: no card was
    # planned or written during `load INGEST` above.
    assert_empty STATS_AFTER_LOAD[:cards],
                 "loading the script must not plan or write any card"
    assert_equal 0, STATS_AFTER_LOAD[:created] + STATS_AFTER_LOAD[:updated] +
                    STATS_AFTER_LOAD[:errors]
  end

  def test_run_requested_is_opt_in_only
    refute RUN_REQUESTED,
           "TRANSCRIPT_INGEST must not be set in the test environment"
  end

  def test_loading_under_a_simulated_decko_process_still_does_not_ingest
    # The regression this guard exists for: `Card` being defined must not be
    # enough to trigger a run. A subprocess defines a dummy Card constant
    # before loading the script, with no TRANSCRIPT_INGEST opt-in.
    script = <<~RUBY
      class Card; def self.fetch(*) = nil; end
      module Card::Auth; def self.as_bot; yield; end; end
      load #{INGEST.inspect}
      puts "CARDS=" + STATS[:cards].length.to_s
      puts "WROTE=" + (STATS[:created] + STATS[:updated]).to_s
    RUBY
    out, err, status = Open3.capture3(
      { "TRANSCRIPT_INGEST" => nil, "TRANSCRIPT_EXPORT_DIR" => nil },
      RbConfig.ruby, "-e", script
    )
    assert status.success?, "loading under a Decko-like process failed: #{err}"
    assert_match(/CARDS=0/, out, "loading with Card defined must not plan cards")
    assert_match(/WROTE=0/, out, "loading with Card defined must not write cards")
    refute_match(/Transcript Ingestion/, out,
                 "run! must not execute merely because Card is defined")
  end
end

# ------------------------------------------------------------
# 2. The delta guard: DELTA without DRY_RUN must refuse to run.
# ------------------------------------------------------------
# Driven as a subprocess because the guard runs at load time and calls abort.
class TestDeltaRequiresDryRun < Minitest::Test
  def run_ingest(env)
    # TRANSCRIPT_INGEST=1 makes the script auto-run, so a guard failure is the
    # only thing that can stop it before it starts planning.
    Open3.capture3(env, RbConfig.ruby, INGEST)
  end

  def test_delta_without_dry_run_aborts
    out, err, status = run_ingest(
      "TRANSCRIPT_INGEST" => "1",
      "TRANSCRIPT_INGEST_DELTA" => "1",
      "TRANSCRIPT_INGEST_DRY_RUN" => nil
    )
    refute status.success?, "delta without dry-run must exit non-zero"
    assert_match(/requires TRANSCRIPT_INGEST_DRY_RUN=1/, err + out)
  end

  def test_abort_happens_before_any_planning
    # The guard must fire before the export dir is even consulted, so no card
    # is fetched, rendered or classified on the way to the refusal.
    out, err, _status = run_ingest(
      "TRANSCRIPT_INGEST" => "1",
      "TRANSCRIPT_INGEST_DELTA" => "1",
      "TRANSCRIPT_INGEST_DRY_RUN" => nil,
      "TRANSCRIPT_EXPORT_DIR" => "/nonexistent-export-dir"
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
      "TRANSCRIPT_INGEST" => "1",
      "TRANSCRIPT_INGEST_DELTA" => "1",
      "TRANSCRIPT_INGEST_DRY_RUN" => "1",
      "TRANSCRIPT_EXPORT_DIR" => "/nonexistent-export-dir"
    )
    combined = out + err
    refute_match(/requires TRANSCRIPT_INGEST_DRY_RUN=1/, combined)
    assert_match(/Export directory not found/, combined)
  end

  def test_full_write_mode_is_unaffected_by_the_guard
    out, err, _status = run_ingest(
      "TRANSCRIPT_INGEST" => "1",
      "TRANSCRIPT_EXPORT_DIR" => "/nonexistent-export-dir"
    )
    refute_match(/requires TRANSCRIPT_INGEST_DRY_RUN=1/, out + err)
  end

  def test_truthy_spellings_are_accepted_for_the_guard
    %w[true yes on].each do |val|
      _out, err, status = run_ingest(
        "TRANSCRIPT_INGEST" => "1",
        "TRANSCRIPT_INGEST_DELTA" => val,
        "TRANSCRIPT_INGEST_DRY_RUN" => nil
      )
      refute status.success?, "DELTA=#{val} must be treated as enabled"
      assert_match(/requires TRANSCRIPT_INGEST_DRY_RUN=1/, err)
    end
  end
end

# ------------------------------------------------------------
# 3. Naming
# ------------------------------------------------------------
class TestSanitizeNamePart < Minitest::Test
  def test_collapses_decko_joint
    assert_equal "LLM-PLN Sync", sanitize_name_part("LLM+PLN Sync")
    assert_equal "Neuromorphic - PC", sanitize_name_part("Neuromorphic + PC")
  end

  def test_collapses_slash_and_markup
    assert_equal "Robot- PR", sanitize_name_part("Robot/ PR")
    assert_equal "Bitgrit - SingularityNET", sanitize_name_part("Bitgrit <> SingularityNET")
  end

  def test_strips_nest_syntax
    # The old sanitizer only handled "+" and "/", so a title with brackets
    # could emit Decko nest/markup syntax into a card name. Each brace run
    # collapses to a single "-", and a trailing one is then trimmed.
    assert_equal "Weekly -Standup", sanitize_name_part("Weekly {{Standup}}")
    assert_equal "A-B", sanitize_name_part("A|B")
    refute_match(/[{}\[\]|<>#"]/, sanitize_name_part('A{{b}}[[c]]|d<e>#f"g'),
                 "no nest/markup character may survive sanitization")
  end

  def test_strips_reserved_prefixes
    assert_equal "account review", sanitize_name_part("*account review")
    assert_equal "foo", sanitize_name_part("~foo")
  end

  def test_blank_becomes_nil
    assert_nil sanitize_name_part("")
    assert_nil sanitize_name_part("   ")
    assert_nil sanitize_name_part("+++")
  end

  def test_single_part_after_sanitize
    # The whole point: a sanitized title must never introduce extra name parts.
    ["LLM+PLN", "Neuromorphic + PC", "a+b+c+d"].each do |raw|
      refute_includes sanitize_name_part(raw), "+",
                      "#{raw.inspect} still contains the joint"
    end
  end
end

class TestParentCardSpelling < Minitest::Test
  def test_parent_card_is_the_display_spelling
    assert_equal "Raw Data+transcripts", PARENT_CARD
  end

  def test_rawdata_and_raw_data_spellings_share_one_key
    # The docs say "RawData+transcripts"; this script says
    # "Raw Data+transcripts". They are the same card, and every identity
    # comparison in the planner goes through name_key for exactly this reason.
    # If these ever diverge, orphan detection reports every live card as both
    # an orphan and a create.
    assert_equal name_key("RawData+transcripts"), name_key(PARENT_CARD)
    assert_equal name_key("RawData+transcripts+Standup+2026-01-02"),
                 name_key("Raw Data+transcripts+Standup+2026-01-02")
  end

  def test_parent_part_count_matches_the_parent
    assert_equal 2, PARENT_PART_COUNT
  end

  def test_a_transcript_card_is_exactly_four_parts
    t = [{ meeting_name: "LLM+PLN Sync", date: "2026-01-02",
           transcript_id: "t1", source_service: "fireflies.ai" }]
    assign_transcript_labels(t)
    assert_equal 4, t[0][:card_name].split("+").length,
                 "#{t[0][:card_name].inspect} has the wrong part count"
  end
end

class TestAssignTranscriptLabels < Minitest::Test
  def tr(id:, name:, date:, service: "fireflies.ai")
    { transcript_id: id, meeting_name: name, date: date, source_service: service }
  end

  def test_unambiguous_titles_are_preserved
    ts = [tr(id: "a1", name: "Weekly Standup", date: "2026-01-02"),
          tr(id: "b2", name: "Design Review", date: "2026-01-03")]
    assign_transcript_labels(ts)
    assert_equal "Weekly Standup", ts[0][:label]
    assert_equal %w[meeting_name meeting_name], ts.map { |t| t[:label_reason] }
    assert_equal "Raw Data+transcripts+Weekly Standup+2026-01-02", ts[0][:card_name]
  end

  def test_same_title_on_different_dates_is_not_a_collision
    ts = [tr(id: "a1", name: "Standup", date: "2026-01-02"),
          tr(id: "b2", name: "Standup", date: "2026-01-03")]
    assign_transcript_labels(ts)
    assert_equal %w[meeting_name meeting_name], ts.map { |t| t[:label_reason] }
    assert_equal 2, ts.map { |t| t[:card_key] }.uniq.length
  end

  def test_same_title_same_date_is_disambiguated_by_transcript_id
    # The data-loss bug this fixes: two transcripts of the same meeting on the
    # same day used to render the same card name, so the second silently
    # overwrote the first.
    ts = [tr(id: "ff-111", name: "Standup", date: "2026-01-02"),
          tr(id: "ff-222", name: "Standup", date: "2026-01-02")]
    assign_transcript_labels(ts)
    assert_equal 2, ts.map { |t| t[:card_key] }.uniq.length,
                 "duplicate title+date must not share a card"
    assert_equal %w[meeting_name+transcript_id meeting_name+transcript_id],
                 ts.map { |t| t[:label_reason] }
    assert_includes ts[0][:label], "ff-111"
    assert_includes ts[1][:label], "ff-222"
  end

  def test_duplicate_title_date_and_missing_ids_still_resolve
    ts = [tr(id: "", name: "Standup", date: "2026-01-02"),
          tr(id: "", name: "Standup", date: "2026-01-02")]
    assign_transcript_labels(ts)
    assert_equal 2, ts.map { |t| t[:card_key] }.uniq.length
  end

  def test_three_way_collision_resolves
    ts = [tr(id: "i1", name: "T", date: "2026-01-02"),
          tr(id: "i2", name: "T", date: "2026-01-02"),
          tr(id: "i3", name: "T", date: "2026-01-02")]
    assign_transcript_labels(ts)
    assert_equal 3, ts.map { |t| t[:card_key] }.uniq.length
  end

  def test_blank_title_falls_back_to_transcript_id
    ts = [tr(id: "fallback-id", name: "   ", date: "2026-01-02")]
    assign_transcript_labels(ts)
    assert_equal "fallback-id", ts[0][:label]
  end

  def test_missing_date_gets_an_explicit_placeholder
    ts = [tr(id: "x", name: "Standup", date: "")]
    assign_transcript_labels(ts)
    assert_equal "unknown-date", ts[0][:date_part]
    assert_equal 4, ts[0][:card_name].split("+").length
  end

  def test_joint_in_title_never_creates_extra_parts
    ts = [tr(id: "p1", name: "LLM+PLN", date: "2026-01-02")]
    assign_transcript_labels(ts)
    assert_equal 4, ts[0][:card_name].split("+").length
    assert_equal "Raw Data+transcripts+LLM-PLN+2026-01-02", ts[0][:card_name]
  end
end

# ------------------------------------------------------------
# 4. Hashing
# ------------------------------------------------------------
class TestHashing < Minitest::Test
  def header(service: "fireflies.ai", name: "Standup", date: "2026-01-02")
    format_transcript_header(
      "meeting_name" => name, "date" => date, "source_service" => service,
      "summary" => "s", "action_items" => ["a"], "participants" => ["p"]
    )
  end

  def test_rendered_header_carries_no_per_run_timestamp
    # The honesty guarantee for the delta: unlike a Mattermost channel card, a
    # transcript card's content is a pure function of the exported transcript.
    # If a run timestamp is ever added to this header, every card goes dirty on
    # every run and the hash would need explicit normalization - so fail loudly
    # here rather than silently producing a useless delta.
    h = header
    refute_match(/Exported:/, h)
    refute_match(/Ingested:/, h)
    refute_match(/Generated:/, h)
    # Rendering twice must be byte-identical.
    assert_equal h, header
  end

  def test_rendering_is_deterministic_across_calls
    data = { "meeting_name" => "Standup", "date" => "2026-01-02",
             "source_service" => "fireflies.ai", "summary" => "",
             "action_items" => [], "full_text" => "alice: hi\nbob: hey" }
    a = format_transcript_header(data) + "\n" + format_full_text(data["full_text"])
    b = format_transcript_header(data) + "\n" + format_full_text(data["full_text"])
    assert_equal content_hash(a), content_hash(b)
  end

  def test_normalization_is_identity
    s = "<p>anything at all</p>\n<hr>\n<pre>body</pre>"
    assert_equal s, normalize_for_hash(s)
  end

  def test_body_change_changes_the_hash
    a = "<p><strong>Date:</strong> 2026-01-02</p>\n<hr>\n<pre>hello</pre>"
    b = "<p><strong>Date:</strong> 2026-01-02</p>\n<hr>\n<pre>hello there</pre>"
    refute_equal content_hash(a), content_hash(b)
  end

  def test_header_is_escaped_so_titles_cannot_inject_markup
    h = format_transcript_header("meeting_name" => "<script>x</script>",
                                 "date" => "2026-01-02")
    refute_match(%r{<script>}, h)
    assert_match(/&lt;script&gt;/, h)
  end
end

# ------------------------------------------------------------
# 5. change_reason classification
# ------------------------------------------------------------
class TestChangeReason < Minitest::Test
  def card(date: "2026-01-02", body: "alice: hi")
    <<~HTML
      <p><strong>Source:</strong> fireflies.ai — Standup</p>
      <p><strong>Date:</strong> #{date}</p>
      <hr>
      <pre>#{body}</pre>
    HTML
  end

  def test_missing_card
    assert_equal "missing_card", change_reason(nil, card)
  end

  def test_text_grew
    before = card(body: "alice: hi")
    after  = card(body: "alice: hi\nbob: hey")
    assert_equal "text_grew", change_reason(before, after)
  end

  def test_text_shrank
    # A truncated or partial re-export: the signal that matters most, because
    # it means a full transcript would be replaced by less content.
    before = card(body: "alice: hi\nbob: hey")
    after  = card(body: "alice: hi")
    assert_equal "text_shrank", change_reason(before, after)
  end

  def test_text_edited_at_equal_length
    before = card(body: "alice: cat")
    after  = card(body: "alice: dog")
    assert_equal "text_edited", change_reason(before, after)
  end

  def test_meta_change_only
    # Header moved (e.g. a summary was regenerated) but the transcript body
    # did not.
    before = card(date: "2026-01-02")
    after  = card(date: "2026-01-03")
    assert_equal "transcript_meta_changed", change_reason(before, after)
  end

  def test_body_after_header_splits_on_the_first_hr
    assert_equal "\n<pre>x</pre>\n", body_after_header("<p>h</p>\n<hr>\n<pre>x</pre>\n")
  end
end

# ------------------------------------------------------------
# 6. Chunk shrink / orphan classification (report-only)
# ------------------------------------------------------------
class TestChunkAndOrphanClassification < Minitest::Test
  def setup
    STATS[:cards].clear
    %i[created updated errors planned_create planned_update
       skipped_unchanged].each { |k| STATS[k] = 0 }
  end

  # Leave the shared global as we found it, so no other test in this process
  # observes this class's fixtures.
  def teardown
    STATS[:cards].clear
  end

  def tr(id:, name:, date:, service: "fireflies.ai")
    { transcript_id: id, meeting_name: name, date: date, source_service: service }
  end

  def base(name = "Standup", date = "2026-01-02")
    "#{PARENT_CARD}+#{name}+#{date}"
  end

  def test_chunk_index_by_base_reads_both_name_forms
    idx = chunk_index_by_base(["#{base}+chunk-1", "RawData+transcripts+Standup+2026-01-02+chunk_2"])
    assert_equal 1, idx.keys.length, "display and key spellings must share a base"
    assert_equal [1, 2], idx.values.first.to_a.sort
  end

  def test_split_chunk_parts
    assert_equal [%w[Standup 2026-01-02], 3],
                 split_chunk_parts(%w[Standup 2026-01-02 chunk-3])
    assert_equal [%w[Standup 2026-01-02], nil],
                 split_chunk_parts(%w[Standup 2026-01-02])
  end

  def test_shrink_names_the_exact_stale_chunk_cards
    ts = [tr(id: "t1", name: "Standup", date: "2026-01-02")]
    assign_transcript_labels(ts)
    live = (1..5).map { |i| "#{base}+chunk-#{i}" } << base
    planned = (1..3).map { |i| "#{base}+chunk-#{i}" } << base
    STATS[:cards] = planned.map { |n| { name: n, action: "update" } }

    changes = chunk_changes(ts, live, planned)
    assert_equal 1, changes.length
    c = changes.first
    assert_equal "shrink", c[:direction]
    assert_equal 5, c[:live_chunks]
    assert_equal 3, c[:planned_chunks]
    assert_equal(-2, c[:delta])
    assert_equal ["#{base}+chunk-4", "#{base}+chunk-5"], c[:stale_chunk_cards]
    assert_empty c[:new_chunk_cards]
  end

  def test_growth_strands_nothing
    ts = [tr(id: "t1", name: "Standup", date: "2026-01-02")]
    assign_transcript_labels(ts)
    live = ["#{base}+chunk-1", base]
    planned = ["#{base}+chunk-1", "#{base}+chunk-2", base]
    STATS[:cards] = planned.map { |n| { name: n, action: "update" } }

    c = chunk_changes(ts, live, planned).first
    assert_equal "grow", c[:direction]
    assert_empty c[:stale_chunk_cards]
    assert_match(/strands nothing/, c[:note])
  end

  def test_gap_in_live_chunk_numbering_is_reported
    # A gap (chunk-1 trashed, 2..4 present) must not hide the shrink: counting
    # consecutive indexes from 1 would report zero live chunks.
    ts = [tr(id: "t1", name: "Standup", date: "2026-01-02")]
    assign_transcript_labels(ts)
    live = [2, 3, 4].map { |i| "#{base}+chunk-#{i}" } << base
    planned = [1, 2].map { |i| "#{base}+chunk-#{i}" } << base
    STATS[:cards] = planned.map { |n| { name: n, action: "update" } }

    c = chunk_changes(ts, live, planned).first
    assert_equal "resegmented", c[:direction]
    assert_equal ["#{base}+chunk-3", "#{base}+chunk-4"], c[:stale_chunk_cards]
    assert_equal ["#{base}+chunk-1"], c[:new_chunk_cards]
    assert_equal [1], c[:live_index_gaps]
  end

  def test_already_stranded_chunks_are_called_out_distinctly
    ts = [tr(id: "t1", name: "Standup", date: "2026-01-02")]
    assign_transcript_labels(ts)
    live = (1..4).map { |i| "#{base}+chunk-#{i}" } << base
    planned = (1..2).map { |i| "#{base}+chunk-#{i}" } << base
    STATS[:cards] = planned.map do |n|
      { name: n, action: n == base ? "skip-unchanged" : "update" }
    end

    c = chunk_changes(ts, live, planned).first
    assert c[:index_already_consistent]
    # Under the default keep policy the note explains preservation rather than
    # stranding; the "already stranded" wording belongs to the review policy.
    assert_match(/preserved as-is/, c[:note])
    assert_match(/already lists only the planned chunks/, c[:note])
  end

  # ------------------------------------------------------------
  # Keep-stale-chunks policy (in-process, default = keep)
  # ------------------------------------------------------------
  def test_keep_policy_is_the_default
    assert KEEP_STALE_CHUNKS,
           "keeping stale chunks must be the default: losing content is " \
           "worse than duplicating it"
    assert_equal "keep", STALE_CHUNK_POLICY
  end

  def test_shrink_is_not_blocking_under_keep_policy
    ts = [tr(id: "t1", name: "Standup", date: "2026-01-02")]
    assign_transcript_labels(ts)
    live = (1..5).map { |i| "#{base}+chunk-#{i}" } << base
    planned = (1..3).map { |i| "#{base}+chunk-#{i}" } << base
    STATS[:cards] = planned.map { |n| { name: n, action: "update" } }

    c = chunk_changes(ts, live, planned).first
    refute c[:blocking], "a shrink must not block a write under keep policy"
    assert_equal "keep", c[:stale_chunk_policy]
    assert c[:stale_chunks_preserved]
  end

  def test_keep_policy_still_names_every_stale_chunk_card
    # Non-blocking must never mean invisible: the whole point of keeping is
    # that a reviewer can still see what was left behind.
    ts = [tr(id: "t1", name: "Standup", date: "2026-01-02")]
    assign_transcript_labels(ts)
    live = (1..5).map { |i| "#{base}+chunk-#{i}" } << base
    planned = (1..3).map { |i| "#{base}+chunk-#{i}" } << base
    STATS[:cards] = planned.map { |n| { name: n, action: "update" } }

    c = chunk_changes(ts, live, planned).first
    assert_equal ["#{base}+chunk-4", "#{base}+chunk-5"], c[:stale_chunk_cards]
    assert_equal 5, c[:live_chunks]
    assert_equal(-2, c[:delta])
    assert_equal "shrink", c[:direction]
  end

  def test_keep_policy_note_promises_no_deletion
    ts = [tr(id: "t1", name: "Standup", date: "2026-01-02")]
    assign_transcript_labels(ts)
    live = (1..4).map { |i| "#{base}+chunk-#{i}" } << base
    planned = (1..2).map { |i| "#{base}+chunk-#{i}" } << base
    STATS[:cards] = planned.map { |n| { name: n, action: "update" } }

    note = chunk_changes(ts, live, planned).first[:note]
    assert_match(/not\s+deleted, re-filed or rewritten/, note)
    assert_match(/duplicat/i, note)
  end

  def test_no_destructive_card_operation_exists_in_the_script
    # The policy is only credible if there is no code that could remove a
    # card. Assert on the source: the only persistence calls are create!/
    # update!, and no delete/destroy/trash-assignment path exists.
    src = File.read(INGEST)
    code = src.lines.reject { |l| l.strip.start_with?("#") }.join

    %w[
      destroy
      delete_all
      Card.delete
      .delete!
      update_attributes
    ].each do |forbidden|
      refute_includes code, forbidden,
                      "#{forbidden} must not appear: stale chunks are never removed"
    end
    refute_match(/\.trash\s*=/, code, "nothing may move a card to the trash")
    refute_match(/\btrash!/, code, "nothing may trash a card")
    # Only reads of `trash` (skipping already-trashed cards) are allowed.
    assert_match(/card\.trash/, code)
  end

  def test_stale_chunk_orphans_are_classified_and_only_labelled
    ts = [tr(id: "t1", name: "Standup", date: "2026-01-02")]
    assign_transcript_labels(ts)
    planned = ["#{base}+chunk-1", base]
    orphans = [{ name: "#{base}+chunk-2", key: name_key("#{base}+chunk-2") }]

    classified = classify_orphans(orphans, planned, ts)
    assert_equal "stale_chunk", classified.first[:classification]
    assert_equal 2, classified.first[:chunk_index]
    assert_equal base, classified.first[:base_card]

    summary = orphan_summary(classified)
    # Default policy is keep: the stale chunk card is still named in the
    # report, but it is not something to decide before a write.
    assert_equal "keep", summary[:stale_chunk_policy]
    assert_equal 0, summary[:needs_attention],
                 "under the keep policy a stale chunk must not demand attention"
    assert_equal ["#{base}+chunk-2"], summary[:stale_chunks],
                 "the stale chunk card must stay visible in the report"
    assert summary[:stale_chunks_preserved]
    assert_equal 0, summary[:unexpected]
  end

  def test_rename_artifact_is_classified_as_superseded
    # Pre-fix naming filed "LLM+PLN" as extra name parts; the sanitized name
    # is where that content lives now.
    ts = [tr(id: "t1", name: "LLM+PLN", date: "2026-01-02")]
    assign_transcript_labels(ts)
    planned = [ts[0][:card_name]]
    old_name = "#{PARENT_CARD}+LLM+PLN+2026-01-02"
    orphans = [{ name: old_name, key: name_key(old_name) }]

    classified = classify_orphans(orphans, planned, ts)
    assert_equal "superseded_by_rename", classified.first[:classification]
    assert_equal ts[0][:card_name], classified.first[:superseded_by]
  end

  def test_relabeled_transcript_is_classified
    ts = [tr(id: "ff-111", name: "Standup", date: "2026-01-02"),
          tr(id: "ff-222", name: "Standup", date: "2026-01-02")]
    assign_transcript_labels(ts)
    planned = ts.map { |t| t[:card_name] }
    bare = "#{PARENT_CARD}+Standup+2026-01-02"
    orphans = [{ name: bare, key: name_key(bare) }]

    classified = classify_orphans(orphans, planned, ts)
    assert_equal "relabeled_transcript", classified.first[:classification]
    assert_match(/ff-111|ff-222/, classified.first[:detail])
  end

  def test_unknown_card_is_vanished_transcript
    ts = [tr(id: "t1", name: "Standup", date: "2026-01-02")]
    assign_transcript_labels(ts)
    gone = "#{PARENT_CARD}+Deleted Meeting+2025-12-01"
    classified = classify_orphans([{ name: gone, key: name_key(gone) }],
                                  ts.map { |t| t[:card_name] }, ts)
    assert_equal "vanished_transcript", classified.first[:classification]
  end

  def test_planned_and_orphaned_is_surfaced_not_swallowed
    ts = [tr(id: "t1", name: "Standup", date: "2026-01-02")]
    assign_transcript_labels(ts)
    planned = ["#{base}+chunk-1", base]
    orphans = [{ name: "#{base}+chunk-1", key: name_key("#{base}+chunk-1") }]
    classified = classify_orphans(orphans, planned, ts)
    assert_equal "unexpected_planned_chunk", classified.first[:classification]
    assert_equal 1, orphan_summary(classified)[:unexpected]
  end

  def test_name_binding_manifest_reports_both_ends_of_a_rename
    ts = [tr(id: "t1", name: "LLM+PLN", date: "2026-01-02")]
    assign_transcript_labels(ts)
    old_name = "#{PARENT_CARD}+LLM+PLN+2026-01-02"
    orphans = classify_orphans([{ name: old_name, key: name_key(old_name) }],
                               ts.map { |t| t[:card_name] }, ts)
    manifest = name_binding_manifest(ts, [old_name], orphans)

    assert_equal 1, manifest.length
    m = manifest.first
    assert_equal "new_card", m[:binding]
    assert_equal [old_name], m[:supersedes_live_cards]
    assert m[:notable]
  end

  def test_bound_transcript_is_not_notable
    ts = [tr(id: "t1", name: "Standup", date: "2026-01-02")]
    assign_transcript_labels(ts)
    manifest = name_binding_manifest(ts, [ts[0][:card_name]], [])
    assert_equal "bound", manifest.first[:binding]
    refute manifest.first[:notable]
  end
end

# ------------------------------------------------------------
# 7. End-to-end dry-run planning over fixtures
# ------------------------------------------------------------
# Driven as a subprocess with TRANSCRIPT_INGEST_DRY_RUN=1 so the real planning
# path runs with no database and no write branch: card_exists? returns false
# without Decko, so every card is classified "would create". This is what
# proves naming, chunking and the index/chunk relationship without touching a
# deck.
class TestDryRunPlanning < Minitest::Test
  def plan(payloads)
    Dir.mktmpdir do |dir|
      payloads.each_with_index do |p, i|
        File.write("#{dir}/#{i}_#{p['transcript_id']}.json", JSON.dump(p))
      end
      report = File.join(dir, "plan.json")
      out, err, status = Open3.capture3(
        { "TRANSCRIPT_INGEST" => "1",
          "TRANSCRIPT_INGEST_DRY_RUN" => "1",
          "TRANSCRIPT_EXPORT_DIR" => dir,
          "TRANSCRIPT_INGEST_REPORT" => report },
        RbConfig.ruby, INGEST
      )
      assert status.success?, "dry run failed: #{err}\n#{out}"
      # Nothing may claim to have written.
      refute_match(/^  Created:|^  Updated:/, out,
                   "dry run must not report real writes")
      yield JSON.parse(File.read(report)), out
    end
  end

  def payload(name:, date:, id: "t1", text: "alice: hi\nbob: hey")
    { "meeting_name" => name, "date" => date, "transcript_id" => id,
      "source_service" => "fireflies.ai", "summary" => "s",
      "action_items" => [], "participants" => ["alice"],
      "keywords" => [], "full_text" => text }
  end

  def test_dry_run_reports_mode_and_writes_nothing
    plan([payload(name: "Standup", date: "2026-01-02")]) do |report, out|
      assert_equal "full-dry-run", report["mode"]
      assert_equal true, report["dry_run"]
      assert_equal 0, report["stats"]["created"]
      assert_equal 0, report["stats"]["updated"]
      assert_equal 0, report["stats"]["errors"]
      assert_match(/DRY RUN - no database writes/, out)
      assert_match(/Dry run complete - nothing was written/, out)
    end
  end

  def test_small_transcript_is_one_card
    plan([payload(name: "Standup", date: "2026-01-02")]) do |report, _out|
      assert_equal 1, report["card_count"]
      assert_equal ["Raw Data+transcripts+Standup+2026-01-02"],
                   report["cards"].map { |c| c["name"] }
      assert_equal 1, report["stats"]["planned_create"]
    end
  end

  def test_large_transcript_chunks_into_index_plus_chunks
    big = (1..40).map { |i| "speaker#{i}: " + ("x" * 2_000) }.join("\n")
    plan([payload(name: "Long", date: "2026-01-02", text: big)]) do |report, _out|
      names = report["cards"].map { |c| c["name"] }
      base = "Raw Data+transcripts+Long+2026-01-02"
      assert_operator names.length, :>, 1, "expected the transcript to chunk"
      assert_equal base, names.first, "index card is planned first"

      chunks = names.drop(1)
      assert_equal chunks, chunks.uniq, "chunk card names must be unique"
      chunks.each_with_index { |n, i| assert_equal "#{base}+chunk-#{i + 1}", n }
      # Every planned card is exactly one name part below its index card.
      chunks.each { |n| assert_equal 5, n.split("+").length }
      assert(report["cards"].all? { |c| c["action"] == "create" })
    end
  end

  def test_duplicate_title_and_date_do_not_share_a_card
    # The data-loss case end to end: two transcripts of the same meeting on the
    # same day must plan two distinct cards, not one overwriting the other.
    plan([payload(name: "Standup", date: "2026-01-02", id: "ff-111"),
          payload(name: "Standup", date: "2026-01-02", id: "ff-222")]) do |report, out|
      names = report["cards"].map { |c| c["name"] }
      assert_equal 2, names.length
      assert_equal names, names.uniq, "duplicate title+date overwrote a card"
      assert_match(/Disambiguated 2 transcript card name/, out)
      reasons = report["transcripts"].map { |t| t["label_reason"] }
      assert_equal %w[meeting_name+transcript_id meeting_name+transcript_id], reasons
    end
  end

  def test_title_with_the_name_joint_stays_one_part
    plan([payload(name: "LLM+PLN", date: "2026-01-02")]) do |report, out|
      name = report["cards"].first["name"]
      assert_equal "Raw Data+transcripts+LLM-PLN+2026-01-02", name
      assert_equal 4, name.split("+").length
      assert_match(/Sanitized 1 meeting title/, out)
    end
  end

  def test_export_summary_is_not_ingested
    Dir.mktmpdir do |dir|
      File.write("#{dir}/a.json",
                 JSON.dump(payload(name: "Standup", date: "2026-01-02")))
      File.write("#{dir}/export_summary.json",
                 JSON.dump("exported_at" => "2026-01-02T00:00:00Z",
                           "total_transcripts" => 1))
      report = File.join(dir, "plan.json")
      _out, err, status = Open3.capture3(
        { "TRANSCRIPT_INGEST" => "1", "TRANSCRIPT_INGEST_DRY_RUN" => "1",
          "TRANSCRIPT_EXPORT_DIR" => dir,
          "TRANSCRIPT_INGEST_REPORT" => report },
        RbConfig.ruby, INGEST
      )
      assert status.success?, err
      data = JSON.parse(File.read(report))
      assert_equal 1, data["transcript_count"]
      assert_equal 1, data["card_count"]
    end
  end

  def test_delta_dry_run_reports_no_write_path
    # With no Decko, live_content is nil, so every card is a planned create and
    # the report must still state plainly that no write path exists.
    Dir.mktmpdir do |dir|
      File.write("#{dir}/a.json",
                 JSON.dump(payload(name: "Standup", date: "2026-01-02")))
      report = File.join(dir, "delta.json")
      out, err, status = Open3.capture3(
        { "TRANSCRIPT_INGEST" => "1", "TRANSCRIPT_INGEST_DRY_RUN" => "1",
          "TRANSCRIPT_INGEST_DELTA" => "1", "TRANSCRIPT_EXPORT_DIR" => dir,
          "TRANSCRIPT_INGEST_REPORT" => report },
        RbConfig.ruby, INGEST
      )
      assert status.success?, err
      data = JSON.parse(File.read(report))
      assert_equal "delta", data["mode"]
      # No Decko here, so there is no live baseline to hash against. The report
      # must say so rather than labelling the run "live-content-hash", which
      # would make an uncompared run look like a clean reconciliation.
      assert_equal "none-no-card-api", data["baseline"]
      assert_equal false, data["baseline_available"]
      assert_equal false, data["write_readiness"]["baseline_compared"]
      assert_equal 1, data["write_readiness"]["blocking"]["no_live_baseline"]
      assert_equal false, data["write_readiness"]["write_path_implemented"]
      assert_match(/never deleted or re-filed/, data["write_readiness"]["note"])
      assert_match(/NOTHING was compared/, data["write_readiness"]["note"])
      assert_match(/NO LIVE BASELINE/, out)
      assert_equal "missing_card", data["cards"].first["reason"]
      refute_nil data["cards"].first["hash_after"]
      assert_match(/DELTA PLAN - report only/, out)
      refute_match(/^  Created:|^  Updated:/, out)
    end
  end

  def test_non_transcript_files_are_declared
    assert_includes NON_TRANSCRIPT_FILES, "export_summary.json"
    assert_includes NON_TRANSCRIPT_FILES, "verification_report.json"
  end
end

# ------------------------------------------------------------
# 8. The stale-chunk policy, end to end through the report
# ------------------------------------------------------------
# These drive the script as a subprocess so the real env parsing and the real
# report serialization are exercised, including the review (=0) branch, which
# the in-process tests cannot reach because the constant is frozen at load.
class TestStaleChunkPolicyReport < Minitest::Test
  def payload(name:, date:, id: "t1", text: "alice: hi\nbob: hey")
    { "transcript_id" => id, "meeting_name" => name, "date" => date,
      "source_service" => "fireflies.ai", "duration_minutes" => 30,
      "participants" => ["alice"], "transcript_text" => text }
  end

  def delta(extra_env = {})
    Dir.mktmpdir do |dir|
      File.write("#{dir}/a.json",
                 JSON.dump(payload(name: "Standup", date: "2026-01-02")))
      report = File.join(dir, "delta.json")
      out, err, status = Open3.capture3(
        { "TRANSCRIPT_INGEST" => "1", "TRANSCRIPT_INGEST_DRY_RUN" => "1",
          "TRANSCRIPT_INGEST_DELTA" => "1", "TRANSCRIPT_EXPORT_DIR" => dir,
          "TRANSCRIPT_INGEST_REPORT" => report }.merge(extra_env),
        RbConfig.ruby, INGEST
      )
      assert status.success?, "delta run failed: #{err}\n#{out}"
      refute_match(/^  Created:|^  Updated:/, out,
                   "a delta dry run must never report real writes")
      yield JSON.parse(File.read(report)), out
    end
  end

  def test_report_declares_the_keep_policy_by_default
    delta do |data, out|
      pol = data["stale_chunk_policy"]
      assert_equal "keep", pol["policy"]
      assert_equal "TRANSCRIPT_KEEP_STALE_CHUNKS", pol["env_var"]
      assert_equal true, pol["keep_stale_chunks"]
      assert_equal true, pol["preserved"]
      assert_equal false, pol["destructive_path_exists"]
      assert_equal false, pol["blocks_write"]
      assert_match(/duplicat/i, pol["rationale"])
      assert_match(/stale-chunk policy: keep/, out)
    end
  end

  def test_keep_policy_zeroes_the_stale_chunk_blockers
    delta do |data, _out|
      wr = data["write_readiness"]
      assert_equal "keep", wr["stale_chunk_policy"]
      assert_equal 0, wr["blocking"]["shrinking_chunk_transcripts"]
      assert_equal 0, wr["blocking"]["stale_chunk_cards"]
      # Still acknowledged, never silently dropped.
      refute_nil wr["acknowledged"]
      assert_match(/PRESERVED and do not block a write/, wr["note"])
      assert_match(/never deleted or re-filed/, wr["note"])
    end
  end

  def test_review_policy_restores_stale_chunks_as_blockers
    delta("TRANSCRIPT_KEEP_STALE_CHUNKS" => "0") do |data, _out|
      assert_equal "review", data["stale_chunk_policy"]["policy"]
      assert_equal false, data["stale_chunk_policy"]["keep_stale_chunks"]
      assert_equal "review", data["write_readiness"]["stale_chunk_policy"]
      assert_match(/POLICY=review/, data["write_readiness"]["note"])
      # Even under review nothing is removed.
      assert_equal false, data["stale_chunk_policy"]["destructive_path_exists"]
      assert_equal true, data["stale_chunk_policy"]["preserved"]
    end
  end

  def test_policy_accepts_the_usual_falsey_spellings
    %w[0 false no off review].each do |v|
      delta("TRANSCRIPT_KEEP_STALE_CHUNKS" => v) do |data, _out|
        assert_equal "review", data["stale_chunk_policy"]["policy"],
                     "#{v.inspect} must select the review policy"
      end
    end
  end

  def test_policy_defaults_to_keep_on_blank_or_unknown_values
    ["", "   ", "1", "yes", "keep"].each do |v|
      delta("TRANSCRIPT_KEEP_STALE_CHUNKS" => v) do |data, _out|
        assert_equal "keep", data["stale_chunk_policy"]["policy"],
                     "#{v.inspect} must keep stale chunks"
      end
    end
  end
end

# ------------------------------------------------------------
# Vanished-transcript generation sub-classification (report only)
# ------------------------------------------------------------
# "vanished_transcript" is one label over several very different situations.
# These tests pin the sub-classification that tells them apart, because the
# difference drives the pre-write decision: an exporter date shift duplicates
# content, whereas an unmatched card is the only copy there is.
class VanishedGenerationTest < Minitest::Test
  PARENT = "Raw Data+transcripts"

  def card(series, date = nil, chunk: nil)
    n = date ? "#{PARENT}+#{series}+#{date}" : "#{PARENT}+#{series}"
    chunk ? "#{n}+chunk-#{chunk}" : n
  end

  def vanished(name, planned)
    by_series, by_date = series_date_index(planned)
    vanished_generation(name, by_series, by_date)
  end

  def test_a_card_with_no_date_part_is_the_undated_legacy_generation
    got = vanished(card("Standup"), [card("Standup", "2026-01-02")])
    assert_equal "undated_legacy", got[:generation]
    assert_nil got[:date]
    assert_match(/pre-date naming generation/, got[:detail])
  end

  def test_a_multi_part_undated_name_is_still_undated_legacy
    # A foreign corpus that never used dated names: the trailing part is not
    # a date, so the whole thing is the series.
    got = vanished("#{PARENT}+AGI 26+vid123+full", [card("Standup", "2026-01-02")])
    assert_equal "undated_legacy", got[:generation]
    assert_equal "AGI 26+vid123+full", got[:series]
  end

  def test_a_one_day_shift_in_an_active_series_is_date_shifted
    # The exact observed case: the orphan sits one day after the planned date.
    got = vanished(card("Weekly", "2026-03-13"), [card("Weekly", "2026-03-12")])
    assert_equal "date_shifted", got[:generation]
    assert_equal "2026-03-12", got[:nearest_planned_date]
    assert_equal 1, got[:date_offset_days]
    assert_match(/not lost content/, got[:detail])
  end

  def test_the_shift_window_is_bounded_and_falls_back_to_series_active
    planned = [card("Weekly", "2026-03-01")]
    assert_equal "date_shifted",
                 vanished(card("Weekly", "2026-03-04"), planned)[:generation],
                 "3 days is inside the tolerance"
    outside = vanished(card("Weekly", "2026-03-05"), planned)
    assert_equal "series_active", outside[:generation],
                 "4 days is outside the tolerance"
    # Even outside the window the evidence is reported, not dropped.
    assert_equal "2026-03-01", outside[:nearest_planned_date]
    assert_equal 4, outside[:date_offset_days]
  end

  def test_the_shift_is_direction_agnostic
    %w[2026-03-11 2026-03-13].each do |d|
      assert_equal "date_shifted",
                   vanished(card("Weekly", d), [card("Weekly", "2026-03-12")])[:generation]
    end
  end

  def test_an_unplanned_series_sharing_a_date_is_series_renamed
    # Old title retired, a different series is planned on exactly that date.
    got = vanished(card("Old Weekly Sync", "2026-03-26"),
                   [card("Meeting @ Elowyn AI", "2026-03-26")])
    assert_equal "series_renamed", got[:generation]
    assert_match(/re-titled/, got[:detail])
    refute_empty got[:planned_series_on_date]
  end

  def test_a_card_with_no_series_and_no_date_in_the_plan_is_unmatched
    got = vanished(card("Gone Forever", "2026-03-03"),
                   [card("Weekly", "2026-04-01")])
    assert_equal "unmatched", got[:generation]
    assert_match(/no planned card for this series/, got[:detail])
  end

  def test_a_chunk_cards_generation_follows_its_base_card
    # The chunk suffix must not be mistaken for the series or the date.
    got = vanished(card("Weekly", "2026-03-13", chunk: 2), [card("Weekly", "2026-03-12")])
    assert_equal "date_shifted", got[:generation]
    assert_equal "Weekly", got[:series]
    assert_equal "2026-03-13", got[:date]
  end

  def test_a_malformed_date_cannot_raise
    # Nothing in a report path may blow up on bad data.
    got = vanished(card("Weekly", "2026-13-99"), [card("Weekly", "2026-03-12")])
    refute_nil got[:generation]
  end

  def test_annotation_labels_only_vanished_entries_and_mutates_nothing_else
    planned = [card("Weekly", "2026-03-12")]
    classified = [
      { name: card("Weekly", "2026-03-13"), classification: "vanished_transcript" },
      { name: card("Weekly", "2026-03-12", chunk: 2), classification: "stale_chunk" }
    ]
    annotate_vanished_generations(classified, planned)

    assert_equal "date_shifted", classified[0][:generation]
    assert_nil classified[1][:generation],
               "a stale_chunk must not be given a vanished generation"
    assert_equal "stale_chunk", classified[1][:classification],
                 "annotation must not change any existing classification"
  end

  def test_the_summary_counts_generations_and_names_what_matters
    planned = [card("Weekly", "2026-03-12")]
    classified = [
      { name: card("Weekly", "2026-03-13"), classification: "vanished_transcript" },
      { name: card("Legacy"), classification: "vanished_transcript" },
      { name: card("Gone", "2026-01-01"), classification: "vanished_transcript" }
    ]
    annotate_vanished_generations(classified, planned)
    summary = vanished_generation_summary(classified)

    assert_equal 3, summary[:total]
    assert_equal 1, summary[:by_generation]["date_shifted"]
    assert_equal 1, summary[:by_generation]["undated_legacy"]
    assert_equal 1, summary[:by_generation]["unmatched"]
    # The two classes a reviewer must see by name.
    assert_equal [card("Gone", "2026-01-01")], summary[:unmatched_cards]
    assert_equal [card("Weekly", "2026-03-13")], summary[:date_shifted_cards]
    assert_match(/Report-only/, summary[:note])
  end

  def test_the_summary_is_absent_when_nothing_vanished
    assert_nil vanished_generation_summary(
      [{ name: card("Weekly", "2026-03-12", chunk: 2), classification: "stale_chunk" }]
    )
  end

  def test_generation_labels_never_change_the_orphan_classification_counts
    planned = [card("Weekly", "2026-03-12")]
    classified = [
      { name: card("Weekly", "2026-03-13"), classification: "vanished_transcript" },
      { name: card("Legacy"), classification: "vanished_transcript" }
    ]
    before = orphan_summary(classified)[:by_classification].dup
    annotate_vanished_generations(classified, planned)
    assert_equal before, orphan_summary(classified)[:by_classification],
                 "sub-classification is additive: it must not reclassify anything"
  end
end


# ------------------------------------------------------------
# Foreign-corpus exclusion (report only)
# ------------------------------------------------------------
# The AGI 26 corpus is conference-video captions ingested by a different
# pipeline, so no transcript export can ever match it: ~120 cards permanently
# "vanished" through no fault of the deck, burying the one genuine gap under 3x
# their own noise. These tests pin an exclusion that is enumerated (never
# structural), anchored to the first name part, and that still counts and names
# every card it excludes.
class ForeignCorpusTest < Minitest::Test
  PARENT = "Raw Data+transcripts"
  # The one irreplaceable card in the real corpus: only the live deck has it.
  ONLY_COPY = "#{PARENT}+Elowyn AI Meeting - Frag, EARTHwise, Magi+2026-03-03"

  def card(series, date = nil, chunk: nil)
    n = date ? "#{PARENT}+#{series}+#{date}" : "#{PARENT}+#{series}"
    chunk ? "#{n}+chunk-#{chunk}" : n
  end

  def agi(*parts)
    (["#{PARENT}+AGI 26"] + parts).join("+")
  end

  def test_the_real_agi26_name_shapes_are_all_matched
    # The three shapes actually observed, plus the bare corpus parent.
    [agi("wPwresMk5dg", "full"), agi("qRA1DoMCCSc", "090-120"),
     agi("Ingestion Notes"), "#{PARENT}+AGI 26"].each do |name|
      assert_equal "AGI 26", foreign_corpus(name), name
    end
  end

  def test_the_stored_rawdata_spelling_matches_identically
    # The deck stores "RawData+transcripts"; the constant reads "Raw Data".
    # The rule must go through relative_parts/name_key, not a string prefix.
    assert_equal "AGI 26",
                 foreign_corpus("RawData+transcripts+AGI 26+wPwresMk5dg+full")
  end

  def test_key_normalization_accepts_the_spelling_variants
    ["AGI-26", "agi 26", "AGI  26"].each do |variant|
      assert_equal "AGI 26", foreign_corpus("#{PARENT}+#{variant}+vid+full"), variant
    end
  end

  def test_a_real_meeting_series_whose_title_contains_agi_is_not_matched
    # "AGI Strategy Biweekly" IS an exported series. A loose /AGI/ rule would
    # start eating real meetings; this is the regression that must not happen.
    assert_nil foreign_corpus(card("AGI Strategy Biweekly", "2026-09-02"))
    assert_nil foreign_corpus(card("Magi Weekly", "2025-12-29"))
  end

  def test_the_one_genuinely_missing_meeting_is_never_matched
    assert_nil foreign_corpus(ONLY_COPY)
    assert_nil foreign_corpus("#{ONLY_COPY}+chunk-1")
  end

  def test_undated_legacy_meeting_stubs_are_not_matched
    # The explicit difference from the rejected "no date part" rule: these are
    # real meeting series and must stay in the signal.
    ["MeTTa Study Group", "Meeting @ Elowyn AI", "Lake <> Alison check-in"].each do |s|
      assert_nil foreign_corpus(card(s)), s
    end
  end

  def test_a_name_with_no_relative_parts_returns_nil
    assert_nil foreign_corpus(PARENT)
    assert_nil foreign_corpus("RawData+transcripts")
  end

  def test_a_corpus_match_is_anchored_to_the_first_relative_part
    assert_nil foreign_corpus("#{PARENT}+Weekly+AGI 26")
    assert_nil foreign_corpus("#{PARENT}+Weekly+2026-03-12+AGI 26")
  end

  def test_annotation_labels_only_matching_entries_and_mutates_nothing_else
    classified = [
      { name: agi("vid", "full"), classification: "vanished_transcript",
        generation: "undated_legacy" },
      { name: ONLY_COPY, classification: "vanished_transcript", generation: "unmatched" },
      { name: card("Weekly", "2026-03-12", chunk: 2), classification: "stale_chunk" }
    ]
    annotate_foreign_corpora(classified)

    assert_equal "AGI 26", classified[0][:foreign_corpus]
    assert_nil classified[1][:foreign_corpus], "the only copy must stay in the signal"
    assert_nil classified[2][:foreign_corpus]
    assert_equal %w[vanished_transcript vanished_transcript stale_chunk],
                 classified.map { |e| e[:classification] },
                 "annotation must not change any classification"
    assert_equal ["undated_legacy", "unmatched", nil],
                 classified.map { |e| e[:generation] },
                 "annotation must not change any generation"
  end

  def test_foreign_corpus_exclusion_never_changes_the_orphan_summary_counts
    classified = [
      { name: agi("vid", "full"), classification: "vanished_transcript" },
      { name: ONLY_COPY, classification: "vanished_transcript" },
      { name: card("Weekly", "2026-03-12", chunk: 2), classification: "stale_chunk" }
    ]
    keys = [:total, :by_classification, :needs_attention, :unexpected]
    before = orphan_summary(classified).slice(*keys)
    annotate_foreign_corpora(classified)
    after = orphan_summary(classified).slice(*keys)

    assert_equal before, after,
                 "foreign-corpus labelling is additive: raw counts must not move"
  end

  def test_the_summary_counts_and_names_every_excluded_card
    classified = [
      { name: agi("bbb", "full"), classification: "vanished_transcript" },
      { name: agi("aaa", "000-030"), classification: "vanished_transcript" },
      { name: ONLY_COPY, classification: "vanished_transcript" }
    ]
    annotate_foreign_corpora(classified)
    summary = foreign_corpus_summary(classified)

    assert_equal 2, summary[:total]
    assert_equal({ "AGI 26" => 2 }, summary[:by_corpus])
    assert_equal({ "vanished_transcript" => 2 }, summary[:by_classification])
    assert_equal ["AGI 26"], summary[:exclusions]
    assert_equal "TRANSCRIPT_FOREIGN_CORPORA", summary[:env_var]
    # The "excluded is not invisible" guarantee: every name, verbatim.
    assert_equal [agi("aaa", "000-030"), agi("bbb", "full")], summary[:cards]
    assert_match(/Report-only/, summary[:note])
    assert_match(/EXCLUDED FROM THE READABLE ORPHAN SIGNAL ONLY/, summary[:note])
    assert_match(/counted and named here/, summary[:note])
    assert_match(/no classification is changed/, summary[:note])
  end

  def test_the_summary_is_absent_when_nothing_is_foreign
    classified = [{ name: ONLY_COPY, classification: "vanished_transcript" }]
    annotate_foreign_corpora(classified)
    assert_nil foreign_corpus_summary(classified)
  end

  def test_the_readable_signal_subtracts_only_the_foreign_cards
    classified = [
      { name: agi("v1", "full"), classification: "vanished_transcript" },
      { name: agi("v2", "full"), classification: "vanished_transcript" },
      { name: ONLY_COPY, classification: "vanished_transcript" },
      { name: card("Weekly", "2026-03-13"), classification: "vanished_transcript" },
      { name: card("Weekly", "2026-03-12", chunk: 2), classification: "stale_chunk" }
    ]
    annotate_foreign_corpora(classified)
    s = orphan_summary(classified)

    assert_equal 4, s[:by_classification]["vanished_transcript"], "raw count unchanged"
    assert_equal 2, s[:by_classification_excluding_foreign]["vanished_transcript"]
    assert_equal 1, s[:by_classification_excluding_foreign]["stale_chunk"]
    assert_equal 2, s[:foreign_corpus]
  end

  def test_the_vanished_generation_summary_reports_both_totals
    # AGI 26 cards genuinely have no date part, so they must still count as
    # undated_legacy: re-labelling them would be a lie about the data.
    planned = [card("Weekly", "2026-03-12")]
    classified = [
      { name: agi("v1", "full"), classification: "vanished_transcript" },
      { name: agi("v2", "full"), classification: "vanished_transcript" },
      { name: card("MeTTa Study Group"), classification: "vanished_transcript" },
      { name: ONLY_COPY, classification: "vanished_transcript" }
    ]
    annotate_vanished_generations(classified, planned)
    annotate_foreign_corpora(classified)
    summary = vanished_generation_summary(classified)

    assert_equal 4, summary[:total]
    assert_equal 3, summary[:by_generation]["undated_legacy"], "raw count unchanged"
    assert_equal 2, summary[:excluding_foreign_corpus][:total]
    assert_equal 1, summary[:excluding_foreign_corpus][:by_generation]["undated_legacy"]
    # The one real gap stays named whatever the exclusion does.
    assert_equal [ONLY_COPY], summary[:unmatched_cards]
  end

  def test_the_exclusion_list_is_configurable_and_can_be_emptied
    probe = <<~RUBY
      puts FOREIGN_CORPORA.inspect
      puts foreign_corpus("Raw Data+transcripts+AGI 26+vid+full").inspect
      puts foreign_corpus("Raw Data+transcripts+Foo Corpus+x").inspect
      puts foreign_corpus(
        "Raw Data+transcripts+Elowyn AI Meeting - Frag, EARTHwise, Magi+x"
      ).inspect
    RUBY

    run = lambda do |value|
      Dir.mktmpdir do |dir|
        script = File.join(dir, "probe.rb")
        File.write(script, "load #{INGEST.inspect}\n#{probe}")
        out, err, status = Open3.capture3({ "TRANSCRIPT_FOREIGN_CORPORA" => value },
                                          RbConfig.ruby, script)
        assert status.success?, "probe failed: #{err}"
        out.lines.map(&:chomp)
      end
    end

    # Disabled: today's behaviour restored exactly.
    off = run.call("")
    assert_equal "[]", off[0]
    assert_equal "nil", off[1], "an empty list must exclude nothing"

    # Semicolon is the separator, so a comma inside a real meeting title is safe.
    on = run.call("AGI 26;Foo Corpus")
    assert_equal '["AGI 26", "Foo Corpus"]', on[0]
    assert_equal '"AGI 26"', on[1]
    assert_equal '"Foo Corpus"', on[2]
    assert_equal "nil", on[3], "a comma must not split an entry"
  end

  def test_the_delta_report_acknowledges_foreign_corpora_without_blocking
    Dir.mktmpdir do |dir|
      File.write("#{dir}/a.json", JSON.dump(
                                    "transcript_id" => "t1", "meeting_name" => "Standup",
                                    "date" => "2026-01-02", "duration_minutes" => 10,
                                    "participants" => ["alice"], "transcript_text" => "hello"
                                  ))
      report = File.join(dir, "delta.json")
      out, err, status = Open3.capture3(
        { "TRANSCRIPT_INGEST" => "1", "TRANSCRIPT_INGEST_DRY_RUN" => "1",
          "TRANSCRIPT_INGEST_DELTA" => "1", "TRANSCRIPT_EXPORT_DIR" => dir,
          "TRANSCRIPT_INGEST_REPORT" => report },
        RbConfig.ruby, INGEST
      )
      assert status.success?, "delta run failed: #{err}\n#{out}"
      data = JSON.parse(File.read(report))
      wr = data["write_readiness"]
      # Acknowledged, never blocking: a foreign corpus is a permanent
      # condition, not a decision someone has to make before a write.
      assert_equal 0, wr["acknowledged"]["foreign_corpus_cards"]
      refute wr["blocking"].key?("foreign_corpus_cards"),
             "a foreign corpus must never block a write"
    end
  end

  def test_no_destructive_card_operation_is_introduced
    src = File.read(INGEST)
    code = src.lines.reject { |l| l.strip.start_with?("#") }.join
    %w[delete destroy trash= prune].each do |op|
      refute_match(/\.#{Regexp.escape(op)}\b/, code,
                   "the exclusion must not introduce a #{op} path")
    end
  end
end


# ------------------------------------------------------------
# Structural ancestor stubs (report only)
# ------------------------------------------------------------
# A Decko compound card is filed under BOTH of its name parts, so writing
# "<parent>+MeTTa Coders+2026-02-11" brings the EMPTY left card
# "<parent>+MeTTa Coders" into existence. The orphan scan sees that ancestor,
# and before this class existed it called it a "vanished_transcript" of the
# "undated_legacy" generation - i.e. a lost meeting. 19 such cards appeared
# the moment a verified, idempotent delta apply ran, and the orphan count went
# 169 -> 188 with nothing lost at all.
#
# These tests pin the narrow rule that fixes the label without ever hiding a
# card: relabel ONLY a card that is (a) a strict left-hand ancestor of a
# PLANNED card and (b) read from the deck and found empty.
class StructuralAncestorStubTest < Minitest::Test
  PARENT = "Raw Data+transcripts"

  # The 19 real series-level ancestors Decko created during the apply.
  REAL_19 = [
    "AGI Strategy Biweekly", "Knowledge Base", "Lake - Ben", "Lake - Sandra",
    "Lake - Ursula", "Lake Watkins and Matthew Ikle", "MeTTa Coders",
    "MeTTa Study Group (6k-DmzTX5eYfzVovyYpLHSg8qo)",
    "MeTTa Study Group (A1gLNauJWSMbbsPGbGF-HvuR6Wg)",
    "MeTTa Study Group (FSSEpW_29sP3tOAGC9C8giofpSI)",
    "MeTTa Study Group (GGjH0K0JvLjAxuR18HnaCDOsjmk)",
    "MeTTa Study Group (H6KBfmwYHgd2ekxwBw0MOTpcs6Q)",
    "MeTTa Study Group (Xs9-x2EZFqvf3BHimZxIgyiPw1I)",
    "MeTTa Study Group (aLKZ6FwozyqO-PbjHBaV0WoFUeI)",
    "MeTTa Study Group (jjoNJsqEl4fd9ijspn6SDbuA2PE)",
    "MeTTa Study Group (zsIkeCG-NHxQPUxHK0a_CC34AOw)",
    "Lake, Anneloes - Elowyn game & AI", "Note",
    "SF AGI Society Kickoff Planning"
  ].freeze

  def card(series, date = nil, chunk: nil)
    n = date ? "#{PARENT}+#{series}+#{date}" : "#{PARENT}+#{series}"
    chunk ? "#{n}+chunk-#{chunk}" : n
  end

  def orphan(name)
    { name: name, key: name_key(name) }
  end

  # A deck that answers "" (empty) for the named cards and nil for anything
  # else. nil is "I could not read it", which must never be relabelled.
  def deck(empty_names, content: {})
    empty_keys = empty_names.map { |n| name_key(n) }
    lambda do |name|
      k = name_key(name)
      next content[k] if content.key?(k)

      empty_keys.include?(k) ? "" : nil
    end
  end

  def classify(orphans, planned, reader)
    classify_orphans(orphans, planned, [], content_reader: reader)
  end

  # ---- the actual regression -------------------------------------------

  def test_the_19_empty_series_ancestors_are_structural_stubs_not_vanished
    planned = REAL_19.map { |s| card(s, "2026-02-11") }
    ancestors = REAL_19.map { |s| card(s) }
    classified = classify(ancestors.map { |n| orphan(n) }, planned,
                          deck(ancestors))

    assert_equal 19, classified.length
    assert_equal ["structural_ancestor_stub"],
                 classified.map { |e| e[:classification] }.uniq
    refute_includes classified.map { |e| e[:classification] },
                    "vanished_transcript",
                    "an empty ancestor of a planned card is not a lost meeting"
  end

  def test_the_stub_detail_names_the_planned_card_it_exists_for
    planned = [card("MeTTa Coders", "2026-02-11")]
    e = classify([orphan(card("MeTTa Coders"))], planned,
                 deck([card("MeTTa Coders")])).first

    assert_equal "structural_ancestor_stub", e[:classification]
    assert_equal 1, e[:structural_ancestor_count]
    assert_equal planned, e[:structural_ancestor_of]
    assert_match(/empty left-hand card/, e[:detail])
    assert_match(/#{Regexp.escape(planned.first)}/, e[:detail])
  end

  def test_an_ancestor_with_many_planned_cards_beneath_counts_them_all
    planned = %w[2026-01-01 2026-02-01 2026-03-01].map { |d| card("Weekly", d) }
    e = classify([orphan(card("Weekly"))], planned, deck([card("Weekly")])).first

    assert_equal 3, e[:structural_ancestor_count]
    assert_equal planned.sort, e[:structural_ancestor_of]
  end

  # ---- what must NOT be relabelled --------------------------------------

  def test_a_nonempty_ancestor_stays_a_vanished_transcript
    # The card holds text under a name no export produces. That is exactly
    # the case a reviewer must still see; emptiness is the whole evidence.
    planned = [card("Magi Weekly", "2026-02-11")]
    reader = deck([], content: { name_key(card("Magi Weekly")) => "~~~{...}~~~" })
    e = classify([orphan(card("Magi Weekly"))], planned, reader).first

    assert_equal "vanished_transcript", e[:classification]
    assert_nil e[:structural_ancestor_count]
  end

  def test_an_unreadable_card_is_never_relabelled
    # nil from the reader means "no Card API / could not read". Relabelling on
    # an absent read would be asserting emptiness nobody checked.
    planned = [card("Weekly", "2026-02-11")]
    e = classify([orphan(card("Weekly"))], planned, ->(_n) { nil }).first
    assert_equal "vanished_transcript", e[:classification]
  end

  def test_an_empty_card_that_is_not_an_ancestor_of_any_plan_stays_vanished
    # Empty alone is not enough: nothing in the current plan explains it.
    planned = [card("Weekly", "2026-02-11")]
    e = classify([orphan(card("Retired Series"))], planned,
                 deck([card("Retired Series")])).first
    assert_equal "vanished_transcript", e[:classification]
  end

  def test_the_ancestor_relation_is_strict_not_self
    # A planned card is not its own ancestor; if it were, every skipped card
    # could be relabelled into invisibility.
    planned = [card("Weekly", "2026-02-11")]
    e = classify([orphan(card("Weekly", "2026-02-11"))], planned,
                 deck(planned)).first
    refute_equal "structural_ancestor_stub", e[:classification]
  end

  def test_the_parent_spelling_variants_still_match
    # The deck stores "RawData+transcripts"; the constant says "Raw Data".
    # The rule compares name keys, so both spellings are the same card.
    planned = [card("MeTTa Coders", "2026-02-11")]
    stored = "RawData+transcripts+MeTTa Coders"
    e = classify([orphan(stored)], planned, deck([stored])).first
    assert_equal "structural_ancestor_stub", e[:classification]
  end

  # ---- the other classes must be untouched ------------------------------

  def test_a_stale_chunk_is_not_relabelled_even_when_empty
    ts = [{ transcript_id: "t1", meeting_name: "Standup", date: "2026-01-02",
            date_part: "2026-01-02" }]
    assign_transcript_labels(ts)
    base = ts.first[:card_name]
    planned = ["#{base}+chunk-1", base]
    stale = "#{base}+chunk-2"
    e = classify_orphans([orphan(stale)], planned, ts,
                         content_reader: deck([stale])).first
    assert_equal "stale_chunk", e[:classification]
  end

  def test_a_nesting_stub_keeps_its_own_more_specific_label
    # nesting_stub runs first and says something stronger: the stub hosted a
    # title that was RENAMED. That must not be flattened into the generic
    # structural label.
    ts = [{ transcript_id: "t1", meeting_name: "LLM+PLN", date: "2026-01-02",
            date_part: "2026-01-02" }]
    assign_transcript_labels(ts)
    planned = [ts.first[:card_name]]
    stub = "#{PARENT}+LLM"
    old  = "#{PARENT}+LLM+PLN+2026-01-02"
    classified = classify_orphans([orphan(stub), orphan(old)], planned, ts,
                                  content_reader: deck([stub, old]))
    assert_equal "nesting_stub", classified.first[:classification]
  end

  def test_agi26_foreign_cards_are_unaffected_by_the_new_class
    # AGI 26 is a foreign corpus: no plan ever files anything beneath it, so
    # it can never satisfy the ancestor condition. It stays vanished and
    # stays foreign.
    agi = "#{PARENT}+AGI 26+wPwresMk5dg+full"
    root = "#{PARENT}+AGI 26"
    planned = [card("Weekly", "2026-02-11")]
    classified = classify([orphan(agi), orphan(root)], planned,
                          deck([agi, root]))
    assert_equal %w[vanished_transcript vanished_transcript],
                 classified.map { |e| e[:classification] }

    annotate_foreign_corpora(classified)
    assert_equal %w[AGI\ 26 AGI\ 26], classified.map { |e| e[:foreign_corpus] }
    assert_equal %w[vanished_transcript vanished_transcript],
                 classified.map { |e| e[:classification] },
                 "foreign labelling must still change no classification"
  end

  def test_the_protected_unmatched_card_is_never_relabelled
    # The one irreplaceable card: only the live deck has it. It holds content
    # and nothing is planned beneath it, so it fails both conditions.
    only_copy = card("Elowyn AI Meeting - Frag, EARTHwise, Magi", "2026-03-03")
    assert_includes DELTA_PROTECTED_NAMES.map { |n| name_key(n) },
                    name_key(only_copy)

    planned = [card("Weekly", "2026-02-11")]
    reader = deck([], content: { name_key(only_copy) => "the only copy" })
    classified = classify([orphan(only_copy)], planned, reader)
    annotate_vanished_generations(classified, planned)

    assert_equal "vanished_transcript", classified.first[:classification]
    assert_equal "unmatched", classified.first[:generation],
                 "the one real gap must stay unmatched"
  end

  def test_an_empty_protected_card_is_still_not_relabelled
    # Belt and braces: even if the protected card were empty, it is not an
    # ancestor of anything planned, so the rule cannot reach it.
    only_copy = DELTA_PROTECTED_NAMES.first
    planned = [card("Weekly", "2026-02-11")]
    e = classify([orphan(only_copy)], planned, deck([only_copy])).first
    assert_equal "vanished_transcript", e[:classification]
  end

  # ---- counts: labels move, totals do not -------------------------------

  def test_orphan_summary_raw_totals_are_unchanged_only_labels_move
    planned = REAL_19.map { |s| card(s, "2026-02-11") }
    ancestors = REAL_19.map { |s| card(s) }
    orphans = ancestors.map { |n| orphan(n) }

    before = classify_orphans(orphans, planned, [], content_reader: ->(_n) { nil })
    after  = classify(orphans.map { |o| o.dup }, planned, deck(ancestors))

    b = orphan_summary(before)
    a = orphan_summary(after)
    assert_equal b[:total], a[:total], "no card may appear or disappear"
    assert_equal b[:total], b[:by_classification].values.sum
    assert_equal a[:total], a[:by_classification].values.sum
    assert_equal b[:needs_attention], a[:needs_attention]
    assert_equal b[:unexpected], a[:unexpected]
    assert_equal b[:foreign_corpus], a[:foreign_corpus]

    assert_equal 19, b[:by_classification]["vanished_transcript"]
    assert_equal 19, a[:by_classification]["structural_ancestor_stub"]
    refute a[:by_classification].key?("vanished_transcript")
  end

  def test_relabelled_cards_leave_the_vanished_generation_count
    # The point of the fix: undated_legacy is the number read as "lost
    # meetings", and 19 scaffolding cards must not be in it.
    planned = REAL_19.map { |s| card(s, "2026-02-11") } + [card("Gone", "2026-01-01")]
    ancestors = REAL_19.map { |s| card(s) }
    orphans = (ancestors + [card("Legacy Series")]).map { |n| orphan(n) }

    classified = classify(orphans, planned, deck(ancestors))
    annotate_vanished_generations(classified, planned)
    summary = vanished_generation_summary(classified)

    assert_equal 1, summary[:total], "only the genuine undated card is left"
    assert_equal 1, summary[:by_generation]["undated_legacy"]
  end

  def test_the_structural_summary_names_every_card_it_relabels
    planned = REAL_19.map { |s| card(s, "2026-02-11") }
    ancestors = REAL_19.map { |s| card(s) }
    classified = classify(ancestors.map { |n| orphan(n) }, planned,
                          deck(ancestors))
    summary = structural_ancestor_summary(classified)

    assert_equal 19, summary[:total]
    assert_equal ancestors.sort, summary[:cards],
                 "relabelled must never mean hidden: every name, verbatim"
    assert_equal 19, summary[:evidence].length
    assert summary[:evidence].all? { |e| e[:planned_cards_beneath].positive? }
    assert_match(/Report-only/, summary[:note])
    assert_match(/Nothing is deleted/, summary[:note])
  end

  def test_the_structural_summary_is_absent_when_nothing_was_relabelled
    planned = [card("Weekly", "2026-02-11")]
    classified = classify([orphan(card("Gone", "2026-01-01"))], planned,
                          ->(_n) { nil })
    assert_nil structural_ancestor_summary(classified)
  end

  # ---- the helper -------------------------------------------------------

  def test_strict_ancestor_keys_excludes_the_name_itself
    keys = strict_ancestor_keys(["a+b+c"])
    assert_equal [name_key("a"), name_key("a+b")].sort, keys.keys.sort
    refute keys.key?(name_key("a+b+c"))
    assert_equal ["a+b+c"], keys[name_key("a+b")]
  end

  def test_strict_ancestor_keys_collects_every_name_beneath_an_ancestor
    keys = strict_ancestor_keys(["p+x+1", "p+x+2", "p+y+1"])
    assert_equal ["p+x+1", "p+x+2"], keys[name_key("p+x")].sort
    assert_equal 3, keys[name_key("p")].length
  end

  # ---- still nothing destructive ---------------------------------------

  def test_the_new_class_introduces_no_destructive_path
    src = File.read(INGEST)
    code = src.lines.reject { |l| l.strip.start_with?("#") }.join
    %w[delete destroy trash= prune].each do |op|
      refute_match(/\.#{Regexp.escape(op)}\b/, code,
                   "the stub class must not introduce a #{op} path")
    end
  end
end
