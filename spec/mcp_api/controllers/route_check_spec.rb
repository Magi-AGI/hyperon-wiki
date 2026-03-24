# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Route Check", type: :request do
  it "checks if MCP routes are loaded" do
    get "/api/mcp/.well-known/jwks.json"
    if response.status == 500
      File.write("/tmp/test_error.html", response.body)
      puts "Error page written to /tmp/test_error.html"
      # Extract just the error message
      body = response.body
      if body =~ /<pre class="exception">(.*?)<\/pre>/m
        puts "Exception: #{$1.strip[0..200]}"
      end
    else
      puts "Success! Status: #{response.status}"
    end
  end
end
