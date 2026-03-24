# MCP API Testing Guide

This document explains the comprehensive test suite for the Magi Archive MCP API.

## Test Types

### 1. Unit Tests
**Location**: `spec/models/`, `spec/lib/`, `spec/controllers/`
**Purpose**: Test individual classes and methods in isolation
**Run**: `bundle exec rspec spec/models/ spec/lib/`

### 2. Request Specs ⭐ NEW
**Location**: `spec/requests/api/mcp/`
**Purpose**: Test full HTTP request/response cycle
**Catches**: Routing errors, constant lookup issues, authentication flows

**Run**:
```bash
bundle exec rspec spec/requests/
```

**What these catch**:
- ❌ Missing routes (`POST /api/mcp/jobs/spoiler-scan` not defined)
- ❌ Constant lookup errors (`Api::Mcp::UserAuthenticator` vs `::Mcp::UserAuthenticator`)
- ❌ Authentication flow failures
- ❌ JSON response structure issues

### 3. Routing Specs ⭐ NEW
**Location**: `spec/routing/api/mcp/`
**Purpose**: Verify all routes are correctly defined
**Catches**: Missing route definitions before deployment

**Run**:
```bash
bundle exec rspec spec/routing/
```

**What these catch**:
- ❌ Routes missing from `config/routes.rb`
- ❌ Incorrect controller/action mappings
- ❌ Parameter routing issues

### 4. Integration Specs ⭐ NEW
**Location**: `spec/integration/`
**Purpose**: Test module loading, constant resolution, production-like behavior
**Catches**: File loading errors, lazy loading issues, constant scoping

**Run**:
```bash
bundle exec rspec spec/integration/
```

**What these catch**:
- ❌ `require_relative` path errors
- ❌ Constant lookup failures in production lazy-loading
- ❌ Module nesting issues
- ❌ File loading order dependencies

## Running Tests

### Run All Tests
```bash
bundle exec rspec
```

### Run Specific Test Types
```bash
# Request specs only
bundle exec rspec spec/requests/

# Routing specs only
bundle exec rspec spec/routing/

# Integration specs only
bundle exec rspec spec/integration/

# Production-like tests only
bundle exec rspec --tag production_like
```

### Run Production-Like Tests
These tests simulate production lazy-loading behavior:

```bash
# Run with production-like configuration
RAILS_ENV=test EAGER_LOAD=false bundle exec rspec --tag production_like
```

### Run with Verbose Output
```bash
bundle exec rspec --format documentation
```

## Test Tags

- `:integration` - Integration tests (full system tests)
- `:production_like` - Tests that simulate production environment
- `:slow` - Tests that take longer to run
- `:request` - Request specs (HTTP tests)

## Continuous Integration

For CI/CD pipelines, run all test types:

```bash
#!/bin/bash
set -e

# Unit tests
bundle exec rspec spec/models/ spec/lib/ spec/controllers/

# Request tests (catch routing and HTTP issues)
bundle exec rspec spec/requests/

# Routing tests (catch missing routes)
bundle exec rspec spec/routing/

# Integration tests (catch constant/loading issues)
bundle exec rspec spec/integration/

# Production-like tests
RAILS_ENV=test bundle exec rspec --tag production_like
```

## What Each Test Type Catches

| Error Type | Unit | Request | Routing | Integration |
|------------|------|---------|---------|-------------|
| Logic bugs | ✅ | ❌ | ❌ | ❌ |
| Missing routes | ❌ | ✅ | ✅ | ❌ |
| Constant lookup (`::Mcp::` vs `Mcp::`) | ❌ | ✅ | ❌ | ✅ |
| File loading (`require_relative`) | ❌ | ❌ | ❌ | ✅ |
| Authentication flows | ⚠️ | ✅ | ❌ | ❌ |
| HTTP response format | ⚠️ | ✅ | ❌ | ❌ |
| Production lazy-loading | ❌ | ❌ | ❌ | ✅ |
| Card::UserID constant issues | ❌ | ❌ | ❌ | ✅ |

✅ = Catches the error
⚠️ = Partially catches (depends on mocking)
❌ = Does not catch

## Examples

### Test That Would Have Caught the Jobs Route Error
```ruby
# spec/routing/api/mcp/mcp_routes_spec.rb
it "routes POST /api/mcp/jobs/spoiler-scan to jobs#spoiler_scan" do
  expect(post: "/api/mcp/jobs/spoiler-scan").to route_to(
    controller: "api/mcp/jobs",
    action: "spoiler_scan"
  )
end
```

### Test That Would Have Caught the Constant Lookup Error
```ruby
# spec/integration/mcp_api_integration_spec.rb
it "correctly resolves constants with :: prefix" do
  expect {
    Api::Mcp::AuthController.new.send(:authenticate_with_username)
  }.not_to raise_error(NameError, /uninitialized constant Api::Mcp::UserAuthenticator/)
end
```

### Test That Would Have Caught the require_relative Error
```ruby
# spec/integration/mcp_api_integration_spec.rb
it "loads auth controller without require_relative errors" do
  expect {
    load Rails.root.join("mod/mcp_api/app/controllers/api/mcp/auth_controller.rb")
  }.not_to raise_error(LoadError)
end
```

## Pre-Deployment Checklist

Before deploying to production, run:

```bash
# 1. All unit tests
bundle exec rspec spec/models/ spec/lib/ spec/controllers/

# 2. Request specs (catches HTTP/routing issues)
bundle exec rspec spec/requests/

# 3. Routing specs (catches missing routes)
bundle exec rspec spec/routing/

# 4. Integration specs (catches loading/constant issues)
bundle exec rspec spec/integration/

# 5. Production-like tests
RAILS_ENV=test bundle exec rspec --tag production_like
```

All tests should pass before deployment!

## Troubleshooting

### Tests Pass Locally But Fail in Production

This usually means:
1. Missing integration tests
2. Not testing with production-like configuration
3. Mocking too much (hiding real issues)

**Solution**: Run production-like tests:
```bash
RAILS_ENV=test EAGER_LOAD=false bundle exec rspec --tag production_like
```

### NameError in Production But Not Tests

This is a constant lookup or lazy-loading issue.

**Solution**: Add integration test:
```ruby
it "loads constant without NameError" do
  expect { YourModule::YourClass }.not_to raise_error(NameError)
end
```

### Route Not Found in Production But Tests Pass

Missing routing spec.

**Solution**: Add routing test:
```ruby
it "routes to your endpoint" do
  expect(post: "/your/path").to route_to(
    controller: "your/controller",
    action: "action"
  )
end
```
