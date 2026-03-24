# MCP API Deployment Status

**Date**: 2025-12-02
**Server**: magi-archive EC2 (54.219.9.17)
**Branch**: feature/mcp-api-phase2
**Commit**: bac5113
**Status**: ✅ **FULLY OPERATIONAL**

---

## Deployment Summary

The MCP API Phase 2 implementation is **fully deployed and operational** on the production server. All security fixes have been applied, service accounts created, and comprehensive testing completed successfully.

### ✅ What's Working

1. **Server Status**: Active and running
   - Service: `magi-archive.service`
   - Routes: MCP API endpoints responding
   - Port: 3000

2. **Unit Tests Passing**:
   - JWT Service: 12/12 ✅
   - Markdown Converter: 18/18 ✅

3. **Infrastructure Fixed**:
   - Routes registered before Decko engine mount
   - Controllers inherit from `::ActionController::Base`
   - Manual controller loading in routes.rb
   - Deck runner working with wrapper script

4. **Service Accounts Configured**: ✅
   - `mcp-user` → User role (default permissions)
   - `mcp-gm` → GM role (read-only)
   - `mcp-admin` → Administrator role (full access)

5. **JWT Authentication Operational**: ✅
   - RS256 token signing with 2048-bit RSA keys
   - JWKS public key distribution at `/.well-known/jwks.json`
   - Role-based token issuance (user/gm/admin)
   - 1-hour token expiry with refresh capability

6. **API Endpoints Verified**: ✅
   - `GET /.well-known/jwks.json` → Returns public JWK ✅
   - `POST /auth` → Returns JWT tokens for all roles ✅
   - `GET /types` → Returns 42 card types ✅
   - `GET /cards` → Returns paginated card lists (2939 total) ✅
   - `GET /cards/:name` → Returns individual card details ✅

7. **Smoke Tests**: 3/3 PASSED ✅

---

## Security Fixes Applied (Server Only)

### Critical Fixes Committed (067ac26)

1. **BaseController Inheritance** (`base_controller.rb:5`)
   - **Before**: Inherited from ApplicationController
   - **After**: Inherits from ::ActionController::Base
   - **Reason**: Avoid Decko's complex controller hierarchy

2. **CSRF Protection Removed** (`base_controller.rb:8`)
   - **Removed**: skip_before_action :verify_authenticity_token
   - **Reason**: Not defined in ActionController::Base

3. **JWKS Authentication Exemption** (`base_controller.rb:17`)
   - **Before**: Only exempted "auth" controller
   - **After**: Exempts both "auth" and "jwks"
   - **Reason**: JWKS endpoint must be public

4. **JwksController Inheritance** (`jwks_controller.rb:5`)
   - **Before**: Inherited from ApplicationController
   - **After**: Inherits from BaseController
   - **Reason**: Consistency with other MCP controllers

5. **Removed skip_modules** (`cards_controller.rb:147,242`)
   - **Before**: Card.fetch(name, skip_modules: true)
   - **After**: Card.fetch(name)
   - **Reason**: Attribute doesn't exist in current Card version

6. **Child Card Permission Context** (`cards_controller.rb:392-400`)
   - **Before**: Card.create!(...) without permission context
   - **After**: Wrapped in Card::Auth.as(current_account.name)
   - **Reason**: Enforce service account permissions for child creation

7. **Routes in Main Config** (`config/routes.rb:4-46`)
   - **Location**: Moved from mod/mcp_api/config/initializers/ to config/routes.rb
   - **Position**: Before Decko::Engine mount to take precedence
   - **Loading**: Manual controller requires to avoid autoload issues

8. **Markdown Converter Security** (`markdown_converter.rb:83-111`)
   - **Sanitization**: Rails sanitizer with explicit allowlists
   - **Placeholders**: Changed to WIKILINKNENDWIKI (no escaping)
   - **Parser**: Switched from GFM to kramdown (no extra gem needed)

---

## Configuration Completed ✅

All required configuration has been successfully applied:

### JWT Keys Generated ✅

```bash
/home/ubuntu/magi-archive/config/jwt_private.pem  # 2048-bit RSA private key
/home/ubuntu/magi-archive/config/jwt_public.pem   # RSA public key
```

### Environment Variables Configured ✅

In `/home/ubuntu/magi-archive/.env.production`:

```bash
JWT_PRIVATE_KEY_PATH=/home/ubuntu/magi-archive/config/jwt_private.pem
JWT_PUBLIC_KEY_PATH=/home/ubuntu/magi-archive/config/jwt_public.pem
JWT_KEY_ID=prod-key-001
JWT_ISSUER=magi-archive
MCP_JWT_ENABLED=true
MCP_API_KEY=cc633b97eb69fc93cf77a0874e9340be1dbdb62342fcfefcd2c285fea780b649

# Service Account Credentials
MCP_USER_NAME=mcp-user
MCP_USER_EMAIL=mcp-user@magi-agi.org
MCP_USER_PASSWORD=[secure-password]
MCP_GM_NAME=mcp-gm
MCP_GM_EMAIL=mcp-gm@magi-agi.org
MCP_GM_PASSWORD=[secure-password]
MCP_ADMIN_NAME=mcp-admin
MCP_ADMIN_EMAIL=mcp-admin@magi-agi.org
MCP_ADMIN_PASSWORD=[secure-password]
```

### Service Accounts Created ✅

Accounts manually created via Decko web interface and approved by admin:
- `mcp-user` - User role
- `mcp-gm` - GM role
- `mcp-admin` - Administrator role

Roles assigned via `rake mcp:setup_roles` task.

---

## Testing Results ✅

### Smoke Test Script Results

```bash
cd /home/ubuntu/magi-archive
ruby bin/smoke_test_mcp.rb http://localhost:3000/api/mcp "$MCP_API_KEY"
```

**Results**: 3/3 PASSED ✅

```
============================================================
MCP API Smoke Test
Base URL: http://localhost:3000/api/mcp
============================================================

Testing JWKS Endpoint (Public)...   JWKS structure valid
PASS
Testing Authentication...   Token received
PASS
Testing Types (Authenticated)...   Types: 42
PASS

============================================================
Results: 3/3 passed
```

### Manual Endpoint Testing Results ✅

All endpoints verified with manual testing:

```bash
# JWKS Endpoint ✅
curl http://localhost:3000/api/mcp/.well-known/jwks.json
# Returns: {"keys":[{"kty":"RSA","kid":"prod-key-001",...}]}

# Authentication - User Role ✅
curl -X POST http://localhost:3000/api/mcp/auth \
  -H "Content-Type: application/json" \
  -d '{"api_key":"cc633b97...","role":"user"}'
# Returns: {"token":"eyJraWQiOi...","role":"user","expires_in":3600}

# Authentication - GM Role ✅
curl -X POST http://localhost:3000/api/mcp/auth \
  -H "Content-Type: application/json" \
  -d '{"api_key":"cc633b97...","role":"gm"}'
# Returns: Valid JWT token for GM role

# Authentication - Admin Role ✅
curl -X POST http://localhost:3000/api/mcp/auth \
  -H "Content-Type: application/json" \
  -d '{"api_key":"cc633b97...","role":"admin"}'
# Returns: Valid JWT token for admin role

# Types Endpoint ✅
curl http://localhost:3000/api/mcp/types?limit=5 \
  -H "Authorization: Bearer $USER_TOKEN"
# Returns: 42 card types with pagination

# Cards Listing ✅
curl http://localhost:3000/api/mcp/cards?limit=3 \
  -H "Authorization: Bearer $USER_TOKEN"
# Returns: {"cards":[...],"total":2939,"limit":3,"offset":0}

# Single Card Retrieval ✅
curl http://localhost:3000/api/mcp/cards/User \
  -H "Authorization: Bearer $USER_TOKEN"
# Returns: Full card details including content and metadata
```

---

## Deck Runner Usage

A wrapper script is available for Codex/Gemini to run card operations:

```bash
/home/ubuntu/run-card-runner.sh 'Ruby code here'
```

**Example**:
```bash
/home/ubuntu/run-card-runner.sh 'puts "Cards: #{Card.count}"'
# Output: Cards: 3085
```

**Update a card**:
```bash
/home/ubuntu/run-card-runner.sh '
  card = Card.fetch("Business Plan+Gaming Cooperative Resources")
  card.content += "\n\nNew addendum content"
  card.save!
  puts "Updated: #{card.name}"
'
```

---

## File Locations

### Key Files Modified on Server

- `config/routes.rb` - MCP routes registered
- `mod/mcp_api/app/controllers/api/mcp/base_controller.rb` - Fixed inheritance
- `mod/mcp_api/app/controllers/api/mcp/cards_controller.rb` - Fixed permissions
- `mod/mcp_api/app/controllers/api/mcp/jwks_controller.rb` - Fixed inheritance
- `mod/mcp_api/lib/mcp_api/markdown_converter.rb` - Fixed sanitization
- `/home/ubuntu/run-card-runner.sh` - Wrapper for deck runner

### New Files Created

- `bin/smoke_test_mcp.rb` - API verification script
- `spec/support/decko_bootstrap.rb` - Test constant stubs
- `mod/mcp_api/lib/mcp_api/engine.rb` - Rails engine (attempted, not used)

---

## Git Status

**Branch**: `feature/mcp-api-phase2`
**Last Commit**: 067ac26 "Fix MCP API deployment issues"
**Files Changed**: 19 files, 2605 insertions, 25 deletions

All server-side fixes have been committed to git. To pull changes to local repo:

```bash
cd magi-archive-mcp  # or appropriate local path
git fetch origin
git checkout feature/mcp-api-phase2
git pull origin feature/mcp-api-phase2
```

---

## Deployment Complete ✅

All deployment steps have been successfully completed:

1. ✅ **JWT Keys Generated** - 2048-bit RSA key pair created
2. ✅ **Environment Configured** - All variables set in `.env.production`
3. ✅ **Service Accounts Created** - mcp-user, mcp-gm, mcp-admin
4. ✅ **Roles Assigned** - Administrator role for mcp-admin
5. ✅ **Service Restarted** - magi-archive.service running
6. ✅ **Smoke Tests Passed** - 3/3 endpoints verified
7. ✅ **Manual Testing Complete** - All roles and endpoints operational

## Next Phase: MCP Client Implementation

With the API fully operational, the next step is implementing the Ruby MCP client as specified in `MCP-SPEC.md`:

1. **Scaffold Ruby Gem** - `bundle gem magi-archive-mcp` in `magi-archive-mcp/` directory
2. **Implement JWT Client** - JWKS fetching, token verification, refresh logic
3. **Create HTTP Client** - Wrapper for Decko API calls with role enforcement
4. **Implement MCP Tools** - `get_card`, `search_cards`, `create_card`, etc.
5. **Add RSpec Tests** - Unit and integration tests for all components
6. **Create Example Scripts** - Demonstrate usage for AI agents

See `magi-archive-mcp/CLAUDE.md` for detailed implementation guide.

---

## References

- **Security Audit**: `docs/FINAL-SECURITY-AUDIT.md`
- **API Spec**: `MCP-SPEC.md`
- **Implementation**: `docs/MCP-PHASE-2-COMPLETE.md`
- **This Status**: `docs/MCP-DEPLOYMENT-STATUS.md`

---

## Updates (Post-Deployment)

### 2025-12-02: Game Master Role Assignment

**Issue Identified**: The `mcp-gm` account was not properly assigned to the "Game Master" role despite the rake task completing successfully.

**Root Cause**: The `assign_role` helper in `lib/tasks/mcp.rake` was only logging that mcp-gm was assigned GM permissions but not actually adding the account to the "Game Master+*members" card.

**Fix Applied**:
1. Manually added `mcp-gm` to Game Master role members ✅
2. Updated `lib/tasks/mcp.rake` to properly fetch and assign the "Game Master" role ✅
3. Verified role assignment through web interface ✅
4. Tested API access with GM token ✅

**Commit**: 92d4850

**Current Status**: 
- `mcp-user` → User (default permissions) ✅
- `mcp-gm` → **Game Master role** ✅ (FIXED)
- `mcp-admin` → Administrator role ✅

All three service accounts are now properly configured with their intended roles.

---

### 2025-12-02: CRITICAL SECURITY FIX - Role Authentication

**SECURITY VULNERABILITY IDENTIFIED**: Anyone with the API key could request admin or GM tokens just by specifying the role parameter. The `allowed_role_for_key?()` method always returned `true`, meaning no authentication was required for elevated roles.

**Impact**:
- ⚠️ **Critical** - Anyone with the API key had full admin access
- Could delete cards, modify content, access all GM content
- No audit trail of who requested elevated access

**Root Cause**:
The auth controller had a placeholder implementation:
```ruby
def allowed_role_for_key?(api_key, role)
  # For MVP: Single API key has access to all roles
  true  # ⚠️ ALWAYS RETURNS TRUE
end
```

**Security Fix Implemented**:

1. **User Role** (API key only):
   ```json
   POST /api/mcp/auth
   {"api_key": "...", "role": "user"}
   ```
   - No change - API key sufficient for basic access

2. **GM Role** (requires credentials):
   ```json
   POST /api/mcp/auth
   {
     "api_key": "...",
     "role": "gm",
     "username": "mcp-gm",
     "password": "Mcpe8bc9b202e226e070fdf562d!Gm"
   }
   ```
   - Now requires username + password
   - Authenticates using Decko's `Card::Auth.authenticate`
   - Verifies user is in "Game Master" role members

3. **Admin Role** (requires credentials):
   ```json
   POST /api/mcp/auth
   {
     "api_key": "...",
     "role": "admin",
     "username": "mcp-admin",
     "password": "Mcpa30f1950765721d153d70ee0!Admin"
   }
   ```
   - Now requires username + password
   - Authenticates using Decko's `Card::Auth.authenticate`
   - Verifies user is in "Administrator" role members

**Implementation Details**:
- Added `authenticate_user(username, password, role)` method
- Added `verify_user_role(user, expected_role)` method
- Removed insecure `allowed_role_for_key?()` placeholder
- Uses Decko's built-in password hashing and verification
- Checks account status is "active"
- Validates role membership before issuing tokens

**Verification Tests**: 5/5 PASSED ✅
- ✅ User role works with API key only
- ✅ GM role rejected without credentials
- ✅ Admin role rejected without credentials
- ✅ GM role works with valid credentials
- ✅ Admin role works with valid credentials

**Commit**: df90d57

**Status**: ✅ **SECURITY FIX DEPLOYED AND VERIFIED**

Only authorized individuals with service account credentials can now obtain GM or admin access tokens. The API key alone only grants user-level access.
