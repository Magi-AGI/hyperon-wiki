#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class MCPSmokeTest
  attr_reader :base_url, :api_key, :results
  
  def initialize(base_url, api_key)
    @base_url = base_url
    @api_key = api_key
    @results = []
    @token = nil
  end
  
  def run_all
    puts "=" * 60
    puts "MCP API Smoke Test"
    puts "Base URL: #{base_url}"
    puts "=" * 60
    puts
    
    test_jwks_endpoint
    test_auth_endpoint
    test_types_endpoint if @token
    
    print_summary
  end
  
  private
  
  def test_jwks_endpoint
    test("JWKS Endpoint (Public)") do
      response = get("/.well-known/jwks.json")
      assert response.code == "200", "Expected 200, got #{response.code}"
      data = JSON.parse(response.body)
      assert data["keys"].is_a?(Array), "Expected keys array"
      puts "  JWKS structure valid"
    end
  end
  
  def test_auth_endpoint
    test("Authentication") do
      response = post("/auth", { api_key: api_key, role: "user" })
      assert response.code == "201", "Expected 201, got #{response.code}"
      data = JSON.parse(response.body)
      assert data["token"], "Expected token"
      @token = data["token"]
      puts "  Token received"
    end
  end
  
  def test_types_endpoint
    test("Types (Authenticated)") do
      response = get("/types", auth: @token)
      assert response.code == "200", "Expected 200, got #{response.code}"
      data = JSON.parse(response.body)
      puts "  Types: #{data["types"].size}"
    end
  end
  
  def test(name)
    print "Testing #{name}... "
    yield
    puts "PASS"
    @results << { name: name, status: :pass }
  rescue => e
    puts "FAIL: #{e.message}"
    @results << { name: name, status: :fail, error: e.message }
  end
  
  def assert(condition, message)
    raise message unless condition
  end
  
  def get(path, auth: nil)
    uri = URI.parse("#{base_url}#{path}")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{auth}" if auth
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.request(request)
  end
  
  def post(path, body)
    uri = URI.parse("#{base_url}#{path}")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = body.to_json
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.request(request)
  end
  
  def print_summary
    puts "\n" + "=" * 60
    passed = @results.count { |r| r[:status] == :pass }
    failed = @results.count { |r| r[:status] == :fail }
    puts "Results: #{passed}/#{@results.size} passed"
    exit(failed > 0 ? 1 : 0)
  end
end

if ARGV.size < 2
  puts "Usage: ruby smoke_test_mcp.rb <base_url> <api_key>"
  exit 1
end

tester = MCPSmokeTest.new(ARGV[0], ARGV[1])
tester.run_all
