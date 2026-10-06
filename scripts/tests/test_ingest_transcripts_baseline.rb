#!/usr/bin/env ruby
# Regression test: delta reports must not claim a live baseline they never had.
#
# Outside a Decko runner there is no `Card` constant, so every orphan/chunk
# query trivially returns empty and every planned card trivially looks like a
# create. A delta report that still advertised baseline "live-content-hash" in
# that situation reads as "nothing to reconcile" when the truth is "nothing was
# compared" - which is exactly the wrong signal for a go-live gate.
#
# Run:
#   ruby scripts/test_ingest_transcripts_baseline.rb
#
# No database, no network, no Decko: that is the point.

require 'json'
require 'tmpdir'
require 'fileutils'

SCRIPT = File.expand_path("../ingest_transcripts.rb", __dir__)

FAILURES = []

def check(label)
  ok = yield
  puts(ok ? "  ok   #{label}" : "  FAIL #{label}")
  FAILURES << label unless ok
rescue StandardError => e
  puts "  FAIL #{label} (#{e.class}: #{e.message})"
  FAILURES << label
end

# A minimal transcript export, shaped like the Read.ai parser's output.
def write_fixture(dir)
  File.write(File.join(dir, "2026-01-01_Fixture.json"), JSON.pretty_generate(
    "meeting_name" => "Baseline Fixture",
    "date" => "2026-01-01",
    "source_service" => "read.ai",
    "summary" => "A short fixture summary.",
    "action_items" => ["Do the thing"],
    "full_text" => "Speaker: hello world."
  ))
end

def run_ingest(export_dir, report_path, env)
  base = {
    "TRANSCRIPT_INGEST" => "1",
    "TRANSCRIPT_EXPORT_DIR" => export_dir,
    "TRANSCRIPT_INGEST_REPORT" => report_path
  }
  out = IO.popen(base.merge(env), ["ruby", SCRIPT], err: [:child, :out], &:read)
  [out, $?.exitstatus]
end

puts "Delta baseline honesty"
Dir.mktmpdir do |dir|
  write_fixture(dir)
  report = File.join(dir, "delta.json")
  out, status = run_ingest(dir, report,
                           "TRANSCRIPT_INGEST_DELTA" => "1",
                           "TRANSCRIPT_INGEST_DRY_RUN" => "1")

  check("delta dry-run exits 0") { status.zero? }
  check("report is written") { File.exist?(report) }

  r = File.exist?(report) ? JSON.parse(File.read(report)) : {}

  check("mode is delta") { r["mode"] == "delta" }

  # The core assertion: with no Card API, the baseline must be labelled absent
  # rather than advertised as a live content-hash comparison.
  check("baseline is not falsely 'live-content-hash'") do
    r["baseline"] != "live-content-hash"
  end
  check("baseline names the absent-API case") do
    r["baseline"] == "none-no-card-api"
  end
  check("baseline_available is false") { r["baseline_available"] == false }

  wr = r["write_readiness"] || {}
  check("write_readiness.baseline_compared is false") do
    wr["baseline_compared"] == false
  end
  check("write_readiness flags no_live_baseline as blocking") do
    wr.dig("blocking", "no_live_baseline") == 1
  end
  check("write_readiness note carries the warning") do
    wr["note"].to_s.include?("NOTHING was compared")
  end
  check("console output warns operator") do
    out.include?("NO LIVE BASELINE")
  end

  # Writes must still be impossible regardless of reporting changes.
  check("still reports no write path") { wr["write_path_implemented"] == false }
end

puts "\nDelta without dry-run still aborts"
Dir.mktmpdir do |dir|
  write_fixture(dir)
  report = File.join(dir, "nope.json")
  out, status = run_ingest(dir, report, "TRANSCRIPT_INGEST_DELTA" => "1")

  check("aborts non-zero") { !status.zero? }
  check("explains the requirement") do
    out.include?("requires TRANSCRIPT_INGEST_DRY_RUN=1")
  end
  check("writes no report") { !File.exist?(report) }
end

puts "\nPlain dry-run is unaffected"
Dir.mktmpdir do |dir|
  write_fixture(dir)
  report = File.join(dir, "plain.json")
  _out, status = run_ingest(dir, report, "TRANSCRIPT_INGEST_DRY_RUN" => "1")

  r = File.exist?(report) ? JSON.parse(File.read(report)) : {}
  check("exits 0") { status.zero? }
  check("mode is full-dry-run") { r["mode"] == "full-dry-run" }
  # Non-delta runs never claimed a baseline; keep that nil.
  check("baseline stays nil outside delta") { r["baseline"].nil? }
  check("baseline_available stays nil outside delta") do
    r["baseline_available"].nil?
  end
  check("nothing written") { r["stats"]["created"].zero? }
end

puts
if FAILURES.empty?
  puts "PASS - all checks green"
  exit 0
else
  puts "FAIL - #{FAILURES.length} check(s) failed:"
  FAILURES.each { |f| puts "  - #{f}" }
  exit 1
end
