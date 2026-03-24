# Phase 2 Testing Guide

This guide walks through testing all Phase 2 features of the MCP API.

## Prerequisites

### 1. Install Dependencies

```bash
cd magi-archive
bundle install
```

**Expected gems to install**:
- `jwt` - RS256 JWT signing
- `kramdown` - Markdown parsing
- `reverse_markdown` - HTML to Markdown conversion

### 2. Set Environment Variables

```bash
# Required for tests
export MCP_API_KEY=test-api-key-12345
export MCP_JWT_ENABLED=true

# Optional (tests use defaults if not set)
export JWT_KEY_ID=test-key-001
export JWT_ISSUER=magi-archive-test
export JWT_EXPIRY=3600
export MCP_TOKEN_TTL=3600

# Service account names (defaults are fine for testing)
export MCP_USER_NAME=mcp-user
export MCP_GM_NAME=mcp-gm
export MCP_ADMIN_NAME=mcp-admin
```

---

## Automated Testing

### Run Full Test Suite

```bash
bundle exec rspec spec/mcp_api/
```

**Expected Output**:
```
Finished in X.XX seconds (files took X.XX seconds to load)
60 examples, 0 failures
```

### Run Tests with Verbose Output

```bash
bundle exec rspec spec/mcp_api/ --format documentation
```

**Expected Output**:
```
McpApi::JwtService
  .generate_token
    generates a valid JWT token
    includes required claims in payload
    respects custom expiry time
  .verify_token
    verifies and decodes valid tokens
    returns nil for invalid tokens
    returns nil for expired tokens
    returns nil for tokens with wrong issuer
  .jwks
    returns valid JWKS structure
    includes RS256 algorithm
    includes key ID
  key generation
    when no key files exist
      generates ephemeral keys for development
      logs warning about ephemeral keys

McpApi::MarkdownConverter
  .markdown_to_html
    converts basic markdown to HTML
    preserves wiki links
    handles complex nested lists
    handles code blocks
    handles tables (GFM)
    sanitizes script tags
    sanitizes style tags
    returns empty string for nil input
    returns empty string for empty input
    preserves wiki links with special characters
  .html_to_markdown
    converts basic HTML to Markdown
    preserves wiki links
    handles lists
    handles links
    returns empty string for nil input
    returns empty string for empty input
    preserves multiple wiki links
  round-trip conversion
    preserves content through markdown -> html -> markdown

... [60 examples total]

Finished in X.XX seconds
60 examples, 0 failures
```

### Run Specific Test Suites

```bash
# JWT Service only
bundle exec rspec spec/mcp_api/services/jwt_service_spec.rb

# Markdown Converter only
bundle exec rspec spec/mcp_api/lib/markdown_converter_spec.rb

# Auth Controller only
bundle exec rspec spec/mcp_api/controllers/auth_controller_spec.rb

# Render endpoints only
bundle exec rspec spec/mcp_api/controllers/render_controller_spec.rb

# JWKS endpoint only
bundle exec rspec spec/mcp_api/controllers/jwks_controller_spec.rb

# Integration tests only
bundle exec rspec spec/mcp_api/integration/full_flow_spec.rb
```

---

## Manual Testing (Without Decko Server)

You can test the core services directly in Ruby without running the full Decko server.

### Test JWT Service

Create `test_jwt.rb`:

```ruby
#!/usr/bin/env ruby
require_relative 'mod/mcp_api/lib/mcp_api/jwt_service'

# Generate a token
token = McpApi::JwtService.generate_token(
  role: "admin",
  api_key_id: "test-key-123",
  expires_in: 3600
)

puts "Generated JWT Token:"
puts token
puts

# Decode the token
payload = McpApi::JwtService.verify_token(token)

puts "Decoded Payload:"
puts JSON.pretty_generate(payload)
puts

# Get JWKS
jwks = McpApi::JwtService.jwks

puts "JWKS (Public Keys):"
puts JSON.pretty_generate(jwks)
```

Run:
```bash
ruby test_jwt.rb
```

**Expected Output**:
```
Generated JWT Token:
eyJhbGciOiJSUzI1NiIsImtpZCI6ImtleS0wMDEifQ.eyJzdWIiOiJ0ZXN0LWtleSIsInJvbGUiOiJhZG1pbiIsImlzcyI6Im1hZ2ktYXJjaGl2ZSIsImlhdCI6MTczMzEzNjAwMCwiZXhwIjoxNzMzMTM5NjAwLCJqdGkiOiI4ZjNhNGI1Yy0uLi4iLCJraWQiOiJrZXktMDAxIn0.signature...

Decoded Payload:
{
  "sub": "test-key-123",
  "role": "admin",
  "iss": "magi-archive",
  "iat": 1733136000,
  "exp": 1733139600,
  "jti": "8f3a4b5c-...",
  "kid": "key-001"
}

JWKS (Public Keys):
{
  "keys": [
    {
      "kty": "RSA",
      "kid": "key-001",
      "use": "sig",
      "alg": "RS256",
      "n": "base64-encoded-modulus...",
      "e": "AQAB"
    }
  ]
}
```

### Test Markdown Converter

Create `test_markdown.rb`:

```ruby
#!/usr/bin/env ruby
require 'kramdown'
require 'reverse_markdown'
require_relative 'mod/mcp_api/lib/mcp_api/markdown_converter'

markdown = <<~MD
  # Test Card

  This is a **test** with [[Wiki+Link]].

  - Item 1
    - Nested item
  - Item 2

  ```ruby
  def hello
    "world"
  end
  ```
MD

puts "Original Markdown:"
puts markdown
puts "\n" + "="*50 + "\n"

# Convert to HTML
html = McpApi::MarkdownConverter.markdown_to_html(markdown)

puts "Converted to HTML:"
puts html
puts "\n" + "="*50 + "\n"

# Convert back to Markdown
markdown_again = McpApi::MarkdownConverter.html_to_markdown(html)

puts "Converted back to Markdown:"
puts markdown_again
puts "\n" + "="*50 + "\n"

# Verify wiki link preservation
if html.include?("[[Wiki+Link]]")
  puts "✅ Wiki links preserved in HTML conversion"
else
  puts "❌ Wiki links NOT preserved in HTML conversion"
end

if markdown_again.include?("[[Wiki+Link]]")
  puts "✅ Wiki links preserved in round-trip conversion"
else
  puts "❌ Wiki links NOT preserved in round-trip conversion"
end
```

Run:
```bash
ruby test_markdown.rb
```

**Expected Output**:
```
Original Markdown:
# Test Card

This is a **test** with [[Wiki+Link]].

- Item 1
  - Nested item
- Item 2

```ruby
def hello
  "world"
end
```

==================================================

Converted to HTML:
<h1>Test Card</h1>
<p>This is a <strong>test</strong> with [[Wiki+Link]].</p>
<ul>
  <li>Item 1
    <ul>
      <li>Nested item</li>
    </ul>
  </li>
  <li>Item 2</li>
</ul>
<pre><code class="language-ruby">def hello
  "world"
end
</code></pre>

==================================================

Converted back to Markdown:
# Test Card

This is a **test** with [[Wiki+Link]].

- Item 1
  - Nested item
- Item 2

```ruby
def hello
  "world"
end
```

==================================================

✅ Wiki links preserved in HTML conversion
✅ Wiki links preserved in round-trip conversion
```

---

## Manual Testing (With Decko Server Running)

If you have the Decko server running, you can test the actual API endpoints.

### 1. Start Decko Server

```bash
cd magi-archive
bundle exec decko server
```

Wait for server to start on `http://localhost:3000`

### 2. Create Service Accounts

```bash
# In another terminal
export MCP_USER_EMAIL=test-user@example.com
export MCP_USER_PASSWORD=test-pass-123
export MCP_GM_EMAIL=test-gm@example.com
export MCP_GM_PASSWORD=test-pass-456
export MCP_ADMIN_EMAIL=test-admin@example.com
export MCP_ADMIN_PASSWORD=test-pass-789

bundle exec rake mcp:setup_roles
```

**Expected Output**:
```
✅ Created: mcp-user(#123), mcp-gm(#124), mcp-admin(#125)
🔐 Role assignments: mcp-admin → Administrator, mcp-gm → GM (read-only), mcp-user → User (default)
```

### 3. Test Authentication Endpoint

```bash
# Get JWT token
curl -X POST http://localhost:3000/api/mcp/auth \
  -H "Content-Type: application/json" \
  -d '{
    "api_key": "test-api-key-12345",
    "role": "admin"
  }'
```

**Expected Response**:
```json
{
  "token": "eyJhbGciOiJSUzI1NiIsImtpZCI6ImtleS0wMDEifQ...",
  "role": "admin",
  "expires_in": 3600,
  "expires_at": 1733139600
}
```

### 4. Test JWKS Endpoint

```bash
curl http://localhost:3000/api/mcp/.well-known/jwks.json
```

**Expected Response**:
```json
{
  "keys": [
    {
      "kty": "RSA",
      "kid": "key-001",
      "use": "sig",
      "alg": "RS256",
      "n": "base64-encoded-modulus...",
      "e": "AQAB"
    }
  ]
}
```

### 5. Test Render Endpoints

```bash
# Save token from auth response
export TOKEN="eyJhbGciOiJSUzI1NiIsImtpZCI6ImtleS0wMDEifQ..."

# Test Markdown → HTML
curl -X POST http://localhost:3000/api/mcp/render/markdown \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "markdown": "# Title\n\nSee [[Wiki+Link]] for **details**."
  }'
```

**Expected Response**:
```json
{
  "html": "<h1>Title</h1>\n<p>See [[Wiki+Link]] for <strong>details</strong>.</p>",
  "format": "html"
}
```

```bash
# Test HTML → Markdown
curl -X POST http://localhost:3000/api/mcp/render \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "html": "<h1>Title</h1><p>See [[Wiki+Link]]</p>"
  }'
```

**Expected Response**:
```json
{
  "markdown": "# Title\n\nSee [[Wiki+Link]]",
  "format": "gfm"
}
```

### 6. Test Backward Compatibility (MessageVerifier)

```bash
# Disable JWT
export MCP_JWT_ENABLED=false

# Restart server, then get MessageVerifier token
curl -X POST http://localhost:3000/api/mcp/auth \
  -H "Content-Type: application/json" \
  -d '{
    "api_key": "test-api-key-12345",
    "role": "user"
  }'
```

**Expected Response**:
```json
{
  "token": "BAhJIiU6MGMyNTI4NzQtZjg3Ni00NzY5LTk2MTEtNjk3YjE2YmQwNjY0BjoGRVQ=--abc123...",
  "role": "user",
  "expires_in": 3600,
  "expires_at": 1733139600
}
```

Note: MessageVerifier token format is different (not JWT 3-part format)

Both token types should work for authenticated requests!

---

## Test Results Checklist

### JWT Service
- [ ] Token generation works
- [ ] Token includes all required claims (sub, role, iss, iat, exp, jti, kid)
- [ ] Token verification works
- [ ] Invalid tokens rejected
- [ ] Expired tokens rejected
- [ ] JWKS structure valid
- [ ] Ephemeral key generation works in development

### Markdown Converter
- [ ] Basic Markdown → HTML conversion works
- [ ] Complex features work (nested lists, tables, code blocks)
- [ ] Wiki links preserved in all conversions
- [ ] XSS sanitization removes script/style tags
- [ ] HTML → Markdown conversion works
- [ ] Round-trip conversion preserves content
- [ ] Edge cases handled (nil, empty input)

### Auth Controller
- [ ] JWT tokens issued when MCP_JWT_ENABLED=true
- [ ] MessageVerifier tokens issued when MCP_JWT_ENABLED=false
- [ ] All three roles work (user, gm, admin)
- [ ] Invalid API key rejected
- [ ] Missing parameters rejected with proper errors
- [ ] Token TTL configuration works

### Render Controller
- [ ] POST /api/mcp/render converts HTML → Markdown
- [ ] POST /api/mcp/render/markdown converts Markdown → HTML
- [ ] Wiki links preserved in both directions
- [ ] Authentication required
- [ ] Missing parameters rejected
- [ ] Complex Markdown features work

### JWKS Controller
- [ ] GET /.well-known/jwks.json returns valid JWKS
- [ ] No authentication required
- [ ] Public key can verify JWT tokens
- [ ] RS256 algorithm specified

### Integration
- [ ] Full workflow works: Auth → Render → CRUD → Delete
- [ ] Both token types accepted (JWT + MessageVerifier)
- [ ] Role-based access control enforced
- [ ] Wiki links preserved through full cycle

---

## Troubleshooting

### Issue: "Cannot load jwt gem"
**Solution**: Run `bundle install` to install dependencies

### Issue: "Card::Auth.as_bot not found"
**Solution**: This test requires full Decko environment. Use automated RSpec tests instead which mock this.

### Issue: "No route matches [POST] /api/mcp/auth"
**Solution**: Ensure routes are loaded. Check `config/initializers/mcp_routes.rb` is present.

### Issue: "Private key not found"
**Solution**: JWT service generates ephemeral keys automatically in development. This is normal and logged as a warning.

### Issue: "Service account not found"
**Solution**: Run `bundle exec rake mcp:setup_roles` to create mcp-user, mcp-gm, mcp-admin accounts.

---

## Next Steps After Testing

1. **All tests pass**: Ready for staging deployment
2. **Some tests fail**: Review error messages and fix issues
3. **Manual testing works**: Create pull request for review
4. **Production deployment**: Generate real RSA keys and configure environment

---

## Summary

**Automated Tests**: 60 specs covering all Phase 2 features
**Manual Tests**: JWT, Markdown, and API endpoint testing
**Expected Result**: 100% test pass rate with no failures

Run tests now:
```bash
bundle exec rspec spec/mcp_api/ --format documentation
```
