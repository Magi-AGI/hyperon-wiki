# frozen_string_literal: true
#
# L5 drift detection (Slice 5a) -- the three pure-Postgres stream monitors + the DriftRunner shell.
# STANDALONE: the SQL builders are asserted as strings; the threshold/streak logic + the runner run
# against a stubbed connection + injected emitter/clock (no Decko boot, no DB).

require_relative "../../mod/atomspace_mirror/lib/drift_monitor"
require_relative "../../mod/atomspace_mirror/lib/drift_runner"

RSpec.describe DriftMonitor do
  describe "SQL builders (locked Section 2 shape)" do
    it "1a tail-lag count: verbatim MAX(card_actions)-MAX(outbox), both scoped > a_start and COALESCEd" do
      sql = DriftMonitor.hook_tail_lag_actions_sql(100)
      expect(sql).to include("MAX(id) FROM card_actions").and include("id > 100 AND draft IS NOT TRUE")
      expect(sql).to include("MAX(action_id) FROM mirror_outbox")
      expect(sql).to include("event_kind = 'decko_action'")
      expect(sql.scan("COALESCE").size).to eq(2)          # both operands fall back to a_start
      expect(sql.scan(/\b100\b/).size).to be >= 4         # 2 filters + 2 COALESCE fallbacks
    end

    it "1a tail-lag seconds: TAIL-ONLY (above the outbox head), never interior gaps (Codex)" do
      sql = DriftMonitor.hook_tail_lag_seconds_sql(100)
      expect(sql).to include("EXTRACT(EPOCH FROM (now() - MIN(act.acted_at)))")
      expect(sql).to include("JOIN card_acts act ON act.id = ca.card_act_id")
      expect(sql).to include("draft IS NOT TRUE")
      # tail head = GREATEST(a_start, MAX mirrored action_id); interior-gap detection is 1b's job only
      expect(sql).to include("ca.id > GREATEST(").and include("MAX(action_id) FROM mirror_outbox")
      expect(sql).not_to include("NOT EXISTS")
      expect(sql).to include("COALESCE(EXTRACT")               # null -> 0, never NULL
    end

    it "1b coverage-gap count: verbatim LEFT JOIN ... mo.action_id IS NULL" do
      sql = DriftMonitor.coverage_gap_count_sql(100)
      expect(sql).to include("COUNT(*) AS coverage_gap_count")
      expect(sql).to include("LEFT JOIN mirror_outbox mo")
      expect(sql).to include("mo.event_kind = 'decko_action'").and include("mo.action_id  = ca.id")
      expect(sql).to include("ca.id > 100").and include("ca.draft IS NOT TRUE").and include("mo.action_id IS NULL")
    end

    it "1b sample: lowest N gap ids, ordered ASC, limit coerced to integer" do
      sql = DriftMonitor.coverage_gap_sample_sql(100, 10)
      expect(sql).to include("ORDER BY ca.id ASC").and include("LIMIT 10")
      expect(DriftMonitor.coverage_gap_sample_sql(0, "7; DROP")).to include("LIMIT 7")  # .to_i strips injection
    end

    it "2 drain watermark: reuses the single-source Mirror SQL with all four advance statuses" do
      sql = Mirror.contiguous_watermark_sql(100)
      Mirror::TERMINAL_ADVANCE_STATUSES.each { |s| expect(sql).to include("'#{s}'") }
      expect(sql).to include("GREATEST")
    end

    it "2 outbox head + drain-lag seconds scope to decko_action above a_start" do
      head = DriftMonitor.max_decko_action_sql(100)
      expect(head).to include("MAX(action_id) FROM mirror_outbox").and include("action_id > 100")
      secs = DriftMonitor.drain_lag_seconds_sql(100)
      expect(secs).to include("status NOT IN (").and include("now() - MIN(created_at)")
      Mirror::TERMINAL_ADVANCE_STATUSES.each { |s| expect(secs).to include("'#{s}'") }
    end
  end

  describe ".hook_tail_lag thresholds" do
    def run(actions, seconds)
      conn = double("conn")
      allow(conn).to receive(:select_value).and_return(actions, seconds)  # actions sql, then seconds sql
      DriftMonitor.hook_tail_lag(100, conn: conn)
    end

    it "ok below both thresholds" do
      expect(run(10, 60.0)[:status]).to eq("ok")              # exactly at threshold = not over
    end

    it "alerts when action lag exceeds the threshold" do
      r = run(11, 0.0)
      expect(r[:status]).to eq("alert")
      expect(r[:lag_actions]).to eq(11)
    end

    it "alerts when the seconds lag exceeds the threshold (even with 0 action lag)" do
      expect(run(0, 60.001)[:status]).to eq("alert")
    end
  end

  describe ".coverage_gap consecutive-run streak" do
    def conn_with(count, ids = [])
      conn = double("conn")
      allow(conn).to receive(:select_value).and_return(count)
      allow(conn).to receive(:select_values).and_return(ids)
      conn
    end

    it "a single transient gap does NOT alert (streak 1 < 2)" do
      r = DriftMonitor.coverage_gap(100, conn: conn_with(3, [101, 102, 103]), prior_nonzero_runs: 0)
      expect(r[:gap_count]).to eq(3)
      expect(r[:gap_action_ids]).to eq([101, 102, 103])
      expect(r[:consecutive_nonzero_runs]).to eq(1)
      expect(r[:status]).to eq("ok")
    end

    it "two consecutive nonzero runs alert" do
      r = DriftMonitor.coverage_gap(100, conn: conn_with(1, [101]), prior_nonzero_runs: 1)
      expect(r[:consecutive_nonzero_runs]).to eq(2)
      expect(r[:status]).to eq("alert")
    end

    it "a zero-count run resets the streak and reports no sample" do
      r = DriftMonitor.coverage_gap(100, conn: conn_with(0), prior_nonzero_runs: 5)
      expect(r[:consecutive_nonzero_runs]).to eq(0)
      expect(r[:gap_action_ids]).to eq([])
      expect(r[:status]).to eq("ok")
    end
  end

  describe ".drain_lag" do
    it "lag = outbox head - watermark; alerts past the action threshold" do
      conn = double("conn")
      # call order: watermark (GREATEST), outbox_head (MAX), lag_seconds (EXTRACT)
      allow(conn).to receive(:select_value).and_return(100, 161, 0.0)
      r = DriftMonitor.drain_lag(100, conn: conn)
      expect(r[:watermark]).to eq(100)
      expect(r[:outbox_head]).to eq(161)
      expect(r[:lag_actions]).to eq(61)
      expect(r[:status]).to eq("alert")            # 61 > 50
    end

    it "ok when fully drained" do
      conn = double("conn")
      allow(conn).to receive(:select_value).and_return(500, 500, 0.0)
      expect(DriftMonitor.drain_lag(100, conn: conn)[:status]).to eq("ok")
    end
  end
end

RSpec.describe DriftRunner do
  let(:emitted) { [] }
  let(:t0) { Time.utc(2026, 6, 24, 12, 0, 0) }
  let(:conn) { double("conn") }

  def runner(clock: -> { t0 })
    DriftRunner.new(emitter: ->(r) { emitted << r }, clock: clock,
                    a_start_provider: -> { 100 }, conn: conn)
  end

  it "stamps each report with ts + duration_ms and emits it" do
    allow(DriftMonitor).to receive(:hook_tail_lag).and_return({ mechanism: "hook_tail_lag", status: "ok" })
    report = runner.run_hook_tail_lag
    expect(report[:ts]).to eq(t0.iso8601)
    expect(report[:duration_ms]).to be_a(Float)
    expect(emitted.last).to include(mechanism: "hook_tail_lag", status: "ok")
  end

  it "passes the prior streak through coverage_gap and stores the returned streak" do
    seen = []
    allow(DriftMonitor).to receive(:coverage_gap) do |_a, **kw|
      seen << kw[:prior_nonzero_runs]
      { mechanism: "coverage_gap", consecutive_nonzero_runs: kw[:prior_nonzero_runs] + 1, status: "ok" }
    end
    r = runner
    r.run_coverage_gap
    r.run_coverage_gap
    expect(seen).to eq([0, 1])                    # streak threaded across runs
  end

  it "catches a mechanism error, emits a structured error report, and does NOT raise" do
    allow(DriftMonitor).to receive(:drain_lag).and_raise(RuntimeError, "boom")
    expect { @ret = runner.run_drain_lag }.not_to raise_error
    expect(@ret).to be_nil
    expect(emitted.last).to include(mechanism: "drain_lag", status: "error")
    expect(emitted.last[:error]).to match(/RuntimeError: boom/)
  end

  describe "#check_heartbeats (missed-run watchdog)" do
    it "does NOT report never-run mechanisms before their first scheduled opportunity (fresh start)" do
      # started_at = t0; at t0+59 nothing has exceeded SKIP_FACTOR x cadence (hook 60s/drain 120s/gap 600s)
      expect(runner.check_heartbeats(now: t0 + 59)).to be_empty
      expect(emitted).to be_empty
    end

    it "reports a never-run mechanism once SKIP_FACTOR x cadence has elapsed since boot" do
      skipped = runner.check_heartbeats(now: t0 + 61)         # hook_tail_lag 2*30 = 60 < 61
      expect(skipped).to eq(["hook_tail_lag"])                # drain (120) / gap (600) not yet due
      expect(emitted.last).to include(signal: "mechanism_run_skipped", last_success: nil)
    end

    it "does not report a mechanism that ran within SKIP_FACTOR x cadence" do
      allow(DriftMonitor).to receive(:hook_tail_lag).and_return({ mechanism: "hook_tail_lag", status: "ok" })
      r = runner
      r.run_hook_tail_lag                                   # last_success = t0 (cadence 30s)
      skipped = r.check_heartbeats(now: t0 + 59)            # < 2*30
      expect(skipped).not_to include("hook_tail_lag")
    end

    it "reports a mechanism stale past SKIP_FACTOR x cadence" do
      allow(DriftMonitor).to receive(:hook_tail_lag).and_return({ mechanism: "hook_tail_lag", status: "ok" })
      r = runner
      r.run_hook_tail_lag
      expect(r.check_heartbeats(now: t0 + 61)).to include("hook_tail_lag")  # > 2*30
    end
  end
end
