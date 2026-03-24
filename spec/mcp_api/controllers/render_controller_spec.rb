# frozen_string_literal: true

require "spec_helper"

RSpec.describe Api::Mcp::RenderController, type: :request do
  include McpApiTestHelper

  let(:token) { generate_jwt_token(role: "user") }
  let(:auth_header) { auth_headers(token) }

  before do
    # Create test service account
    Card::Auth.as_bot do
      unless Card["mcp-user"]
        Card.create!(
          name: "mcp-user",
          type_id: Card.fetch_id(:user)
        )
      end
    end
  end

  describe "POST /api/mcp/render (HTML to Markdown)" do
    it "converts HTML to Markdown" do
      html = "<h1>Title</h1><p>This is <strong>bold</strong> text.</p>"

      post "/api/mcp/render",
           params: { html: html },
           headers: auth_header

      expect(response).to have_http_status(:ok)
      json = json_response

      expect(json["markdown"]).to include("# Title")
      expect(json["markdown"]).to include("**bold**")
      expect(json["format"]).to eq("gfm")
    end

    it "preserves wiki links during conversion" do
      html = "<p>See [[Card+Name]] and [[Another+Card|Label]]</p>"

      post "/api/mcp/render",
           params: { html: html },
           headers: auth_header

      expect(response).to have_http_status(:ok)
      json = json_response

      expect(json["markdown"]).to include("[[Card+Name]]")
      expect(json["markdown"]).to include("[[Another+Card|Label]]")
    end

    it "accepts content parameter as alias" do
      html = "<h2>Heading</h2>"

      post "/api/mcp/render",
           params: { content: html },
           headers: auth_header

      expect(response).to have_http_status(:ok)
      json = json_response

      expect(json["markdown"]).to include("## Heading")
    end

    it "returns error for missing html" do
      post "/api/mcp/render",
           params: {},
           headers: auth_header

      expect(response).to have_http_status(:bad_request)
      json = json_response

      expect(json["error"]["code"]).to eq("validation_error")
      expect(json["error"]["message"]).to include("Missing html or content")
    end

    it "requires authentication" do
      post "/api/mcp/render",
           params: { html: "<p>test</p>" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/mcp/render/markdown (Markdown to HTML)" do
    it "converts Markdown to HTML" do
      markdown = "# Title\n\nThis is **bold** text."

      post "/api/mcp/render/markdown",
           params: { markdown: markdown },
           headers: auth_header

      expect(response).to have_http_status(:ok)
      json = json_response

      expect(json["html"]).to include("<h1>Title</h1>")
      expect(json["html"]).to include("<strong>bold</strong>")
      expect(json["format"]).to eq("html")
    end

    it "preserves wiki links during conversion" do
      markdown = "See [[Card+Name]] for details."

      post "/api/mcp/render/markdown",
           params: { markdown: markdown },
           headers: auth_header

      expect(response).to have_http_status(:ok)
      json = json_response

      expect(json["html"]).to include("[[Card+Name]]")
    end

    it "handles complex markdown features" do
      markdown = <<~MD
        # Header

        - List item 1
        - List item 2

        ```ruby
        def hello
          "world"
        end
        ```

        | Col1 | Col2 |
        |------|------|
        | A    | B    |
      MD

      post "/api/mcp/render/markdown",
           params: { markdown: markdown },
           headers: auth_header

      expect(response).to have_http_status(:ok)
      json = json_response

      expect(json["html"]).to include("<h1>Header</h1>")
      expect(json["html"]).to include("<ul>")
      expect(json["html"]).to include("<li>List item 1</li>")
      expect(json["html"]).to include("<code>")
      expect(json["html"]).to include("<table>")
    end

    it "sanitizes dangerous HTML" do
      markdown = "<script>alert('xss')</script>\n\n# Safe"

      post "/api/mcp/render/markdown",
           params: { markdown: markdown },
           headers: auth_header

      expect(response).to have_http_status(:ok)
      json = json_response

      expect(json["html"]).not_to include("<script>")
      expect(json["html"]).to include("Safe")
    end

    it "accepts content parameter as alias" do
      markdown = "## Heading"

      post "/api/mcp/render/markdown",
           params: { content: markdown },
           headers: auth_header

      expect(response).to have_http_status(:ok)
      json = json_response

      expect(json["html"]).to include("<h2>Heading</h2>")
    end

    it "returns error for missing markdown" do
      post "/api/mcp/render/markdown",
           params: {},
           headers: auth_header

      expect(response).to have_http_status(:bad_request)
      json = json_response

      expect(json["error"]["code"]).to eq("validation_error")
      expect(json["error"]["message"]).to include("Missing markdown or content")
    end

    it "requires authentication" do
      post "/api/mcp/render/markdown",
           params: { markdown: "# test" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "round-trip conversion" do
    it "preserves content through both conversions" do
      original_markdown = "# Title\n\nSee [[Wiki+Link]] for **details**."

      # Markdown → HTML
      post "/api/mcp/render/markdown",
           params: { markdown: original_markdown },
           headers: auth_header

      html = json_response["html"]

      # HTML → Markdown
      post "/api/mcp/render",
           params: { html: html },
           headers: auth_header

      back_to_markdown = json_response["markdown"]

      expect(back_to_markdown).to include("# Title")
      expect(back_to_markdown).to include("[[Wiki+Link]]")
      expect(back_to_markdown).to include("**details**")
    end
  end
end
