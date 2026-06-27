# frozen_string_literal: true

require "spec_helper"
require_relative "../../../mod/editorial_review/lib/base_resolver"

# Pure unit specs for the WS6 BaseResolver tier logic — no database needed.
RSpec.describe BaseResolver do
  describe ".classify" do
    it "stamped + matching hash => :verified" do
      expect(described_class.classify(stamped: true, base_hash_ok: true, window_count: 0)).to eq(:verified)
    end

    it "stamped + hash mismatch => :stale (hard failure, never silent 3-way)" do
      expect(described_class.classify(stamped: true, base_hash_ok: false, window_count: 0)).to eq(:stale)
    end

    it "unstamped + no nearby revisions => :estimated (unambiguous old base)" do
      expect(described_class.classify(stamped: false, base_hash_ok: false, window_count: 0)).to eq(:estimated)
    end

    it "unstamped + exactly one nearby revision => :estimated" do
      expect(described_class.classify(stamped: false, base_hash_ok: false, window_count: 1)).to eq(:estimated)
    end

    it "unstamped + two-or-more nearby revisions => :unreliable (race)" do
      expect(described_class.classify(stamped: false, base_hash_ok: false, window_count: 2)).to eq(:unreliable)
      expect(described_class.classify(stamped: false, base_hash_ok: false, window_count: 5)).to eq(:unreliable)
    end
  end

  describe ".three_way?" do
    it "is true only for :verified and :estimated" do
      expect(described_class.three_way?(:verified)).to be true
      expect(described_class.three_way?(:estimated)).to be true
      expect(described_class.three_way?(:stale)).to be false
      expect(described_class.three_way?(:unreliable)).to be false
    end
  end
end
