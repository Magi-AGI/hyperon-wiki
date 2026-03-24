# MkDocs to Decko Migration Guide

**Project**: magi-archive
**Source**: 5 MkDocs repositories
**Target**: Decko card-based wiki
**Approach**: Manual migration with review
**Timeline**: Week 2 of Phase 1
**Last Updated**: 2025-10-16

---

## Overview

This guide outlines the process for migrating content from multiple MkDocs repositories to the Decko wiki system. The migration is **manual** to allow for review, cleanup, consolidation, and proper card type assignment.

---

## Source Repositories

Content lives in 5 separate MkDocs repositories:

```
E:\GitLab\the-smithy1\magi\magi-knowledge-repo      (main)
E:\GitLab\the-smithy1\magi\magi-knowledge-repo-2    (branch/variant)
E:\GitLab\the-smithy1\magi\magi-knowledge-repo-3    (branch/variant)
E:\GitLab\the-smithy1\magi\magi-knowledge-repo-4    (branch/variant)
E:\GitLab\the-smithy1\magi\magi-knowledge-repo-5    (branch/variant)
```

**Key Questions to Answer First**:
1. Which repo contains canonical/most current content?
2. Are repos 2-5 branches with divergent content or duplicates?
3. What content is unique vs duplicated across repos?
4. What can be archived vs actively migrated?

---

## Migration Philosophy

### Why Manual Migration?

**Pros**:
- ✅ Review each piece of content for accuracy/relevance
- ✅ Consolidate duplicate content across repos
- ✅ Assign appropriate card types based on content
- ✅ Clean up outdated/inconsistent information
- ✅ Restructure content for better card relationships
- ✅ Opportunity to improve writing quality

**Cons**:
- ❌ Time-consuming (estimated 10-20 hours)
- ❌ Risk of missing content
- ❌ Manual work prone to human error

**Decision**: Manual migration worth the effort for quality control

### Automated Script (Reference Only)

An automated script could be used for initial bulk import, but **requires review**:

```ruby
# scripts/import_mkdocs.rb
# WARNING: Review all imported content before making public!

require 'yaml'
require 'fileutils'

class MkDocsImporter
  REPOS = [
    'E:/GitLab/the-smithy1/magi/magi-knowledge-repo',
    'E:/GitLab/the-smithy1/magi/magi-knowledge-repo-2',
    'E:/GitLab/the-smithy1/magi/magi-knowledge-repo-3',
    'E:/GitLab/the-smithy1/magi/magi-knowledge-repo-4',
    'E:/GitLab/the-smithy1/magi/magi-knowledge-repo-5'
  ].freeze

  def import_all
    REPOS.each_with_index do |repo_path, index|
      puts "Processing repo #{index + 1}/#{REPOS.length}: #{repo_path}"
      import_repo(repo_path, index + 1)
    end
  end

  def import_repo(repo_path, repo_num)
    docs_path = File.join(repo_path, 'docs')
    return unless Dir.exist?(docs_path)

    Dir.glob("#{docs_path}/**/*.md").each do |file_path|
      import_file(file_path, repo_num)
    end
  end

  def import_file(file_path, repo_num)
    content = File.read(file_path)

    # Extract metadata
    title = extract_title(content)
    type = infer_type(file_path, content)

    # Skip if duplicate (check by title)
    if Card.exists?(name: "#{type}: #{title}")
      puts "  SKIP (duplicate): #{title}"
      return
    end

    # Create card
    card = Card.create!(
      name: "#{type}: #{title}",
      type: type,
      content: clean_content(content),
      tags: ["repo-#{repo_num}", "imported", "needs-review"]
    )

    puts "  ✓ Imported: #{card.name}"
  rescue => e
    puts "  ✗ ERROR: #{file_path} - #{e.message}"
  end

  def extract_title(content)
    # Try frontmatter first
    if content.match(/^---\n(.*?)\n---\n/m)
      frontmatter = YAML.load($1)
      return frontmatter['title'] if frontmatter['title']
    end

    # Fall back to first heading
    if content.match(/^#\s+(.+)$/)
      return $1.strip
    end

    # Fall back to filename
    "Untitled Document"
  end

  def infer_type(file_path, content)
    # Infer from directory structure
    case file_path
    when /factions/ then "Faction"
    when /species/ then "Species"
    when /characters/ then "Character"
    when /mechanics/ then "Mechanic"
    when /narrative|story|lore/ then "Narrative"
    when /locations|worlds|places/ then "Location"
    when /tech|technical/ then "Technical"
    when /games|butterfly-galaxii|godsgame/ then "Game"
    else
      # Try to infer from content
      if content.match?(/class|race|species/i)
        "Species"
      elsif content.match?(/faction|empire|guild/i)
        "Faction"
      elsif content.match?(/character|npc|protagonist/i)
        "Character"
      else
        "GameIdea"  # Default
      end
    end
  end

  def clean_content(content)
    # Remove frontmatter
    content = content.gsub(/^---\n.*?\n---\n/m, '')

    # Convert MkDocs-specific syntax if needed
    # (admonitions, etc.)

    content.strip
  end
end

# Usage:
# bundle exec rails runner scripts/import_mkdocs.rb
MkDocsImporter.new.import_all
```

**Note**: This script is **reference only**. Do NOT run blindly. Use for bulk initial import, then manually review every card.

---

## Migration Process

### Phase 1: Preparation

#### 1.1 Inventory Existing Content

Create a spreadsheet tracking all content:

| Repo | File Path | Title | Type | Status | Notes |
|------|-----------|-------|------|--------|-------|
| 1 | docs/factions/korvax.md | Korvax Empire | Faction | To Migrate | Canonical version |
| 2 | docs/factions/korvax.md | Korvax Empire | Faction | Skip | Duplicate, outdated |
| ... | ... | ... | ... | ... | ... |

**Tools**:
- Manual: Walk through each repo, list files
- Script: Run `find docs/ -name "*.md"` in each repo, export to CSV

#### 1.2 Identify Canonical Sources

For each piece of content appearing in multiple repos:
- Compare versions (use `diff` or visual inspection)
- Determine which is most current/accurate
- Mark others as "Skip (duplicate)"

#### 1.3 Define Card Types

Create card types in Decko **before** migration:

```ruby
# In Rails console: bundle exec rails console
card_types = %w[
  Game
  Faction
  Species
  Character
  Mechanic
  Narrative
  Location
  Item
  Technical
  Reference
]

card_types.each do |type|
  Card.create!(name: type, type: "Cardtype") unless Card.exists?(name: type)
  puts "✓ Created card type: #{type}"
end
```

### Phase 2: Migration Workflow

#### 2.1 Per-File Process

For each markdown file to migrate:

1. **Read the file** in MkDocs repo
2. **Review content**:
   - Is this current and accurate?
   - Does it duplicate other content?
   - Should it be split into multiple cards?
3. **Determine card type**:
   - Based on content and directory location
   - Use card type naming convention: `[Type]: [Name]`
4. **Extract metadata**:
   - Frontmatter (if present)
   - Headings, tags, related pages
5. **Create Decko card**:
   - Via web UI: Click "New Card", enter details
   - Via Rails console: `Card.create!(...)`
6. **Set relationships**:
   - Pointer cards to related content
   - Nested cards for sub-topics
7. **Tag for tracking**:
   - `imported` - Was migrated from MkDocs
   - `repo-N` - Which repo it came from
   - `needs-review` - Not yet verified by owner

#### 2.2 Web UI Migration (Recommended for Most Content)

1. **Open Decko in browser**: https://yourdomain.com
2. **Click "+ New Card"**
3. **Enter details**:
   - Name: `[Type]: [Title from MkDocs]`
   - Type: Select from dropdown
   - Content: Copy-paste from MkDocs markdown
4. **Add relationships** (if applicable):
   - Related cards (pointer fields)
5. **Save card**
6. **Mark file as migrated** in tracking spreadsheet

#### 2.3 Rails Console Migration (Bulk/Scripted)

For bulk import or when web UI is slow:

```ruby
# In Rails console
content = File.read('E:/GitLab/the-smithy1/magi/magi-knowledge-repo/docs/factions/korvax.md')

Card.create!(
  name: "Faction: Korvax Empire",
  type: "Faction",
  content: content.gsub(/^---\n.*?\n---\n/m, '').strip,  # Remove frontmatter
  tags: ["imported", "repo-1", "butterfly-galaxii"]
)
```

### Phase 3: Consolidation

#### 3.1 Merge Duplicates

For content appearing in multiple repos:

1. Open all versions side-by-side
2. Identify differences (new info, corrections, etc.)
3. Create single consolidated card with best content from all sources
4. Note in card content: "Consolidated from repos 1, 3, 4"

#### 3.2 Restructure Content

MkDocs may have had suboptimal structure. Improve it:

**Example - MkDocs had**:
```
docs/
  games/
    butterfly-galaxii.md (1000 lines, everything about the game)
```

**Decko should have**:
```
Card: "Game: Butterfly Galaxii" (overview, 200 lines)
  ↓ includes (pointers)
Card: "Faction: Korvaxian Empire"
Card: "Species: Korvax Synthetics"
Card: "Mechanic: Asteroid Mining"
Card: "Narrative: The Great Collapse"
  ... (each as separate card)
```

Split large MkDocs files into multiple focused Decko cards.

#### 3.3 Establish Relationships

Once cards created, link them:

**Pointer Cards** (references):
- Game card → points to Faction cards
- Character card → points to Game card
- Mechanic card → points to related Mechanics

**Nested Cards** (hierarchy):
- `Game: Butterfly Galaxii/Overview`
- `Game: Butterfly Galaxii/Factions`
- `Game: Butterfly Galaxii/Timeline`

### Phase 4: Verification

#### 4.1 Completeness Check

- [ ] All critical content migrated (check against inventory)
- [ ] No important files left behind
- [ ] Each card has appropriate type
- [ ] Relationships established between related cards

#### 4.2 Quality Review

For each card:
- [ ] Content is accurate and current
- [ ] Naming follows convention: `[Type]: [Name] (+Context)`
- [ ] Markdown renders correctly in Decko
- [ ] Links to other cards work (no broken references)
- [ ] Tags are appropriate

#### 4.3 Player Validation

- [ ] Share with 2-3 players for review
- [ ] Ask: "Can you find information you need?"
- [ ] Note any missing or confusing content
- [ ] Iterate based on feedback

---

## Card Naming Conventions

### Standard Format

```
[Type]: [Name] (+Context)
```

**Examples**:
- `Game: Butterfly Galaxii`
- `Faction: Korvaxian Empire +Butterfly Galaxii`
- `Character: Alice +Butterfly Galaxii`
- `Mechanic: Asteroid Mining +Butterfly Galaxii`
- `Narrative: The Great Collapse +Butterfly Galaxii`

### Why `+Context`?

When card names appear in search results or lists, context clarifies which game/project they belong to:
- `Character: Alice +Butterfly Galaxii` (sci-fi game)
- `Character: Alice +Wonderland Game` (fantasy game)

Without context, "Character: Alice" is ambiguous.

### Nested Cards

For sub-topics:

```
Game: Butterfly Galaxii/Overview
Game: Butterfly Galaxii/Factions
Game: Butterfly Galaxii/Species
Game: Butterfly Galaxii/Timeline
```

Decko treats `/` as nesting operator.

---

## Content Mapping

### MkDocs Directory → Decko Card Type

| MkDocs Path | Decko Card Type | Example |
|-------------|-----------------|---------|
| `docs/games/*.md` | Game | `Game: Butterfly Galaxii` |
| `docs/factions/*.md` | Faction | `Faction: Korvaxian Empire` |
| `docs/species/*.md` | Species | `Species: Korvax Synthetics` |
| `docs/characters/*.md` | Character | `Character: Alice` |
| `docs/mechanics/*.md` | Mechanic | `Mechanic: Crafting System` |
| `docs/narrative/*.md` | Narrative | `Narrative: Act 1 - Discovery` |
| `docs/locations/*.md` | Location | `Location: Korvax Homeworld` |
| `docs/items/*.md` | Item | `Item: Mining Laser` |
| `docs/tech/*.md` | Technical | `Technical: API Specification` |
| `docs/notes/*.md` | Reference | `Reference: Design Philosophy` |

### Special Cases

**Multi-topic Files**:
- If MkDocs file covers multiple topics, split into multiple cards
- Example: `factions.md` with 5 factions → 5 separate Faction cards

**Index/Overview Files**:
- `index.md` or `overview.md` → Becomes parent card with nested children
- Content describes overall structure, children are details

**Changelog/Meta Files**:
- `changelog.md`, `todo.md` → Consider if worth migrating (probably not)
- If needed, use "Reference" card type

---

## Migration Checklist

### Pre-Migration
- [ ] Inventory all 5 MkDocs repos (create spreadsheet)
- [ ] Identify canonical sources for duplicated content
- [ ] Create all Decko card types
- [ ] Set up Decko production instance (Phase 1, Week 1)

### During Migration (Per Repo)
- [ ] **Repo 1** (main):
  - [ ] Migrate games content
  - [ ] Migrate factions content
  - [ ] Migrate species content
  - [ ] Migrate characters content
  - [ ] Migrate mechanics content
  - [ ] Migrate narrative content
  - [ ] Migrate other content
- [ ] **Repo 2-5**: Migrate unique content only (skip duplicates)

### Post-Migration
- [ ] Consolidate duplicate cards
- [ ] Establish all card relationships (pointers, nesting)
- [ ] Remove `needs-review` tags after verification
- [ ] Archive MkDocs repos (keep for reference, not active development)
- [ ] Update all references (links, documentation) to point to Decko

---

## Tracking Progress

### Migration Spreadsheet Template

Create a Google Sheet or Excel file:

**Columns**:
1. **Repo** (1-5)
2. **File Path** (relative to docs/)
3. **Title** (extracted from content)
4. **Proposed Card Name** (following naming convention)
5. **Card Type** (Game, Faction, etc.)
6. **Status** (Not Started | In Progress | Migrated | Skipped)
7. **Decko Card URL** (link to created card)
8. **Notes** (duplicates, issues, etc.)

**Example Rows**:

| Repo | File Path | Title | Proposed Card Name | Card Type | Status | Decko URL | Notes |
|------|-----------|-------|-------------------|-----------|--------|-----------|-------|
| 1 | games/butterfly-galaxii.md | Butterfly Galaxii | Game: Butterfly Galaxii | Game | Migrated | https://... | Split into multiple cards |
| 1 | factions/korvax.md | Korvax Empire | Faction: Korvaxian Empire +BG | Faction | Migrated | https://... | Canonical version |
| 2 | factions/korvax.md | Korvax Empire | - | - | Skipped | - | Duplicate, outdated |
| 3 | species/korvax-synthetics.md | Korvax Synthetics | Species: Korvax Synthetics +BG | Species | In Progress | - | Need to consolidate with repo 1 |

### Daily Progress Tracking

During migration week, track daily:

**Day 1**:
- [ ] Repos inventoried: 1/5
- [ ] Cards created: 15
- [ ] Issues encountered: [list]

**Day 2**:
- [ ] Repos inventoried: 3/5
- [ ] Cards created: 28 (total: 43)
- [ ] Issues encountered: [list]

*(Continue through Week 2)*

---

## Common Issues & Solutions

### Issue 1: Frontmatter Not Supported

**Problem**: MkDocs frontmatter (YAML) doesn't render in Decko

**Solution**:
- Remove frontmatter before pasting into Decko
- Extract metadata (tags, dates) and add as Decko card fields
- Script: `content.gsub(/^---\n.*?\n---\n/m, '')`

### Issue 2: Internal Links Broken

**Problem**: MkDocs `[link](../other-file.md)` doesn't work in Decko

**Solution**:
- Replace with Decko card links: `[[Card Name]]`
- Or use full URL: `[link](https://wiki.example.com/cards/card-name)`
- Search and replace: `s/\.\.\//\[\[/g` (approximate)

### Issue 3: Images Not Importing

**Problem**: Images in `docs/images/` not accessible in Decko

**Solution**:
- Upload images to Decko's file storage
- Update image references: `![alt](image.png)` → `![alt](https://wiki.../files/image.png)`
- Or use external image hosting (Imgur, S3, etc.)

### Issue 4: Code Blocks Rendering Poorly

**Problem**: MkDocs code blocks don't render well in Decko

**Solution**:
- Ensure markdown code fence syntax: ` ```language `
- Check Decko's markdown processor (may need card-mod-markdown)
- Test rendering, adjust if needed

### Issue 5: Duplicate Content Across Repos

**Problem**: Same content in multiple repos, which to use?

**Solution**:
1. Compare versions (use `diff` tool)
2. Identify most recent or authoritative
3. Consolidate: take best parts from each
4. Create single Decko card
5. Skip duplicates in tracking spreadsheet

### Issue 6: Unclear Card Type

**Problem**: Content doesn't fit neatly into existing types

**Solution**:
- Create new card type if needed (e.g., "Weapon", "Vehicle")
- Or use closest existing type (e.g., "Item" for weapons)
- Use "Reference" for meta/documentation content
- Tag with `unclear-type` for later review

---

## Automation Opportunities

### Semi-Automated Workflow

1. **Script extracts files and metadata** → Outputs CSV
2. **Human reviews CSV** → Assigns card types, marks duplicates
3. **Script creates Decko cards** → Based on reviewed CSV
4. **Human verifies and edits** → Via Decko web UI

**Benefit**: Faster than fully manual, more accurate than fully automated

### Extraction Script

```ruby
# scripts/extract_mkdocs_inventory.rb
require 'csv'

inventory = []

REPOS.each_with_index do |repo_path, repo_num|
  Dir.glob("#{repo_path}/docs/**/*.md").each do |file_path|
    content = File.read(file_path)
    title = extract_title(content)
    suggested_type = infer_type(file_path, content)

    inventory << {
      repo: repo_num + 1,
      file_path: file_path.gsub(repo_path, ''),
      title: title,
      suggested_card_name: "#{suggested_type}: #{title}",
      card_type: suggested_type,
      status: 'Not Started',
      notes: ''
    }
  end
end

CSV.open('mkdocs_inventory.csv', 'w') do |csv|
  csv << inventory.first.keys  # Headers
  inventory.each { |row| csv << row.values }
end

puts "Inventory exported to mkdocs_inventory.csv"
```

**Usage**:
1. Run script: `bundle exec ruby scripts/extract_mkdocs_inventory.rb`
2. Open `mkdocs_inventory.csv` in Excel/Google Sheets
3. Human reviews: correct card types, mark duplicates, add notes
4. Import reviewed CSV with creation script

### Creation Script

```ruby
# scripts/create_cards_from_csv.rb
require 'csv'

CSV.foreach('mkdocs_inventory_reviewed.csv', headers: true) do |row|
  next if row['status'] == 'Skipped'
  next if Card.exists?(name: row['suggested_card_name'])

  file_path = "#{REPOS[row['repo'].to_i - 1]}#{row['file_path']}"
  content = File.read(file_path)

  Card.create!(
    name: row['suggested_card_name'],
    type: row['card_type'],
    content: clean_content(content),
    tags: ["imported", "repo-#{row['repo']}", "needs-review"]
  )

  puts "✓ Created: #{row['suggested_card_name']}"
end
```

**Usage**:
1. Review and edit CSV (add `_reviewed` suffix)
2. Run script: `bundle exec rails runner scripts/create_cards_from_csv.rb`
3. Verify cards in Decko web UI
4. Manually edit/improve as needed

---

## Timeline Estimate

### Breakdown

| Task | Time Estimate | Notes |
|------|---------------|-------|
| **Inventory repos** | 2-4 hours | Walk through all files, create spreadsheet |
| **Identify canonical sources** | 1-2 hours | Compare duplicates, mark to skip |
| **Create card types** | 15 minutes | One-time setup in Rails console |
| **Migrate Repo 1 (main)** | 4-8 hours | Largest repo, most content |
| **Migrate Repos 2-5 (unique only)** | 2-4 hours | Skip duplicates, only unique content |
| **Consolidate duplicates** | 1-2 hours | Merge best content from multiple sources |
| **Establish relationships** | 2-4 hours | Set up pointers, nesting |
| **Verification & cleanup** | 2-3 hours | Review all cards, fix issues |
| **Player validation** | 1-2 hours | Share with players, gather feedback |

**Total**: ~15-30 hours (depends on content volume and complexity)

**Recommended Schedule**:
- **Day 1-2**: Inventory and planning (6 hours)
- **Day 3-5**: Migration (12 hours)
- **Day 6**: Consolidation and relationships (6 hours)
- **Day 7**: Verification and launch (4 hours)

---

## Post-Migration

### Archive MkDocs Repositories

Once migration complete and verified:

1. **Tag final state** in Git:
   ```bash
   cd magi-knowledge-repo
   git tag -a "pre-decko-migration" -m "Last version before migrating to Decko"
   git push --tags
   ```

2. **Add deprecation notice** to README:
   ```markdown
   # ARCHIVED - Content Migrated to Decko

   This repository has been archived. All content has been migrated to the Decko wiki:

   **New Wiki**: https://wiki.example.com

   This repository is kept for historical reference only.
   ```

3. **Make read-only** (GitLab/GitHub settings)

4. **Keep for reference**: Don't delete, may need to reference during Decko iteration

### Update All References

Search for and update links to MkDocs:
- [ ] Other project documentation (TheSmithy, spyder, etc.)
- [ ] Discord/Slack pinned messages
- [ ] Email signatures
- [ ] Social media profiles
- [ ] Any external websites linking to MkDocs

---

## Success Criteria

Migration is considered successful when:

- [ ] All critical content from MkDocs is in Decko
- [ ] No important information lost
- [ ] Cards properly typed and named
- [ ] Relationships established between related cards
- [ ] Players can find information they need
- [ ] No broken links or missing images
- [ ] MkDocs repos archived with deprecation notice
- [ ] All external references updated to point to Decko

---

## Appendix: Example Migrations

### Example 1: Faction Card

**MkDocs Source** (`docs/factions/korvax.md`):
```markdown
---
title: Korvaxian Empire
tags: [faction, butterfly-galaxii, synthetic]
---

# Korvaxian Empire

The Korvaxian Empire is a technocratic faction of synthetic beings...

## History
Founded in the year 2347...

## Notable Members
- Emperor Korvax Prime
- Admiral Synth-7

## Relations
- Allies: None
- Enemies: Organic Alliance
```

**Decko Card**:
- **Name**: `Faction: Korvaxian Empire +Butterfly Galaxii`
- **Type**: `Faction`
- **Content**:
  ```markdown
  The Korvaxian Empire is a technocratic faction of synthetic beings...

  ## History
  Founded in the year 2347...

  ## Notable Members
  - [[Character: Emperor Korvax Prime +Butterfly Galaxii]]
  - [[Character: Admiral Synth-7 +Butterfly Galaxii]]

  ## Relations
  - Allies: None
  - Enemies: [[Faction: Organic Alliance +Butterfly Galaxii]]
  ```
- **Pointers**:
  - Game: `Game: Butterfly Galaxii`
  - Characters: `Character: Emperor Korvax Prime`, `Character: Admiral Synth-7`
- **Tags**: `imported`, `repo-1`, `butterfly-galaxii`

**Notes**:
- Removed YAML frontmatter
- Converted character names to card links: `[[Character: ...]]`
- Added `+Butterfly Galaxii` context to name
- Created separate Character cards for notable members
- Set up pointer relationships to game and characters

### Example 2: Game Card (Split)

**MkDocs Source** (`docs/games/butterfly-galaxii.md`) - 1000 lines covering everything

**Decko Cards** (split into multiple):

1. **`Game: Butterfly Galaxii`** (overview, 200 lines)
   ```markdown
   # Butterfly Galaxii

   A sci-fi RPG set in a galaxy of sentient butterflies and synthetic beings...

   ## Overview
   [Brief description]

   ## Related Content
   - [[Game: Butterfly Galaxii/Factions]]
   - [[Game: Butterfly Galaxii/Species]]
   - [[Game: Butterfly Galaxii/Timeline]]
   ```

2. **`Game: Butterfly Galaxii/Factions`** (nested card)
   - Lists all factions with links to detailed Faction cards

3. **`Game: Butterfly Galaxii/Species`** (nested card)
   - Lists all species with links to detailed Species cards

4. **`Game: Butterfly Galaxii/Timeline`** (nested card)
   - Historical timeline

**Benefit**: Modular, easier to navigate than single 1000-line card

---

**Last Updated**: 2025-10-16
**Next Review**: After migration complete (end of Week 2)
**Maintained By**: Lake + Claude Code
