# frozen_string_literal: true
#
# L4 bootstrap runner -- the #run_locked orchestration (guard -> empty-Space -> A_start -> run row ->
# sweep -> completion). STANDALONE: stubbed MirrorBootstrapRun / MirrorState / MirrorOutbox / Card +
# an injected sidecar (no Decko boot, no DB). The advisory lock + real DB are dev-gated (#run).

require_relative "../../mod/atomspace_mirror/lib/bootstrap"

RSpec.describe Bootstrap do
  FakeCard = Struct.new(:id)

  class BRun
    attr_accessor :id, :a_start, :status, :last_card_id_swept, :completed_at, :cards_swept, :actor, :started_at
    attr_reader :updates
    def initialize(**attrs)
      @id = 1
      @updates = []
      attrs.each { |k, v| public_send("#{k}=", v) }
    end

    def update!(**attrs)
      @updates << attrs
      attrs.each { |k, v| public_send("#{k}=", v) if respond_to?("#{k}=") }
      true
    end
  end

  class BState
    attr_reader :updates
    def initialize; @updates = []; end
    def update!(**attrs); @updates << attrs; true; end
  end

  class BSidecar
    attr_reader :bulk_calls
    def initialize(atom_count: 0, bulk: nil)
      @atom_count = atom_count
      @bulk = bulk
      @bulk_calls = []
    end

    def space_stats; { "atom_count" => @atom_count }; end

    def bulk_load(atoms)
      @bulk_calls << atoms
      return @bulk.call(atoms) if @bulk
      atoms.length
    end
  end

  def stub_models(running: false, batches: [], run: BRun.new)
    mbr = Class.new
    mbr.define_singleton_method(:where) { |**_| Object.new.tap { |o| o.define_singleton_method(:exists?) { running } } }
    mbr.define_singleton_method(:create!) do |**attrs|
      attrs.each { |k, v| run.public_send("#{k}=", v) if run.respond_to?("#{k}=") }
      run
    end
    stub_const("MirrorBootstrapRun", mbr)

    @state = BState.new
    state = @state
    ms = Class.new
    ms.define_singleton_method(:lock) { Object.new.tap { |o| o.define_singleton_method(:first) { state } } }
    stub_const("MirrorState", ms)

    @captured = []
    captured = @captured
    mo = Class.new
    mo.define_singleton_method(:transaction) { |&blk| blk.call }
    mo.define_singleton_method(:where) do |**cond|
      rel = Object.new
      rel.define_singleton_method(:where) do |sql, *args|
        Object.new.tap { |o| o.define_singleton_method(:update_all) { |attrs| captured << [cond, sql, args, attrs] } }
      end
      rel
    end
    stub_const("MirrorOutbox", mo)

    card = Class.new
    card.define_singleton_method(:where) do |**_|
      Object.new.tap { |o| o.define_singleton_method(:find_in_batches) { |**_kw, &blk| batches.each { |b| blk.call(b) } } }
    end
    stub_const("Card", card)
    run
  end

  before { allow(CardAtomEncoder).to receive(:encode_card_snapshot) { |c| [{ "atom" => "DeckoCard", "fields" => [["Id", c.id]] }] } }

  it "happy path: sweeps batches, bulk-loads, then completes (supersede + activate draining)" do
    run = stub_models(batches: [[FakeCard.new(1), FakeCard.new(2)], [FakeCard.new(3)]])
    sc = BSidecar.new(atom_count: 0)
    bs = Bootstrap.new(sidecar: sc)
    allow(bs).to receive(:snapshot_a_start).and_return(100)

    result = bs.run_locked

    expect(result.status).to eq("completed")
    expect(result.a_start).to eq(100)
    expect(result.cards_swept).to eq(3)
    expect(result.last_card_id_swept).to eq(3)
    expect(sc.bulk_calls.size).to eq(2)                      # one /bulk_load per batch
    expect(@state.updates).to include(hash_including(bootstrap_a_start: 100, last_drained_action_id: 100, draining_enabled: true))
    # pre-A_start queued rows superseded in the completion txn
    cond, sql, args, attrs = @captured.first
    expect(cond).to eq(status: "queued")
    expect(sql).to match(/action_id <= /)
    expect(args).to eq([100])
    expect(attrs).to eq(status: "superseded_by_bootstrap")
  end

  it "refuses to start when a run is already 'running' (single-run guard)" do
    stub_models(running: true)
    bs = Bootstrap.new(sidecar: BSidecar.new)
    allow(bs).to receive(:snapshot_a_start).and_return(100)
    expect { bs.run_locked }.to raise_error(Bootstrap::AlreadyRunning)
  end

  it "refuses to load into a non-empty Space (Option A: fresh-sidecar only)" do
    stub_models
    bs = Bootstrap.new(sidecar: BSidecar.new(atom_count: 5))
    expect { bs.run_locked }.to raise_error(Bootstrap::NonEmptySpace, /not empty/)
  end

  it "marks the run 'failed' and re-raises on a bulk_load failure mid-sweep" do
    run = stub_models(batches: [[FakeCard.new(1)]])
    failing = BSidecar.new(atom_count: 0, bulk: ->(_a) { raise SidecarClient::BulkLoadError, "boom" })
    bs = Bootstrap.new(sidecar: failing)
    allow(bs).to receive(:snapshot_a_start).and_return(100)

    expect { bs.run_locked }.to raise_error(SidecarClient::BulkLoadError, /boom/)
    expect(run.status).to eq("failed")
  end
end
