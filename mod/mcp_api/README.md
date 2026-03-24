# MCP API Mod

Model Context Protocol (MCP) API for Decko, providing JSON API access to cards with role-based permissions.

## Features

- **Authentication**: MessageVerifier-based bearer tokens (Phase 1), RS256 JWT (Phase 2)
- **Role-Based Access**: Three roles (user, gm, admin) with different permission levels
- **CRUD Operations**: Create, read, update, delete cards via JSON API
- **Type Management**: List and lookup card types by name
- **Search & Filtering**: Query cards with multiple filter parameters
- **Batch Operations**: Bulk create/update with partial failure handling
- **Rate Limiting**: Configurable per-API-key rate limits
- **Markdown Support**: Inline markdown-to-HTML conversion

## Setup

### 1. Install Dependencies

```bash
bundle install
```

### 2. Create Service Accounts

```bash
# Set environment variables for account credentials
export MCP_USER_EMAIL="mcp-user@example.com"
export MCP_USER_PASSWORD="secure-password-1"
export MCP_GM_EMAIL="mcp-gm@example.com"
export MCP_GM_PASSWORD="secure-password-2"
export MCP_ADMIN_EMAIL="mcp-admin@example.com"
export MCP_ADMIN_PASSWORD="secure-password-3"

# Run setup task
bundle exec rake mcp:setup_roles
```

### 3. Configure API Key

```bash
# Add to .env.production or environment
export MCP_API_KEY="your-secure-api-key-here"
```

### 4. Start Server

```bash
decko server
```

## API Endpoints

### Authentication

```bash
POST /api/mcp/auth
{
  "api_key": "your-api-key",
  "role": "user|gm|admin"
}

# Response:
{
  "token": "signed-token",
  "role": "user",
  "expires_in": 3600,
  "expires_at": 1234567890
}
```

### Types

```bash
# List all types
GET /api/mcp/types
Authorization: Bearer <token>

# Get specific type
GET /api/mcp/types/RichText
Authorization: Bearer <token>
```

### Cards

```bash
# Search cards
GET /api/mcp/cards?q=search&type=RichText&limit=50&offset=0
Authorization: Bearer <token>

# Get card
GET /api/mcp/cards/Games+Butterfly%20Galaxii+Player
Authorization: Bearer <token>

# Create card
POST /api/mcp/cards
Authorization: Bearer <token>
{
  "name": "My+New+Card",
  "type": "RichText",
  "markdown_content": "# Hello\n\nThis is [[Another+Card]]"
}

# Update card
PATCH /api/mcp/cards/My+New+Card
Authorization: Bearer <token>
{
  "markdown_content": "# Updated content"
}

# Update with replace_between
PATCH /api/mcp/cards/My+Card
Authorization: Bearer <token>
{
  "patch": {
    "mode": "replace_between",
    "start_marker": "<h2>Section</h2>",
    "end_marker": "<h2>",
    "replacement_html": "<h2>Section</h2><p>New content</p>"
  }
}

# Delete card (admin only)
DELETE /api/mcp/cards/My+Card
Authorization: Bearer <token>

# List children
GET /api/mcp/cards/Parent+Card/children
Authorization: Bearer <token>
```

### Batch Operations

```bash
POST /api/mcp/cards/batch
Authorization: Bearer <token>
{
  "ops": [
    {
      "action": "create",
      "name": "Card1",
      "type": "RichText",
      "content": "<p>Content</p>"
    },
    {
      "action": "update",
      "name": "Card2",
      "markdown_content": "Updated"
    }
  ],
  "mode": "per_item"
}
```

## Configuration

### Environment Variables

```bash
# Required
MCP_API_KEY                  # API key for authentication

# Service Account Names (optional, defaults shown)
MCP_USER_NAME="mcp-user"
MCP_GM_NAME="mcp-gm"
MCP_ADMIN_NAME="mcp-admin"

# Service Account Credentials (required for setup)
MCP_USER_EMAIL
MCP_USER_PASSWORD
MCP_GM_EMAIL
MCP_GM_PASSWORD
MCP_ADMIN_EMAIL
MCP_ADMIN_PASSWORD

# Token Configuration
MCP_TOKEN_TTL=3600           # Token expiry in seconds (default: 1 hour)

# Rate Limiting
MCP_RATE_LIMITING=true       # Enable/disable rate limiting
MCP_RATE_LIMIT_PER_HOUR=1000 # Requests per hour per API key

# Caching
MCP_TYPES_CACHE_TTL=3600     # Type list cache duration (seconds)
```

## Role Permissions

### User Role
- Read player-visible content only
- Cannot see cards with +GM or +AI in name
- Cannot delete cards
- Create/update allowed for player cards

### GM Role
- Read all content including +GM and +AI cards
- Cannot delete cards
- Create/update allowed

### Admin Role
- Full access to all cards
- Can delete cards
- All operations allowed

## Development

### Testing

```bash
# Run tests (when available)
bundle exec rspec spec/mcp_api/
```

### Adding New Endpoints

1. Add route in `config/initializers/mcp_routes.rb`
2. Create controller in `app/controllers/api/mcp/`
3. Inherit from `Api::Mcp::BaseController`
4. Add tests in `spec/`

## Phase 2 Features (Planned)

- RS256 JWT authentication with JWKS
- Render endpoints (HTML ↔ Markdown)
- Named query templates
- Jobs (spoiler-scan)
- Regex patch mode with guardrails
- Batch dry-run and validation-only modes
- Recursive children listing
- Card history endpoint

## License

Same as main Decko project
