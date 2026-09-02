# frozen_string_literal: true

require_relative "../../../mod/editorial_review/lib/proposal_mode"

# Pure unit specs for the WS6 CP006C proposal-mode gate.
#
# Deliberately self-contained: it requires ONLY the pure lib, not spec_helper,
# so the fail-closed classification can be verified without booting Rails or a
# database. The Card-aware wrapper (.for_proposal) is exercised by the
# integration specs instead.
RSpec.describe ProposalMode do
  describe ".classify — fail closed" do
    it "treats a missing sidecar as not mergeable" do
      r = described_class.classify(nil)
      expect(r[:mergeable]).to be false
      expect(r[:reason]).to eq(:missing)
      expect(r[:mode]).to be_nil
    end

    it "treats a blank or whitespace-only sidecar as missing, not as a mode" do
      ["", "   ", "\n", "\r\n  \t"].each do |raw|
        r = described_class.classify(raw)
        expect(r[:mergeable]).to be(false), "expected #{raw.inspect} to be blocked"
        expect(r[:reason]).to eq(:missing)
      end
    end

    it "treats an unrecognized value as unknown and not mergeable" do
      r = described_class.classify("full replacement please")
      expect(r[:mergeable]).to be false
      expect(r[:known]).to be false
      expect(r[:reason]).to eq(:unknown)
    end

    it "does not let arbitrary prose in the sidecar pass as a mode" do
      expect(described_class.mergeable?("This proposal replaces the parent.")).to be false
    end
  end

  describe ".classify — known but unsupported by this workbench" do
    it "recognizes manual-review-packet but refuses to merge it" do
      r = described_class.classify("manual-review-packet")
      expect(r[:known]).to be true
      expect(r[:mergeable]).to be false
      expect(r[:reason]).to eq(:unsupported_by_workbench)
      expect(r[:mode]).to eq("manual-review-packet")
    end

    it "recognizes diff but refuses to merge it" do
      r = described_class.classify("diff")
      expect(r[:known]).to be true
      expect(r[:mergeable]).to be false
      expect(r[:reason]).to eq(:unsupported_by_workbench)
      expect(r[:mode]).to eq("diff")
    end
  end

  describe ".classify — the one supported mode" do
    it "allows full-replacement" do
      r = described_class.classify("full-replacement")
      expect(r[:known]).to be true
      expect(r[:mergeable]).to be true
      expect(r[:reason]).to eq(:ok)
      expect(r[:mode]).to eq("full-replacement")
    end

    it "tolerates only the surrounding whitespace Decko may store around the token" do
      ["full-replacement\n", "  full-replacement  ", "full-replacement\r\n", "\tfull-replacement"].each do |raw|
        expect(described_class.mergeable?(raw)).to be(true), "expected #{raw.inspect} to be allowed"
      end
    end

    # The approved contract is that the sidecar contains exactly
    # `full-replacement`. Storage whitespace is incidental and forgiven; a
    # different spelling is not the agreed token, so it fails closed rather than
    # being silently coerced into an assertion the author did not write.
    it "is case-sensitive: a differently-cased spelling is not the agreed token" do
      ["Full-Replacement", "FULL-REPLACEMENT", "Full-replacement"].each do |raw|
        r = described_class.classify(raw)
        expect(r[:mergeable]).to be(false), "expected #{raw.inspect} to be blocked"
        expect(r[:reason]).to eq(:unknown)
      end
    end

    it "is case-sensitive for the recognized-but-unsupported labels too" do
      expect(described_class.classify("Manual-Review-Packet")[:reason]).to eq(:unknown)
      expect(described_class.classify("DIFF")[:reason]).to eq(:unknown)
    end

    it "tells the author the token is case-sensitive when it does not match" do
      expect(described_class.rejection_message("Full-Replacement")).to match(/case-sensitive/i)
    end

    it "exposes full-replacement as the only currently mergeable mode" do
      expect(described_class::MERGEABLE_MODES).to eq(["full-replacement"])
      expect(described_class::KNOWN_MODES).to include("manual-review-packet", "diff")
    end
  end

  describe ".sidecar_name" do
    it "builds the +mode sidecar name from the proposal name" do
      expect(described_class.sidecar_name("A+B+proposal")).to eq("A+B+proposal+mode")
    end
  end

  describe ".rejection_message" do
    it "explains a missing mode and names the required sidecar value" do
      msg = described_class.rejection_message(nil)
      expect(msg).to include("+mode")
      expect(msg).to include("full-replacement")
    end

    it "names the offending mode when it is known but unsupported" do
      expect(described_class.rejection_message("diff")).to include("diff")
    end

    it "is nil when the proposal is mergeable" do
      expect(described_class.rejection_message("full-replacement")).to be_nil
    end
  end

  describe ".blocked_notice_html — the fail-closed workbench screen" do
    let(:html) { described_class.blocked_notice_html(nil, proposal_name: "A+B+proposal") }

    it "renders an explicit warning naming the required sidecar" do
      expect(html).to include("alert")
      expect(html).to include("+mode")
      expect(html).to include("full-replacement")
    end

    it "emits none of the merge affordances" do
      expect(html).not_to include("ws6-mw-data")
      expect(html).not_to include('data-ws6="polish"')
      expect(html).not_to include('data-ws6="apply"')
      expect(html).not_to include('data-ws6="assemble"')
      expect(html).not_to include('data-ws6="reset"')
    end

    it "escapes an untrusted mode value from card content" do
      evil = described_class.blocked_notice_html("<script>alert(1)</script>", proposal_name: "A+B+proposal")
      expect(evil).not_to include("<script>alert(1)</script>")
      expect(evil).to include("&lt;script&gt;")
    end

    it "escapes the proposal name" do
      out = described_class.blocked_notice_html(nil, proposal_name: "A+<img src=x>")
      expect(out).not_to include("<img src=x>")
    end
  end
end
