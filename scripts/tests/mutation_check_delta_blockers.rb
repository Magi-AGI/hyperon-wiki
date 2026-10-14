#!/usr/bin/env ruby
# Mutation check: does the suite actually CATCH the two blockers?
#
# A test suite that passes is not evidence; a test suite that fails when the
# fix is removed is. This script makes two surgical edits to a COPY of the
# applier, runs the relevant tests against each copy, and reports whether the
# suite noticed.
#
#   mutant 1 (blocker 1): delete the derived write-scope gate, so the applier
#            is back to trusting the manifest's own scope booleans.
#   mutant 2 (blocker 2): make the classifier ignore type drift.
#
# "caught" is the only passing verdict, and it is only given after the same
# tests have passed on an UNMUTATED copy: a suite that is red for some other
# reason would otherwise look as if it caught everything. Every other outcome
# exits 1 under its own name:
#
#   NOT APPLIED  the edit was not made, because its anchor matches nowhere in
#                the applier or in more than one place. That says nothing
#                about the suite; the applier moved, so update the anchor.
#   SURVIVED     the edit was made and the suite stayed green: a real gap.
#   NO VERDICT   the suite went red without a failing test - it did not load,
#                or crashed - so the red cannot be credited to the edit.
#   NOT GREEN    the unmutated copy failed the same tests, so no mutant was
#                run; each one is reported NOT RUN.
#
# LINE ENDINGS. The applier is read and written as bytes, and every anchor
# accepts LF or CRLF. The anchors used to be LF-only. They matched on Windows
# only because a text-mode read strips CR there; in the Linux container they
# missed, and the miss was reported as two surviving mutants.
#
# Run: ruby scripts/tests/mutation_check_delta_blockers.rb
# Nothing is written outside a temp dir; the real applier is untouched.
#
# With TRANSCRIPT_DELTA_MUTATION_CHECK_LIB=1 this file defines its mutants and
# helpers and runs nothing, so test_mutation_check_delta_blockers.rb can drive
# the real edit step without the slow suite runs.

require "tmpdir"
require "open3"
require "fileutils"

APPLIER = File.expand_path("../apply_transcript_delta.rb", __dir__)
SUITE = File.expand_path("test_apply_transcript_delta.rb", __dir__)

# Load-only mode for the offline test suite: define everything, run nothing.
MUTATION_CHECK_LIB_ONLY = ENV["TRANSCRIPT_DELTA_MUTATION_CHECK_LIB"] == "1"

# Each anchor must match the applier exactly once. It ends in an `eol` group,
# so the replacement keeps whichever line ending the source has.
MUTANTS = {
  "blocker1_trusts_manifest_scope" => {
    # Neuter the derived scope gate: report, but never refuse. The anchor is
    # the whole `die! ... if violations.any?` statement and no more, so
    # removing it leaves valid Ruby.
    anchor: /^  die! "#\{violations\.length\} row\(s\) fail this applier's own write-scope " \\\r?\n[^\r\n]* if\r?\n    violations\.any\?(?<eol>\r?\n)/,
    replacement: "  # MUTANT: refusal removed",
    tests: %w[DerivedWriteScope ZeroWriteProof]
  },
  "blocker2_ignores_type_drift" => {
    anchor: /^    state = "type_drift"(?<eol>\r?\n)/,
    replacement: "    state = state # MUTANT: type drift ignored",
    tests: %w[ResumeClassification ZeroWriteProof]
  }
}.freeze

class MutationNotApplied < StandardError; end

# The source with one mutant's edit made, or MutationNotApplied. No match and
# several matches both refuse: the first would test the unmutated applier, the
# second whichever occurrence happened to come first. Each search restarts one
# character past the previous match start, so overlapping matches count too.
def mutate_source(source, mutant)
  hits = []
  pos = 0
  while (hit = mutant[:anchor].match(source, pos))
    hits << hit
    pos = hit.begin(0) + 1
  end
  raise MutationNotApplied, "anchor not found - the applier changed or the anchor drifted" if hits.empty?
  if hits.length > 1
    lines = hits.map { |h| source[0...h.begin(0)].count("\n") + 1 }
    raise MutationNotApplied,
          "anchor matches #{hits.length} times (lines #{lines.join(', ')}) - refusing to pick one"
  end

  hit = hits.first
  mutated = hit.pre_match + mutant[:replacement] + hit[:eol] + hit.post_match
  raise MutationNotApplied, "the edit changed nothing" if mutated == source

  mutated
end

# Mirror the scripts dir so relative loads (the planner, the stub deck) still
# resolve, and yield the applier's path inside the copy.
def with_scripts_copy
  Dir.mktmpdir do |root|
    FileUtils.cp_r(File.dirname(APPLIER), root)
    yield File.join(root, File.basename(File.dirname(APPLIER)), File.basename(APPLIER))
  end
end

def run_suite(applier_path, tests)
  dir = File.dirname(applier_path)
  out, err, status = Open3.capture3(
    { "TRANSCRIPT_DELTA_APPLIER_LIB" => nil },
    RbConfig.ruby, File.join(dir, "tests", File.basename(SUITE)),
    "-n", "/#{tests.join('|')}/"
  )
  [out + err, status]
end

# Minitest's closing tally as [line, runs, failures + errors], or nil when the
# suite never got that far.
def suite_tally(output)
  found = nil
  output.b.scan(/^(\d+) runs, \d+ assertions, (\d+) failures, (\d+) errors, \d+ skips/) do
    found = Regexp.last_match
  end
  found && [found[0], found[1].to_i, found[2].to_i + found[3].to_i]
end

def judge_baseline(output, status)
  line, runs, red = suite_tally(output)
  return [:not_green, "no test results (exit #{status.exitstatus.inspect})"] if line.nil?
  return [:not_green, "no test selected - #{line}"] if runs.zero?
  return [:green, line] if status.success? && red.zero?

  [:not_green, "exit #{status.exitstatus.inspect} - #{line}"]
end

# Caught means tests ran and some failed. Green is a survivor; red with no
# failing test is not credited to the edit.
def judge_mutant(output, status)
  line, runs, red = suite_tally(output)
  return [:no_verdict, "no test results (exit #{status.exitstatus.inspect})"] if line.nil?
  return [:no_verdict, "no test selected - #{line}"] if runs.zero?
  return [:survived, "the suite stayed green - #{line}"] if status.success?
  return [:caught, line] if red.positive?

  [:no_verdict, "red with no failing test (exit #{status.exitstatus.inspect}) - #{line}"]
end

def mutation_check
  source = File.binread(APPLIER)
  verdicts = {}
  edited = {}
  MUTANTS.each do |label, mutant|
    begin
      edited[label] = mutate_source(source, mutant)
    rescue MutationNotApplied => e
      verdicts[label] = [:not_applied, e.message]
    end
  end

  baseline =
    if edited.empty?
      [:skipped, "no mutant could be applied"]
    else
      tests = edited.keys.flat_map { |label| MUTANTS[label][:tests] }.uniq
      judge_baseline(*with_scripts_copy { |target| run_suite(target, tests) })
    end

  edited.each do |label, mutated|
    verdicts[label] =
      if baseline.first == :green
        with_scripts_copy do |target|
          File.binwrite(target, mutated)
          judge_mutant(*run_suite(target, MUTANTS[label][:tests]))
        end
      else
        [:not_run, "the unmutated copy is not green"]
      end
  end

  report(baseline, verdicts)
end

VERDICT_WORDS = {
  green: "green", skipped: "not run", not_green: "NOT GREEN",
  caught: "caught", survived: "SURVIVED", not_applied: "NOT APPLIED",
  no_verdict: "NO VERDICT", not_run: "NOT RUN"
}.freeze

# Print the verdicts and return the exit status.
def report(baseline, verdicts)
  puts "Mutation check against scripts/tests/test_apply_transcript_delta.rb"
  puts "-" * 64
  puts format("%-34s %s: %s", "baseline (unmutated copy)", VERDICT_WORDS.fetch(baseline[0]), baseline[1])
  MUTANTS.each_key do |label|
    kind, detail = verdicts.fetch(label)
    puts format("%-34s %s: %s", label, VERDICT_WORDS.fetch(kind), detail)
  end
  puts "-" * 64

  # Pass on a positive result for every mutant, never on the absence of a
  # recognised problem.
  if baseline.first == :green && MUTANTS.each_key.all? { |label| verdicts.fetch(label).first == :caught }
    puts "OK: every blocker fix is load-bearing."
    return 0
  end

  counts = Hash.new(0)
  verdicts.each_value { |kind, _| counts[kind] += 1 }
  if baseline.first == :not_green
    puts "PROBLEM: the unmutated copy is NOT GREEN on these tests, so no mutant was run " \
         "and nothing was learned. Fix the suite first."
  end
  if counts[:not_applied].positive?
    puts "PROBLEM: #{counts[:not_applied]} mutant(s) NOT APPLIED. The checker could not edit " \
         "the applier, so no conclusion about the suite is available. Update the anchor(s) in MUTANTS."
  end
  if counts[:survived].positive?
    puts "PROBLEM: #{counts[:survived]} mutant(s) SURVIVED. The suite stayed green with a " \
         "blocker fix removed."
  end
  if counts[:no_verdict].positive?
    puts "PROBLEM: #{counts[:no_verdict]} mutant run(s) gave NO VERDICT. The suite went red " \
         "without a failing test, so the red cannot be credited to the edit."
  end
  1
end

if MUTATION_CHECK_LIB_ONLY
  # A checker that quietly does nothing reads as a pass to anything that only
  # looks at the exit status. The flag is for `load`; a direct run refuses.
  abort "TRANSCRIPT_DELTA_MUTATION_CHECK_LIB=1 is set, so nothing was checked." if $PROGRAM_NAME == __FILE__
else
  exit(mutation_check)
end
