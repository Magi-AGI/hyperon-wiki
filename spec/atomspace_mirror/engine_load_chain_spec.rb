# frozen_string_literal: true
#
# Proves the mod ENTRY (lib/atomspace_mirror.rb) requires the WHOLE engine -- including the Slice 3
# drain core -- so the deck initializer's `require "atomspace_mirror"` makes everything available at
# runtime. Requiring files directly in the other specs does NOT prove this (Codex load-chain
# blocker). A minimal ActiveRecord stub lets the AR-model files load without a Rails boot.

# Robust to a PARTIAL ActiveRecord already defined by another standalone spec (e.g. the writer spec
# defines only ActiveRecord::RecordNotUnique): ensure the module + Base + RecordNotUnique each exist,
# independently, so requiring the AR-model files never hits an uninitialized ActiveRecord::Base.
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

require_relative "../../mod/atomspace_mirror/lib/atomspace_mirror"

RSpec.describe "engine load chain" do
  it "defines every engine constant after requiring the mod entry point" do
    %w[
      MirrorState MirrorOutbox MirrorBootstrapRun MirrorReconcileRun
      ReadConsistency CardAtomEncoder MirrorOutboxWriter
      Mirror MirrorDrainValidator SidecarClient DrainDelivery DrainWorker Bootstrap
    ].each do |const|
      expect(Object.const_defined?(const)).to be(true), "#{const} was not loaded by the mod entry point"
    end
  end
end
