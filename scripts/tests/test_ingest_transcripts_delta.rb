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

# ------------------------------------------------------------
# 1. The load-time guard
# ------------------------------------------------------------
class TestLoadTimeGuard < Minitest::Test
  def test_loading_this_file_did_not_run_an_ingest
    # If the guard were `defined?(Card)` (or absent), merely loading the script
    # under Decko would ingest. The proof it did not run here: no card was
    # planned or written during `load INGEST` above.
    assert_empty STATS[:cards],
                 "loading the script must not plan or write any card"
    assert_equal 0, STATS[:created] + STATS[:updated] + STATS[:errors]
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
    assert_match(/ALREADY stranded/, c[:note])
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
    assert_equal 1, summary[:needs_attention]
    assert_equal ["#{base}+chunk-2"], summary[:stale_chunks]
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

