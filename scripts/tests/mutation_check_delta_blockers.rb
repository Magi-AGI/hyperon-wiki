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
# Run: ruby scripts/tests/mutation_check_delta_blockers.rb
# Nothing is written outside a temp dir; the real applier is untouched.

require "tmpdir"
require "open3"
require "fileutils"

APPLIER = File.expand_path("../apply_transcript_delta.rb", __dir__)
SUITE = File.expand_path("test_apply_transcript_delta.rb", __dir__)

MUTANTS = {
  "blocker1_trusts_manifest_scope" => lambda do |src|
    # Neuter the derived scope gate: report, but never refuse.
    src.sub(
      /  die! "#\{violations\.length\} row\(s\) fail this applier's own write-scope " \\\n.*?\n    violations\.any\?\n/m,
      "  # MUTANT: refusal removed\n"
    )
  end,
  "blocker2_ignores_type_drift" => lambda do |src|
    src.sub(/    state = "type_drift"\n/, "    state = state # MUTANT: type drift ignored\n")
  end
}

def run_suite(applier_path, filter)
  dir = File.dirname(applier_path)
  out, err, status = Open3.capture3(
    { "TRANSCRIPT_DELTA_APPLIER_LIB" => nil },
    RbConfig.ruby, File.join(dir, "tests", File.basename(SUITE)),
    "-n", filter
  )
  [out + err, status]
end

results = {}
MUTANTS.each do |label, mutate|
  Dir.mktmpdir do |root|
    # Mirror the scripts dir so relative loads (the planner, the stub deck)
    # still resolve.
    FileUtils.cp_r(File.dirname(APPLIER), root)
    scripts = File.join(root, File.basename(File.dirname(APPLIER)))
    target = File.join(scripts, File.basename(APPLIER))

    original = File.read(target)
    mutated = mutate.call(original)
    if mutated == original
      results[label] = "MUTATION DID NOT APPLY (pattern no longer matches)"
      next
    end
    File.write(target, mutated)

    filter = label.start_with?("blocker1") ? "/DerivedWriteScope|ZeroWriteProof/" \
                                           : "/ResumeClassification|ZeroWriteProof/"
    output, status = run_suite(target, filter)
    summary = output.lines.grep(/runs,/).last.to_s.strip
    results[label] = status.success? ? "NOT CAUGHT - suite still green: #{summary}" \
                                     : "caught: #{summary}"
  end
end

puts "Mutation check against scripts/tests/test_apply_transcript_delta.rb"
puts "-" * 64
results.each { |label, verdict| puts format("%-34s %s", label, verdict) }
failed = results.values.grep(/NOT CAUGHT|DID NOT APPLY/)
puts "-" * 64
puts failed.empty? ? "OK: every blocker fix is load-bearing." \
                   : "PROBLEM: #{failed.length} mutant(s) survived."
exit(failed.empty? ? 0 : 1)
