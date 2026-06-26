# frozen_string_literal: true
#
# C1 integration seam: the Lane C L9 ReadConsistencyPort (mod/mcp_api), bound to Lane A's REAL L7
# ReadConsistency module (the binding the app-level config/initializers/atomspace_mirror.rb performs
# at boot), delegates `check_event_ready` and fails closed when unbound.
#
# STANDALONE: a minimal ActiveRecord stub lets read_consistency.rb load (it requires the mirror_outbox
# AR model) without a Rails boot; `check_event_ready` is stubbed so NO database is touched -- this
# proves the SEAM (port -> real ReadConsistency), not ReadConsistency's internals (covered by
# read_consistency_spec) or the controller poll loop (covered by the mcp_api controller spec).

module ActiveRecord; end unless defined?(ActiveRecord)
unless defined?(ActiveRecord::Base)
  class ActiveRecord::Base
    def self.table_name=(value)
      @table_name = value
    end

    def self.table_name
      @table_name
    end
  end
end
unless defined?(ActiveRecord::RecordNotUnique)
  class ActiveRecord::RecordNotUnique < StandardError; end
end

require_relative "../../mod/mcp_api/lib/atomspace/read_consistency_port"
require_relative "../../mod/atomspace_mirror/lib/read_consistency"

RSpec.describe "C1: L7 read-consistency binding seam" do
  after { Atomspace::ReadConsistencyPort.reset! }

  it "fails closed (NotWired) when the port is unbound -- never a silent green" do
    Atomspace::ReadConsistencyPort.reset!
    expect { Atomspace::ReadConsistencyPort.check_event_ready("decko:action:1") }
      .to raise_error(Atomspace::ReadConsistencyPort::NotWired)
  end

  it "the real ReadConsistency module satisfies the port's contract method" do
    expect(ReadConsistency).to respond_to(:check_event_ready)
  end

  it "once bound to the real ReadConsistency, the port delegates check_event_ready (the C1 binding)" do
    Atomspace::ReadConsistencyPort.impl = ReadConsistency               # exactly what the initializer does
    allow(ReadConsistency).to receive(:check_event_ready).with("decko:action:42").and_return(:ready)

    expect(Atomspace::ReadConsistencyPort.check_event_ready("decko:action:42")).to eq(:ready)
    expect(ReadConsistency).to have_received(:check_event_ready).with("decko:action:42")
  end

  it "forwards every readiness symbol verbatim (contract: :ready/:not_yet/:not_yet_inserted/:failed/:integrity_error)" do
    Atomspace::ReadConsistencyPort.impl = ReadConsistency
    %i[ready not_yet not_yet_inserted failed integrity_error].each do |sym|
      allow(ReadConsistency).to receive(:check_event_ready).and_return(sym)
      expect(Atomspace::ReadConsistencyPort.check_event_ready("e")).to eq(sym)
    end
  end
end
