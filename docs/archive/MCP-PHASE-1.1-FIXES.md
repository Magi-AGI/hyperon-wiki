# MCP API Phase 1.1 - Critical Fixes

## Gemini Code Review Feedback (Dec 2, 2025)

### Overall Assessment
> "The code quality is high and follows the MCP-IMPLEMENTATION.md plan closely. It correctly uses Decko's internal API (Card.fetch, Card.search) and standard Rails patterns."

### Critical Issue Identified

**Problem**: Rake task creates service accounts but doesn't assign them to Decko roles
- The `mcp:setup_roles` task created User cards (`mcp-user`, `mcp-gm`, `mcp-admin`)
- **BUT** it did not assign them to Decko Roles (e.g., "Administrator")
- **Consequence**: `mcp-admin` exists but has no actual power to delete cards
- When `Card::Auth.as("mcp-admin")` runs in `CardsController#destroy`, Decko's core throws `PermissionDenied` because the user isn't actually an admin

**Fix Applied** (lib/tasks/mcp.rake):
```ruby
# Now assigns mcp-admin to Administrator role's +members
admin_role = Card.fetch("Administrator")
members_card = Card.fetch("#{admin_role.name}+*members", new: {})
current_members = members_card.item_names || []

unless current_members.include?(user_card.name)
  members_card.items = current_members + [user_card.name]
  members_card.save!
end
```

### Additional Issues Addressed

**1. Missing jwt Gem**
- **Problem**: jwt gem was missing from root Gemfile
- **Fix**: Added `gem "jwt"` with comment for Phase 2 upgrade path
- **Status**: ✅ Fixed in Gemfile:32

**2. Fragile Markdown Parser**
- **Issue**: `CardsController#convert_markdown_to_html` uses regex for Markdown conversion
- **Impact**: Will break on nested lists, code blocks inside lists, bold text across lines
- **Status**: ⚠️ Acknowledged - acceptable for Phase 1 MVP
- **Recommendation**: Upgrade to proper markdown gem (e.g., `redcarpet`, `kramdown`) in Phase 2

**3. Single API Key Limitation**
- **Issue**: `AuthController` checks single `ENV["MCP_API_KEY"]`
- **Impact**: Limits deployment to one API key for all clients; prevents independent revocation
- **Status**: ⚠️ Acknowledged - per MVP spec design
- **Recommendation**: Implement database-backed API keys in Phase 2

## Changes Made (Phase 1.1)

### 1. Updated lib/tasks/mcp.rake
**Added**:
- `assign_role` helper method to assign service accounts to Decko roles
- Administrator role assignment for `mcp-admin`
- Role tracking and reporting in output
- Idempotent role assignment (works for existing accounts too)

**New Output**:
```
✅ Created: mcp-admin(#123), mcp-gm(#124), mcp-user(#125)
🔐 Role assignments: mcp-admin → Administrator, mcp-gm → GM (read-only), mcp-user → User (default)
```

### 2. Updated Gemfile
**Added**:
```ruby
gem "jwt" # For future RS256 JWT auth (Phase 2)
```

## Testing Plan

1. **Verify role assignment**:
   ```ruby
   # In Rails console after running rake mcp:setup_roles
   admin_role = Card.fetch("Administrator")
   members = Card.fetch("#{admin_role.name}+*members")
   members.item_names # Should include "mcp-admin"
   ```

2. **Test admin permissions**:
   ```ruby
   # Test that mcp-admin can actually delete
   Card::Auth.as("mcp-admin") do
     test_card = Card.create!(name: "Test+Delete", content: "test")
     test_card.delete! # Should succeed without PermissionDenied
   end
   ```

3. **Test API delete endpoint**:
   ```bash
   # Get admin token
   curl -X POST http://localhost:3000/api/mcp/auth \
     -H "Content-Type: application/json" \
     -d '{"api_key": "your-key", "role": "admin"}'

   # Delete card (should work now)
   curl -X DELETE http://localhost:3000/api/mcp/cards/Test+Card \
     -H "Authorization: Bearer <admin-token>"
   ```

## Recommendation: Phase 2 Priorities

Based on Gemini's feedback, prioritize these for Phase 2:

1. **Proper Markdown Parser**: Replace regex with `kramdown` or `redcarpet`
2. **Database-Backed API Keys**: Support multiple keys with independent revocation
3. **Enhanced Role Management**: More granular permission controls for GM role
4. **RS256 JWT**: Upgrade from MessageVerifier to proper JWT with JWKS

## Status

- ✅ Critical issue fixed (role assignment)
- ✅ jwt gem added
- ✅ Ready for testing
- ⏳ Pending: Integration tests for permission matrix
- ⏳ Pending: Staging deployment verification

## Approval

**Status**: Ready for merge after testing role assignment on staging environment.

**Next Steps**:
1. Run `bundle install` to install jwt gem
2. Run `rake mcp:setup_roles` with credentials
3. Verify Administrator role membership
4. Test DELETE endpoint with admin token
5. Merge to main if all tests pass
