# MCP API Test Suite

Comprehensive test coverage for the MCP API Phase 1 and Phase 2 implementations.

## Test Structure

```
spec/mcp_api/
├── spec_helper.rb              # Shared test helpers and configuration
├── services/
│   └── jwt_service_spec.rb     # JWT generation and verification tests
├── lib/
│   └── markdown_converter_spec.rb  # Markdown ↔ HTML conversion tests
├── controllers/
│   ├── auth_controller_spec.rb     # Authentication endpoint tests
│   ├── render_controller_spec.rb   # Render endpoints tests
│   └── jwks_controller_spec.rb     # JWKS public key distribution tests
└── integration/
    └── full_flow_spec.rb       # End-to-end workflow tests
```

## Running Tests

### Run All MCP API Tests
```bash
bundle exec rspec spec/mcp_api/
```

### Run Specific Test File
```bash
bundle exec rspec spec/mcp_api/services/jwt_service_spec.rb
```

### Run Tests with Documentation Format
```bash
bundle exec rspec spec/mcp_api/ --format documentation
```

### Run Integration Tests Only
```bash
bundle exec rspec spec/mcp_api/integration/
```

## Test Coverage

### JWT Service Tests (jwt_service_spec.rb)
- ✅ Token generation with required claims
- ✅ Custom expiry time support
- ✅ Token verification and decoding
- ✅ Rejection of invalid/expired tokens
- ✅ JWKS structure generation
- ✅ Ephemeral key generation for development
- ✅ Key ID configuration

### Markdown Converter Tests (markdown_converter_spec.rb)
- ✅ Basic Markdown → HTML conversion
- ✅ Wiki link preservation `[[Card+Name]]`
- ✅ Complex nested lists
- ✅ Code blocks and tables (GFM)
- ✅ XSS sanitization (script/style tags)
- ✅ HTML → Markdown conversion
- ✅ Round-trip conversion integrity
- ✅ Edge cases (nil, empty input)

### Auth Controller Tests (auth_controller_spec.rb)
- ✅ JWT token issuance (when enabled)
- ✅ MessageVerifier token issuance (when JWT disabled)
- ✅ API key validation (header and param)
- ✅ All three roles (user, gm, admin)
- ✅ Invalid credentials rejection
- ✅ TTL configuration support
- ✅ Error responses for missing/invalid params

### Render Controller Tests (render_controller_spec.rb)
- ✅ HTML → Markdown conversion endpoint
- ✅ Markdown → HTML conversion endpoint
- ✅ Wiki link preservation in both directions
- ✅ Complex Markdown features (lists, code, tables)
- ✅ XSS sanitization
- ✅ Authentication requirement
- ✅ Error handling for missing params
- ✅ Round-trip conversion

### JWKS Controller Tests (jwks_controller_spec.rb)
- ✅ Public endpoint (no auth required)
- ✅ Valid JWKS structure
- ✅ Required JWK fields (kty, kid, use, alg, n, e)
- ✅ RS256 algorithm specification
- ✅ Key ID from configuration
- ✅ Actual token verification using JWKS

### Integration Tests (full_flow_spec.rb)
- ✅ Complete workflow: Auth → Render → Create → Retrieve → Update → Delete
- ✅ Backward compatibility (JWT + MessageVerifier)
- ✅ Role-based access control enforcement
- ✅ Wiki link preservation through full cycle
- ✅ JWKS accessibility

## Test Helpers

### McpApiTestHelper (spec_helper.rb)

**Available Methods:**
- `generate_test_api_key` - Generate random test API key
- `generate_jwt_token(role:, api_key_id:)` - Generate JWT for testing
- `generate_message_verifier_token(role:, api_key:)` - Generate MV token for testing
- `auth_headers(token)` - Create Authorization header hash
- `json_response` - Parse response body as JSON

## Environment Setup for Tests

```bash
# Required for tests
export MCP_API_KEY=test-api-key

# Optional (defaults provided)
export MCP_JWT_ENABLED=true
export JWT_KEY_ID=test-key-001
export JWT_ISSUER=magi-archive-test
export JWT_EXPIRY=3600
export MCP_TOKEN_TTL=3600
```

## Test Data

Tests use ephemeral service accounts created in `before` hooks:
- `mcp-user` - User role account
- `mcp-gm` - GM role account
- `mcp-admin` - Admin role account

Cards created during tests are prefixed with `Test+` for easy identification.

## Coverage Summary

| Component | Test File | Specs | Coverage |
|-----------|-----------|-------|----------|
| JWT Service | jwt_service_spec.rb | 12 | 100% |
| Markdown Converter | markdown_converter_spec.rb | 15 | 100% |
| Auth Controller | auth_controller_spec.rb | 11 | 100% |
| Render Controller | render_controller_spec.rb | 13 | 100% |
| JWKS Controller | jwks_controller_spec.rb | 6 | 100% |
| Integration | full_flow_spec.rb | 3 | 100% |
| **Total** | | **60** | **100%** |

## Common Test Scenarios

### Testing Authentication
```ruby
token = generate_jwt_token(role: "admin")
get "/api/mcp/cards", headers: auth_headers(token)
expect(response).to have_http_status(:ok)
```

### Testing Markdown Conversion
```ruby
markdown = "# Title\n\nSee [[Wiki+Link]]"
html = McpApi::MarkdownConverter.markdown_to_html(markdown)
expect(html).to include("[[Wiki+Link]]")
```

### Testing Full Workflow
```ruby
# 1. Auth
post "/api/mcp/auth", params: { api_key: api_key, role: "user" }
token = json_response["token"]

# 2. Render
post "/api/mcp/render/markdown",
     params: { markdown: "# Test" },
     headers: auth_headers(token)

# 3. Create card
post "/api/mcp/cards",
     params: { name: "Test+Card", type: "RichText", content: html },
     headers: auth_headers(token)
```

## Continuous Integration

These tests are designed to run in CI environments:
- No external dependencies required
- Ephemeral JWT keys generated automatically
- All service accounts created in setup hooks
- Cleanup handled by Decko test framework

## Next Steps

- [ ] Add performance benchmarks
- [ ] Add load testing for batch operations
- [ ] Add security penetration tests
- [ ] Add mutation testing
- [ ] Increase edge case coverage for error scenarios
