# frozen_string_literal: true
#
# L8 Mirror constants + the Section 2 contiguous-watermark SQL builder. The SQL builder is pure
# (STANDALONE); compute_contiguous_watermark execution is DB-gated and validated on the dev box.

require_relative "../../mod/atomspace_mirror/lib/mirror"

RSpec.describe Mirror do
  describe "DRAIN_LOCK_ID" do
    it "is the signed-int64-safe value (not the overflowing 0xA705...)" do
      expect(Mirror::DRAIN_LOCK_ID).to eq(0x7705_BEEF_DEAD_F00D)
      expect(Mirror::DRAIN_LOCK_ID).to be <= (2**63 - 1)
      expect(Mirror::DRAIN_LOCK_ID).to be >= -(2**63)
      expect(0xA705_BEEF_DEAD_F00D).to be > (2**63 - 1) # documents why the original overflows
    end
  end

  describe "contiguous_watermark_sql (pure)" do
    let(:sql) { Mirror.contiguous_watermark_sql(100) }

    it "embeds exactly the four terminal-advance statuses" do
      Mirror::TERMINAL_ADVANCE_STATUSES.each { |s| expect(sql).to include("'#{s}'") }
      expect(Mirror::TERMINAL_ADVANCE_STATUSES).to contain_exactly(
        "delivered", "superseded_by_bootstrap", "superseded_by_later", "superseded_by_reconcile"
      )
    end

    it "is the hole-aware contiguous-prefix formula scoped to action_id > a_start" do
      expect(sql).to include("MIN(action_id) - 1")  # one below the lowest hole
      expect(sql).to include("MAX(action_id)")      # fallback: max terminal when no holes
      expect(sql).to include("NOT IN")              # holes
      expect(sql).to include("action_id > 100")     # scoped above a_start (bound coerced to_i)
      expect(sql).to include("event_kind = 'decko_action'")
      expect(sql).to include("GREATEST")            # clamp >= a_start
    end

    it "coerces a_start to an integer (no injection surface)" do
      expect(Mirror.contiguous_watermark_sql("5; DROP TABLE x")).to include("action_id > 5")
    end
  end
end
