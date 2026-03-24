# frozen_string_literal: true

module Api
  module Mcp
    class RenderController < BaseController
      # POST /api/mcp/render
      # Convert HTML to Markdown
      def html_to_markdown
        html = params[:html] || params[:content]

        return render_error("validation_error", "Missing html or content parameter") unless html

        markdown = McpApi::MarkdownConverter.html_to_markdown(html)

        render json: {
          markdown: markdown,
          format: "gfm"
        }
      rescue StandardError => e
        render_error(
          "conversion_error",
          "Failed to convert HTML to Markdown",
          { error: e.message }
        )
      end

      # POST /api/mcp/render/markdown
      # Convert Markdown to Decko-safe HTML
      def markdown_to_html
        markdown = params[:markdown] || params[:content]

        return render_error("validation_error", "Missing markdown or content parameter") unless markdown

        html = McpApi::MarkdownConverter.markdown_to_html(markdown)

        render json: {
          html: html,
          format: "html"
        }
      rescue StandardError => e
        render_error(
          "conversion_error",
          "Failed to convert Markdown to HTML",
          { error: e.message }
        )
      end
    end
  end
end
