# frozen_string_literal: true

require "spec_helper"

RSpec.describe McpApi::MarkdownConverter do
  describe ".markdown_to_html" do
    it "converts basic markdown to HTML" do
      markdown = "# Hello\n\nThis is **bold** and *italic*."
      html = described_class.markdown_to_html(markdown)

      expect(html).to include("<h1>Hello</h1>")
      expect(html).to include("<strong>bold</strong>")
      expect(html).to include("<em>italic</em>")
    end

    it "preserves wiki links" do
      markdown = "See [[Card+Name]] and [[Another+Card|Label]]"
      html = described_class.markdown_to_html(markdown)

      expect(html).to include("[[Card+Name]]")
      expect(html).to include("[[Another+Card|Label]]")
    end

    it "handles complex nested lists" do
      markdown = <<~MD
        - Item 1
          - Nested item
            - Deep nested
        - Item 2
      MD

      html = described_class.markdown_to_html(markdown)

      expect(html).to include("<ul>")
      expect(html).to include("<li>")
      expect(html).to match(/<ul>.*<ul>.*<ul>/m) # Nested lists
    end

    it "handles code blocks" do
      markdown = <<~MD
        ```ruby
        def hello
          puts "world"
        end
        ```
      MD

      html = described_class.markdown_to_html(markdown)

      expect(html).to include("<code>")
      expect(html).to include("def hello")
    end

    it "handles tables (GFM)" do
      markdown = <<~MD
        | Name | Value |
        |------|-------|
        | Foo  | Bar   |
      MD

      html = described_class.markdown_to_html(markdown)

      expect(html).to include("<table>")
      expect(html).to include("<th>Name</th>")
      expect(html).to include("<td>Foo</td>")
    end

    it "sanitizes script tags" do
      markdown = "<script>alert('xss')</script>\n\n# Safe content"
      html = described_class.markdown_to_html(markdown)

      expect(html).not_to include("<script>")
      expect(html).to include("Safe content")
    end

    it "sanitizes style tags" do
      markdown = "<style>body { display: none; }</style>\n\n# Content"
      html = described_class.markdown_to_html(markdown)

      expect(html).not_to include("<style>")
      expect(html).to include("Content")
    end

    it "returns empty string for nil input" do
      expect(described_class.markdown_to_html(nil)).to eq("")
    end

    it "returns empty string for empty input" do
      expect(described_class.markdown_to_html("")).to eq("")
    end

    it "preserves wiki links with special characters" do
      markdown = "Link to [[Games+Butterfly Galaxii+Player]]"
      html = described_class.markdown_to_html(markdown)

      expect(html).to include("[[Games+Butterfly Galaxii+Player]]")
    end
  end

  describe ".html_to_markdown" do
    it "converts basic HTML to Markdown" do
      html = "<h1>Hello</h1><p>This is <strong>bold</strong>.</p>"
      markdown = described_class.html_to_markdown(html)

      expect(markdown).to include("# Hello")
      expect(markdown).to include("**bold**")
    end

    it "preserves wiki links" do
      html = "<p>See [[Card+Name]] for details.</p>"
      markdown = described_class.html_to_markdown(html)

      expect(markdown).to include("[[Card+Name]]")
    end

    it "handles lists" do
      html = "<ul><li>Item 1</li><li>Item 2</li></ul>"
      markdown = described_class.html_to_markdown(html)

      expect(markdown).to include("- Item 1")
      expect(markdown).to include("- Item 2")
    end

    it "handles links" do
      html = '<a href="http://example.com">Link</a>'
      markdown = described_class.html_to_markdown(html)

      expect(markdown).to include("[Link](http://example.com)")
    end

    it "returns empty string for nil input" do
      expect(described_class.html_to_markdown(nil)).to eq("")
    end

    it "returns empty string for empty input" do
      expect(described_class.html_to_markdown("")).to eq("")
    end

    it "preserves multiple wiki links" do
      html = "<p>See [[Card1]] and [[Card2|Label]]</p>"
      markdown = described_class.html_to_markdown(html)

      expect(markdown).to include("[[Card1]]")
      expect(markdown).to include("[[Card2|Label]]")
    end
  end

  describe "round-trip conversion" do
    it "preserves content through markdown -> html -> markdown" do
      original = "# Title\n\nSee [[Wiki+Link]] for **details**."
      html = described_class.markdown_to_html(original)
      back_to_markdown = described_class.html_to_markdown(html)

      expect(back_to_markdown).to include("# Title")
      expect(back_to_markdown).to include("[[Wiki+Link]]")
      expect(back_to_markdown).to include("**details**")
    end
  end
end
