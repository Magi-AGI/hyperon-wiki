#!/usr/bin/env ruby
# Offline tests for scripts/tests/mutation_check_delta_blockers.rb, the check
# that removes each delta-applier blocker fix from a copy of the applier and
# demands the applier suite go red.
#
# That check is only evidence if its edits land. Its anchors used to assume
# LF: on a CRLF checkout read without text-mode translation (the Linux
# container) neither edit applied, and the miss was reported as two surviving
# mutants. These tests drive the checker's OWN edit step and its OWN command
# line; nothing here re-implements an anchor.
#
#   1. LF source: each edit applies once, inside its function, and nothing
#      else changes
#   2. CRLF source: the same edit, and the edited line keeps its CRLF
#   3. both edits leave valid Ruby in both line-ending flavours
#   4. an anchor that is gone refuses - NOT APPLIED, exit 1, never "survived"
#   5. an anchor that matches twice refuses rather than editing either one
#   6. caught, survived, not applied, no verdict and a red baseline stay
#      distinct through the real command line, against stand-in suites
#   7. the load-only flag cannot turn a direct run into a silent pass
#
# The slow half of the claim - that the real applier suite catches both
# mutants - is the checker's own end-to-end run, not a test here.
#
# Run: ruby scripts/tests/test_mutation_check_delta_blockers.rb

require "minitest/autorun"
require "open3"
require "tmpdir"
require "fileutils"

CHECKER = File.expand_path("mutation_check_delta_blockers.rb", __dir__)

# ------------------------------------------------------------
# Load the checker's mutants and edit step into THIS process
# ------------------------------------------------------------
# TRANSCRIPT_DELTA_MUTATION_CHECK_LIB=1 makes the checker define MUTANTS and
# mutate_source and run nothing. The variable is deleted straight after, so
# the checker subprocesses below run for real instead of loading and exiting.
ENV["TRANSCRIPT_DELTA_MUTATION_CHECK_LIB"] = "1"
load CHECKER
ENV.delete("TRANSCRIPT_DELTA_MUTATION_CHECK_LIB")

# ------------------------------------------------------------
# Shared fixtures
# ------------------------------------------------------------
module MutationCheckFixtures
  # What each edit must remove and leave behind, and the function it must
  # land in. Written out by hand: this is the expectation, not an anchor.
  EDITS = {
    "blocker1_trusts_manifest_scope" => {
      function: "apply_gate_derived_scope!",
      removed: [
        %q(  die! "#{violations.length} row(s) fail this applier's own write-scope " \\),
        %q(       "check: #{violations.first(5).map { |v| [v[:card_name], v[:reason]] }.inspect}" if),
        %q(    violations.any?)
      ],
      added: ["  # MUTANT: refusal removed"]
    },
    "blocker2_ignores_type_drift" => {
      function: "apply_classify_row",
      removed: [%q(    state = "type_drift")],
      added: ["    state = state # MUTANT: type drift ignored"]
    }
  }.freeze

  # A plain-text change a refactor might make to each target statement, after
  # which its anchor must no longer match.
  REWORDINGS = {
    "blocker1_trusts_manifest_scope" => ["fail this applier's own write-scope",
                                         "fail the derived write-scope"],
    "blocker2_ignores_type_drift" => ['state = "type_drift"', 'state = "type_changed"']
  }.freeze

  # The shipped applier in each line-ending flavour, otherwise byte for byte.
  def lf_source
    File.binread(APPLIER).gsub("\r\n", "\n")
  end

  def crlf_source
    lf_source.gsub("\n", "\r\n")
  end

  def flavours
    { "LF" => [lf_source, "\n"], "CRLF" => [crlf_source, "\r\n"] }
  end

  # The target statement exactly as a source with this line ending has it.
  def statement(label, eol)
    EDITS.fetch(label)[:removed].map { |line| line + eol }.join
  end

  def with_statement_reworded(source, label)
    from, to = REWORDINGS.fetch(label)
    out = source.gsub(from) { to }
    raise "fixture: #{label} has nothing to reword" if out == source

    out
  end

  def with_statement_doubled(source, label, eol)
    text = statement(label, eol)
    out = source.sub(text) { text + text }
    raise "fixture: #{label} statement not found" if out == source

    out
  end
end

# ------------------------------------------------------------
# 1-3. The edits land, in both line-ending flavours
# ------------------------------------------------------------
class TestMutantEditsLand < Minitest::Test
  include MutationCheckFixtures

  def test_every_mutant_has_a_written_out_expectation
    assert_equal MUTANTS.keys.sort, EDITS.keys.sort
    assert_equal MUTANTS.keys.sort, REWORDINGS.keys.sort
  end

  def test_each_edit_lands_once_in_its_function_on_an_lf_source
    assert_each_edit_lands(*flavours.fetch("LF"))
  end

  def test_each_edit_lands_once_in_its_function_on_a_crlf_source
    assert_each_edit_lands(*flavours.fetch("CRLF"))
  end

  def test_both_flavours_get_the_same_edit
    MUTANTS.each do |label, mutant|
      assert_equal mutate_source(lf_source, mutant).gsub("\n", "\r\n"),
                   mutate_source(crlf_source, mutant), label
    end
  end

  def test_every_edit_leaves_valid_ruby_in_both_flavours
    Dir.mktmpdir do |dir|
      flavours.each do |flavour, (source, _eol)|
        MUTANTS.each do |label, mutant|
          path = File.join(dir, "#{label}_#{flavour}.rb")
          File.binwrite(path, mutate_source(source, mutant))
          out, status = Open3.capture2e(RbConfig.ruby, "-c", path)
          assert status.success?, "#{label} on a #{flavour} source is not valid Ruby:\n#{out}"
        end
      end
    end
  end

  private

  # The one run of lines that differs: [index of its first line, removed, added].
  def changed_lines(before, after)
    a = before.lines
    b = after.lines
    head = 0
    head += 1 while head < a.length && head < b.length && a[head] == b[head]
    tail = 0
    tail += 1 while tail < a.length - head && tail < b.length - head && a[-1 - tail] == b[-1 - tail]
    [head, a[head...(a.length - tail)], b[head...(b.length - tail)]]
  end

  def enclosing_def(source, index)
    source.lines[0...index].reverse_each do |line|
      return line[/\Adef ([\w!?]+)/, 1] if line.start_with?("def ")
    end
    nil
  end

  def assert_each_edit_lands(source, eol)
    MUTANTS.each do |label, mutant|
      want = EDITS.fetch(label)
      at, removed, added = changed_lines(source, mutate_source(source, mutant))
      assert_equal want[:removed].map { |l| l + eol }, removed, "#{label} removed the wrong lines"
      assert_equal want[:added].map { |l| l + eol }, added, "#{label} left the wrong line"
      assert_equal want[:function], enclosing_def(source, at), "#{label} edited the wrong function"
    end
  end
end

# ------------------------------------------------------------
# 4-5. An edit that cannot be made exactly once refuses
# ------------------------------------------------------------
class TestMutantEditsRefuse < Minitest::Test
  include MutationCheckFixtures

  def test_an_anchor_that_is_gone_refuses_in_both_flavours
    flavours.each do |flavour, (source, _eol)|
      MUTANTS.each do |label, mutant|
        error = assert_raises(MutationNotApplied, "#{label} on #{flavour}") do
          mutate_source(with_statement_reworded(source, label), mutant)
        end
        assert_match(/anchor not found/, error.message)
      end
    end
  end

  def test_an_anchor_that_matches_twice_refuses_in_both_flavours
    flavours.each do |flavour, (source, eol)|
      MUTANTS.each do |label, mutant|
        error = assert_raises(MutationNotApplied, "#{label} on #{flavour}") do
          mutate_source(with_statement_doubled(source, label, eol), mutant)
        end
        assert_match(/anchor matches 2 times/, error.message)
      end
    end
  end

  def test_overlapping_matches_count_as_ambiguous
    # "aaa" holds this two-character anchor at offsets 0 and 1. A scan that
    # resumed after each whole match would see only one of them.
    mutant = { anchor: /a(?<eol>a)/, replacement: "b" }
    error = assert_raises(MutationNotApplied) { mutate_source("aaa", mutant) }
    assert_match(/matches 2 times/, error.message)
  end

  def test_an_edit_that_changes_nothing_refuses
    mutant = { anchor: /^same(?<eol>\n)/, replacement: "same" }
    error = assert_raises(MutationNotApplied) { mutate_source("same\n", mutant) }
    assert_match(/changed nothing/, error.message)
  end
end

# ------------------------------------------------------------
# 6-7. The verdicts, through the real command line
# ------------------------------------------------------------
# A copy of the checker runs inside a throwaway scripts/ tree. It resolves
# APPLIER and SUITE next to itself, so it edits the applier source given here
# and runs a stand-in for the applier suite - which keeps every run fast and
# lets each verdict be forced on purpose.
class TestCommandLineVerdicts < Minitest::Test
  include MutationCheckFixtures

  # One test in each class the checker's -n filters select. `prelude` runs
  # before minitest is loaded.
  def self.stand_in_suite(body, prelude: "")
    prelude + <<~RUBY
      require "minitest/autorun"
      APPLIER = File.expand_path("../apply_transcript_delta.rb", __dir__)
      class TestDerivedWriteScope < Minitest::Test
        def test_scope_gate; #{body}; end
      end
      class TestResumeClassification < Minitest::Test
        def test_type_drift; #{body}; end
      end
    RUBY
  end

  # Red as soon as the copy it runs against has been edited.
  CATCHING = stand_in_suite(%(refute_includes File.binread(APPLIER), "MUTANT"))
  # Green no matter what.
  BLIND = stand_in_suite("assert true")
  # Red no matter what.
  RED = stand_in_suite(%(flunk "red without any edit"))
  # Green on the unedited copy; raises before minitest loads on an edited one.
  CRASHING = stand_in_suite("assert true", prelude: <<~'RUBY')
    edited = File.binread(File.expand_path("../apply_transcript_delta.rb", __dir__))
    raise "the edited applier does not load" if edited.include?("MUTANT")
  RUBY

  def run_checker(applier_source, suite, env: {})
    Dir.mktmpdir do |root|
      scripts = File.join(root, "scripts")
      FileUtils.mkdir_p(File.join(scripts, "tests"))
      checker = File.join(scripts, "tests", File.basename(CHECKER))
      FileUtils.cp(CHECKER, checker)
      File.binwrite(File.join(scripts, File.basename(APPLIER)), applier_source)
      File.write(File.join(scripts, "tests", File.basename(SUITE)), suite)
      out, err, status = Open3.capture3(
        { "TRANSCRIPT_DELTA_MUTATION_CHECK_LIB" => nil }.merge(env),
        RbConfig.ruby, checker
      )
      [out + err, status.exitstatus]
    end
  end

  def test_anchors_that_are_gone_are_not_applied_and_never_survivors
    # The blind suite is green on an unedited copy, so a checker that ran it
    # anyway would report survivors. This one must not run it at all.
    gone = MUTANTS.keys.reduce(crlf_source) { |src, label| with_statement_reworded(src, label) }
    out, code = run_checker(gone, BLIND)
    assert_equal 1, code, out
    MUTANTS.each_key { |label| assert_match(/^#{label} +NOT APPLIED: anchor not found/, out) }
    assert_match(/^baseline \(unmutated copy\) +not run: no mutant could be applied/, out)
    assert_match(/^PROBLEM: 2 mutant\(s\) NOT APPLIED\. The checker could not edit the applier/, out)
    refute_match(/surviv/i, out)
    refute_match(/caught|^OK:/, out)
  end

  def test_anchors_that_match_twice_are_not_applied
    doubled = MUTANTS.keys.reduce(crlf_source) do |src, label|
      with_statement_doubled(src, label, "\r\n")
    end
    out, code = run_checker(doubled, BLIND)
    assert_equal 1, code, out
    MUTANTS.each_key { |label| assert_match(/^#{label} +NOT APPLIED: anchor matches 2 times/, out) }
    refute_match(/surviv/i, out)
    refute_match(/caught|^OK:/, out)
  end

  def test_one_unapplied_mutant_fails_the_run_even_when_the_rest_are_caught
    source = with_statement_reworded(crlf_source, "blocker1_trusts_manifest_scope")
    out, code = run_checker(source, CATCHING)
    assert_equal 1, code, out
    assert_match(/^blocker1_trusts_manifest_scope +NOT APPLIED: anchor not found/, out)
    assert_match(/^blocker2_ignores_type_drift +caught: 1 runs, \d+ assertions, 1 failures/, out)
    assert_match(/^PROBLEM: 1 mutant\(s\) NOT APPLIED\./, out)
    refute_match(/^OK:/, out)
  end

  def test_a_catching_suite_passes_on_lf_and_on_crlf
    flavours.each do |flavour, (source, _eol)|
      out, code = run_checker(source, CATCHING)
      assert_equal 0, code, "#{flavour}:\n#{out}"
      assert_match(/^baseline \(unmutated copy\) +green: 2 runs, \d+ assertions, 0 failures, 0 errors/, out)
      MUTANTS.each_key do |label|
        assert_match(/^#{label} +caught: 1 runs, \d+ assertions, 1 failures/, out)
      end
      assert_match(/^OK: every blocker fix is load-bearing\./, out)
    end
  end

  def test_a_blind_suite_reports_survivors_not_unapplied_edits
    out, code = run_checker(crlf_source, BLIND)
    assert_equal 1, code, out
    MUTANTS.each_key { |label| assert_match(/^#{label} +SURVIVED: the suite stayed green/, out) }
    assert_match(/^PROBLEM: 2 mutant\(s\) SURVIVED\./, out)
    refute_match(/NOT APPLIED/, out)
  end

  def test_a_red_baseline_runs_no_mutant
    out, code = run_checker(crlf_source, RED)
    assert_equal 1, code, out
    assert_match(/^baseline \(unmutated copy\) +NOT GREEN: /, out)
    MUTANTS.each_key { |label| assert_match(/^#{label} +NOT RUN: /, out) }
    assert_match(/^PROBLEM: the unmutated copy is NOT GREEN/, out)
    refute_match(/caught|^OK:/, out)
  end

  def test_a_suite_that_will_not_load_is_no_verdict_not_a_catch
    out, code = run_checker(crlf_source, CRASHING)
    assert_equal 1, code, out
    MUTANTS.each_key { |label| assert_match(/^#{label} +NO VERDICT: no test results/, out) }
    assert_match(/^PROBLEM: 2 mutant run\(s\) gave NO VERDICT\./, out)
    refute_match(/caught|^OK:/, out)
  end

  def test_the_load_only_flag_cannot_make_a_direct_run_pass
    out, code = run_checker(crlf_source, CATCHING,
                            env: { "TRANSCRIPT_DELTA_MUTATION_CHECK_LIB" => "1" })
    refute_equal 0, code, out
    assert_match(/nothing was checked/, out)
  end
end
