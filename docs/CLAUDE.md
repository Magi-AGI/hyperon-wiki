# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is the **magi-archive** repository - a documentation and knowledge management system built on the [Decko framework](https://github.com/decko-commons/decko) (formerly Wagn). This repository serves as an experimental testbed to evaluate whether database-backed wiki systems can work effectively with AI coding assistants, compared to static site generators like MkDocs.

**Project Purpose**: Test AI workflow compatibility with Decko's card-based database architecture for game design documentation.

## Technology Stack

- **Framework**: Decko (Ruby-based wiki framework)
- **Language**: Ruby 2.7+
- **Database**: PostgreSQL (production) / SQLite (development)
- **Web Framework**: Rails (underlying Decko)
- **Deployment**: Railway + GitLab CI/CD (planned)
- **Documentation Model**: Cards (key-value pairs stored in database)

## Architecture

### Decko Card Model

In Decko, everything is a **card**:
- **Card**: Basic unit - a key/value pair with a name (key) and content (value)
- **Card Types**: Cards can have types (e.g., "Game Idea", "Mechanic", "Character")
- **Card Relationships**: Cards can reference other cards via pointers and nesting
- **Sets**: Collections of cards organized by rules

### Data Storage

**Important for AI workflows**:
- Cards are stored in a **database** (PostgreSQL/MySQL), NOT as files
- No direct filesystem access to card content
- Must use Rails console or API for programmatic access
- Cannot use standard filesystem tools (grep, find, cat) directly on content

## Development Setup

### Initial Setup

```bash
# Install Decko gem
gem install decko

# Create new deck (if starting fresh)
decko new magi-archive
cd magi-archive

# Install dependencies
bundle install

# Setup database and seed initial data
decko seed

# Start development server
decko server
# Access at http://localhost:3000
```

### Production Configuration

For PostgreSQL in production, configure `config/database.yml`:

```yaml
production:
  adapter: postgresql
  encoding: unicode
  database: <%= ENV['PGDATABASE'] %>
  username: <%= ENV['PGUSER'] %>
  password: <%= ENV['PGPASSWORD'] %>
  host: <%= ENV['PGHOST'] %>
  port: <%= ENV['PGPORT'] %>
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
```

## Working with Cards (AI Assistant Guide)

### Rails Console Access

Access the Rails console for programmatic card operations:

```bash
# Local development
bundle exec rails console

# Production (via Railway CLI)
railway run bundle exec rails console
```

### Card CRUD Operations

**Reading Cards:**
```ruby
# Fetch by name
card = Card.fetch("Game Idea: Space Adventure")
card = "Game Idea: Space Adventure".card  # Shortcut

# Fetch by ID
card = Card.fetch(42)
card = 42.card

# Fetch by codename
card = Card.fetch(:help)
card = :help.card

# Access content
card.content        # Official content (may include structure rules)
card.db_content     # Raw database content
card.name           # Card name
card.type_name      # Type as string
card.type_id        # Type ID
```

**Searching/Querying Cards:**
```ruby
# Search by type
Card.search(type_id: 4)
Card.search(type: "Basic")

# Search by name pattern (CQL - Card Query Language)
Card.search(name: ["match", "game"])

# More complex queries use CQL syntax
# Note: Full CQL documentation at decko.org/CQL
```

**Creating Cards:**
```ruby
# Basic creation
Card.create!(name: "New Game Idea", content: "Description here")

# With type
Card.create!(
  name: "Character: Alice",
  content: "A brave explorer",
  type_id: character_type_id
)

# With type code
Card.create!(
  name: "Mechanic: Crafting",
  content: "Players can combine items",
  type_code: :basic
)
```

**Updating Cards:**
```ruby
card = Card.fetch("My Card")
card.content = "Updated content"
card.save!

# Or in one step
card.update!(content: "Updated content")
```

**Deleting Cards:**
```ruby
card = Card.fetch("Old Idea")
card.delete!
```

### AI Workflow Commands

**Quick card lookup via rails runner:**
```bash
# Read card content
bundle exec rails runner "puts Card.fetch('Card Name').content"

# Search for cards
bundle exec rails runner "Card.search(type: 'Game Idea').each {|c| puts c.name}"

# Create card
bundle exec rails runner "Card.create!(name: 'New Idea', content: 'Content')"
```

**Performance Note**: Each `rails runner` command boots Rails (~2-5 seconds). For multiple operations, use an interactive console session instead.

## AI Workflow Considerations

### Limitations vs Static Files

**No Direct File Search:**
- Cannot use `grep -r "keyword" docs/`
- Must use database queries: `Card.search(...)`
- **Workaround**: Export cards to markdown periodically for search

**No Direct File Editing:**
- Cannot use `cat`, `sed`, `awk` on card content
- Must use Rails console or API
- **Latency**: 2-5 seconds per operation vs <100ms for files

**Server Dependency:**
- Requires database + Rails server running
- Cannot work offline with just files
- More complex development environment

### Recommended AI Workflows

**For exploration/search tasks:**
1. Keep a Rails console session open: `bundle exec rails console`
2. Use Ruby commands interactively
3. Avoid repeated `rails runner` calls (slow boot time)

**For bulk operations:**
```ruby
# In Rails console - create multiple cards efficiently
ideas = [
  {name: "Idea 1", content: "..."},
  {name: "Idea 2", content: "..."}
]
ideas.each { |i| Card.create!(i) }
```

**For content search:**
```ruby
# Search card content (in Rails console)
Card.search.select { |c| c.content.include?("keyword") }

# More efficient with CQL if possible
Card.search(content: ["match", "keyword"])
```

## Common Commands

```bash
# Development
decko server                    # Start development server
bundle exec rails console       # Open Rails console
decko seed                      # Seed database with initial data

# Database
decko update                    # Run migrations
bundle exec rails db:migrate    # Alternative migration command
bundle exec rails db:reset      # Reset database (destructive!)

# Testing
bundle exec rspec               # Run all tests
bundle exec rspec spec/path     # Run specific test

# Deployment (Railway)
railway login                   # Login to Railway
railway link                    # Link to Railway project
railway run <command>           # Run command in Railway environment
railway run bundle exec rails console  # Production console access
```

## Export/Import (Planned)

Decko supports export functionality for offline AI access:

```ruby
# Export cards to JSON (in Rails console)
# Format and exact commands TBD - check decko.org/support_simple_import_and_export

# Planned: Export to markdown for AI search
# This would enable: grep -r "keyword" exports/
```

## Project Structure

```
magi-archive/
├── mod/                        # Custom Decko modifications
│   └── game_ideas/            # Game documentation mods
│       ├── set/               # Card set definitions
│       ├── lib/               # Ruby library code
│       └── format/            # Output format customizations
├── config/
│   ├── database.yml           # Database configuration
│   └── application.rb         # Rails app config
├── db/                        # Database migrations and schema
├── files/                     # Uploaded assets
├── script/                    # Helper scripts
├── docs/                      # Static documentation (for reference)
│   └── decko conversation.md  # Previous planning conversation
├── Gemfile                    # Ruby dependencies
└── CLAUDE.md                  # This file
```

## Card Types for Game Documentation

Planned card types for organizing game ideas:

- **Game Idea**: High-level game concepts
- **Mechanic**: Gameplay mechanics and systems
- **Character**: Character concepts and descriptions
- **Narrative**: Story elements and lore
- **Technical**: Implementation notes
- **Asset**: References to art/audio/3D assets

Create card types through Decko's web interface or programmatically via Rails console.

## Experiment Metrics

**This repository is an experiment** comparing Decko vs MkDocs for AI workflows. Track:

- **Operation latency**: Time for create/read/search operations
- **Workflow friction**: Complexity of common tasks
- **AI assistant effectiveness**: Can Claude Code work efficiently with database-backed cards?

Compare against static file alternatives (MkDocs, Obsidian, plain markdown).

## Related Projects

Part of The Smithy monorepo ecosystem:
- **TheSmithy**: Main Evennia-based MUD server
- **Core/endless-cascade**: Unreal Engine 5 3D client
- **spyder**: Asset management & API service
- **magi**: Future sci-fi experience world (parent project)

## Resources

- **Decko Documentation**: https://decko.org
- **GitHub**: https://github.com/decko-commons/decko
- **Card API Docs**: https://docs.decko.org/docs/Card/Query
- **CQL Syntax**: https://decko.org/CQL

## License

GNU General Public License v3.0 (GPL-3.0)
