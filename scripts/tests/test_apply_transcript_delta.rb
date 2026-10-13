#!/usr/bin/env ruby
# Offline tests for the GATED DELTA WRITE PATH:
#   scripts/apply_transcript_delta.rb  (the applier)
#   the manifest builder in scripts/ingest_transcripts.rb (the planner)
#
# These run WITHOUT Decko/Rails. That is deliberate and is itself the point of
# most of these tests: the applier must refuse, with zero writes, long before
# it would need a database. The few tests that need a live deck are named in
# the "not covered here" list at the bottom of this file.
#
# What is covered:
#   1. the write path is disabled by default (dry run)
#   2. every write gate individually refuses: write env, manifest sha,
#      confirm token, loopback origin
#   3. refusal probes perform zero writes and exit non-zero
#   4. the applier has no delete/trash/rename/raw-SQL/network callsite
#   5. the planner's manifest declares zero destructive operations and names
#      the preserve set (keep-stale chunks, orphans, foreign corpora)
#   6. manifest rows are creates and updates ONLY
#   7. a protected or foreign-corpus card in the write set refuses
#   8. a changed export file / changed renderer refuses (hash gates)
#   9. the renderer is pure and matches what the planner hashed
#  10. idempotent-resume classification, driven through the applier's OWN
#      classifier function rather than a copy of its decision table
#  11. write-scope invariants RE-DERIVED by the applier, including a manifest
#      that lies about them (base_card "*all", a sibling card, a foreign
#      corpus, a protected card, a non-descendant parent)
#  12. positive zero-write proof: refusal probes run against a stub deck that
#      RECORDS every mutating call, so an empty recorder means the applier
#      reached the write path and declined, not that it never got there
#
# Run: ruby scripts/tests/test_apply_transcript_delta.rb

require "minitest/autorun"
require "json"
require "open3"
require "tmpdir"
require "fileutils"
require "digest"

APPLIER = File.expand_path("../apply_transcript_delta.rb", __dir__)
PLANNER = File.expand_path("../ingest_transcripts.rb", __dir__)
STUB_RUNNER = File.expand_path("support/run_applier_with_stub_deck.rb", __dir__)
STUB_DECK = File.expand_path("support/stub_card_deck.rb", __dir__)

CONFIRM_TOKEN = "APPLY-TRANSCRIPT-DELTA-LOCAL"
PARENT = "Raw Data+transcripts"

# ------------------------------------------------------------
# Load the applier's functions into THIS process
# ------------------------------------------------------------
# TRANSCRIPT_DELTA_APPLIER_LIB=1 makes the applier define its gates, scope
# functions and classifier and then run nothing: no manifest read, no live
# phase, no exit. That is what lets the classifier/scope tests below call the
# SHIPPED functions instead of a copy of their decision tables.
#
# The variable is deleted immediately afterwards. Open3.capture3(env, ...)
# merges env into this process's environment, so leaving it set would turn
# every subprocess applier into a no-op that writes no report - and every
# refusal test would then "pass" against nothing at all.
ENV["TRANSCRIPT_DELTA_APPLIER_LIB"] = "1"
load APPLIER
ENV.delete("TRANSCRIPT_DELTA_APPLIER_LIB")

# ------------------------------------------------------------
# Shared fixtures
# ------------------------------------------------------------
module DeltaFixtures
  # A transcript export small enough to render to one card.
  def transcript(id: "t1", name: "Standup", date: "2026-01-02", text: "alice: hi")
    { "transcript_id" => id, "meeting_name" => name, "date" => date,
      "source_service" => "fireflies.ai", "duration_minutes" => 10,
      "participants" => ["alice"], "full_text" => text }
  end

  def write_export(dir, basename, data)
    path = File.join(dir, basename)
    File.write(path, JSON.dump(data))
    path
  end

  # Render a transcript the way the planner does, in a throwaway subprocess, so
  # the fixture's desired_hash is the planner's own hash and not a guess.
  def planner_render(dir, basename, card_name)
    script = <<~RUBY
      ENV["TRANSCRIPT_INGEST_DRY_RUN"] = "1"
      load #{PLANNER.dump}
      require "json"
      data = JSON.parse(File.read(#{File.join(dir, basename).dump}))
      out = render_transcript_cards_from_data(data, #{card_name.dump}).map do |c|
        { "name" => c[:name], "content" => c[:content], "role" => c[:role].to_s,
          "hash" => content_hash(c[:content]), "chars" => c[:content].length }
      end
      puts JSON.dump(out)
    RUBY
    out, err, status = Open3.capture3(RbConfig.ruby, "-e", script)
    raise "planner render failed: #{err}" unless status.success?

    JSON.parse(out.lines.last)
  end

  # A minimal but structurally complete manifest for one card.
  def manifest_for(dir, basename, card_name, action: "create", live_hash: nil,
                   overrides: {})
    cards = planner_render(dir, basename, card_name)
    row = cards.first
    source_sha = Digest::SHA256.hexdigest(File.binread(File.join(dir, basename)))

    m = {
      "manifest_version" => 1,
      "generated_utc" => "2026-10-13T00:00:00Z",
      "generator" => "scripts/ingest_transcripts.rb delta planner",
      "confirm_token" => CONFIRM_TOKEN,
      "target_environment" => "local_loopback_only",
      "production_contacted" => false,
      "deck_origin_at_plan_time" => "http://127.0.0.1:3100",
      "export_dir" => dir,
      "parent_card" => "Raw Data+transcripts",
      "max_card_chars" => 50_000,
      "baseline" => "live-content-hash",
      "baseline_available" => true,
      "hash_algorithm" => "sha256",
      "hash_normalization" => ["none_required_no_export_timestamp"],
      "transcript_count" => 1,
      "export_files_pinned" => 1,
      "write_set" => {
        "creates" => (action == "create" ? 1 : 0),
        "updates" => (action == "update" ? 1 : 0),
        "total" => 1, "skipped_unchanged" => 0
      },
      "rows" => [{
        "card_name" => row["name"],
        "card_key" => row["name"].downcase.gsub(/[^a-z0-9+]+/, "_"),
        "action" => action,
        "reason" => (action == "create" ? "missing_card" : "text_grew"),
        "role" => row["role"],
        "base_card" => card_name,
        "transcript_id" => "t1",
        "source_basename" => basename,
        "source_sha256" => source_sha,
        "render_index" => 0, "render_total" => cards.length,
        "type_code" => "raw_data",
        "live_hash" => live_hash,
        "desired_hash" => row["hash"],
        "live_chars" => (live_hash ? 10 : nil),
        "desired_chars" => row["chars"]
      }],
      "deletes_in_scope" => 0, "trashes_in_scope" => 0,
      "renames_in_scope" => 0, "orphan_cleanup_in_scope" => 0,
      "stale_chunk_prunes_in_scope" => 0, "destructive_path_exists" => false,
      "preserve" => {
        "policy" => "keep", "keep_stale_chunks" => true,
        "stale_chunk_cards" => [], "stale_chunk_cards_total" => 0,
        "shrinking_chunk_transcripts" => 0,
        "orphan_cards_total" => 0, "orphan_cards_excluding_foreign" => 0,
        "foreign_corpus_cards" => 0, "foreign_corpora" => ["AGI 26"],
        "protected_names" => [
          "Raw Data+transcripts+Elowyn AI Meeting - Frag, EARTHwise, Magi+2026-03-03"
        ],
        "note" => "preserved"
      },
      "scope" => {
        "actions_allowed" => %w[create update],
        "protected_rows_in_write_set" => [],
        "foreign_corpus_rows_in_write_set" => [],
        "all_rows_under_parent" => true,
        "unique_card_names" => true,
        "every_row_has_desired_hash" => true,
        "every_update_has_live_hash" => (action == "update"),
        "every_create_has_no_live_hash" => true
      },
      "blocking" => {
        "unexpected_planned_chunks" => 0, "no_live_baseline" => 0,
        "stale_chunk_cards" => 0, "protected_rows_in_write_set" => 0,
        "foreign_corpus_rows_in_write_set" => 0
      },
      "note" => "frozen plan"
    }
    # "every_update_has_live_hash" is vacuously true with no update rows.
    m["scope"]["every_update_has_live_hash"] = true if action == "create"
    deep_merge(m, overrides)
  end

  def deep_merge(a, b)
    b.each do |k, v|
      a[k] = a[k].is_a?(Hash) && v.is_a?(Hash) ? deep_merge(a[k], v) : v
    end
    a
  end

  def write_manifest(dir, manifest, basename: "manifest.json")
    path = File.join(dir, basename)
    File.write(path, JSON.pretty_generate(manifest))
    [path, Digest::SHA256.hexdigest(File.binread(path))]
  end

  # Run the applier in a clean subprocess. Returns [report_hash, stdout,
  # stderr, status]. report_hash is nil when the applier wrote no report.
  def run_applier(env)
    Dir.mktmpdir do |rdir|
      report = File.join(rdir, "apply_report.json")
      full = { "TRANSCRIPT_DELTA_REPORT" => report }.merge(env)
      out, err, status = Open3.capture3(full, RbConfig.ruby, APPLIER)
      data = File.exist?(report) ? JSON.parse(File.read(report)) : nil
      return [data, out, err, status]
    end
  end

  # ----------------------------------------------------------------------
  # Stub-deck runs: the applier's LIVE phase, offline
  # ----------------------------------------------------------------------
  # A card fixture for the stub deck. The default type is RawData because
  # that is what the applier demands; tests that want type_drift override it.
  def deck_card(name, content: "", type_name: "RawData", trash: false)
    { "name" => name, "content" => content,
      "type_name" => type_name, "trash" => trash }
  end

  # The parent card plus whatever else a test needs. The applier refuses when
  # the parent is missing, so almost every deck includes it.
  def deck_with_parent(*cards)
    [deck_card(PARENT, content: "transcripts", type_name: "Basic")] + cards
  end

  # Run the real applier against the stub deck and return
  # [report, mutation_log, stdout, stderr, status].
  #
  # mutation_log["mutations"] is the recorder: EVERY create/update the applier
  # attempted, plus any forbidden call (destroy/delete/trash=/save/rename/raw
  # SQL) it tried to make. An empty list after a run that reached the live
  # phase is positive evidence of zero writes.
  #
  # allow_writes: false (the default) makes the stub refuse even a legitimate
  # create!/update!, which is what a refusal probe wants: if the applier ever
  # did reach a write, the recorder would show it and the run would fail.
  def run_applier_on_stub_deck(env, deck:, allow_writes: false)
    Dir.mktmpdir do |rdir|
      report = File.join(rdir, "apply_report.json")
      cards = File.join(rdir, "deck.json")
      mutations = File.join(rdir, "mutations.json")
      File.write(cards, JSON.dump(deck))

      full = {
        "TRANSCRIPT_DELTA_REPORT" => report,
        "STUB_DECK_CARDS" => cards,
        "STUB_MUTATION_LOG" => mutations,
        "STUB_ALLOW_WRITES" => (allow_writes ? "1" : "0")
      }.merge(env)

      out, err, status = Open3.capture3(full, RbConfig.ruby, STUB_RUNNER)
      [File.exist?(report) ? JSON.parse(File.read(report)) : nil,
       File.exist?(mutations) ? JSON.parse(File.read(mutations)) : nil,
       out, err, status]
    end
  end

  # Positive zero-write proof. Requires that the recorder EXISTS (so the run
  # really did boot a deck) and that it is empty.
  def assert_recorder_empty(log, context)
    refute_nil log, "#{context}: the stub deck wrote no mutation log, so this " \
                    "run proves nothing about writes"
    assert_equal [], log["mutations"],
                 "#{context}: the applier attempted #{log['mutations'].length} " \
                 "mutating call(s): #{log['mutations'].inspect}"
    assert_equal 0, log["write_ops"], "#{context}: write_ops must be 0"
    assert_equal 0, log["forbidden_ops"], "#{context}: forbidden_ops must be 0"
  end

  # Both kinds of evidence at once: the applier's self-report and the deck's
  # independent recorder.
  def assert_proven_zero_writes(report, log, context)
    assert_zero_writes report, context
    assert_recorder_empty log, context
  end

  # Assert a run performed no mutation of any kind.
  def assert_zero_writes(report, context)
    refute_nil report, "#{context}: the applier wrote no report"
    %w[writes_performed creates_performed updates_performed
       deletes_performed renames_performed trashes_performed].each do |k|
      assert_equal 0, report[k], "#{context}: #{k} must be 0"
    end
  end
end

# ------------------------------------------------------------
# 1. Disabled by default
# ------------------------------------------------------------
class TestWritePathDisabledByDefault < Minitest::Test
  include DeltaFixtures

  def test_no_env_at_all_refuses_with_zero_writes
    report, out, _err, status = run_applier({})
    refute status.success?, "a bare invocation must exit non-zero"
    assert_zero_writes report, "bare invocation"
    assert_equal "dry_run", report["mode"]
    assert_match(/TRANSCRIPT_DELTA_MANIFEST is required/, report["halt_reason"].to_s)
    assert_match(/REFUSED|HALTED/, out)
  end

  def test_mode_is_dry_run_unless_the_write_gate_is_exactly_one
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m = manifest_for(dir, "a.json", "Raw Data+transcripts+Standup+2026-01-02")
      path, sha = write_manifest(dir, m)

      # Every near-miss spelling of the write gate must stay in dry run.
      ["", "0", "true", "yes", "on", "TRUE", "y", "2", " 1", "1 "].each do |spelling|
        report, = run_applier(
          "TRANSCRIPT_DELTA_MANIFEST" => path,
          "TRANSCRIPT_DELTA_WRITE" => spelling,
          "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha,
          "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
          "DECK_ORIGIN" => "http://127.0.0.1:3100",
          "TRANSCRIPT_EXPORT_DIR" => dir
        )
        assert_equal "dry_run", report["mode"],
                     "TRANSCRIPT_DELTA_WRITE=#{spelling.inspect} must not enable writes"
        assert_equal false, report["gates"]["write_requested"]
        assert_zero_writes report, "write gate spelling #{spelling.inspect}"
      end
    end
  end

  def test_a_full_dry_run_passes_every_static_gate_and_still_writes_nothing
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m = manifest_for(dir, "a.json", "Raw Data+transcripts+Standup+2026-01-02")
      path, = write_manifest(dir, m)

      report, = run_applier(
        "TRANSCRIPT_DELTA_MANIFEST" => path,
        "DECK_ORIGIN" => "http://127.0.0.1:3100",
        "TRANSCRIPT_EXPORT_DIR" => dir
      )
      g = report["gates"]
      assert_equal true, g["loopback_origin"]
      assert_equal true, g["manifest_static_valid"]
      assert_equal true, g["rerender_matches_manifest"],
                   "the re-render must reproduce the manifest's desired_hash"
      # No Card API offline: the applier refuses rather than reporting on
      # nothing. That refusal is the correct outcome here.
      refute g.key?("card_api_available")
      assert_match(/no Card API/, report["halt_reason"].to_s)
      assert_zero_writes report, "offline dry run"
    end
  end
end

# ------------------------------------------------------------
# 2. Each write gate refuses on its own
# ------------------------------------------------------------
class TestWriteGates < Minitest::Test
  include DeltaFixtures

  def base_env(dir, path, sha)
    { "TRANSCRIPT_DELTA_MANIFEST" => path,
      "TRANSCRIPT_DELTA_WRITE" => "1",
      "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha,
      "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
      "DECK_ORIGIN" => "http://127.0.0.1:3100",
      "TRANSCRIPT_EXPORT_DIR" => dir }
  end

  def with_fixture
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m = manifest_for(dir, "a.json", "Raw Data+transcripts+Standup+2026-01-02")
      path, sha = write_manifest(dir, m)
      yield dir, path, sha, m
    end
  end

  def test_write_gate_without_manifest_sha_refuses
    with_fixture do |dir, path, sha|
      env = base_env(dir, path, sha)
      env.delete("TRANSCRIPT_DELTA_MANIFEST_SHA")
      report, _o, _e, status = run_applier(env)
      refute status.success?
      assert_match(/MANIFEST_SHA is required/, report["halt_reason"].to_s)
      assert_zero_writes report, "missing manifest sha"
    end
  end

  def test_write_gate_with_wrong_manifest_sha_refuses
    with_fixture do |dir, path, sha|
      env = base_env(dir, path, sha)
      env["TRANSCRIPT_DELTA_MANIFEST_SHA"] = "0" * 64
      report, _o, _e, status = run_applier(env)
      refute status.success?
      assert_match(/does not match the manifest on disk/, report["halt_reason"].to_s)
      assert_zero_writes report, "wrong manifest sha"
    end
  end

  def test_manifest_sha_of_a_different_but_valid_manifest_refuses
    with_fixture do |dir, path, _sha, m|
      # A reviewer approved manifest A; manifest B is also internally valid.
      # Pinning A's sha while handing over B must refuse.
      m2 = deep_merge(Marshal.load(Marshal.dump(m)),
                      { "generated_utc" => "2026-10-14T00:00:00Z" })
      path2, _sha2 = write_manifest(dir, m2, basename: "manifest2.json")
      sha_of_first = Digest::SHA256.hexdigest(File.binread(path))

      env = base_env(dir, path2, sha_of_first)
      report, _o, _e, status = run_applier(env)
      refute status.success?
      assert_match(/does not match/, report["halt_reason"].to_s)
      assert_zero_writes report, "sha of a different manifest"
    end
  end

  def test_write_gate_without_confirm_token_refuses
    with_fixture do |dir, path, sha|
      env = base_env(dir, path, sha)
      env.delete("TRANSCRIPT_DELTA_CONFIRM")
      report, _o, _e, status = run_applier(env)
      refute status.success?
      assert_match(/CONFIRM is required/, report["halt_reason"].to_s)
      assert_zero_writes report, "missing confirm token"
    end
  end

  def test_write_gate_with_wrong_confirm_token_refuses
    with_fixture do |dir, path, sha|
      ["apply", "APPLY-TRANSCRIPT-DELTA", "apply-transcript-delta-local",
       "APPLY-DATESHIFT-REFREWRITE-LOCAL", "#{CONFIRM_TOKEN} "].each do |bad|
        env = base_env(dir, path, sha).merge("TRANSCRIPT_DELTA_CONFIRM" => bad)
        report, _o, _e, status = run_applier(env)
        refute status.success?, "token #{bad.inspect} must be refused"
        assert_match(/token is wrong/, report["halt_reason"].to_s)
        assert_zero_writes report, "confirm token #{bad.inspect}"
      end
    end
  end

  def test_non_loopback_origin_refuses_even_with_every_other_gate_set
    with_fixture do |dir, path, sha|
      ["https://wiki.hyperon.dev", "https://dev-wiki.hyperon.dev",
       "http://10.0.0.5:3000", "https://example.com", ""].each do |origin|
        env = base_env(dir, path, sha).merge("DECK_ORIGIN" => origin)
        report, _o, _e, status = run_applier(env)
        refute status.success?, "origin #{origin.inspect} must be refused"
        assert_match(/not loopback|forbidden host/, report["halt_reason"].to_s)
        assert_zero_writes report, "origin #{origin.inspect}"
        refute report["gates"]["loopback_origin"],
               "the loopback gate must not be recorded as passed"
      end
    end
  end

  def test_production_hostnames_are_refused_by_name_not_only_by_shape
    with_fixture do |dir, path, sha|
      # A loopback-looking origin that also names prod must still refuse: the
      # deny-list is checked before the allow-list.
      env = base_env(dir, path, sha)
             .merge("DECK_ORIGIN" => "http://127.0.0.1:3100/?h=wiki.hyperon.dev")
      report, _o, _e, status = run_applier(env)
      refute status.success?
      assert_match(/forbidden host/, report["halt_reason"].to_s)
      assert_zero_writes report, "loopback origin naming prod"
    end
  end

  def test_loopback_variants_are_accepted_by_the_origin_gate
    with_fixture do |dir, path, sha|
      ["http://127.0.0.1:3100", "http://localhost:3100",
       "http://[::1]:3100"].each do |origin|
        report, = run_applier(base_env(dir, path, sha).merge("DECK_ORIGIN" => origin))
        assert_equal true, report["gates"]["loopback_origin"],
                     "#{origin} must pass the loopback gate"
        # still refuses later (no Card API), with zero writes
        assert_zero_writes report, "loopback origin #{origin}"
      end
    end
  end

  def test_all_gates_set_reaches_the_card_api_gate_and_stops_there
    with_fixture do |dir, path, sha|
      report, _o, _e, status = run_applier(base_env(dir, path, sha))
      refute status.success?
      assert_equal "apply", report["mode"]
      assert_equal true, report["gates"]["manifest_sha_matched"]
      assert_equal true, report["gates"]["confirm_token_matched"]
      assert_match(/no Card API/, report["halt_reason"].to_s)
      # The last gate before any database access is the one that stopped it,
      # so this is the furthest a write can get without a real deck.
      assert_zero_writes report, "all gates set, offline"
    end
  end
end

# ------------------------------------------------------------
# 3. Manifest validity gates
# ------------------------------------------------------------
class TestManifestValidation < Minitest::Test
  include DeltaFixtures

  # `row:` patches field(s) INTO the existing row rather than replacing the
  # rows array, so a test about one bad field is not pre-empted by the
  # write_set counter gate complaining about a row that lost its action.
  def refuse_with(overrides, pattern, row: nil)
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m = manifest_for(dir, "a.json", "Raw Data+transcripts+Standup+2026-01-02",
                       overrides: overrides)
      m["rows"][0] = m["rows"][0].merge(row) if row
      path, sha = write_manifest(dir, m)
      report, _o, _e, status = run_applier(
        "TRANSCRIPT_DELTA_MANIFEST" => path,
        "TRANSCRIPT_DELTA_WRITE" => "1",
        "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha,
        "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
        "DECK_ORIGIN" => "http://127.0.0.1:3100",
        "TRANSCRIPT_EXPORT_DIR" => dir
      )
      refute status.success?, "#{overrides.inspect} must be refused"
      assert_match(pattern, report["halt_reason"].to_s)
      assert_zero_writes report, overrides.inspect
    end
  end

  def test_wrong_manifest_version_refuses
    refuse_with({ "manifest_version" => 2 }, /manifest_version/)
    refuse_with({ "manifest_version" => nil }, /manifest_version/)
  end

  def test_non_local_target_environment_refuses
    refuse_with({ "target_environment" => "production" }, /not local-only/)
    refuse_with({ "target_environment" => nil }, /not local-only/)
  end

  def test_declared_production_contact_refuses
    refuse_with({ "production_contacted" => true }, /production contact/)
  end

  def test_a_manifest_with_no_live_baseline_refuses
    refuse_with({ "baseline_available" => false }, /no live baseline/)
    refuse_with({ "baseline" => "none-no-card-api" }, /no live baseline/)
  end

  def test_any_declared_destructive_operation_refuses
    refuse_with({ "deletes_in_scope" => 1 }, /deletes_in_scope/)
    refuse_with({ "trashes_in_scope" => 1 }, /trashes_in_scope/)
    refuse_with({ "renames_in_scope" => 1 }, /renames_in_scope/)
    refuse_with({ "orphan_cleanup_in_scope" => 1 }, /orphan_cleanup_in_scope/)
    refuse_with({ "stale_chunk_prunes_in_scope" => 1 }, /stale_chunk_prunes/)
    refuse_with({ "destructive_path_exists" => true }, /destructive path/)
  end

  def test_a_wrong_confirm_token_inside_the_manifest_refuses
    refuse_with({ "confirm_token" => "SOMETHING-ELSE" },
                /confirm token does not match/)
  end

  def test_write_set_counts_must_agree_with_the_rows
    refuse_with({ "write_set" => { "total" => 2 } }, /write_set.total/)
    refuse_with({ "write_set" => { "creates" => 5 } }, /write_set.creates/)
    refuse_with({ "write_set" => { "updates" => 5 } }, /write_set.updates/)
  end

  def test_an_action_other_than_create_or_update_refuses
    refuse_with({ "scope" => { "actions_allowed" => %w[create update delete] } },
                /beyond create\/update/)
    # a row action the manifest's own counters cannot explain
    %w[delete trash rename prune skip-unchanged].each do |bad|
      refuse_with({ "write_set" => { "creates" => 0 } },
                  /not in create\/update/, row: { "action" => bad })
    end
  end

  def test_a_false_scope_assertion_refuses
    %w[all_rows_under_parent unique_card_names every_row_has_desired_hash
       every_update_has_live_hash every_create_has_no_live_hash].each do |k|
      refuse_with({ "scope" => { k => false } }, /#{k} is not true/)
    end
  end

  def test_a_protected_card_in_the_write_set_refuses
    refuse_with(
      { "scope" => { "protected_rows_in_write_set" =>
        ["Raw Data+transcripts+Elowyn AI Meeting - Frag, EARTHwise, Magi+2026-03-03"] } },
      /protected card/
    )
  end

  def test_a_foreign_corpus_card_in_the_write_set_refuses
    refuse_with(
      { "scope" => { "foreign_corpus_rows_in_write_set" =>
        ["Raw Data+transcripts+AGI 26+keynote"] } },
      /foreign-corpus card/
    )
  end

  def test_any_declared_blocker_refuses
    refuse_with({ "blocking" => { "unexpected_planned_chunks" => 1 } },
                /reports blockers/)
    refuse_with({ "blocking" => { "no_live_baseline" => 1 } }, /reports blockers/)
    refuse_with({ "blocking" => { "protected_rows_in_write_set" => 1 } },
                /reports blockers/)
  end

  def test_an_empty_manifest_refuses
    refuse_with({ "rows" => [], "write_set" => { "total" => 0, "creates" => 0 } },
                /no rows/)
  end

  def test_a_row_without_a_sha256_desired_hash_refuses
    refuse_with({}, /no desired_hash/, row: { "desired_hash" => "" })
    refuse_with({}, /not a sha256/, row: { "desired_hash" => "deadbeef" })
    refuse_with({}, /not a sha256/, row: { "desired_hash" => "Z" * 64 })
    refuse_with({}, /source_sha256 is not a sha256/,
                row: { "source_sha256" => "nope" })
  end

  def test_an_update_row_whose_live_hash_equals_its_desired_hash_refuses
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m = manifest_for(dir, "a.json", "Raw Data+transcripts+Standup+2026-01-02",
                       action: "update", live_hash: "a" * 64)
      m["rows"][0]["live_hash"] = m["rows"][0]["desired_hash"]
      path, sha = write_manifest(dir, m)
      report, _o, _e, status = run_applier(
        "TRANSCRIPT_DELTA_MANIFEST" => path, "TRANSCRIPT_DELTA_WRITE" => "1",
        "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha,
        "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
        "DECK_ORIGIN" => "http://127.0.0.1:3100", "TRANSCRIPT_EXPORT_DIR" => dir
      )
      refute status.success?
      assert_match(/would be a no-op/, report["halt_reason"].to_s)
      assert_zero_writes report, "no-op update row"
    end
  end

  def test_a_create_row_carrying_a_live_hash_refuses
    refuse_with({}, /carries a live_hash/, row: { "live_hash" => "b" * 64 })
  end

  def test_a_row_with_an_unexpected_type_code_refuses
    refuse_with({}, /unexpected type_code/, row: { "type_code" => "markdown" })
    refuse_with({}, /unexpected type_code/, row: { "type_code" => nil })
  end

  def test_a_row_in_the_preserve_set_refuses
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m = manifest_for(dir, "a.json", "Raw Data+transcripts+Standup+2026-01-02")
      # the planned card is simultaneously declared a kept stale chunk
      m["preserve"]["stale_chunk_cards"] = [m["rows"][0]["card_name"]]
      m["preserve"]["stale_chunk_cards_total"] = 1
      path, sha = write_manifest(dir, m)
      report, _o, _e, status = run_applier(
        "TRANSCRIPT_DELTA_MANIFEST" => path, "TRANSCRIPT_DELTA_WRITE" => "1",
        "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha,
        "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
        "DECK_ORIGIN" => "http://127.0.0.1:3100", "TRANSCRIPT_EXPORT_DIR" => dir
      )
      refute status.success?
      assert_match(/in the preserve set/, report["halt_reason"].to_s)
      assert_zero_writes report, "row in preserve set"
    end
  end
end

# ------------------------------------------------------------
# 4. Baseline / payload drift gates
# ------------------------------------------------------------
class TestDriftGates < Minitest::Test
  include DeltaFixtures

  def test_a_changed_export_file_refuses_before_any_write
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m = manifest_for(dir, "a.json", "Raw Data+transcripts+Standup+2026-01-02")
      path, sha = write_manifest(dir, m)

      # the export is re-exported with more text after planning
      write_export(dir, "a.json", transcript(text: "alice: hi\nbob: hello again"))

      report, _o, _e, status = run_applier(
        "TRANSCRIPT_DELTA_MANIFEST" => path, "TRANSCRIPT_DELTA_WRITE" => "1",
        "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha,
        "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
        "DECK_ORIGIN" => "http://127.0.0.1:3100", "TRANSCRIPT_EXPORT_DIR" => dir
      )
      refute status.success?
      assert_match(/export file changed since planning/, report["halt_reason"].to_s)
      assert_zero_writes report, "changed export"
    end
  end

  def test_a_missing_export_file_refuses
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m = manifest_for(dir, "a.json", "Raw Data+transcripts+Standup+2026-01-02")
      path, sha = write_manifest(dir, m)
      File.unlink(File.join(dir, "a.json"))

      report, _o, _e, status = run_applier(
        "TRANSCRIPT_DELTA_MANIFEST" => path, "TRANSCRIPT_DELTA_WRITE" => "1",
        "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha,
        "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
        "DECK_ORIGIN" => "http://127.0.0.1:3100", "TRANSCRIPT_EXPORT_DIR" => dir
      )
      refute status.success?
      assert_match(/export file missing/, report["halt_reason"].to_s)
      assert_zero_writes report, "missing export"
    end
  end

  def test_a_desired_hash_the_renderer_cannot_reproduce_refuses
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m = manifest_for(dir, "a.json", "Raw Data+transcripts+Standup+2026-01-02")
      # simulate a renderer change: the manifest's desired_hash no longer
      # matches what this code renders
      m["rows"][0]["desired_hash"] = "c" * 64
      path, sha = write_manifest(dir, m)

      report, _o, _e, status = run_applier(
        "TRANSCRIPT_DELTA_MANIFEST" => path, "TRANSCRIPT_DELTA_WRITE" => "1",
        "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha,
        "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
        "DECK_ORIGIN" => "http://127.0.0.1:3100", "TRANSCRIPT_EXPORT_DIR" => dir
      )
      refute status.success?
      assert_match(/re-render hash mismatch/, report["halt_reason"].to_s)
      assert_zero_writes report, "unreproducible desired hash"
    end
  end

  def test_a_desired_char_count_that_disagrees_with_the_render_refuses
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m = manifest_for(dir, "a.json", "Raw Data+transcripts+Standup+2026-01-02")
      m["rows"][0]["desired_chars"] = 999_999
      path, sha = write_manifest(dir, m)

      report, _o, _e, status = run_applier(
        "TRANSCRIPT_DELTA_MANIFEST" => path, "TRANSCRIPT_DELTA_WRITE" => "1",
        "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha,
        "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
        "DECK_ORIGIN" => "http://127.0.0.1:3100", "TRANSCRIPT_EXPORT_DIR" => dir
      )
      refute status.success?
      assert_match(/re-render length mismatch/, report["halt_reason"].to_s)
      assert_zero_writes report, "char count disagreement"
    end
  end

  def test_a_row_naming_a_card_the_render_does_not_produce_refuses
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m = manifest_for(dir, "a.json", "Raw Data+transcripts+Standup+2026-01-02")
      m["rows"][0]["card_name"] = "Raw Data+transcripts+Standup+2026-01-02+chunk-9"
      path, sha = write_manifest(dir, m)

      report, _o, _e, status = run_applier(
        "TRANSCRIPT_DELTA_MANIFEST" => path, "TRANSCRIPT_DELTA_WRITE" => "1",
        "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha,
        "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
        "DECK_ORIGIN" => "http://127.0.0.1:3100", "TRANSCRIPT_EXPORT_DIR" => dir
      )
      refute status.success?
      assert_match(/re-render produced no card named/, report["halt_reason"].to_s)
      assert_zero_writes report, "phantom card name"
    end
  end

  def test_a_manifest_that_disagrees_with_itself_on_an_export_hash_refuses
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript(text: "x\n" * 40_000))
      cards = planner_render(dir, "a.json", "Raw Data+transcripts+Big+2026-01-02")
      assert_operator cards.length, :>, 1, "fixture must chunk"

      m = manifest_for(dir, "a.json", "Raw Data+transcripts+Big+2026-01-02")
      source_sha = m["rows"][0]["source_sha256"]
      m["rows"] = cards.first(2).each_with_index.map do |c, i|
        m["rows"][0].merge(
          "card_name" => c["name"], "role" => c["role"],
          "desired_hash" => c["hash"], "desired_chars" => c["chars"],
          "render_index" => i, "render_total" => cards.length,
          # second row claims a different source hash for the same file
          "source_sha256" => (i.zero? ? source_sha : "d" * 64)
        )
      end
      m["write_set"] = { "creates" => 2, "updates" => 0, "total" => 2,
                         "skipped_unchanged" => 0 }
      path, sha = write_manifest(dir, m)

      report, _o, _e, status = run_applier(
        "TRANSCRIPT_DELTA_MANIFEST" => path, "TRANSCRIPT_DELTA_WRITE" => "1",
        "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha,
        "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
        "DECK_ORIGIN" => "http://127.0.0.1:3100", "TRANSCRIPT_EXPORT_DIR" => dir
      )
      refute status.success?
      assert_match(/disagrees with itself/, report["halt_reason"].to_s)
      assert_zero_writes report, "self-inconsistent manifest"
    end
  end
end

# ------------------------------------------------------------
# 5. Static mutation-surface audit of the applier itself
# ------------------------------------------------------------
class TestApplierMutationSurface < Minitest::Test
  # Executable lines only: a comment saying "never delete" must not fail an
  # audit that is looking for a delete callsite.
  def executable_lines
    @executable_lines ||= File.readlines(APPLIER).each_with_index
      .reject { |l, _i| l.strip.empty? || l.strip.start_with?("#") }
  end

  # `allow` classifies the benign matches explicitly rather than loosening the
  # pattern: ENV.delete is env scrubbing, not a card operation, and saying so
  # here keeps the audit able to catch a real Card#delete.
  def refute_callsite(regex, label, allow: [])
    hits = executable_lines.select do |l, _i|
      l.match?(regex) && allow.none? { |a| l.include?(a) }
    end
    assert_empty hits.map { |l, i| "#{i + 1}: #{l.strip}" },
                 "#{label} must not appear in an executable line of the applier"
  end

  # Offset of the first EXECUTABLE occurrence of a needle. The file's header
  # comment names Card.create! while describing what the applier may do, so a
  # raw String#index on the source finds the documentation, not the callsite.
  def executable_offset(needle)
    lines = File.readlines(APPLIER)
    offset = 0
    lines.each do |l|
      return offset if !l.strip.start_with?("#") && l.include?(needle)

      offset += l.length
    end
    nil
  end

  def test_no_delete_or_trash_callsite
    refute_callsite(/\.delete\b/, "Card#delete", allow: ["ENV.delete"])
    refute_callsite(/\.delete!/, "Card#delete!")
    refute_callsite(/\.destroy\b/, "destroy")
    refute_callsite(/\.destroy_all\b/, "destroy_all")
    refute_callsite(/\.trash\s*=/, "trash=")
    refute_callsite(/\.update_column/, "update_column")
    refute_callsite(/delete_all/, "delete_all")
  end

  def test_no_rename_callsite
    refute_callsite(/\.name\s*=[^=]/, "Card#name=")
    refute_callsite(/update_references_out/, "reference rewriting")
  end

  def test_no_raw_sql_callsite
    refute_callsite(/connection\.execute/, "connection.execute")
    refute_callsite(/exec_query/, "exec_query")
    refute_callsite(/exec_update/, "exec_update")
    refute_callsite(/find_by_sql/, "find_by_sql")
    refute_callsite(/select_all/, "select_all")
    refute_callsite(/sanitize_sql/, "sanitize_sql")
  end

  def test_no_network_or_production_callsite
    refute_callsite(/Net::HTTP/, "Net::HTTP")
    refute_callsite(/require\s+["']net\/http/, "net/http")
    refute_callsite(/open-uri|URI\.open/, "URI.open")
    refute_callsite(/system\(|`|Open3|spawn\(|(?<![a-z_])exec\(/, "a shell escape")
    # production hostnames may only appear inside the deny-list constant
    src = File.read(APPLIER)
    prod_lines = src.lines.each_with_index.select do |l, _i|
      l.include?("hyperon.dev") && !l.strip.start_with?("#")
    end
    assert_equal 1, prod_lines.length,
                 "hyperon.dev may appear exactly once, in FORBIDDEN_ORIGIN_MARKERS"
    assert_match(/hyperon\.dev$/, prod_lines.first[0].strip)
  end

  def test_the_only_write_callsites_are_one_create_and_one_update
    creates = executable_lines.select { |l, _i| l.match?(/Card\.create!/) }
    updates = executable_lines.select { |l, _i| l.match?(/\.update!\(/) }
    assert_equal 1, creates.length, "exactly one Card.create! callsite"
    assert_equal 1, updates.length, "exactly one update! callsite"
  end

  def test_both_write_callsites_sit_behind_the_write_gate
    # The dry-run early exit must appear before either write callsite. Pinned
    # to the exit's own banner rather than to "unless APPLY_WRITE", which also
    # occurs in the write-authorization gate far earlier in the file.
    guard = executable_offset("DRY RUN (no write gate set)")
    refute_nil guard, "the applier must have a dry-run early exit"
    assert_operator guard, :<, executable_offset("Card.create!"),
                    "the dry-run exit must precede the create callsite"
    assert_operator guard, :<, executable_offset(".update!("),
                    "the dry-run exit must precede the update callsite"
    # and the exit must actually be guarded by the write gate
    assert_match(/unless APPLY_WRITE\s*\n\s*puts "DRY RUN/, File.read(APPLIER))
  end

  def test_the_write_gate_is_an_exact_string_comparison
    src = File.read(APPLIER)
    assert_match(/APPLY_WRITE\s*=\s*ENV\["TRANSCRIPT_DELTA_WRITE"\]\s*==\s*"1"/,
                 src, "the write gate must be an exact == \"1\", not a truthy list")
  end

  def test_the_applier_namespaces_its_constants_against_the_planner_load
    # `load`ing the planner re-evaluates its top level in this process, so any
    # shared constant name would be silently reassigned - including the report
    # path, i.e. the evidence of what the applier just did.
    src = File.read(APPLIER)
    planner_consts = File.read(PLANNER).scan(/^([A-Z][A-Z0-9_]{2,})\s*=/).flatten.uniq
    applier_consts = src.scan(/^([A-Z][A-Z0-9_]{2,})\s*=/).flatten.uniq
    assert_empty (planner_consts & applier_consts),
                 "these constants collide with the planner and would be clobbered"
    assert_match(/gate_fingerprint/, src,
                 "the applier must verify its gates survived the planner load"
    )
  end

  def test_the_applier_never_sets_the_planners_ingest_env
    executable_lines.each do |l, i|
      refute_match(/ENV\["TRANSCRIPT_INGEST"\]\s*=[^=]/, l,
                   "line #{i + 1} sets TRANSCRIPT_INGEST, which would run a full ingest")
    end
  end

  def test_loading_the_planner_scrubs_the_ingest_env
    src = File.read(APPLIER)
    assert_match(/ENV\.delete\(k\)/, src)
    assert_match(/TRANSCRIPT_INGEST TRANSCRIPT_INGEST_DELTA/, src,
                 "the planner's run/abort env must be scrubbed for the load")
  end
end

# ------------------------------------------------------------
# 6. The planner's manifest builder
# ------------------------------------------------------------
class TestPlannerManifest < Minitest::Test
  include DeltaFixtures

  # Build a manifest with the real planner, offline. Offline there is no Card
  # API, so the planner refuses to pretend it has a baseline - which is
  # exactly what the first test asserts.
  # Offline there is no Card API, so the planner honestly records
  # baseline_available=false and the applier refuses it (asserted directly in
  # test_a_manifest_the_planner_just_built_passes_every_applier_static_gate).
  # `baseline: :live` patches only those two fields so the OTHER gates can be
  # exercised on real planner output.
  def plan(dir, extra_env = {}, baseline: :offline)
    manifest = File.join(dir, "out_manifest.json")
    report = File.join(dir, "out_report.json")
    env = { "TRANSCRIPT_INGEST" => "1", "TRANSCRIPT_INGEST_DRY_RUN" => "1",
            "TRANSCRIPT_INGEST_DELTA" => "1", "TRANSCRIPT_EXPORT_DIR" => dir,
            "TRANSCRIPT_DELTA_MANIFEST" => manifest,
            "TRANSCRIPT_INGEST_REPORT" => report }.merge(extra_env)
    out, err, status = Open3.capture3(env, RbConfig.ruby, PLANNER)
    m = File.exist?(manifest) ? JSON.parse(File.read(manifest)) : nil
    if m && baseline == :live
      m["baseline"] = "live-content-hash"
      m["baseline_available"] = true
      m["blocking"]["no_live_baseline"] = 0
      File.write(manifest, JSON.pretty_generate(m))
    end
    [m, (File.exist?(report) ? JSON.parse(File.read(report)) : nil),
     out, err, status]
  end

  def test_the_manifest_requires_delta_mode
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      _m, _r, out, err, status = Open3.capture3(
        { "TRANSCRIPT_INGEST" => "1", "TRANSCRIPT_INGEST_DRY_RUN" => "1",
          "TRANSCRIPT_EXPORT_DIR" => dir,
          "TRANSCRIPT_DELTA_MANIFEST" => File.join(dir, "m.json") },
        RbConfig.ruby, PLANNER
      ).then { |o, e, s| [nil, nil, o, e, s] }
      refute status.success?, "a manifest without delta mode must abort"
      assert_match(/requires TRANSCRIPT_INGEST_DELTA=1/, out + err)
      refute File.exist?(File.join(dir, "m.json")),
             "the aborted run must not leave a manifest"
    end
  end

  def test_the_planner_still_refuses_delta_writes
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      out, err, status = Open3.capture3(
        { "TRANSCRIPT_INGEST" => "1", "TRANSCRIPT_INGEST_DELTA" => "1",
          "TRANSCRIPT_EXPORT_DIR" => dir },
        RbConfig.ruby, PLANNER
      )
      refute status.success?
      combined = out + err
      assert_match(/requires TRANSCRIPT_INGEST_DRY_RUN=1/, combined)
      # and it must point at the real write path rather than leaving the
      # operator to guess
      assert_match(/apply_transcript_delta\.rb/, combined)
    end
  end

  def test_the_manifest_declares_zero_destructive_operations
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m, = plan(dir)
      refute_nil m, "the planner must emit a manifest"
      assert_equal 0, m["deletes_in_scope"]
      assert_equal 0, m["trashes_in_scope"]
      assert_equal 0, m["renames_in_scope"]
      assert_equal 0, m["orphan_cleanup_in_scope"]
      assert_equal 0, m["stale_chunk_prunes_in_scope"]
      assert_equal false, m["destructive_path_exists"]
      assert_equal "local_loopback_only", m["target_environment"]
      assert_equal false, m["production_contacted"]
      assert_equal CONFIRM_TOKEN, m["confirm_token"]
      assert_equal 1, m["manifest_version"]
    end
  end

  def test_manifest_rows_are_creates_and_updates_only
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      write_export(dir, "b.json", transcript(id: "t2", name: "Retro"))
      m, = plan(dir)
      actions = m["rows"].map { |r| r["action"] }.uniq.sort
      assert_equal %w[create], actions,
                   "offline every row is a create; no other action may appear"
      assert_equal %w[create update], m["scope"]["actions_allowed"]
      m["rows"].each do |r|
        assert_includes %w[create update], r["action"]
        assert_equal "raw_data", r["type_code"]
        assert_match(/\A[0-9a-f]{64}\z/, r["desired_hash"])
        assert_match(/\A[0-9a-f]{64}\z/, r["source_sha256"])
      end
    end
  end

  def test_the_manifest_pins_each_rows_source_export_by_hash
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m, = plan(dir)
      row = m["rows"].first
      assert_equal "a.json", row["source_basename"]
      assert_equal Digest::SHA256.hexdigest(File.binread(File.join(dir, "a.json"))),
                   row["source_sha256"]
      assert_equal 1, m["export_files_pinned"]
    end
  end

  def test_the_manifests_desired_hash_is_reproducible_from_the_export
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m, = plan(dir)
      row = m["rows"].first
      rendered = planner_render(dir, "a.json", row["base_card"])
      match = rendered.find { |c| c["name"] == row["card_name"] }
      refute_nil match, "the renderer must produce the manifest's card"
      assert_equal row["desired_hash"], match["hash"],
                   "the applier re-renders and compares exactly this"
      assert_equal row["desired_chars"], match["chars"]
    end
  end

  def test_a_chunked_transcript_produces_an_index_row_and_chunk_rows
    Dir.mktmpdir do |dir|
      write_export(dir, "big.json", transcript(name: "Big", text: "x\n" * 40_000))
      m, = plan(dir)
      roles = m["rows"].map { |r| r["role"] }
      assert_includes roles, "index"
      assert_includes roles, "chunk"
      assert_equal 1, roles.count("index"), "exactly one index card per transcript"
      # chunk cards must be named under the index card, never beside it
      index = m["rows"].find { |r| r["role"] == "index" }
      m["rows"].select { |r| r["role"] == "chunk" }.each do |r|
        assert r["card_name"].start_with?("#{index['card_name']}+chunk-"),
               "#{r['card_name']} must be a child of the index card"
      end
    end
  end

  def test_the_manifest_names_the_preserve_set_rather_than_counting_it
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m, = plan(dir)
      p = m["preserve"]
      assert_equal "keep", p["policy"]
      assert_equal true, p["keep_stale_chunks"]
      assert_kind_of Array, p["stale_chunk_cards"]
      assert_equal p["stale_chunk_cards"].length, p["stale_chunk_cards_total"]
      assert_includes p["foreign_corpora"], "AGI 26"
      assert_includes p["protected_names"].join("|"), "Frag, EARTHwise, Magi"
    end
  end

  def test_the_keep_stale_policy_never_puts_a_prune_in_the_manifest
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      # both policies, since review mode is the one that *blocks* rather than
      # the one that prunes - neither may ever emit a prune
      ["1", "0"].each do |policy|
        m, = plan(dir, { "TRANSCRIPT_KEEP_STALE_CHUNKS" => policy })
        assert_equal 0, m["stale_chunk_prunes_in_scope"],
                     "policy=#{policy} must still declare zero prunes"
        assert_equal 0, m["deletes_in_scope"]
        assert_equal false, m["destructive_path_exists"]
      end
    end
  end

  def test_the_report_still_says_the_planner_has_no_write_path
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      _m, report, = plan(dir)
      wr = report["write_readiness"]
      assert_equal false, wr["write_path_implemented"],
                   "ingest_transcripts.rb itself must never claim a write path"
      assert_equal "scripts/apply_transcript_delta.rb", wr["delta_applier"]
      assert_equal true, wr["delta_manifest_emitted"]
    end
  end

  def test_the_manifest_scope_assertions_are_self_consistent
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      write_export(dir, "b.json", transcript(id: "t2", name: "Retro"))
      m, = plan(dir)
      s = m["scope"]
      assert_equal true, s["all_rows_under_parent"]
      assert_equal true, s["unique_card_names"]
      assert_equal true, s["every_row_has_desired_hash"]
      assert_equal true, s["every_update_has_live_hash"]
      assert_equal true, s["every_create_has_no_live_hash"]
      assert_empty s["protected_rows_in_write_set"]
      assert_empty s["foreign_corpus_rows_in_write_set"]
      assert_equal m["rows"].length, m["write_set"]["total"]
    end
  end

  def test_a_manifest_the_planner_just_built_passes_every_applier_static_gate
    # The end-to-end contract: planner output is applier input. Offline the
    # applier stops at the Card-API gate, which means every gate before it
    # passed on a real planner-built manifest.
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      write_export(dir, "big.json", transcript(id: "t2", name: "Big",
                                               text: "y\n" * 40_000))
      m, = plan(dir)
      path = File.join(dir, "out_manifest.json")
      sha = Digest::SHA256.hexdigest(File.binread(path))

      # offline the planner has no baseline, so it must be refused for that
      # reason and no other
      report, = run_applier(
        "TRANSCRIPT_DELTA_MANIFEST" => path, "TRANSCRIPT_DELTA_WRITE" => "1",
        "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha,
        "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
        "DECK_ORIGIN" => "http://127.0.0.1:3100", "TRANSCRIPT_EXPORT_DIR" => dir
      )
      assert_equal false, m["baseline_available"],
                   "offline planning has no live baseline"
      assert_match(/no live baseline/, report["halt_reason"].to_s)
      assert_zero_writes report, "offline planner manifest"

      # with the baseline flags patched to what a real decko-runner plan
      # produces, every remaining static gate must pass
      m["baseline"] = "live-content-hash"
      m["baseline_available"] = true
      m["blocking"]["no_live_baseline"] = 0
      path2, sha2 = write_manifest(dir, m, basename: "patched.json")
      report2, = run_applier(
        "TRANSCRIPT_DELTA_MANIFEST" => path2, "TRANSCRIPT_DELTA_WRITE" => "1",
        "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha2,
        "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
        "DECK_ORIGIN" => "http://127.0.0.1:3100", "TRANSCRIPT_EXPORT_DIR" => dir
      )
      g = report2["gates"]
      assert_equal true, g["loopback_origin"]
      assert_equal true, g["manifest_static_valid"]
      assert_equal true, g["manifest_sha_matched"]
      assert_equal true, g["confirm_token_matched"]
      assert_equal true, g["rerender_matches_manifest"],
                   "every row of a real planner manifest must re-render exactly"
      assert_match(/no Card API/, report2["halt_reason"].to_s)
      assert_zero_writes report2, "patched planner manifest"
    end
  end
end

# ------------------------------------------------------------
# 7. Idempotent resume classification - THE REAL CLASSIFIER
# ------------------------------------------------------------
# The applier's phase-1 classifier is the part that decides skip vs write vs
# halt. These tests call it DIRECTLY (see the lib-only load at the top of this
# file) rather than reimplementing its decision table, which is the only way
# the assertions can fail when the applier changes.
class TestResumeClassification < Minitest::Test
  include DeltaFixtures

  # No local decision table. This is the shipped function.
  def classify(action:, live:, manifest_live:, desired:, type: "RawData")
    apply_classify_row(
      action: action, live_present: !live.nil?, live_hash: live,
      manifest_live_hash: manifest_live, desired_hash: desired,
      live_type_name: (live.nil? ? nil : type)
    )
  end

  def test_the_loaded_applier_really_is_the_shipped_classifier
    # Guards against the lib-only load silently not happening, which would
    # make every test below pass against a NoMethodError-free accident.
    # Top-level defs land as PRIVATE methods on Object, so the private-aware
    # form of respond_to? is the one that answers this question.
    assert respond_to?(:apply_classify_row, true),
           "the applier was not loaded in lib-only mode"
    assert respond_to?(:apply_scope_violations, true)
    assert_equal APPLY_SAFE_STATES,
                 %w[pending_create pending_update already_applied]
  end

  def test_an_absent_card_is_a_pending_create
    assert_equal "pending_create",
                 classify(action: "create", live: nil, manifest_live: nil, desired: "d")
  end

  def test_a_create_whose_card_already_holds_the_desired_content_is_skipped
    assert_equal "already_applied",
                 classify(action: "create", live: "d", manifest_live: nil, desired: "d")
  end

  def test_a_create_colliding_with_unrelated_content_halts
    assert_equal "collision_create",
                 classify(action: "create", live: "x", manifest_live: nil, desired: "d")
  end

  def test_an_update_at_its_planned_baseline_is_pending
    assert_equal "pending_update",
                 classify(action: "update", live: "l", manifest_live: "l", desired: "d")
  end

  def test_an_update_already_at_the_desired_content_is_skipped
    assert_equal "already_applied",
                 classify(action: "update", live: "d", manifest_live: "l", desired: "d")
  end

  def test_an_update_whose_baseline_moved_is_drift_and_halts
    assert_equal "drift_update",
                 classify(action: "update", live: "zzz", manifest_live: "l", desired: "d")
  end

  def test_an_update_whose_card_vanished_halts
    assert_equal "vanished_update",
                 classify(action: "update", live: nil, manifest_live: "l", desired: "d")
  end

  def test_an_unknown_action_is_never_classified_as_safe
    state = classify(action: "delete", live: "l", manifest_live: "l", desired: "d")
    assert_equal "unknown_action", state
    refute_includes APPLY_SAFE_STATES, state
  end

  # ---- type_drift ------------------------------------------------------
  # A card whose type changed under us is not safe to write through even when
  # the content hash still lines up: the type change is someone else's edit,
  # and writing would silently revert part of it.
  def test_an_update_whose_card_is_no_longer_raw_data_is_type_drift
    assert_equal "type_drift",
                 classify(action: "update", live: "l", manifest_live: "l",
                          desired: "d", type: "Basic")
  end

  def test_an_already_applied_row_whose_type_changed_is_still_type_drift
    assert_equal "type_drift",
                 classify(action: "update", live: "d", manifest_live: "l",
                          desired: "d", type: "Pointer")
  end

  def test_a_create_colliding_with_a_non_raw_data_card_still_halts
    # collision_create is already unsafe; the type check must not downgrade it
    # to something safe.
    state = classify(action: "create", live: "x", manifest_live: nil,
                     desired: "d", type: "Basic")
    refute_includes APPLY_SAFE_STATES, state
  end

  def test_type_drift_is_recognised_case_and_space_insensitively
    ["RawData", "raw data", "Raw Data", "RAWDATA"].each do |ok|
      assert_equal "pending_update",
                   classify(action: "update", live: "l", manifest_live: "l",
                            desired: "d", type: ok),
                   "#{ok.inspect} must count as RawData"
    end
    ["Basic", "Pointer", "RawDataArchive", "", "File"].each do |bad|
      assert_equal "type_drift",
                   classify(action: "update", live: "l", manifest_live: "l",
                            desired: "d", type: bad),
                   "#{bad.inspect} must not count as RawData"
    end
  end

  def test_every_unsafe_state_the_classifier_can_emit_is_outside_the_safe_list
    emitted = [
      classify(action: "create", live: "x", manifest_live: nil, desired: "d"),
      classify(action: "update", live: nil, manifest_live: "l", desired: "d"),
      classify(action: "update", live: "zzz", manifest_live: "l", desired: "d"),
      classify(action: "update", live: "l", manifest_live: "l", desired: "d",
               type: "Basic"),
      classify(action: "nonsense", live: "l", manifest_live: "l", desired: "d")
    ].uniq
    assert_equal 5, emitted.length, "each unsafe case must have its own state"
    emitted.each { |s| refute_includes APPLY_SAFE_STATES, s }
  end

  def test_only_three_states_are_safe_to_proceed_from
    src = File.read(APPLIER)
    assert_match(/safe_states\s*=\s*%w\[pending_create pending_update already_applied\]/,
                 src, "the safe-state list must be exactly these three")
    assert_match(/APPLY_SAFE_STATES\s*=/, src,
                 "the classifier must publish its safe-state list for the tests")
  end

  def executable_offset(needle)
    offset = 0
    File.readlines(APPLIER).each do |l|
      return offset if !l.strip.start_with?("#") && l.include?(needle)

      offset += l.length
    end
    nil
  end

  def test_the_live_sweep_uses_the_classifier_rather_than_an_inline_table
    src = File.read(APPLIER)
    assert_match(/apply_classify_row\(/, src)
    # the sweep must call it, not re-decide
    assert_operator executable_offset("def apply_classify_row"), :<,
                    executable_offset("plan = rows.map"),
                    "the classifier must be defined before the sweep uses it"
  end

  def test_an_unsafe_row_halts_the_whole_run_not_just_that_row
    i_unsafe = executable_offset("phase-1 sweep found")
    refute_nil i_unsafe
    assert_operator i_unsafe, :<, executable_offset("DRY RUN (no write gate set)"),
                    "the all-or-nothing sweep must precede the dry-run exit"
    assert_operator i_unsafe, :<, executable_offset("Card.create!"),
                    "the all-or-nothing sweep must precede any write"
  end

  def test_the_pre_write_reread_can_still_skip_an_already_applied_row
    # resume safety: between phase 1 and the write, a row may have been
    # applied by an earlier interrupted run
    assert_match(/skip_already_applied/, src_text)
    assert_operator executable_offset("skip_already_applied"), :<,
                    executable_offset("Card.create!"),
                    "the pre-write skip must be tested before the create callsite"
  end

  def src_text
    @src_text ||= File.read(APPLIER)
  end
end

# ------------------------------------------------------------
# 7b. Write-scope invariants, RE-DERIVED by the applier
# ------------------------------------------------------------
# Blocker: the applier used to accept the manifest's own `scope` booleans as
# proof of the invariants they describe. A stale or hand-edited manifest could
# therefore claim all_rows_under_parent=true while naming a card anywhere in
# the deck, and - given a matching desired_hash - have it written.
#
# These tests drive the applier's own scope functions with manifests that lie.
class TestDerivedWriteScope < Minitest::Test
  include DeltaFixtures

  def row(name, base: nil, action: "create")
    { "card_name" => name, "base_card" => (base || name), "action" => action }
  end

  def reasons_for(rows)
    apply_scope_violations(rows).map { |v| v[:reason] }
  end

  def test_a_row_under_the_parent_is_in_scope
    assert_empty apply_scope_violations([row("#{PARENT}+Standup+2026-01-02")])
  end

  def test_a_chunk_row_under_its_base_card_is_in_scope
    base = "#{PARENT}+Standup+2026-01-02"
    assert_empty apply_scope_violations([row("#{base}+chunk-3", base: base)])
  end

  # The specific attack in the blocker report.
  def test_a_row_whose_base_card_is_a_set_card_is_refused
    rs = reasons_for([row("*all", base: "*all")])
    assert_includes rs.join("|"), "reserved name part"
    assert_includes rs.join("|"), "not a descendant"
  end

  def test_a_row_naming_a_card_outside_the_parent_is_refused
    ["Basic", "*all+*self", "Home", "Raw Data", "Raw Data+other+x",
     "Some Other Parent+transcripts+x"].each do |name|
      refute_empty apply_scope_violations([row(name)]),
                   "#{name.inspect} must be out of scope"
    end
  end

  def test_the_parent_card_itself_is_not_a_writable_target
    refute_empty apply_scope_violations([row(PARENT)]),
                 "the parent card is not a transcript card"
  end

  def test_a_row_whose_name_is_not_derivable_from_its_base_card_is_refused
    base = "#{PARENT}+Standup+2026-01-02"
    # a sibling, a cousin, and a bogus chunk suffix
    [["#{PARENT}+Other+2026-01-02", "neither base_card nor"],
     ["#{base}+appendix", "neither base_card nor"],
     ["#{base}+chunk-x", "neither base_card nor"]].each do |name, expected|
      rs = reasons_for([row(name, base: base)])
      assert_includes rs.join("|"), expected, "#{name.inspect} must be refused"
    end
  end

  def test_a_protected_card_is_refused_even_when_the_manifest_omits_it
    # The applier's protected list is its own config, so a manifest with an
    # empty preserve.protected_names cannot shrink it.
    protected_name =
      "#{PARENT}+Elowyn AI Meeting - Frag, EARTHwise, Magi+2026-03-03"
    rs = reasons_for([row(protected_name)])
    assert_includes rs.join("|"), "protected card"
  end

  def test_a_foreign_corpus_card_is_refused_by_derivation
    rs = reasons_for([row("#{PARENT}+AGI 26+Opening Keynote")])
    assert_includes rs.join("|"), "foreign corpus"
  end

  def test_a_real_series_whose_name_merely_starts_like_a_corpus_is_in_scope
    # "AGI 26" is anchored to a whole name part, so this must NOT match.
    assert_empty apply_scope_violations([row("#{PARENT}+AGI Strategy Biweekly+2026-01-02")])
  end

  def test_duplicate_card_names_are_refused_by_key_not_by_string
    base = "#{PARENT}+Standup+2026-01-02"
    rs = reasons_for([row(base), row(base.sub("Raw Data", "RawData"))])
    assert_includes rs.join("|"), "duplicate card name key"
  end

  def test_scope_derivation_ignores_what_the_manifest_asserts_about_itself
    # Exactly the blocker: a row that is out of scope, in a manifest whose own
    # scope block swears everything is fine.
    rows = [row("*all", base: "*all").merge("manifest_says" => "fine")]
    refute_empty apply_scope_violations(rows)
  end

  def test_the_applier_does_not_read_scope_booleans_as_proof
    src = File.read(APPLIER)
    # the derived check must exist and must run on the rows
    assert_match(/def apply_scope_violations/, src)
    assert_match(/apply_gate_derived_scope!/, src)
    # and the manifest's claims must be documented as fail-closed only
    assert_match(/FAIL-CLOSED ONLY/, src)
  end

  def test_the_parent_is_configuration_not_manifest_content
    src = File.read(APPLIER)
    # The scope inputs must come from ENV, not from the manifest. Whitespace
    # is permissive because these are multi-line ENV.fetch calls.
    { "APPLY_PARENT_CARD" => "TRANSCRIPT_DELTA_PARENT",
      "APPLY_PROTECTED_NAMES" => "TRANSCRIPT_DELTA_PROTECTED",
      "APPLY_FOREIGN_CORPORA" => "TRANSCRIPT_FOREIGN_CORPORA" }.each do |const, var|
      assert_match(/#{const}\s*=\s*ENV\.fetch\(\s*"#{var}"/, src,
                   "#{const} must be read from #{var}")
    end
    # ...and the derived values must be reported, so a reviewer can see what
    # scope the run actually used rather than what the manifest claimed.
    assert_match(/derived_scope/, src)
  end

  def test_the_ancestor_chain_names_the_cards_decko_would_create_implicitly
    assert_equal ["#{PARENT}+A", "#{PARENT}+A+B"],
                 apply_ancestor_chain("#{PARENT}+A+B+chunk-1")
    assert_empty apply_ancestor_chain("#{PARENT}+A")
  end

  def test_a_manifest_naming_a_different_parent_card_is_refused_end_to_end
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m = manifest_for(dir, "a.json", "#{PARENT}+Standup+2026-01-02")
      m["parent_card"] = "Some Other Parent"
      path, sha = write_manifest(dir, m)
      report, _o, _e, status = run_applier(
        "TRANSCRIPT_DELTA_MANIFEST" => path, "TRANSCRIPT_DELTA_WRITE" => "1",
        "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha,
        "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
        "DECK_ORIGIN" => "http://127.0.0.1:3100", "TRANSCRIPT_EXPORT_DIR" => dir
      )
      refute status.success?
      assert_match(/is not the configured write parent/, report["halt_reason"].to_s)
      assert_zero_writes report, "manifest with a foreign parent"
    end
  end

  def test_an_out_of_scope_row_is_refused_end_to_end_despite_true_assertions
    Dir.mktmpdir do |dir|
      write_export(dir, "a.json", transcript)
      m = manifest_for(dir, "a.json", "#{PARENT}+Standup+2026-01-02")
      # the blocker's exact shape: base_card "*all", every scope boolean true
      m["rows"][0]["base_card"] = "*all"
      m["rows"][0]["card_name"] = "*all"
      path, sha = write_manifest(dir, m)
      report, _o, _e, status = run_applier(
        "TRANSCRIPT_DELTA_MANIFEST" => path, "TRANSCRIPT_DELTA_WRITE" => "1",
        "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha,
        "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
        "DECK_ORIGIN" => "http://127.0.0.1:3100", "TRANSCRIPT_EXPORT_DIR" => dir
      )
      refute status.success?
      assert_equal true, m["scope"]["all_rows_under_parent"],
                   "the manifest must still be asserting that it is fine"
      assert_match(/write-scope check/, report["halt_reason"].to_s)
      assert_zero_writes report, "out-of-scope row with true assertions"
      assert_operator report["derived_scope"]["violation_count"], :>, 0
    end
  end
end

# ------------------------------------------------------------
# 7c. Cards Decko invents: the auto-created name-part guard
# ------------------------------------------------------------
# Blocker: creating "<parent>+Series+2026-01-02" does not create one card. A
# Decko compound card is filed under BOTH of its name parts, so Decko also
# materialises the missing compound left card AND an empty card for each
# SIMPLE name part it has never seen ("Series", "2026-01-02"). The simple ones
# have no left card at all, so no ancestry gate describes them, and the
# aggregate card-count invariant used to absorb them with a TOLERANCE BAND
# (growth >= creates && growth <= creates + ancestors). Any card appearing
# inside that band - a concurrent editor's card, a hook's card, a card with
# content - was waved through by arithmetic.
#
# These tests drive the applier's OWN enumeration and refusal functions, so
# the decision table under test is the shipped one, and then prove the same
# refusals end to end against a stub deck that actually invents those cards.
class TestAutocreatedNamePartGuard < Minitest::Test
  include DeltaFixtures

  ROW_NAME  = "#{PARENT}+Standup+2026-01-02".freeze
  COMPOUND  = "#{PARENT}+Standup".freeze
  PROTECTED = "#{PARENT}+Elowyn AI Meeting - Frag, EARTHwise, Magi+2026-03-03".freeze

  def rows(*names)
    names.map { |n| { "card_name" => n, "base_card" => n, "action" => "create" } }
  end

  # Every name the applier says Decko may invent for the one-row plan.
  def expected
    @expected ||= apply_expected_autocreated_names(rows(ROW_NAME), [COMPOUND])
  end

  # The shipped refusal function, with only the property under test varied.
  # Defaults describe the card Decko really does invent: empty, RichText.
  def refusal(name: "Standup", content: "", type_name: "RichText",
              trash: false, expected_names: nil)
    apply_autocreated_refusal(
      name: name, content: content, type_name: type_name, trash: trash,
      expected_names: (expected_names || expected)
    )
  end

  # ---- enumeration: the expectation is built BEFORE any write ---------
  def test_the_expected_set_names_the_simple_parts_decko_would_invent
    # Both simple parts and the compound left card, shallowest first - and
    # NOT "Raw Data"/"transcripts", which must already exist because the
    # parent card does.
    assert_equal ["2026-01-02", "Standup", COMPOUND], expected
    refute_includes expected, "Raw Data"
    refute_includes expected, "transcripts"
  end

  def test_a_chunk_row_expects_its_chunk_suffix_as_a_name_part_too
    chunk = "#{ROW_NAME}+chunk-1"
    names = apply_expected_autocreated_names(rows(chunk), [COMPOUND, ROW_NAME])
    assert_includes names, "chunk-1", "Decko invents a card for 'chunk-1' too"
    assert_includes names, "Standup"
    assert_includes names, ROW_NAME
  end

  def test_the_expected_set_is_derived_from_the_rows_not_from_the_manifest
    # A manifest cannot widen the allow-list: the only inputs are the rows
    # and the implicit ancestors the applier itself derived.
    noisy = rows(ROW_NAME).map { |r| r.merge("manifest_says_also_fine" => "Hacked") }
    assert_equal expected, apply_expected_autocreated_names(noisy, [COMPOUND])
  end

  # ---- 1. the allowed case -------------------------------------------
  def test_an_empty_expected_name_part_is_allowed
    assert_nil refusal(name: "Standup"), "an empty RichText name part is allowed"
    assert_nil refusal(name: "2026-01-02")
    assert_nil refusal(name: COMPOUND)
    # Basic is the other type Decko uses for a part it invents.
    assert_nil refusal(name: "Standup", type_name: "Basic")
    # Type matching is case/space-insensitive, like every other type check.
    assert_nil refusal(name: "Standup", type_name: "rich text")
  end

  # ---- 2. a non-empty auto-created card ------------------------------
  def test_a_non_empty_auto_created_card_is_refused
    r = refusal(name: "Standup", content: "someone typed here")
    refute_nil r, "a card with content is not a card Decko invented"
    assert_match(/18 char\(s\) of content/, r)
    # One character is enough.
    assert_match(/1 char\(s\) of content/, refusal(name: "Standup", content: "x"))
  end

  # ---- 3. the wrong type ---------------------------------------------
  def test_an_auto_created_card_of_the_wrong_type_is_refused
    ["Pointer", "Search", "Cardtype", "File", "Image", "Set", ""].each do |t|
      r = refusal(name: "Standup", type_name: t)
      refute_nil r, "type #{t.inspect} must be refused"
      assert_match(/not an empty structural type/, r)
    end
  end

  def test_an_auto_created_raw_data_card_is_refused
    # The sharpest case: RawData is the type this applier writes. A transcript
    # card must never come into existence as a side effect of another row.
    r = refusal(name: "Standup", type_name: "RawData")
    assert_match(/RawData, which this applier only ever writes as a planned row/, r)
    # ...and not by spelling.
    assert_match(/RawData/, refusal(name: "Standup", type_name: "raw data"))
    refute_includes APPLY_AUTOCREATED_TYPES, "rawdata",
                    "RawData must never be an auto-creatable type"
  end

  # ---- 4. a card nothing in the plan needed --------------------------
  def test_a_card_no_planned_row_needed_is_refused
    ["Some Other Card", "#{PARENT}+Other Meeting+2026-02-02", "Home",
     "Standup Notes", "2026-01-03"].each do |name|
      r = refusal(name: name)
      refute_nil r, "#{name.inspect} must be refused"
      assert_match(/not a name part any planned row needed/, r)
    end
  end

  def test_a_reserved_or_empty_name_is_refused_before_anything_else
    assert_match(/reserved\/structural name/, refusal(name: "*all"))
    assert_match(/reserved\/structural name/, refusal(name: "~1234"))
    assert_match(/no usable name/, refusal(name: ""))
    # ...even when something put it in the expected set.
    assert_match(/reserved\/structural name/,
                 refusal(name: "*all", expected_names: ["*all"]))
  end

  # ---- 5. a protected card -------------------------------------------
  def test_a_protected_card_is_refused_even_when_it_is_an_expected_name
    # Belt and braces: even if a plan somehow listed a protected card as a
    # name part it needed, the guard still refuses it.
    r = refusal(name: PROTECTED, expected_names: [PROTECTED])
    assert_match(/protected card/, r)
  end

  # ---- 6. a foreign corpus card --------------------------------------
  def test_a_foreign_corpus_card_is_refused_both_ways_round
    # As a descendant name...
    foreign = "#{PARENT}+AGI 26+Opening Keynote"
    assert_match(/foreign corpus AGI 26/,
                 refusal(name: foreign, expected_names: [foreign]))
    # ...and as the bare simple part that simply IS a corpus root, which is
    # exactly the shape Decko invents when filing "<parent>+AGI 26+x".
    assert_match(/foreign corpus AGI 26/,
                 refusal(name: "AGI 26", expected_names: ["AGI 26"]))
    # A real series that merely starts like a corpus is still allowed.
    assert_nil refusal(name: "AGI Strategy Biweekly",
                       expected_names: ["AGI Strategy Biweekly"])
  end

  # ---- 7. a trashed card ---------------------------------------------
  def test_a_trashed_card_is_refused
    # Defence in depth: apply_live_card already hides trashed cards, so this
    # branch should be unreachable in the live loop. It is asserted anyway so
    # a future reader that stops filtering trash cannot silently accept one.
    assert_match(/is trashed/, refusal(name: "Standup", trash: true))
    assert_match(/is trashed/, refusal(name: COMPOUND, trash: true))
  end

  # ---- 8. regression: no tolerance band anywhere ---------------------
  def test_the_card_count_invariant_is_an_exact_equality_not_a_tolerance_band
    src = File.read(APPLIER)
    # The old shape: growth >= creates && growth <= creates + ancestors.
    refute_match(/card_growth\s*>=/, src,
                 "a lower-bound tolerance on card growth must not come back")
    refute_match(/card_growth\s*<=/, src,
                 "an upper-bound tolerance on card growth must not come back")
    # The new shape: an exact equality against the VERIFIED set.
    assert_match(/card_growth\s*==\s*explained/, src)
    assert_match(/explained\s*=\s*APPLY_REPORT\[:creates_performed\]\s*\+\s*
                  autocreated_verified\.length/x, src)
    # ...and the allow-list the act audit uses must be the verified ids, not
    # the merely-expected names.
    assert_match(/allowed\s*=\s*\(written_ids\s*\+\s*autocreated_ids\)/, src)
    refute_match(/allowed\s*=\s*\(written_ids\s*\+\s*ancestor_ids\)/, src)
  end

  def test_the_expectation_is_built_before_the_write_loop_not_after
    src = File.read(APPLIER)
    enumerate = src.index("expected_autocreated = apply_expected_autocreated_names")
    snapshot  = src.index("autocreatable_absent = expected_autocreated.reject")
    verify    = src.index("autocreated_refused <<")
    refute_nil enumerate
    refute_nil snapshot
    refute_nil verify
    assert_operator enumerate, :<, verify,
                    "the allow-list must be enumerated before the apply verifies it"
    assert_operator snapshot, :<, verify,
                    "absence must be snapshotted before the write, not inferred after"
  end

  def test_every_refusal_reason_is_a_property_of_the_card_not_a_count
    # The guard must never be able to say "the number worked out".
    src = File.read(APPLIER)
    body = src[src.index("def apply_autocreated_refusal")...src.index("# ============================================================\n# Gates")]
    refute_match(/count|length\s*[<>]|tolerance/, body.sub(/content\.to_s\.length/, ""),
                 "the refusal decision must not consult a count")
  end
end

# ------------------------------------------------------------
# 7d. The same guard, end to end against a deck that invents cards
# ------------------------------------------------------------
# The stub deck now reproduces Decko's two side effects of a create: the
# missing compound left card, and an empty card per unseen simple name part.
# STUB_STRUCTURAL_TYPE / STUB_STRUCTURAL_CONTENT make it invent a card the
# applier must REFUSE, and STUB_SURPRISE_CARD makes it invent one no planned
# row ever named - the case the old tolerance band absorbed.
class TestAutocreatedNamePartGuardAgainstStubDeck < Minitest::Test
  include DeltaFixtures

  def setup
    @dir = Dir.mktmpdir
    write_export(@dir, "a.json", transcript)
    @base = "#{PARENT}+Standup+2026-01-02"
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def gated_env
    m = manifest_for(@dir, "a.json", @base)
    path, sha = write_manifest(@dir, m)
    { "TRANSCRIPT_DELTA_MANIFEST" => path,
      "TRANSCRIPT_DELTA_WRITE" => "1",
      "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha,
      "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
      "DECK_ORIGIN" => "http://127.0.0.1:3100",
      "TRANSCRIPT_EXPORT_DIR" => @dir }
  end

  def run_with(stub_env = {})
    run_applier_on_stub_deck(gated_env.merge(stub_env),
                             deck: deck_with_parent, allow_writes: true)
  end

  def test_one_create_really_does_bring_several_cards_into_existence
    # The premise. Without this the guard tests below would be checking a
    # scenario the harness never produces.
    report, log, _o, _e, status = run_with
    assert status.success?, "the healthy case must still apply"
    assert_equal 1, log["write_ops"], "the applier made exactly one write call"
    assert_equal 3, log["autovivified"].length,
                 "the deck invented the compound left card and two name parts"
    assert_equal 4, report["final"]["cards_live_delta"],
                 "so the live card count grew by four, not one"
  end

  def test_the_verified_name_parts_explain_the_growth_exactly
    report, _log, _o, _e, status = run_with
    assert status.success?
    a = report["autocreated"]
    assert_equal 3, a["expected"], "two simple parts plus one compound ancestor"
    assert_equal 3, a["absent_before"]
    assert_equal 3, a["verified"]
    assert_empty a["refused"]
    assert_equal ["2026-01-02", "Standup", "#{PARENT}+Standup"].sort,
                 a["names"].sort
    assert_equal 1, report["creates_performed"]
    assert_equal report["creates_performed"] + a["verified"],
                 report["final"]["cards_live_delta"],
                 "growth must equal creates + VERIFIED parts, exactly"
  end

  def test_a_non_empty_card_decko_invents_halts_the_apply
    report, log, _o, _e, status = run_with("STUB_STRUCTURAL_CONTENT" => "not empty")
    refute status.success?, "a name part with content must halt"
    assert_match(/not empty name parts Decko invented/, report["halt_reason"].to_s)
    assert_match(/char\(s\) of content/, report["autocreated"]["refused"].to_json)
    assert_equal 0, log["forbidden_ops"]
    assert_equal 0, report["updates_performed"],
                  "the halt must not have been papered over by a second write"
  end

  def test_a_raw_data_card_decko_invents_halts_the_apply
    report, _log, _o, _e, status = run_with("STUB_STRUCTURAL_TYPE" => "RawData")
    refute status.success?
    assert_match(/not empty name parts Decko invented/, report["halt_reason"].to_s)
    assert_match(/only ever writes as a planned row/,
                 report["autocreated"]["refused"].to_json)
  end

  def test_a_wrongly_typed_card_decko_invents_halts_the_apply
    report, _log, _o, _e, status = run_with("STUB_STRUCTURAL_TYPE" => "Pointer")
    refute status.success?
    assert_match(/not an empty structural type/,
                 report["autocreated"]["refused"].to_json)
  end

  def test_a_card_no_row_named_halts_even_though_it_is_empty_and_structural
    # The regression the tolerance band allowed through: an empty RichText
    # card appearing mid-apply that no planned row ever needed. It is not in
    # the pre-enumerated allow-list, so the EXACT card-count equality catches
    # it even though every individual property looks innocent.
    report, log, _o, _e, status = run_with(
      "STUB_SURPRISE_CARD" => "#{PARENT}+Concurrent Editor Card"
    )
    refute status.success?, "an unexplained card must halt the apply"
    assert_match(/live card count moved by 5/, report["halt_reason"].to_s)
    assert_match(/1 create\(s\) were performed plus 3 verified empty name part/,
                 report["halt_reason"].to_s)
    assert_equal 3, report["autocreated"]["verified"],
                 "the three real name parts are still verified..."
    assert_empty report["autocreated"]["refused"],
                 "...and the surprise card is caught by the count, not by them"
    assert_equal 1, log["write_ops"], "the applier itself still wrote once"
  end

  def test_the_act_audit_allow_list_is_the_verified_parts_only
    report, _log, _o, _e, status = run_with
    assert status.success?
    audit = report["act_audit"]
    assert_equal "checked", audit["status"]
    assert_empty audit["unexpected_card_ids"]
    assert_equal 3, audit["autocreated_card_ids"].length,
                 "the allow-list must name the verified parts explicitly"
  end

  def test_a_dry_run_reports_what_decko_would_invent_without_writing
    env = gated_env
    env.delete("TRANSCRIPT_DELTA_WRITE")
    report, log, _o, _e, status = run_applier_on_stub_deck(
      env, deck: deck_with_parent, allow_writes: true
    )
    assert status.success?
    assert_equal "dry_run", report["mode"]
    assert_equal 3, report["derived_scope"]["expected_autocreated_names"].length
    assert_equal 3, report["derived_scope"]["expected_autocreated_absent"]
    assert_proven_zero_writes report, log, "autocreation dry run"
  end
end

# ------------------------------------------------------------
# 8. Readback and preservation verification is planned
# ------------------------------------------------------------
class TestReadbackAndPreservation < Minitest::Test
  def src
    @src ||= File.read(APPLIER)
  end

  # Offset of the first EXECUTABLE occurrence: the file's header comment names
  # Card.create! while documenting what the applier may do.
  def executable_offset(needle)
    offset = 0
    File.readlines(APPLIER).each do |l|
      return offset if !l.strip.start_with?("#") && l.include?(needle)

      offset += l.length
    end
    nil
  end

  def test_every_write_is_followed_by_a_readback_before_the_next_row
    assert_match(/per-row readback/, src)
    # the readback must compare the hash, the char count, the type and trash
    assert_match(/post-write: .*content hash/, src)
    assert_match(/post-write: .*char count mismatch/, src)
    assert_match(/post-write: .*is not RawData/, src)
    assert_match(/post-write: .*is trashed/, src)
  end

  def test_the_preserve_set_is_captured_before_and_compared_after
    i_before = src.index("preserve_before =")
    i_after = src.index("preserve-set card(s) changed")
    refute_nil i_before
    refute_nil i_after
    create_at = executable_offset("Card.create!")
    assert_operator i_before, :<, create_at,
                    "the preserve set must be captured before the first write"
    assert_operator create_at, :<, i_after,
                    "the preserve set must be re-read after the writes"
  end

  def test_aggregate_invariants_cover_trash_and_card_count
    assert_match(/cards were trashed during apply/, src)
    assert_match(/live card count moved by/, src)
    assert_match(/performed a delete\/rename\/trash/, src)
  end

  def test_the_report_is_written_in_an_ensure_block
    # The run block is nested inside `unless APPLY_LIB_ONLY`, so the ensure is
    # indented; anchoring to column 0 would silently stop finding it.
    ensure_i = src.index(/^\s*ensure$/)
    refute_nil ensure_i, "the applier must write its report from an ensure block"
    assert_operator ensure_i, :<, src.index("File.write(APPLY_REPORT_PATH"),
                    "the report write must sit inside the ensure block"
  end

  def test_a_refusal_exits_non_zero
    assert_match(/exit\(1\) if APPLY_REPORT\[:halted\]/, src,
                 "a refusal must not look like success to a wrapper")
  end
end

# ------------------------------------------------------------
# 9. Positive zero-write proof, against a recording stub deck
# ------------------------------------------------------------
# Blocker: the refusal probes above prove zero writes only from the applier's
# own counters, and offline they never reach the write path at all (no Card
# API). "Zero writes" was therefore the absence of an opportunity.
#
# These tests boot a fake deck (scripts/tests/support/stub_card_deck.rb) that
# RECORDS every mutating call it receives - create, update, and the forbidden
# set (destroy/delete/trash=/save/rename/update_column/raw SQL) - and then run
# the real applier against it. The applier now walks its whole live phase, so
# an empty recorder is evidence it declined to write, not evidence it never
# got the chance. A forbidden call is recorded AND raised, so a future edit
# that introduces one fails loudly.
class TestZeroWriteProofAgainstStubDeck < Minitest::Test
  include DeltaFixtures

  def setup
    @dir = Dir.mktmpdir
    write_export(@dir, "a.json", transcript)
    @base = "#{PARENT}+Standup+2026-01-02"
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def manifest(action: "create", live_hash: nil, overrides: {})
    m = manifest_for(@dir, "a.json", @base, action: action,
                                     live_hash: live_hash, overrides: overrides)
    write_manifest(@dir, m)
  end

  def base_env(path, sha)
    { "TRANSCRIPT_DELTA_MANIFEST" => path,
      "TRANSCRIPT_DELTA_WRITE" => "1",
      "TRANSCRIPT_DELTA_MANIFEST_SHA" => sha,
      "TRANSCRIPT_DELTA_CONFIRM" => CONFIRM_TOKEN,
      "DECK_ORIGIN" => "http://127.0.0.1:3100",
      "TRANSCRIPT_EXPORT_DIR" => @dir }
  end

  # The desired content for the one planned card, so a deck fixture can be
  # built in the already-applied or drifted state.
  def desired
    @desired ||= planner_render(@dir, "a.json", @base).first
  end

  # ---- the harness itself must be trustworthy -------------------------
  def test_the_stub_deck_records_a_write_when_one_is_actually_attempted
    # Control case. Without this, an empty recorder could just mean the
    # recorder is broken. Here the applier IS permitted to write, so the
    # recorder must show exactly one create and nothing else.
    path, sha = manifest
    report, log, _o, _e, status = run_applier_on_stub_deck(
      base_env(path, sha), deck: deck_with_parent, allow_writes: true
    )
    assert status.success?, "a fully gated apply against the stub must succeed"
    assert_equal 1, log["write_ops"], "the recorder must see the create"
    assert_equal "create", log["mutations"].first["op"]
    assert_equal @base, log["mutations"].first["card"]
    assert_equal 0, log["forbidden_ops"]
    assert_equal 1, report["creates_performed"]
    assert_equal 1, report["verified"]
  end

  def test_the_stub_deck_reaches_the_live_phase_at_all
    # Proves the Card-API gate passed, i.e. the refusal tests below are
    # refusing from inside the live phase rather than before it.
    path, sha = manifest
    report, = run_applier_on_stub_deck(base_env(path, sha), deck: deck_with_parent,
                                                            allow_writes: true)
    assert_equal true, report["gates"]["card_api_available"]
    assert_equal true, report["gates"]["live_scope_valid"]
    refute_nil report["baseline"]["cards_live"]
  end

  # ---- refusal probes, now with the write path reachable --------------
  def test_a_dry_run_against_a_live_deck_performs_zero_recorded_writes
    path, sha = manifest
    env = base_env(path, sha)
    env.delete("TRANSCRIPT_DELTA_WRITE")
    report, log, _o, _e, status = run_applier_on_stub_deck(
      env, deck: deck_with_parent, allow_writes: true
    )
    assert status.success?, "a dry run against a healthy deck must succeed"
    assert_equal "dry_run", report["mode"]
    assert_equal 1, report["plan_summary"]["pending_create"]
    assert_proven_zero_writes report, log, "dry run with a live deck"
  end

  def test_a_missing_write_gate_writes_nothing_even_with_the_deck_reachable
    path, sha = manifest
    ["", "0", "true", "yes", "TRUE", " 1"].each do |spelling|
      env = base_env(path, sha).merge("TRANSCRIPT_DELTA_WRITE" => spelling)
      report, log, = run_applier_on_stub_deck(env, deck: deck_with_parent,
                                                   allow_writes: true)
      assert_equal "dry_run", report["mode"], "WRITE=#{spelling.inspect}"
      assert_proven_zero_writes report, log, "write gate #{spelling.inspect}"
    end
  end

  def test_a_wrong_manifest_sha_writes_nothing
    path, sha = manifest
    env = base_env(path, sha).merge("TRANSCRIPT_DELTA_MANIFEST_SHA" => "0" * 64)
    report, log, _o, _e, status = run_applier_on_stub_deck(
      env, deck: deck_with_parent, allow_writes: true
    )
    refute status.success?
    assert_match(/does not match the manifest on disk/, report["halt_reason"].to_s)
    assert_proven_zero_writes report, log, "wrong manifest sha"
  end

  def test_a_missing_confirm_token_writes_nothing
    path, sha = manifest
    env = base_env(path, sha)
    env.delete("TRANSCRIPT_DELTA_CONFIRM")
    report, log, _o, _e, status = run_applier_on_stub_deck(
      env, deck: deck_with_parent, allow_writes: true
    )
    refute status.success?
    assert_match(/CONFIRM is required/, report["halt_reason"].to_s)
    assert_proven_zero_writes report, log, "missing confirm token"
  end

  def test_a_non_loopback_origin_writes_nothing
    path, sha = manifest
    ["https://wiki.hyperon.dev", "http://10.0.0.5:3000", ""].each do |origin|
      env = base_env(path, sha).merge("DECK_ORIGIN" => origin)
      report, log, _o, _e, status = run_applier_on_stub_deck(
        env, deck: deck_with_parent, allow_writes: true
      )
      refute status.success?, "origin #{origin.inspect} must refuse"
      assert_proven_zero_writes report, log, "origin #{origin.inspect}"
    end
  end

  def test_a_forbidden_database_host_writes_nothing
    path, sha = manifest
    report, log, _o, _e, status = run_applier_on_stub_deck(
      base_env(path, sha).merge("STUB_DB_HOST" => "prod.rds.amazonaws.com"),
      deck: deck_with_parent, allow_writes: true
    )
    refute status.success?
    assert_match(/database host names a forbidden host/, report["halt_reason"].to_s)
    assert_proven_zero_writes report, log, "forbidden db host"
  end

  # ---- scope refusals, with a deck that would have accepted the write --
  def test_an_out_of_scope_row_writes_nothing_against_a_live_deck
    # The blocker's exact scenario, end to end: a manifest whose scope block
    # asserts everything is fine, a row naming "*all", a reachable deck, and
    # every write gate set. The recorder must be empty.
    path, sha = manifest
    m = JSON.parse(File.read(path))
    m["rows"][0]["card_name"] = "*all"
    m["rows"][0]["base_card"] = "*all"
    assert_equal true, m["scope"]["all_rows_under_parent"]
    path2, sha2 = write_manifest(@dir, m, basename: "evil.json")

    report, log, _o, _e, status = run_applier_on_stub_deck(
      base_env(path2, sha2),
      deck: deck_with_parent(deck_card("*all", content: "set card",
                                               type_name: "Basic")),
      allow_writes: true
    )
    refute status.success?
    assert_match(/write-scope check/, report["halt_reason"].to_s)
    assert_proven_zero_writes report, log, "*all row with a reachable deck"
  end

  def test_a_protected_card_writes_nothing_even_when_the_manifest_is_silent
    protected_name =
      "#{PARENT}+Elowyn AI Meeting - Frag, EARTHwise, Magi+2026-03-03"
    path, sha = manifest(overrides: { "preserve" => { "protected_names" => [] } })
    m = JSON.parse(File.read(path))
    m["rows"][0]["card_name"] = protected_name
    m["rows"][0]["base_card"] = protected_name
    path2, sha2 = write_manifest(@dir, m, basename: "prot.json")

    report, log, _o, _e, status = run_applier_on_stub_deck(
      base_env(path2, sha2),
      deck: deck_with_parent(deck_card(protected_name, content: "keep me")),
      allow_writes: true
    )
    refute status.success?
    assert_proven_zero_writes report, log, "protected card, manifest silent"
  end

  def test_a_foreign_corpus_row_writes_nothing
    foreign = "#{PARENT}+AGI 26+Opening Keynote"
    path, sha = manifest
    m = JSON.parse(File.read(path))
    m["rows"][0]["card_name"] = foreign
    m["rows"][0]["base_card"] = foreign
    path2, sha2 = write_manifest(@dir, m, basename: "foreign.json")

    report, log, _o, _e, status = run_applier_on_stub_deck(
      base_env(path2, sha2),
      deck: deck_with_parent(deck_card(foreign, content: "captions")),
      allow_writes: true
    )
    refute status.success?
    assert_proven_zero_writes report, log, "foreign corpus row"
  end

  def test_a_missing_parent_card_writes_nothing
    # The applier must not create the subtree root it is scoped to.
    path, sha = manifest
    report, log, _o, _e, status = run_applier_on_stub_deck(
      base_env(path, sha), deck: [], allow_writes: true
    )
    refute status.success?
    assert_match(/does not exist live/, report["halt_reason"].to_s)
    assert_proven_zero_writes report, log, "missing parent card"
  end

  def test_an_update_target_outside_the_live_parent_writes_nothing
    # A name that looks right, filed somewhere else entirely by left_id. The
    # name-level check cannot catch this; only the live ancestry walk can.
    path, sha = manifest(action: "update", live_hash: "a" * 64)
    m = JSON.parse(File.read(path))
    m["rows"][0]["live_hash"] = Digest::SHA256.hexdigest("stale body")
    path2, sha2 = write_manifest(@dir, m, basename: "misfiled.json")

    deck = deck_with_parent(
      deck_card("Elsewhere", content: "", type_name: "Basic"),
      deck_card(@base, content: "stale body").merge("left" => "Elsewhere")
    )
    report, log, _o, _e, status = run_applier_on_stub_deck(
      base_env(path2, sha2), deck: deck, allow_writes: true
    )
    refute status.success?
    assert_match(/not live-filed|not a live descendant|not filed under/,
                 report["halt_reason"].to_s)
    assert_proven_zero_writes report, log, "misfiled update target"
  end

  # ---- classifier refusals, through the live sweep --------------------
  def test_a_drifted_update_writes_nothing
    path, sha = manifest(action: "update", live_hash: "a" * 64)
    m = JSON.parse(File.read(path))
    m["rows"][0]["live_hash"] = Digest::SHA256.hexdigest("what the plan expected")
    path2, sha2 = write_manifest(@dir, m, basename: "drift.json")

    report, log, _o, _e, status = run_applier_on_stub_deck(
      base_env(path2, sha2),
      deck: deck_with_parent(deck_card(@base, content: "something else entirely")),
      allow_writes: true
    )
    refute status.success?
    assert_match(/drift_update/, report["halt_reason"].to_s + report.to_json)
    assert_proven_zero_writes report, log, "drifted update"
  end

  def test_a_create_colliding_with_an_existing_card_writes_nothing
    path, sha = manifest
    report, log, _o, _e, status = run_applier_on_stub_deck(
      base_env(path, sha),
      deck: deck_with_parent(deck_card(@base, content: "someone got there first")),
      allow_writes: true
    )
    refute status.success?
    assert_match(/collision_create/, report.to_json)
    assert_proven_zero_writes report, log, "create collision"
  end

  # The type_drift case, end to end: a card whose content hash is exactly what
  # the plan wants but whose type someone changed.
  def test_a_type_drifted_row_writes_nothing
    path, sha = manifest(action: "update", live_hash: "a" * 64)
    m = JSON.parse(File.read(path))
    m["rows"][0]["live_hash"] = Digest::SHA256.hexdigest("old body")
    path2, sha2 = write_manifest(@dir, m, basename: "typedrift.json")

    report, log, _o, _e, status = run_applier_on_stub_deck(
      base_env(path2, sha2),
      deck: deck_with_parent(deck_card(@base, content: "old body",
                                              type_name: "Basic")),
      allow_writes: true
    )
    refute status.success?
    assert_match(/type_drift/, report.to_json)
    assert_proven_zero_writes report, log, "type drift"
  end

  def test_an_already_applied_row_is_skipped_rather_than_rewritten
    # Resume safety, proven by the recorder: the card already holds the
    # desired bytes, so a correct applier issues NO update at all.
    path, sha = manifest
    report, log, _o, _e, status = run_applier_on_stub_deck(
      base_env(path, sha),
      deck: deck_with_parent(deck_card(@base, content: desired["content"])),
      allow_writes: true
    )
    assert status.success?, "an already-applied row must not halt a resume"
    assert_equal 1, report["skipped_already_applied"]
    assert_equal 1, report["plan_summary"]["already_applied"]
    assert_recorder_empty log, "already-applied resume"
  end

  # ---- the forbidden surface, exercised rather than grepped -----------
  def test_a_whole_successful_apply_touches_nothing_but_its_own_rows
    path, sha = manifest
    bystanders = [
      deck_card("#{PARENT}+Other Meeting+2026-02-02", content: "untouched"),
      deck_card("#{PARENT}+AGI 26+Keynote", content: "foreign"),
      deck_card("#{PARENT}+Elowyn AI Meeting - Frag, EARTHwise, Magi+2026-03-03",
                content: "protected"),
      deck_card("#{PARENT}+Shrunk+2026-01-01+chunk-9", content: "stale chunk")
    ]
    report, log, _o, _e, status = run_applier_on_stub_deck(
      base_env(path, sha), deck: deck_with_parent(*bystanders), allow_writes: true
    )
    assert status.success?
    # exactly one mutation, and it is the planned create
    assert_equal 1, log["mutations"].length
    assert_equal "create", log["mutations"].first["op"]
    assert_equal @base, log["mutations"].first["card"]
    assert_equal 0, log["forbidden_ops"],
                 "no destroy/delete/trash/rename/save/raw-SQL call may happen"
    assert_equal 0, report["preserve_changed"]
    assert_equal 0, report["final"]["trashed_delta"]
  end

  def test_the_act_audit_names_the_cards_the_deck_itself_recorded
    path, sha = manifest
    report, = run_applier_on_stub_deck(base_env(path, sha), deck: deck_with_parent,
                                                            allow_writes: true)
    audit = report["act_audit"]
    assert_equal "checked", audit["status"]
    assert_empty audit["unexpected_card_ids"],
                 "the deck must not record a change this apply did not plan"
  end
end

# ------------------------------------------------------------
# 10. The stub deck harness is itself checked
# ------------------------------------------------------------
# A recorder that cannot fail is worth nothing, so these tests assert the
# harness records and refuses the calls it claims to.
class TestStubDeckHarness < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @log = File.join(@dir, "mutations.json")
    @cards = File.join(@dir, "deck.json")
    File.write(@cards, JSON.dump([{ "name" => "A+b", "content" => "x" }]))
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  # Drive the stub directly in a subprocess, since it defines Card.
  def probe(body)
    script = <<~RUBY
      load #{STUB_DECK.dump}
      StubDeck.boot!
      at_exit { StubDeck.flush! }
      begin
        #{body}
      rescue StandardError => e
        puts "raised:\#{e.class}"
      end
    RUBY
    out, _err, _status = Open3.capture3(
      { "STUB_DECK_CARDS" => @cards, "STUB_MUTATION_LOG" => @log,
        "STUB_ALLOW_WRITES" => "1" },
      RbConfig.ruby, "-e", script
    )
    [out, JSON.parse(File.read(@log))]
  end

  def test_a_destroy_is_recorded_and_raises
    out, log = probe('Card.fetch("A+b").destroy')
    assert_match(/raised:StubDeck::ForbiddenCall/, out)
    assert_equal 1, log["forbidden_ops"]
  end

  def test_a_trash_assignment_is_recorded_and_raises
    out, log = probe('Card.fetch("A+b").trash = true')
    assert_match(/raised:StubDeck::ForbiddenCall/, out)
    assert_equal "trash_assign", log["mutations"].first["op"]
  end

  def test_a_rename_is_recorded_and_raises
    out, log = probe('Card.fetch("A+b").name = "C+d"')
    assert_match(/raised:StubDeck::ForbiddenCall/, out)
    assert_equal "rename", log["mutations"].first["op"]
  end

  def test_a_bare_save_is_recorded_and_raises
    out, log = probe('Card.fetch("A+b").save!')
    assert_match(/raised:StubDeck::ForbiddenCall/, out)
    assert_equal "save_bang", log["mutations"].first["op"]
  end

  def test_raw_sql_is_recorded_and_raises
    out, log = probe('ActiveRecord::Base.connection.execute("delete from cards")')
    assert_match(/raised:StubDeck::ForbiddenCall/, out)
    assert_equal "raw_sql", log["mutations"].first["op"]
  end

  def test_a_legitimate_update_is_recorded_as_a_write
    _out, log = probe('Card.fetch("A+b").update!(content: "y")')
    assert_equal 1, log["write_ops"]
    assert_equal 0, log["forbidden_ops"]
  end

  def test_writes_are_refused_unless_the_harness_opts_in
    # Same call, STUB_ALLOW_WRITES unset: recorded, then refused.
    script = <<~RUBY
      load #{STUB_DECK.dump}
      StubDeck.boot!
      at_exit { StubDeck.flush! }
      begin
        Card.fetch("A+b").update!(content: "y")
      rescue StandardError => e
        puts "raised:\#{e.class}"
      end
    RUBY
    out, _err, _status = Open3.capture3(
      { "STUB_DECK_CARDS" => @cards, "STUB_MUTATION_LOG" => @log,
        "STUB_ALLOW_WRITES" => "0" },
      RbConfig.ruby, "-e", script
    )
    assert_match(/raised:StubDeck::WriteRefused/, out)
    log = JSON.parse(File.read(@log))
    assert_equal 1, log["write_ops"], "the attempt must still be recorded"
  end

  def test_left_ids_are_resolved_from_names_so_ancestry_is_real
    File.write(@cards, JSON.dump([
                                   { "name" => "A", "content" => "" },
                                   { "name" => "A+b", "content" => "" },
                                   { "name" => "A+b+c", "content" => "" }
                                 ]))
    out, = probe('puts Card.where(left_id: [Card.fetch("A").id]).to_a.map(&:name).inspect')
    assert_match(/A\+b/, out)
  end
end

# ------------------------------------------------------------
# Not covered here (needs a live local deck):
#   * an actual create/update against the local loopback wiki
#   * Decko's real Cardname keying, type system and left-card autocreation
#   * the live preserve-set readback after a real write
# Those are exercised by a gated dry-run and refusal probes against the
# container, recorded as run artifacts, not by this offline suite. The stub
# deck above models the invariants the applier reads, not Decko itself.
# ------------------------------------------------------------
