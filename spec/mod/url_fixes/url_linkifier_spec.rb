# frozen_string_literal: true

require "nokogiri"
require_relative "../../../mod/url_fixes/lib/url_linkifier"

RSpec.describe UrlLinkifier do
  def linkified_fragment(html)
    Nokogiri::HTML::DocumentFragment.parse(described_class.linkify_html(html))
  end

  def anchor_for(html, selector = "a[href]")
    linkified_fragment(html).at_css(selector)
  end

  def linkify_times(html, times)
    times.times.reduce(html) { |memo, _| described_class.linkify_html(memo) }
  end

  describe ".linkify_html" do
    context "with authored anchors from the CP056A malformed-href corpus" do
      it "does not absorb a following word into an authored repository anchor" do
        html = %(<li><a href="https://github.com/trueagi-io/chaining">trueagi-io/chaining</a> holds dependent-type-logic chaining.</li>)

        anchor = anchor_for(html, "a[href^='https://github.com/trueagi-io/chaining']")

        expect(anchor["href"]).to eq("https://github.com/trueagi-io/chaining")
        expect(anchor.text).to eq("trueagi-io/chaining")
      end

      it "does not absorb cross-element code tokens into an authored code anchor" do
        html = %(<p>The <a href="https://github.com/trueagi-io/chaining"><code>chaining/</code></a> repository contains DTL, including <code>RuleAtom</code>.</p>)

        anchor = anchor_for(html, "a[href^='https://github.com/trueagi-io/chaining']")

        expect(anchor["href"]).to eq("https://github.com/trueagi-io/chaining")
        expect(anchor.text).to eq("chaining/")
        expect(anchor.at_css("code").text).to eq("chaining/")
      end

      it "does not absorb title prose and punctuation into an authored repo anchor" do
        html = %(<li><a href="https://github.com/trueagi-io/pln-experimental">pln-experimental</a> is a research platform. Its formalization document is titled <em>Towards a Complete Formalization of PLN</em>, and remains in progress.</li>)

        anchor = anchor_for(html, "a[href^='https://github.com/trueagi-io/pln-experimental']")

        expect(anchor["href"]).to eq("https://github.com/trueagi-io/pln-experimental")
        expect(anchor.text).to eq("pln-experimental")
      end

      it "does not absorb parenthetical punctuation into an authored PDF anchor" do
        html = %(<p><em>(See <a href="https://github.com/ngeiswei/presentations/blob/master/2025/AITP-25/ProbEstThrmInfCtrlPrsn.pdf">AITP-25 slides 12–16</a>.)</em></p>)

        anchor = anchor_for(html, "a[href^='https://github.com/ngeiswei']")

        expect(anchor["href"]).to eq("https://github.com/ngeiswei/presentations/blob/master/2025/AITP-25/ProbEstThrmInfCtrlPrsn.pdf")
        expect(anchor.text).to eq("AITP-25 slides 12–16")
      end

      it "does not absorb a following comma or flatten child code in an authored code anchor" do
        html = %(<p>(<a href="https://github.com/trueagi-io/PLN/blob/main/lib_pln.metta"><code>lib_pln.metta</code></a>, source reviewed)</p>)

        anchor = anchor_for(html, "a[href^='https://github.com/trueagi-io/PLN/blob/main/lib_pln.metta']")

        expect(anchor["href"]).to eq("https://github.com/trueagi-io/PLN/blob/main/lib_pln.metta")
        expect(anchor.text).to eq("lib_pln.metta")
        expect(anchor.at_css("code").text).to eq("lib_pln.metta")
      end

      it "does not absorb an em dash separator into an authored example anchor" do
        html = %(<li><a href="https://github.com/trueagi-io/PLN/blob/main/examples/FlyingRaven.metta">FlyingRaven</a> &mdash; deduction chain.</li>)

        anchor = anchor_for(html, "a[href^='https://github.com/trueagi-io/PLN/blob/main/examples/FlyingRaven']")

        expect(anchor["href"]).to eq("https://github.com/trueagi-io/PLN/blob/main/examples/FlyingRaven.metta")
        expect(anchor.text).to eq("FlyingRaven")
      end

      it "does not absorb a following prose word on non-PLN authored anchors" do
        html = %(<p><a href="https://example.com/doc">the docs</a> explain everything.</p>)

        anchor = anchor_for(html, "a[href^='https://example.com/doc']")

        expect(anchor["href"]).to eq("https://example.com/doc")
        expect(anchor.text).to eq("the docs")
      end
    end

    context "with real split autolinker output" do
      it "still rejoins an em dash continuation when the anchor text is the URL" do
        html = %(<p><a href="https://example.com/a">https://example.com/a</a>&mdash;b for details.</p>)

        anchor = anchor_for(html, "a[href^='https://example.com/a']")

        expect(anchor["href"]).to eq("https://example.com/a%E2%80%94b")
        expect(anchor.text).to eq("https://example.com/a—b")
      end

      it "keeps terminal punctuation as following text when rejoining a split URL" do
        html = %(<p><a href="https://example.com/a">https://example.com/a</a>&mdash;b. More.</p>)

        fragment = linkified_fragment(html)
        anchor = fragment.at_css("a[href^='https://example.com/a']")

        expect(anchor["href"]).to eq("https://example.com/a%E2%80%94b")
        expect(anchor.text).to eq("https://example.com/a—b")
        expect(fragment.to_html).to include(%(</a>. More.))
      end

      it "still rejoins www-style autolinker output" do
        html = %(<p><a href="https://www.example.com">www.example.com</a>/path is canonical.</p>)

        anchor = anchor_for(html, "a[href^='https://www.example.com']")

        expect(anchor["href"]).to eq("https://www.example.com/path")
        expect(anchor.text).to eq("www.example.com/path")
      end
    end

    it "is idempotent for authored-anchor and split-autolinker cases" do
      authored = %(<p><a href="https://example.com/doc">the docs</a> explain everything.</p>)
      split = %(<p><a href="https://example.com/a">https://example.com/a</a>&mdash;b for details.</p>)

      expect(linkify_times(authored, 3)).to eq(described_class.linkify_html(authored))
      expect(linkify_times(split, 3)).to eq(described_class.linkify_html(split))
    end

    it "still linkifies a URL with an em dash from a plain text node" do
      html = %(<p>See https://example.com/a—b. Done.</p>)

      anchor = anchor_for(html, "a[href^='https://example.com/a']")

      expect(anchor["href"]).to eq("https://example.com/a%E2%80%94b")
      expect(anchor.text).to eq("https://example.com/a—b")
    end

    it "still unwraps filename-shaped pseudo-url anchors" do
      fragment = linkified_fragment(%(<p><a href="http://nace.py">nace.py</a> remains a filename.</p>))

      expect(fragment.css("a")).to be_empty
      expect(fragment.text).to include("nace.py remains a filename")
    end
  end
end
