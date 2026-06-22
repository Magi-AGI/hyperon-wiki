# frozen_string_literal: true
#
# Proves the mod ENTRY (lib/atomspace_mirror.rb) requires the WHOLE engine -- including the Slice 3
# drain core -- so the deck initializer's `require "atomspace_mirror"` makes everything available at
# runtime. Requiring files directly in the other specs does NOT prove this (Codex load-chain
# blocker). A minimal ActiveRecord stub lets the AR-model files load without a Rails boot.

unless defined?(ActiveRecord)
  module ActiveRecord
    class Base
      def self.table_name=(value)
        @table_name = value
      end

      def self.table_name
        @table_name
      end
    end
    class RecordNotUnique < StandardError; end
  end
end

require_relative "../../mod/atomspace_mirror/lib/atomspace_mirror"

RSpec.describe "engine load chain" do
  it "defines every engine constant after requiring the mod entry point" do
    %w[
      MirrorState MirrorOutbox MirrorBootstrapRun MirrorReconcileRun
      ReadConsistency CardAtomEncoder MirrorOutboxWriter
      Mirror MirrorDrainValidator SidecarClient DrainDelivery DrainWorker
    ].each do |const|
      expect(Object.const_defined?(const)).to be(true), "#{const} was not loaded by the mod entry point"
    end
  end
end
