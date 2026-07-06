# frozen_string_literal: true
#
# Level 9 read-readiness gate (Phase 5). STANDALONE: requires the module directly with all probes
# injected, so it runs without Decko boot / DB / sidecar (mirrors the drain_worker_spec pattern).
# Locks the fail-closed truth table that keeps the L9 read surface from serving an empty / partial /
# post-restart Space.

require_relative "../../../mod/mcp_api/lib/atomspace/mirror_readiness"

RSpec.describe Atomspace::MirrorReadiness do
  # A minimal mirror_state stand-in.
  State = Struct.new(:bootstrap_a_start, :draining_enabled)

  # Sensible defaults so each example overrides only the probe it exercises; the happy path is READY.
  # expected_cards is the last completed bootstrap's cards_swept (the corpus baseline).
  def wire(enabled: true, state: State.new(100, true), running: false, expected_cards: 9663)
    described_class.enabled_probe        = -> { enabled }
    described_class.state_probe          = -> { state }
    described_class.running_probe        = -> { running }
    described_class.expected_cards_probe = -> { expected_cards }
  end

  # A sidecar reporting a fully-populated Space (DeckoCard count at/above the baseline).
  def ok_sidecar(card_count: 9663) = -> { { reachable: true, card_count: card_count } }

  after { described_class.reset! }

  it "is ready on the fully-green path (sidecar populated at the bootstrap baseline)" do
    wire
    result = described_class.check(ok_sidecar)
    expect(result).to be_ready
    expect(result.reason).to be_nil
  end

  it "is ready when the sidecar has MORE cards than baseline (additive forward path)" do
    wire(expected_cards: 9663)
    expect(described_class.check(ok_sidecar(card_count: 9700))).to be_ready
  end

  it "fails closed mirroring_disabled when the env gate is off" do
    wire(enabled: false)
    expect(described_class.check(ok_sidecar).reason).to eq("mirroring_disabled")
  end

  it "fails closed mirror_tables_unavailable when the state probe reports missing tables" do
    wire(state: :tables_unavailable)
    expect(described_class.check(ok_sidecar).reason).to eq("mirror_tables_unavailable")
  end

  it "fails closed mirror_not_bootstrapped when there is no mirror_state row" do
    wire(state: nil)
    expect(described_class.check(ok_sidecar).reason).to eq("mirror_not_bootstrapped")
  end

  it "fails closed mirror_rebuild_in_progress when a bootstrap run is running" do
    wire(running: true)
    expect(described_class.check(ok_sidecar).reason).to eq("mirror_rebuild_in_progress")
  end

  it "fails closed mirror_not_bootstrapped when bootstrap_a_start is nil" do
    wire(state: State.new(nil, true))
    expect(described_class.check(ok_sidecar).reason).to eq("mirror_not_bootstrapped")
  end

  it "fails closed mirror_not_bootstrapped when draining is disabled" do
    wire(state: State.new(100, false))
    expect(described_class.check(ok_sidecar).reason).to eq("mirror_not_bootstrapped")
  end

  it "fails closed mirror_not_bootstrapped when no completed run gives an expected count (nil)" do
    wire(expected_cards: nil)
    expect(described_class.check(ok_sidecar).reason).to eq("mirror_not_bootstrapped")
  end

  it "fails closed mirror_not_bootstrapped when the expected count is zero" do
    wire(expected_cards: 0)
    expect(described_class.check(ok_sidecar).reason).to eq("mirror_not_bootstrapped")
  end

  it "fails closed sidecar_unreachable when the sidecar probe reports unreachable" do
    wire
    expect(described_class.check(-> { { reachable: false, card_count: 0 } }).reason)
      .to eq("sidecar_unreachable")
  end

  it "fails closed sidecar_empty_post_restart when the Space is reachable but empty" do
    wire
    expect(described_class.check(-> { { reachable: true, card_count: 0 } }).reason)
      .to eq("sidecar_empty_post_restart")
  end

  # Codex C2 regression: a post-restart empty Space that the drain has partially re-applied reports a
  # POSITIVE card_count below the bootstrap baseline. A bare non-empty check would false-green; the
  # cards_swept threshold keeps it not-ready.
  it "fails closed sidecar_below_expected when a partial Space has SOME but < baseline cards" do
    wire(expected_cards: 9663)
    expect(described_class.check(-> { { reachable: true, card_count: 1 } }).reason)
      .to eq("sidecar_below_expected")
  end

  it "fails closed sidecar_below_expected one card short of the baseline" do
    wire(expected_cards: 9663)
    expect(described_class.check(-> { { reachable: true, card_count: 9662 } }).reason)
      .to eq("sidecar_below_expected")
  end

  it "does not call the sidecar probe until the DB-side checks pass (lazy IPC)" do
    wire(enabled: false)
    called = false
    described_class.check(-> { called = true; { reachable: true, card_count: 9663 } })
    expect(called).to be(false)
  end

  it "fails closed readiness_probe_error when a probe raises" do
    wire
    described_class.running_probe = -> { raise "boom" }
    expect(described_class.check(ok_sidecar).reason).to start_with("readiness_probe_error")
  end

  it "the DEFAULT sidecar probe fails closed (production must inject a real probe)" do
    wire # DB-side all green, but no sidecar override -> default {reachable:false}
    expect(described_class.check.reason).to eq("sidecar_unreachable")
  end
end
