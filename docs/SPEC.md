# Magi-Archive Implementation Specification

**Project**: magi-archive
**Framework**: Decko (Ruby-based wiki)
**Purpose**: Experimental AI-friendly documentation system for game design
**Status**: Planning Phase
**Last Updated**: 2025-10-16

---

## Executive Summary

This specification outlines the implementation of a Decko-based documentation repository for game design ideas, specifically testing whether database-backed wiki systems can match or exceed the AI workflow efficiency of static site generators (MkDocs, Obsidian, etc.).

**Core Hypothesis**: Decko's structured card model may provide better semantic relationships and querying capabilities that offset the latency penalty of database operations versus direct file access.

---

## 1. Project Goals

### Primary Goals

1. **Evaluate AI Workflow Compatibility**
   - Measure operation latency vs static files (target: <10x slower)
   - Assess Claude Code's ability to work with database-backed content
   - Document workflow friction points

2. **Create Structured Game Documentation System**
   - Organize game ideas with typed cards
   - Enable rich relationships between concepts (characters ↔ mechanics ↔ narrative)
   - Support multiple game projects in one deck

3. **Test Decko for MAGI Project**
   - Serve as testbed for larger MAGI sci-fi world documentation
   - Integrate with The Smithy ecosystem if successful
   - Provide template for other documentation needs

### Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Card creation time** | <5 seconds | Time from command to completion |
| **Card search time** | <3 seconds | Query to results displayed |
| **Bulk operations (10 cards)** | <30 seconds | Create/update 10 cards |
| **AI comprehension** | 90%+ accuracy | Claude correctly interprets card structure |
| **Developer satisfaction** | 7/10 or higher | Subjective workflow rating |

---

## 2. Architecture

### 2.1 Card Type Hierarchy

```
Base Card Types:
├── Game Project
│   ├── Game Idea (high-level concept)
│   ├── Design Document (formal spec)
│   └── Development Log (journal entries)
│
├── Game Element
│   ├── Mechanic (gameplay systems)
│   ├── Character (NPCs, players, entities)
│   ├── Narrative (story beats, lore, worldbuilding)
│   ├── Location (places, worlds, maps)
│   └── Item (objects, equipment, collectibles)
│
├── Technical
│   ├── Implementation Note
│   ├── API Specification
│   └── Data Model
│
└── Meta
    ├── Tag (for cross-referencing)
    ├── Status (tracking card lifecycle)
    └── Reference (external links/resources)
```

### 2.2 Card Naming Conventions

```
Pattern: [Type]: [Name] (+Context)

Examples:
- Game Idea: Space Mining Roguelike
- Character: Alice +Butterfly Galaxii
- Mechanic: Resource Extraction +Space Mining
- Narrative: The Great Collapse +Butterfly Galaxii
- Tech: Card Export System +magi-archive
```

**Rationale**: Clear prefixes enable easy filtering and maintain context when cards appear in search results.

### 2.3 Card Relationships

**Pointer Cards** (references to other cards):
- `Game Idea: X` → includes → `[Mechanic cards, Character cards]`
- `Character: Y` → appears_in → `[Narrative cards]`
- `Mechanic: Z` → requires → `[Tech cards]`

**Nested Cards** (composition):
- `Game Idea: Space Mining/Overview` (child of parent)
- `Game Idea: Space Mining/Mechanics`
- `Game Idea: Space Mining/Characters`

### 2.4 Data Model Example

```ruby
# Game Idea Card
{
  name: "Game Idea: Space Mining Roguelike",
  type: "Game Idea",
  content: "A roguelike game about mining asteroids...",
  pointers: {
    mechanics: ["Mechanic: Resource Extraction", "Mechanic: Ship Upgrades"],
    characters: ["Character: Mining Captain"],
    status: "Status: Concept"
  }
}

# Character Card
{
  name: "Character: Mining Captain +Space Mining",
  type: "Character",
  content: "A grizzled veteran of the asteroid belt...",
  pointers: {
    game: "Game Idea: Space Mining Roguelike",
    mechanics: ["Mechanic: Ship Command"],
    narrative: ["Narrative: Tutorial Mission"]
  }
}
```

---

## 3. Development Workflow

### 3.1 Local Development Setup

```bash
# Initial setup
gem install decko
decko new magi-archive
cd magi-archive
bundle install

# Database setup
decko seed                    # Initialize with default cards
bundle exec rails console     # Open for custom setup

# Create initial card types (in console)
%w[GameIdea Mechanic Character Narrative Location Item Technical].each do |type|
  Card.create!(name: type, type: "Cardtype") unless Card.exists?(name: type)
end

# Start development server
decko server
```

### 3.2 AI Assistant Workflow

**Recommended Pattern** (minimize latency):

1. **Start persistent console**:
   ```bash
   bundle exec rails console
   ```

2. **Use Ruby commands interactively**:
   ```ruby
   # Search
   ideas = Card.search(type: "GameIdea")
   ideas.map(&:name)

   # Create
   Card.create!(
     name: "Game Idea: Underwater Exploration",
     type: "GameIdea",
     content: "Explore deep ocean trenches..."
   )

   # Read
   card = Card.fetch("Game Idea: Underwater Exploration")
   puts card.content

   # Update
   card.update!(content: "#{card.content}\n\nNew design note...")
   ```

3. **Bulk operations** (all in console):
   ```ruby
   # Create multiple related cards
   game = Card.create!(name: "Game Idea: Forest Quest", type: "GameIdea")

   characters = ["Hero", "Villain", "Mentor"].map do |role|
     Card.create!(
       name: "Character: #{role} +Forest Quest",
       type: "Character",
       content: "A #{role.downcase} in the forest..."
     )
   end
   ```

### 3.3 Anti-Patterns (Avoid)

❌ **Repeated `rails runner` calls**:
```bash
# BAD - boots Rails each time (2-5 sec overhead)
bundle exec rails runner "Card.create!(...)"
bundle exec rails runner "Card.create!(...)"
bundle exec rails runner "Card.create!(...)"
```

✅ **Use console session instead**:
```ruby
# GOOD - one Rails boot, multiple operations
# In console:
3.times { |i| Card.create!(...) }
```

---

## 4. Implementation Phases

### Phase 1: Foundation (Week 1)
**Status**: Not Started

- [ ] Initialize Decko project locally
- [ ] Configure database (SQLite for dev)
- [ ] Create card types (Game Idea, Mechanic, Character, etc.)
- [ ] Set up GitLab repository
- [ ] Write initial documentation (seed cards)

**Deliverables**:
- Working local Decko instance
- 5-10 example cards demonstrating each type
- GitLab repo with initial commit

### Phase 2: AI Workflow Testing (Week 2)
**Status**: Not Started

- [ ] Test card CRUD operations via Rails console
- [ ] Measure operation latency (create/read/search)
- [ ] Document workflow friction points
- [ ] Create helper scripts/aliases for common operations
- [ ] Test bulk operations (10+ cards)

**Deliverables**:
- Latency benchmark results
- Workflow documentation
- Helper script library

### Phase 3: Content Migration (Week 3)
**Status**: Not Started

- [ ] Import existing game ideas (if any)
- [ ] Create 20-30 real cards across types
- [ ] Establish card relationships (pointers)
- [ ] Test search/query patterns
- [ ] Validate card naming conventions

**Deliverables**:
- Populated deck with real content
- Documented query patterns
- Refined naming conventions

### Phase 4: Production Deployment (Week 4)
**Status**: Not Started

**Choose deployment platform**: Railway (simple) or AWS EC2 (full control)

#### Option A: Railway Deployment
- [ ] Configure Railway deployment
- [ ] Set up PostgreSQL production database (auto-provisioned)
- [ ] Configure environment variables
- [ ] Set up GitLab CI/CD pipeline
- [ ] Deploy to production

#### Option B: AWS EC2 Deployment (See AWS-DEPLOYMENT.md)
- [ ] Set up AWS account and IAM user
- [ ] Create RDS PostgreSQL instance
- [ ] Launch EC2 instance (Ubuntu 22.04)
- [ ] Configure security groups and Elastic IP
- [ ] Install Ruby, Decko, and dependencies
- [ ] Configure Nginx reverse proxy
- [ ] Set up SSL with Let's Encrypt
- [ ] Create systemd service for auto-start
- [ ] Configure backups and monitoring

**Deliverables**:
- Live production instance
- Automated deployment pipeline (Railway) or manual deployment runbook (AWS)
- Production access documentation
- Collaborator onboarding guide

### Phase 5: Evaluation & Iteration (Ongoing)
**Status**: Not Started

- [ ] Compare metrics vs static file baseline
- [ ] Document pros/cons
- [ ] Identify optimization opportunities
- [ ] Decide: continue with Decko or revert to static files
- [ ] Create migration guide if reverting

**Deliverables**:
- Evaluation report
- Decision documentation
- Migration plan (if needed)

---

## 5. Migration Considerations

### 5.1 From MkDocs (If Applicable)

If migrating from existing MkDocs documentation:

```ruby
# Import script concept (to be developed)
Dir.glob("docs/**/*.md").each do |file|
  # Extract frontmatter
  content = File.read(file)
  title = content.match(/^#\s+(.+)$/)[1] rescue File.basename(file, ".md")

  # Infer type from directory or frontmatter
  type = case file
         when /mechanics/ then "Mechanic"
         when /characters/ then "Character"
         else "GameIdea"
         end

  # Create card
  Card.create!(
    name: "#{type}: #{title}",
    type: type,
    content: content
  )
end
```

### 5.2 Export Back to Static Files

For AI search compatibility, periodic export:

```ruby
# Export script concept
Card.search.each do |card|
  filename = "exports/#{card.name.parameterize}.md"
  File.write(filename, <<~MD)
    # #{card.name}

    **Type**: #{card.type_name}
    **Created**: #{card.created_at}
    **Updated**: #{card.updated_at}

    #{card.content}
  MD
end
```

This enables: `grep -r "keyword" exports/`

---

## 6. Technical Stack

### 6.1 Dependencies

```ruby
# Gemfile additions
gem 'decko'
gem 'pg', '~> 1.1'              # Production database
gem 'puma', '~> 5.0'            # Web server
gem 'rails_12factor'            # Railway/Heroku compatibility

group :development, :test do
  gem 'sqlite3', '~> 1.4'       # Local database
  gem 'rspec-rails'             # Testing
  gem 'pry-rails'               # Better console
end

group :development do
  gem 'annotate'                # Model annotations
  gem 'bullet'                  # N+1 query detection
end
```

### 6.2 Environment Variables

**Local Development** (`.env`):
```bash
RAILS_ENV=development
DATABASE_URL=sqlite3:db/development.sqlite3
```

**Production** (Railway):
```bash
RAILS_ENV=production
SECRET_KEY_BASE=<generated>
PGDATABASE=<auto-provisioned>
PGHOST=<auto-provisioned>
PGPASSWORD=<auto-provisioned>
PGPORT=<auto-provisioned>
PGUSER=<auto-provisioned>
RAILS_SERVE_STATIC_FILES=true
RAILS_LOG_TO_STDOUT=true
```

### 6.3 Infrastructure

#### Railway Option (Recommended for Testing)
- **Version Control**: GitLab (gitlab.com/yourusername/magi-archive)
- **Hosting**: Railway (railway.app)
- **Database**: PostgreSQL 13+ (Railway-managed)
- **CDN**: Railway's built-in
- **Monitoring**: Railway logs + metrics
- **Cost**: ~$5-20/month (free tier available)

#### AWS EC2 Option (Recommended for Production)
- **Version Control**: GitLab (gitlab.com/yourusername/magi-archive)
- **Hosting**: AWS EC2 t3.small Ubuntu 22.04
- **Database**: AWS RDS PostgreSQL (db.t3.micro/small)
- **Web Server**: Nginx + Puma
- **SSL**: Let's Encrypt (Certbot)
- **Monitoring**: CloudWatch + Enhanced RDS monitoring
- **Backups**: RDS automated backups + S3 for uploads
- **Cost**: ~$35-45/month ($0-5/month with free tier first year)

**See AWS-DEPLOYMENT.md for complete AWS setup guide.**

---

## 7. Testing Strategy

### 7.1 Functional Testing

```ruby
# spec/models/game_idea_spec.rb
RSpec.describe "Game Idea cards" do
  it "creates a game idea with mechanics" do
    game = Card.create!(
      name: "Game Idea: Test Game",
      type: "GameIdea",
      content: "A test game"
    )

    mechanic = Card.create!(
      name: "Mechanic: Jump +Test Game",
      type: "Mechanic"
    )

    expect(game).to be_valid
    expect(mechanic.name).to include("+Test Game")
  end
end
```

### 7.2 Performance Testing

```ruby
# Benchmark script
require 'benchmark'

puts Benchmark.measure {
  Card.create!(name: "Perf Test", content: "...")
}

puts Benchmark.measure {
  Card.search(type: "GameIdea").to_a
}

puts Benchmark.measure {
  10.times { |i| Card.create!(name: "Bulk #{i}", content: "...") }
}
```

### 7.3 AI Workflow Testing

Manual testing checklist:
- [ ] Claude can create cards via console commands
- [ ] Claude can search for cards by name/type
- [ ] Claude can update existing cards
- [ ] Claude understands card relationships
- [ ] Claude can bulk-create related cards
- [ ] Latency is acceptable (<5 sec per operation)

---

## 8. Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| **Latency too high for AI workflows** | High | Medium | Keep console open; create export layer |
| **Database complexity overwhelming** | Medium | Low | Start simple; add features incrementally |
| **Decko learning curve steep** | Medium | Medium | Extensive documentation; limit custom mods |
| **Migration back to static files costly** | Medium | Low | Keep export scripts; maintain parallel docs |
| **Railway costs exceed budget** | Low | Low | Monitor usage; use free tier initially |

---

## 9. Decision Points

### Go/No-Go Criteria (End of Phase 2)

**Proceed with Decko if**:
- Average operation latency <5 seconds
- AI comprehension >80%
- Structured relationships provide clear value
- Developer satisfaction ≥6/10

**Revert to static files if**:
- Average operation latency >10 seconds
- Frequent AI errors or confusion
- Relationships don't justify complexity
- Developer satisfaction <5/10

---

## 10. Open Questions

1. **Card versioning**: How to track card history? Use Decko's built-in history or external git?
2. **Search optimization**: Can we pre-export cards for grep access without losing db benefits?
3. **Integration**: How to link cards to assets in spyder service?
4. **Access control**: Do we need user authentication for production?
5. **Backup strategy**: How often to backup database? Automated or manual?

---

## 11. References

### Core Documentation
- **Decko Documentation**: https://decko.org
- **Decko GitHub**: https://github.com/decko-commons/decko
- **Railway Docs**: https://docs.railway.app
- **Claude Code Guide**: `CLAUDE.md`
- **Previous Conversation**: `decko conversation.md`

### Implementation Guides
- **Deployment Guide (AWS)**: `AWS-DEPLOYMENT.md`
- **Development Roadmap**: `ROADMAP.md` ⭐
- **Migration Guide (MkDocs→Decko)**: `MIGRATION.md`
- **Atomspace Integration**: `ATOMSPACE-INTEGRATION.md` (future)
- **AI Gamemaster Vision**: `AI-GAMEMASTER-VISION.md` (long-term)

---

## Appendix A: Example Card Templates

### Game Idea Template
```markdown
# [Game Title]

## Concept
[High-level concept in 2-3 sentences]

## Core Mechanics
- [Mechanic 1]: [Brief description]
- [Mechanic 2]: [Brief description]

## Target Audience
[Who is this for?]

## Unique Selling Point
[What makes this different?]

## Related Cards
- Mechanics: [links to mechanic cards]
- Characters: [links to character cards]
- Narrative: [links to narrative cards]
```

### Character Template
```markdown
# [Character Name] +[Game Context]

## Overview
[2-3 sentence description]

## Role
[Protagonist/Antagonist/Supporting/NPC]

## Traits
- Personality: [key traits]
- Abilities: [special powers/skills]
- Motivation: [what drives them]

## Relationships
- [Character]: [relationship description]

## Narrative Connections
[Which story beats feature this character?]
```

### Mechanic Template
```markdown
# [Mechanic Name] +[Game Context]

## Description
[What is this mechanic?]

## Purpose
[Why does this mechanic exist? What problem does it solve?]

## Implementation Notes
[How would this work technically?]

## Synergies
- Works well with: [other mechanics]
- Conflicts with: [incompatible mechanics]

## Inspiration
[Similar mechanics in other games]
```

---

---

**Version**: 1.1 (Revised with complete roadmap)
**Authors**: Lake (with Claude Code assistance)
**Last Updated**: 2025-10-16
**Next Review**: After Phase 1 deployment (Week 2)

---

## Document History

- **v1.0** (2025-10-16): Initial specification for Decko wiki
- **v1.1** (2025-10-16): Added comprehensive roadmap, migration guide, Atomspace integration plan, AI GM vision

## Quick Start

**New to this project?** Start here:

1. **Read**: `ROADMAP.md` - Complete phased implementation plan
2. **Deploy**: Follow Phase 1 in `ROADMAP.md` or `AWS-DEPLOYMENT.md`
3. **Migrate**: Use `MIGRATION.md` to import MkDocs content
4. **Future**: See `ATOMSPACE-INTEGRATION.md` and `AI-GAMEMASTER-VISION.md` for long-term goals
