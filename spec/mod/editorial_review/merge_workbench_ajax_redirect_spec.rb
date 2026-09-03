# frozen_string_literal: true

require "rspec"

# CP006E — the merge workbench's AJAX save handling must not report a COMMITTED
# save as a network failure.
#
# THE BUG. Decko POST-redirect-GETs on a successful /card/update: it answers
# `303 See Other` pointing at the deck's CONFIGURED origin. When the browser is
# on a different origin than that configured one (the local stack serves the
# same deck on http://127.0.0.1:3100 while the deck is configured for its
# production host), `fetch`'s default `redirect: 'follow'` chases the redirect
# cross-origin, CORS blocks the follow-up GET, and the promise REJECTS. The
# workbench's `.catch` then told the human "Network error ... The parent was NOT
# changed." — after the server had already created the merge draft / written the
# parent. A false negative on the success path, which is worse than a plain
# error: it invites a destructive retry.
#
# THE FIX under test is client-side and narrow: post with `redirect: 'manual'`
# so fetch STOPS at the redirect instead of chasing it, and read the redirect
# itself as the server's success verdict (Decko rejects with a non-redirect
# status + JSON errors, never with a redirect). Rejection handling is unchanged,
# so true 403/validation failures and pre-response network failures still fail
# closed.
#
# WHY THIS SPEC IS Rails-FREE. It asserts on the JS source that
# mod/editorial_review/set/right/proposal.rb emits inline, which needs neither a
# Decko boot nor a database. Keeping it free of `spec_helper` means the guard
# runs in a plain `rspec` as well as inside the DB-backed runner, and it lets
# the behavioural Node harness (spec/javascripts/ws6_merge_workbench_ajax_spec.js)
# be driven from here wherever `node` exists. The Decko runtime image ships no
# JS runtime, so that harness is skipped there and only the structural guards
# below apply.
RSpec.describe "WS6 merge workbench AJAX redirect handling" do
  REPO_ROOT = File.expand_path("../../..", __dir__)
  PROPOSAL_RB = File.join(REPO_ROOT, "mod", "editorial_review", "set", "right", "proposal.rb")
  MERGE_DRAFT_RB = File.join(REPO_ROOT, "mod", "editorial_review", "set", "right", "merge_draft.rb")
  NODE_HARNESS = File.join(REPO_ROOT, "spec", "javascripts", "ws6_merge_workbench_ajax_spec.js")

  # The inline JS, extracted from its squiggly heredoc exactly as the deck emits
  # it. CRLF-normalized so a Windows checkout does not change what we match.
  def workbench_js
    src = File.read(PROPOSAL_RB).gsub("\r\n", "\n")
    body = src[/^WS6_MW_JS = <<~'WS6JS'\n(.*?)^WS6JS$/m, 1]
    raise "WS6_MW_JS heredoc not found in #{PROPOSAL_RB}" unless body

    indent = body.lines.reject { |l| l.strip.empty? }.map { |l| l[/\A */].size }.min.to_i
    body.lines.map { |l| l[indent..] || l }.join
  end

  let(:js) { workbench_js }

  # Every `fetch(...)` init object in the workbench JS, keyed by the URL posted
  # to, so a new call site cannot quietly opt back into redirect-following.
  def fetch_inits(js)
    js.scan(/fetch\(\s*'([^']+)'\s*,\s*\{(.*?)\n(\s*)\}\)/m).map do |url, init, _|
      [url, init]
    end
  end

  describe "the /card/update save transport" do
    it "routes the seed AND apply POSTs through one shared transport" do
      # A single call site is the point: the two paths cannot drift apart on
      # what they send or on how they read a redirect.
      expect(js.scan("'/card/update'").size).to eq(1)
      expect(js.scan(/function postCardUpdate\(/).size).to eq(1)
      # Two callers (seed + apply), excluding the definition itself.
      expect(js.scan(/(?<!function )postCardUpdate\(fd, token\)/).size).to eq(2)
    end

    it "opts the /card/update POST out of following redirects" do
      inits = fetch_inits(js).select { |url, _| url == "/card/update" }
      expect(inits.size).to eq(1)
      _url, init = inits.first
      expect(init).to include("redirect: 'manual'"),
                      "the /card/update POST must set redirect: 'manual' so a " \
                      "configured-origin 303 cannot surface as a network failure; got:\n#{init}"
    end

    it "keeps the authenticated, same-origin, CSRF-stamped posting contract" do
      _url, init = fetch_inits(js).find { |url, _| url == "/card/update" }
      expect(init).to include("method: 'POST'")
      expect(init).to include("credentials: 'same-origin'")
      expect(init).to include("'X-CSRF-Token': token")
    end
  end

  describe "the success predicate" do
    it "accepts an opaque redirect as a committed save" do
      expect(js).to include("opaqueredirect")
    end

    it "accepts a visible 3xx as a committed save" do
      expect(js).to match(/status\s*>=\s*300\s*&&\s*.*status\s*<\s*400/)
    end

    it "still accepts a normal 2xx" do
      expect(js).to match(/res\.ok/)
    end
  end

  describe "fail-closed behaviour that must NOT be weakened" do
    it "still reports a non-redirect rejection on the seed path" do
      expect(js).to include("Could not create the merge draft (HTTP '")
    end

    it "still detects the stale-parent rejection and reloads" do
      expect(js).to match(%r{/parent changed\|parent_act_id/i})
      expect(js).to include("window.location.reload()")
    end

    it "still reports a non-redirect rejection on the apply path, echoing the server reason" do
      expect(js).to include("Apply rejected (HTTP '")
      expect(js).to include("serverErrors(body)")
      expect(js).to include("The parent was NOT changed.")
    end

    it "never treats a pre-response network failure as success" do
      # Both catch blocks must report failure; neither may navigate or claim a
      # commit. A catch fires BEFORE any response, so it is not proof of a save.
      catches = js.scan(/\.catch\(function \([^)]*\) \{(.*?)\n(\s*)\}\)/m).map(&:first)
      expect(catches.size).to eq(2)
      catches.each do |body|
        expect(body).to match(/Network error/)
        expect(body).not_to include("window.location.href")
        expect(body).not_to include("setApplyStatus('ok'")
      end
    end

    it "does not report 'NOT changed' on the apply success branch" do
      # The success branch is keyed off the shared predicate, so a future call
      # site cannot diverge on what "saved" means.
      # Anchored to the APPLY branch (the multi-line one); the seed branch is a
      # single-line `if (savedOk(res)) { ... }`.
      success = js[/if \(savedOk\(res\)\) \{\n(.*?)\n(\s*)\}/m, 1]
      expect(success).not_to be_nil, "apply must branch on the shared savedOk(res) predicate"
      expect(success).to include("setApplyStatus('ok'")
      expect(success).not_to include("NOT changed")
    end
  end

  describe "server-side gates are untouched by this client-side fix" do
    it "keeps the CP006C proposal-mode fail-closed gate on the workbench view" do
      rb = File.read(PROPOSAL_RB)
      expect(rb).to include("ProposalMode.for_proposal(card)")
      expect(rb).to include("unless mode_info[:mergeable]")
      expect(rb).to include("ProposalMode.blocked_notice_html")
    end

    it "keeps the Phase 8.1 capability gate on the legacy bridge" do
      rb = File.read(PROPOSAL_RB)
      expect(rb).to include("event :guard_legacy_bridge")
      expect(rb).to include("unless parent&.ok?(:update)")
    end

    it "keeps the seed-side mode gate, parent optimistic lock and apply gate" do
      rb = File.read(MERGE_DRAFT_RB)
      expect(rb).to include("errors.add(:proposal_mode")
      expect(rb).to include("errors.add(:parent_act_id")
      expect(rb).to include("event :apply_merge_draft")
      expect(rb).to include("def merge_apply_reject")
    end
  end

  # Behavioural coverage: drives the real handlers over stubbed responses.
  # Skipped where no JS runtime exists (notably the Decko runtime image).
  describe "behavioural harness", if: (system("node --version > #{File::NULL} 2>&1") ? true : false) do
    it "passes the WS6 merge-workbench AJAX behaviour suite" do
      output = `node "#{NODE_HARNESS}" 2>&1`
      expect($CHILD_STATUS || $?).to be_success, "node harness failed:\n#{output}"
    end
  end
end
