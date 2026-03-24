# MCP API Phase 2 Implementation Plan

## Goals

Phase 2 upgrades the MVP to production-ready quality with:
- **Security**: RS256 JWT with JWKS key rotation
- **Robustness**: Proper Markdown parsing, database-backed API keys
- **Advanced Features**: Render endpoints, named queries, jobs
- **Safety**: Dry-run modes, validation-only operations

## Phase 2 Features (Priority Order)

### Priority 1: Core Upgrades (Critical for Production)

#### 1.1 RS256 JWT Authentication with JWKS
**Why**: MessageVerifier tokens aren't suitable for distributed systems; JWT standard enables:
- Key rotation without service interruption
- Token verification without database lookups
- Industry-standard security

**Implementation**:
- Generate RSA key pair for signing JWTs
- Expose JWKS endpoint at `/api/mcp/.well-known/jwks.json`
- Update `AuthController` to issue RS256 JWTs
- Update `BaseController` to verify JWTs via JWKS
- Maintain MessageVerifier fallback for backward compatibility
- Add key rotation mechanism with overlapping validity

**Files**:
- `lib/mcp_api/jwt_service.rb` - JWT generation and verification
- `app/controllers/api/mcp/jwks_controller.rb` - JWKS endpoint
- Update `auth_controller.rb` and `base_controller.rb`

#### 1.2 Proper Markdown Parser
**Why**: Regex-based conversion breaks on nested lists, code blocks, complex formatting

**Implementation**:
- Add `kramdown` gem (well-maintained, feature-rich)
- Replace `convert_markdown_to_html` in `CardsController`
- Preserve wiki links `[[...]]` via custom processor
- Add sanitization for untrusted content
- Support GFM (GitHub Flavored Markdown) extensions

**Files**:
- Update `Gemfile` with `kramdown`
- `lib/mcp_api/markdown_converter.rb` - Proper conversion service
- Update `cards_controller.rb` to use new converter

#### 1.3 Database-Backed API Keys
**Why**: Single ENV-based key prevents:
- Independent key revocation per client/agent
- Usage tracking and rate limit per key
- Audit trail of which key performed what action

**Implementation**:
- Create `ApiKey` model with fields: `key_hash`, `name`, `role`, `rate_limit`, `expires_at`, `last_used_at`
- Migration to create `api_keys` table
- Update `AuthController` to look up keys from database
- Add admin endpoints for key management (CRUD)
- Hash keys with bcrypt (store hash, not plaintext)

**Files**:
- `db/migrate/XXXXXX_create_api_keys.rb`
- `app/models/api_key.rb`
- `app/controllers/api/mcp/api_keys_controller.rb` (admin-only)
- Update `auth_controller.rb` for DB lookup

### Priority 2: Advanced Features

#### 2.1 Render Endpoints
**Why**: AI agents need to convert between HTML (Decko storage) and Markdown (LLM-friendly)

**Implementation**:
- `POST /api/mcp/render` - HTML → Markdown conversion
- `POST /api/mcp/render/markdown` - Markdown → HTML conversion
- Use `kramdown` for Markdown → HTML
- Use `reverse_markdown` gem for HTML → Markdown
- Preserve wiki links in both directions

**Files**:
- Update `Gemfile` with `reverse_markdown`
- `app/controllers/api/mcp/render_controller.rb`

#### 2.2 Named Query Templates
**Why**: Exposing even limited CQL is risky; named queries provide safe, tested patterns

**Implementation**:
- Define common query templates in config
- `GET /api/mcp/queries/faction_cards?game=Butterfly+Galaxii`
- `GET /api/mcp/queries/recent_updates?since=2025-01-01&limit=50`
- Templates use parameter substitution with validation
- No raw CQL exposure

**Files**:
- `config/mcp_queries.yml` - Query definitions
- `lib/mcp_api/query_template.rb` - Template processor
- `app/controllers/api/mcp/queries_controller.rb`

#### 2.3 run_query Endpoint (Limited CQL)
**Why**: Fallback for queries not covered by templates; must be heavily restricted

**Implementation**:
- `POST /api/mcp/run_query` with JSON query spec
- Allowed filters only: `name`, `prefix`, `not_name`, `type`, `updated_since/before`, `tag`, `limit/offset`
- Disallow: destructive views, raw SQL, pointer deref, content mutation
- Enforce caps: max limit 100, timeout 30s
- Return structured results with pagination

**Files**:
- `app/controllers/api/mcp/run_query_controller.rb`
- `lib/mcp_api/query_validator.rb` - Filter whitelist enforcement

### Priority 3: Safety & Operations

#### 3.1 Batch Dry-Run and Validation Modes
**Why**: Let agents preview changes before committing (reduce errors)

**Implementation**:
- Add `dry_run: true` parameter to batch endpoint
- Returns what would happen without executing
- Add `return_diff: true` to show before/after content
- Add `validate_only: true` to check without saving
- Update batch response to include validation errors and diffs

**Files**:
- Update `cards_controller.rb` batch action
- Add `lib/mcp_api/batch_preview.rb` for diff generation

#### 3.2 Jobs Endpoint (Spoiler-Scan)
**Why**: Replace SSH scripts for long-running operations

**Implementation**:
- `POST /api/mcp/jobs/spoiler-scan`
- Input: `{ terms_card, results_card, scope: "player|ai", limit }`
- Queues background job (use Decko's delayed_job if available)
- Returns job ID and status URL
- `GET /api/mcp/jobs/:id` to check status
- Writes formatted results to specified card when complete

**Files**:
- `app/controllers/api/mcp/jobs_controller.rb`
- `app/jobs/mcp_spoiler_scan_job.rb` (if delayed_job available)
- Otherwise inline execution with timeout

#### 3.3 Enhanced Role Management for GM
**Why**: GM role needs read access to +GM cards but no delete

**Implementation**:
- Create custom read permission rule for +GM cards
- GM role can read but not modify GM content
- Update `can_view_card?` logic in CardsController
- Add permission tests to verify GM boundaries

**Files**:
- Update `cards_controller.rb` permission checks
- Add Decko permission rules (via cards or mod)

### Priority 4: Nice-to-Have

#### 4.1 Card History Endpoint
- `GET /api/mcp/cards/:name/history` - List versions
- `GET /api/mcp/cards/:name/history/:version` - Get specific version
- Expose Decko's built-in versioning

#### 4.2 Recursive Children Listing
- Add `recursive=true` parameter to `/api/mcp/cards/:name/children`
- Return tree structure with depth limits

#### 4.3 Attachment Handling
- `POST /api/mcp/attachments` with multipart upload
- Size and MIME type restrictions
- Link to card via pointer

#### 4.4 Long-Lived Tokens (Optional)
- Special token type for non-interactive agents
- Longer expiry (7-30 days) with secure storage requirements

## Implementation Sequence

### Week 1: Core Security Upgrades
1. RS256 JWT with JWKS (2 days)
2. Database-backed API keys (2 days)
3. Proper Markdown parser (1 day)

### Week 2: Advanced Features
4. Render endpoints (1 day)
5. Named query templates (2 days)
6. run_query with validation (2 days)

### Week 3: Safety & Operations
7. Batch dry-run/validation modes (2 days)
8. Jobs endpoint (spoiler-scan) (2 days)
9. Enhanced GM role permissions (1 day)

### Week 4: Polish & Testing
10. Integration tests for all Phase 2 features
11. Documentation updates
12. Staging deployment and verification

## Dependencies

**New Gems Required**:
```ruby
gem "jwt"              # Already added in Phase 1.1
gem "kramdown"         # Markdown parsing
gem "reverse_markdown" # HTML → Markdown conversion
gem "bcrypt"           # API key hashing (likely already present via Devise/Rails)
```

## Configuration

**New Environment Variables**:
```bash
# JWT Configuration
JWT_PRIVATE_KEY_PATH=/path/to/private_key.pem
JWT_PUBLIC_KEY_PATH=/path/to/public_key.pem
JWT_KEY_ID=key-001
JWT_ISSUER=magi-archive
JWT_EXPIRY=3600  # 1 hour

# API Key Management
API_KEY_ADMIN_REQUIRED=true  # Require admin role for key CRUD

# Query Limits
MAX_QUERY_LIMIT=100
QUERY_TIMEOUT=30  # seconds

# Jobs
JOBS_ENABLED=true
SPOILER_SCAN_TIMEOUT=300  # 5 minutes
```

## Backward Compatibility

**Phase 1 Compatibility**:
- MessageVerifier tokens continue to work alongside JWT
- ENV-based `MCP_API_KEY` remains valid (migrated to DB automatically)
- All Phase 1 endpoints unchanged (only internal implementation upgraded)

**Migration Path**:
1. Deploy Phase 2 with dual auth support (JWT + MessageVerifier)
2. Issue new JWT-based tokens to clients
3. Monitor usage of old MessageVerifier tokens
4. After transition period (e.g., 30 days), deprecate MessageVerifier

## Success Criteria

Phase 2 is complete when:
- ✅ All Phase 1 functionality preserved
- ✅ JWT authentication working with key rotation
- ✅ Database-backed API keys with admin management
- ✅ Proper Markdown conversion (kramdown-based)
- ✅ Render endpoints functional
- ✅ Named queries and run_query implemented with safety guards
- ✅ Batch dry-run/validation modes working
- ✅ Spoiler-scan job executable via API
- ✅ Integration tests pass for all new features
- ✅ Documentation updated
- ✅ Staging deployment successful

## Risks & Mitigations

**Risk 1: JWT key management complexity**
- Mitigation: Start with single key, add rotation in Phase 2.5
- Use environment variables for initial keys

**Risk 2: Markdown conversion edge cases**
- Mitigation: Comprehensive test suite with real wiki content samples
- Preserve wiki links as highest priority

**Risk 3: Database migration on production**
- Mitigation: Test migration on staging first
- Have rollback plan ready
- Populate initial API key from ENV automatically

**Risk 4: Backward compatibility breakage**
- Mitigation: Dual auth support during transition
- Feature flags for gradual rollout
- Extensive regression testing

## Next Steps

1. Create feature branch: `feature/mcp-api-phase2`
2. Start with Priority 1.1: RS256 JWT implementation
3. Add kramdown gem and upgrade Markdown conversion
4. Implement API key model and admin endpoints
5. Continue through priorities in order

Ready to begin implementation!
