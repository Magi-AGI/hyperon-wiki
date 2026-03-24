# Decko Content Upload Guide for AI Agents

**Date**: 2025-11-28
**Context**: Documentation of the process for uploading structured game content (cultures, factions, species, etc.) from markdown files to the Decko wiki.

## Overview

This guide documents the complete workflow for taking structured content from the magi-knowledge-repo-3 `deko-card-drafts/` folder and uploading it to the Decko wiki at wiki.magi-agi.org, maintaining proper card hierarchy, formatting, and nested inclusions.

## Prerequisites

- SSH access to EC2 instance: `ssh -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17`
- Rails console access via: `script/card runner -`
- Source files in `magi-knowledge-repo-3/deko-card-drafts/`
- Understanding of Decko card naming conventions

## The Pattern: Hierarchical Content with GM/AI Split

Content follows a four-tier structure:

1. **Player Card** - Core player-facing content (visible to all)
2. **AI Card** - Extended player-visible lore (still in-world)
3. **GM Card** - GM-only secrets, plot hooks, campaign guidance
4. **GM+AI Card** - AI generation guidelines for GM content

### File Naming Convention

Files in `deko-card-drafts/` follow this pattern:
```
Major-Culture-{CultureName}_Player.md
Major-Culture-{CultureName}_AI.md
Major-Culture-{CultureName}_GM.md
Major-Culture-{CultureName}_GM-AI.md
```

Similar patterns exist for factions, species, etc.

### Decko Card Naming Convention

Cards in Decko use `+` as hierarchy separator:
```
Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+{CultureName}
Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+{CultureName}+AI
Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+{CultureName}+GM
Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+{CultureName}+GM+AI
```

**Important**: Use underscores in section names (e.g., `Major_Cultures`), not hyphens.

## Step-by-Step Process

### Phase 1: Create Custom Card Type (if needed)

**When to do this**: If you're uploading a new content category (factions, species, etc.) that doesn't have a card type yet.

**Naming Convention**: Prefix with `BG_` for Butterfly Galaxii content:
- `BG_Culture` - Major cultures
- `BG_Faction` - Factions
- `BG_Species` - Species
- etc.

**How to create**:

```ruby
# Via SSH to EC2
Card::Auth.as_bot do
  # Create the cardtype
  cardtype = Card.fetch("BG_Faction", new: {
    type_id: Card.fetch("Cardtype").id,
    content: "" # Cardtype cards have no content
  })

  if cardtype.save
    puts "✓ Created cardtype: BG_Faction (ID: #{cardtype.id})"
  else
    puts "✗ Failed: #{cardtype.errors.full_messages.join(', ')}"
  end
end
```

### Phase 2: Create Default Template for Card Type

The template defines what new cards of this type will contain by default.

```ruby
Card::Auth.as_bot do
  richtext_type = Card.fetch("RichText")

  template = Card.fetch("BG_Faction+*type+*default", new: {
    type_id: richtext_type.id,
    content: <<~'HTML'
      <h1>[Faction Name]</h1>

      <p><strong>Type</strong>: [Faction type]<br>
      <strong>Allegiance</strong>: [Primary allegiance]</p>

      <h2>[Tagline/Core Concept]</h2>

      <p>[Player-facing faction description]</p>

      <h2>Key Characteristics</h2>

      <p>[2-3 key traits]</p>

      <hr>

      <p>{{+AI|closed}}</p>

      <hr>

      <p>{{+GM|closed}}</p>
    HTML
  })

  if template.save
    puts "✓ Created template (ID: #{template.id})"
  else
    puts "✗ Failed: #{template.errors.full_messages.join(', ')}"
  end
end
```

**Note**: The template includes `{{+AI|closed}}` and `{{+GM|closed}}` inclusions at the end.

### Phase 3: Create Section Structure

Create the organizational cards that will contain your content cards.

**Example for Major Cultures**:

```ruby
Card::Auth.as_bot do
  richtext_type = Card.fetch("RichText")

  # 1. Create section organizer
  cultures = Card.fetch("Games+Butterfly Galaxii+Player+Cultures", new: {
    type_id: richtext_type.id,
    content: "{{+Major_Cultures|content}}"
  })
  cultures.save

  # 2. Create Major_Cultures organizer
  major_cultures = Card.fetch("Games+Butterfly Galaxii+Player+Cultures+Major_Cultures", new: {
    type_id: richtext_type.id,
    content: "{{+intro|content}}\n\n{{+table-of-contents|content}}"
  })
  major_cultures.save

  # 3. Create intro
  intro = Card.fetch("Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+intro", new: {
    type_id: richtext_type.id,
    content: <<~HTML
      <p>Major cultures are the dominant linguistic and philosophical traditions...</p>
    HTML
  })
  intro.save

  # 4. Create table of contents
  toc = Card.fetch("Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+table-of-contents", new: {
    type_id: richtext_type.id,
    content: <<~HTML
      <ol>
        <li>[[Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Araithi|Araithi]]</li>
        <li>[[Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Daresh-Tral|Daresh-Tral]]</li>
      </ol>
    HTML
  })
  toc.save

  puts "✓ Structure cards created"
end
```

**Important Notes**:
- Table of contents cards are **RichText** with numbered `<ol>` lists, NOT Pointer type
- Use wiki-style links: `[[Full+Card+Name|Display Text]]`
- Organizer cards use `{{+ChildCard|content}}` to include child cards

### Phase 4: Upload Content Files to Server

Transfer markdown files from local repo to EC2 `/tmp/` directory:

```bash
# Upload all culture files for one culture
ssh -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17 "cat > /tmp/Araithi_player.md" < "E:/GitLab/the-smithy1/magi/magi-knowledge-repo-3/deko-card-drafts/Major-Culture-Araithi_Player.md"

# Or batch upload with a loop:
for culture in "Araithi" "Daresh-Tral" "Exakom"; do
  ssh -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17 "cat > /tmp/${culture}_player.md" < "path/to/Major-Culture-${culture}_Player.md"
  ssh -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17 "cat > /tmp/${culture}_ai.md" < "path/to/Major-Culture-${culture}_AI.md"
  ssh -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17 "cat > /tmp/${culture}_gm.md" < "path/to/Major-Culture-${culture}_GM.md"
  ssh -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17 "cat > /tmp/${culture}_gm_ai.md" < "path/to/Major-Culture-${culture}_GM-AI.md"
done
```

### Phase 5: Create Cards from Files

**Important**: RichText cards require HTML, not Markdown. Markdown content must be converted.

```ruby
Card::Auth.as_bot do
  bg_culture_type = Card.fetch("BG_Culture")
  richtext_type = Card.fetch("RichText")

  # Read files
  player_content = File.read("/tmp/Araithi_player.md")
  ai_content = File.read("/tmp/Araithi_ai.md")
  gm_content = File.read("/tmp/Araithi_gm.md")
  gm_ai_content = File.read("/tmp/Araithi_gm_ai.md")

  # Create Player card (custom type)
  player = Card.fetch("Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Araithi", new: {
    type_id: bg_culture_type.id,
    content: player_content
  })
  player.save

  # Create AI card (RichText)
  ai = Card.fetch("Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Araithi+AI", new: {
    type_id: richtext_type.id,
    content: ai_content
  })
  ai.save

  # Create GM card (RichText)
  gm = Card.fetch("Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Araithi+GM", new: {
    type_id: richtext_type.id,
    content: gm_content
  })
  gm.save

  # Create GM+AI card (RichText)
  gm_ai = Card.fetch("Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Araithi+GM+AI", new: {
    type_id: richtext_type.id,
    content: gm_ai_content
  })
  gm_ai.save

  puts "✓ Created all 4 cards for Araithi"
end
```

### Phase 6: Convert Markdown to HTML

**Critical Step**: RichText cards display Markdown as plain text without conversion. You must convert to HTML.

```ruby
def md_to_html(content)
  html = content.dup

  # Headers
  html.gsub!(/^### (.+)$/, '<h3>\1</h3>')
  html.gsub!(/^## (.+)$/, '<h2>\1</h2>')
  html.gsub!(/^# (.+)$/, '<h1>\1</h1>')

  # Bold and italic
  html.gsub!(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
  html.gsub!(/\*(.+?)\*/, '<em>\1</em>')

  # Unordered list items
  html.gsub!(/^- (.+)$/, '<li>\1</li>')
  html.gsub!(/(<li>.*?<\/li>\n?)+/m) { |match| "<ul>\n#{match}</ul>\n" }

  # Blockquotes
  html.gsub!(/^> (.+)$/, '<blockquote>\1</blockquote>')

  # Horizontal rules
  html.gsub!(/^---+$/, '<hr>')

  # Paragraphs - wrap non-tagged lines
  lines = html.split("\n")
  result = []
  current_p = []

  lines.each do |line|
    if line =~ /^<(h\d|ul|li|hr|blockquote)/ || line.strip.empty?
      if current_p.any?
        result << "<p>#{current_p.join(' ')}</p>"
        current_p = []
      end
      result << line unless line.strip.empty?
    else
      current_p << line.strip
    end
  end

  if current_p.any?
    result << "<p>#{current_p.join(' ')}</p>"
  end

  result.join("\n\n")
end

Card::Auth.as_bot do
  # Convert specific cards by ID
  card_ids = [2526, 2528, 2530, 2531] # Player, AI, GM, GM+AI

  card_ids.each do |id|
    card = Card.find_by_id(id)
    next unless card

    # Skip if already HTML
    next if card.content.include?("<h1>") || card.content.include?("<p>")

    card.content = md_to_html(card.content)
    card.save
    puts "✓ Converted card #{id} to HTML"
  end
end
```

### Phase 7: Add Child Card Inclusions

**Final Step**: Add `{{+AI|closed}}` and `{{+GM|closed}}` inclusions at the end of appropriate cards.

```ruby
Card::Auth.as_bot do
  # Update Player card
  player = Card.find_by_id(2526)
  content = player.content.gsub(/<p>\{\{[+]AI.*?\}\}<\/p>/, '').gsub(/<p>\{\{[+]GM.*?\}\}<\/p>/, '').strip
  player.content = content + "\n<p>{{+AI|closed}}</p>\n<p>{{+GM|closed}}</p>"
  player.save

  # Update GM card
  gm = Card.find_by_id(2530)
  content = gm.content.gsub(/<p>\{\{[+]AI.*?\}\}<\/p>/, '').strip
  gm.content = content + "\n<p>{{+AI|closed}}</p>"
  gm.save

  puts "✓ Added child inclusions"
end
```

**Pattern**:
- **Player cards** end with: `{{+AI|closed}}` and `{{+GM|closed}}`
- **GM cards** end with: `{{+AI|closed}}` (for GM+AI guidelines)
- **AI and GM+AI cards** have no inclusions (they're leaf nodes)

## Complete Card Hierarchy

```
Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Araithi (BG_Culture)
├── Content: Player-facing core info
├── {{+AI|closed}} → includes AI card below
└── {{+GM|closed}} → includes GM card below

Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Araithi+AI (RichText)
└── Content: Extended player-visible lore

Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Araithi+GM (RichText)
├── Content: GM-only secrets and campaign hooks
└── {{+AI|closed}} → includes GM+AI card below

Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Araithi+GM+AI (RichText)
└── Content: AI generation guidelines for GM content
```

## Card Types Summary

| Card | Type | Why |
|------|------|-----|
| Player cards (e.g., `+Araithi`) | `BG_Culture` | Uses custom template, inherits default structure |
| AI/GM/GM+AI cards | `RichText` | Simple formatted text, supports HTML |
| Organizer cards | `RichText` | Needs to include child cards with `{{+Child\|content}}` |
| Intro cards | `RichText` | Simple formatted text |
| Table of contents | `RichText` | Contains numbered HTML lists, NOT Pointer type |

## Common Pitfalls

### 1. Using Markdown in RichText Cards

**Problem**: Content shows as plain text with visible `#` and `**` characters.

**Solution**: Always convert Markdown to HTML before saving RichText cards.

### 2. Newlines Disappearing

**Problem**: Content appears as one long block.

**Solution**: Use proper HTML tags (`<p>`, `<h2>`, etc.) with newlines between them.

### 3. Card.find_by_name Not Finding Cards

**Problem**: `Card.find_by_name("Some+Card+Name")` returns `nil` even though card exists.

**Solution**: Use `Card.fetch("Some+Card+Name")` instead, especially for cards with special characters.

### 4. Table of Contents as Pointer Type

**Problem**: TOC doesn't display properly.

**Solution**: TOC cards should be RichText with explicit `<ol><li>` HTML lists, not Pointer type.

### 5. Missing Child Inclusions

**Problem**: Player card doesn't show AI/GM content.

**Solution**: Ensure Player cards end with `{{+AI|closed}}` and `{{+GM|closed}}`, GM cards end with `{{+AI|closed}}`.

### 6. Spaces vs Underscores in Section Names

**Problem**: Card names inconsistent, links break.

**Solution**: Use underscores for section names (e.g., `Major_Cultures`), but spaces for game names (e.g., `Butterfly Galaxii`).

## Verification Checklist

After uploading content, verify:

- [ ] Custom cardtype exists (e.g., `BG_Faction`)
- [ ] Template exists with child inclusions (`BG_Faction+*type+*default`)
- [ ] Section structure created (organizer, intro, TOC)
- [ ] All content files uploaded to `/tmp/`
- [ ] All cards created with correct types
- [ ] All RichText cards converted to HTML
- [ ] Player cards end with `{{+AI|closed}}` and `{{+GM|closed}}`
- [ ] GM cards end with `{{+AI|closed}}`
- [ ] Content displays properly on wiki (check a sample card)

## Query Examples

### Check Cards by ID Range

```ruby
cards = Card.where("id >= ? AND id <= ?", 2519, 2576).order(:id)
cards.each { |c| puts "#{c.id}: #{c.name} (#{c.type_name})" }
```

### Find All Cards of a Type

```ruby
bg_culture_type = Card.fetch("BG_Culture")
cultures = Card.where(type_id: bg_culture_type.id).order(:name)
cultures.each { |c| puts c.name }
```

### Search by Name Pattern

```ruby
cards = Card.where("name LIKE ?", "%Major_Cultures%").order(:name)
cards.each { |c| puts "#{c.name} (#{c.type_name}, ID: #{c.id})" }
```

## Batch Upload Script Template

For uploading multiple items (e.g., 10 cultures):

```ruby
Card::Auth.as_bot do
  cultures = ["Araithi", "Daresh-Tral", "Exakom"] # etc.
  bg_culture_type = Card.fetch("BG_Culture")
  richtext_type = Card.fetch("RichText")
  base_path = "Games+Butterfly Galaxii+Player+Cultures+Major_Cultures"

  cultures.each do |culture|
    puts "\n=== Processing #{culture} ==="

    # Read files
    player_content = File.read("/tmp/#{culture}_player.md")
    ai_content = File.read("/tmp/#{culture}_ai.md")
    gm_content = File.read("/tmp/#{culture}_gm.md")
    gm_ai_content = File.read("/tmp/#{culture}_gm_ai.md")

    # Create all 4 cards
    player = Card.fetch("#{base_path}+#{culture}", new: {
      type_id: bg_culture_type.id,
      content: player_content
    })
    player.save

    ai = Card.fetch("#{base_path}+#{culture}+AI", new: {
      type_id: richtext_type.id,
      content: ai_content
    })
    ai.save

    gm = Card.fetch("#{base_path}+#{culture}+GM", new: {
      type_id: richtext_type.id,
      content: gm_content
    })
    gm.save

    gm_ai = Card.fetch("#{base_path}+#{culture}+GM+AI", new: {
      type_id: richtext_type.id,
      content: gm_ai_content
    })
    gm_ai.save

    puts "  ✓ Created 4/4 cards for #{culture}"
  end
end
```

## Related Documentation

- Decko section pattern: See `docs/DECKO-SECTION-PATTERN.md`
- Card type creation: See Phase 1 of this guide
- HTML conversion: See Phase 6 of this guide
- Content structure: See `/magi-knowledge-repo-3/deko-card-drafts/` for examples

### Phase 8: Restructuring Existing Content (Player vs AI Split)

**Date Added**: 2025-11-28
**Context**: After initial upload of faction intro.md files, restructure to separate essential player info from detailed worldbuilding.

#### When to Use This Process

Use this when you have existing faction/culture/species cards that are too long and need to be split into:
- **Player Card** (4-5K chars) - Brief, scannable essentials for character creation
- **+AI Card** (25-30K chars) - Extended lore, worldbuilding depth, expanded descriptions

#### Design Principles for Player Cards

**Keep it Brief and Scannable**:
- Aim for complete sentences, NOT bullet points
- But commit only to the most important/compelling sentences
- Prioritize what players need for character creation over worldbuilding depth
- Everything else goes in +AI card

**Voice and Tone**:
- Use third person, NOT second person
- Example: "Idealists join because..." NOT "You join if you believe..."
- Be concise but NOT incomplete

#### Example: Coalition of Planets Restructure

**Before**: Single 16K character card with all content mixed together

**After**:
- Player card: 4,055 characters (opening, brief appeal, species list, culture list, condensed relationships)
- +AI card: 27,550 characters (expanded everything + worldbuilding sections)

**Key Lessons Learned**:
1. **Brevity over bullets** - Complete sentences work better than bullet points, just use fewer words
2. **Third person feels more encyclopedic** - Matches wiki tone better than second person
3. **Links create interconnection** - Species and culture sections become hubs connecting related content
4. **Template helps consistency** - Following same structure for all factions keeps them comparable
5. **~4K for player, ~25-30K for +AI** - This ratio works well for factions
6. **Upload files first** - Use SCP to get markdown files to server `/tmp/`, then process them
7. **Verify against source material** - Always check original intro.md files before making assumptions about species, cultures, or relationships
8. **Cross-reference with culture cards** - When describing cultures in faction cards, ensure consistency with existing culture cards. Keep substantial content in culture cards, use light references in faction cards
9. **Check naming conventions** - Ensure location names, subfaction names, and terminology match between source files and what's being uploaded

See Phase 4-7 above for file upload and card creation procedures.

### Phase 9: Subcultures and Subfactions Pattern

**Date Added**: 2025-11-30
**Context**: Organizing hierarchical relationships within cultures and factions using intermediate container cards.

#### Pattern Overview

When cultures have subcultures (variants, dialects) or factions have subfactions (sub-organizations), use an **intermediate container card** to separate them from metadata children (+AI, +GM, +table-of-contents).

**Structure**:
```
Major_Culture+CultureName
├── +AI (metadata)
├── +GM (metadata)
├── +table-of-contents (metadata)
└── +Subcultures (container)
    ├── +Subcultures+SubcultureName1 (actual subculture)
    ├── +Subcultures+SubcultureName2 (actual subculture)
    └── +Subcultures+table-of-contents (lists subcultures)
```

**For Factions**:
```
Major_Factions+FactionName
├── +AI (metadata)
├── +GM (metadata)
├── +table-of-contents (metadata)
└── +Subfactions (container)
    ├── +Subfactions+SubfactionName1 (actual subfaction)
    ├── +Subfactions+SubfactionName2 (actual subfaction)
    └── +Subfactions+table-of-contents (lists subfactions)
```

#### Why Use This Pattern

1. **Semantic Clarity** - Clearly separates organizational hierarchy from metadata
2. **Namespace Organization** - Prevents clutter in direct children
3. **Consistent Structure** - Same pattern works for cultures, factions, species, etc.
4. **Scalability** - Easy to add many subcultures/subfactions without confusion

#### Implementation Example: Netsugo Subcultures

```ruby
Card::Auth.as_bot do
  richtext_type = Card.fetch("RichText")
  bg_culture_type = Card.fetch("BG_Culture")

  # 1. Create +Subcultures container
  subcultures_parent = Card.fetch(
    "Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Netsugo+Subcultures",
    new: { type_id: richtext_type.id }
  )
  subcultures_parent.content = "<p>Subcultures and regional variants of Netsugo.</p>"
  subcultures_parent.save

  # 2. Create subculture under +Subcultures
  shikkei = Card.fetch(
    "Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Netsugo+Subcultures+Shikkei",
    new: { type_id: bg_culture_type.id }
  )
  shikkei.content = File.read("/tmp/shikkei_culture.html")
  shikkei.save

  # 3. Create +Subcultures table-of-contents
  subcultures_toc = Card.fetch(
    "Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Netsugo+Subcultures+table-of-contents",
    new: { type_id: richtext_type.id }
  )
  subcultures_toc.content = '<ol><li>[[Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Netsugo+Subcultures+Shikkei|Shikkei]]</li></ol>'
  subcultures_toc.save

  # 4. Update parent culture's table-of-contents to reference +Subcultures
  netsugo_toc = Card.fetch(
    "Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Netsugo+table-of-contents"
  )
  netsugo_toc.content = '<ol><li>[[Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Netsugo+Subcultures|Subcultures]]<br>{{Games+Butterfly Galaxii+Player+Cultures+Major_Cultures+Netsugo+Subcultures+table-of-contents|content}}</li></ol>'
  netsugo_toc.save

  puts "✓ Created Netsugo subculture structure"
end
```

#### Table of Contents Nesting Pattern

**Critical**: The parent culture/faction TOC must list the container AND include its nested TOC:

```html
<ol>
  <li>[[Path+To+Subcultures|Subcultures]]<br>
  {{Path+To+Subcultures+table-of-contents|content}}</li>
</ol>
```

**Breakdown**:
- `[[Path+To+Subcultures|Subcultures]]` - Link to the container card
- `<br>` - Line break between link and inclusion
- `{{Path+To+Subcultures+table-of-contents|content}}` - Nested inclusion of subcultures list

**Wrong Patterns to Avoid**:
- `{{+Subcultures+table-of-contents|content}}` ❌ (relative path works but less clear)
- Listing subcultures directly without the container ❌
- Using only the container link without the nested TOC ❌

#### Complete Example: Coalition of Planets Subfactions

```ruby
Card::Auth.as_bot do
  richtext_type = Card.fetch("RichText")

  # Parent faction TOC
  coalition_toc = Card.fetch(
    "Games+Butterfly Galaxii+Player+Factions+Major_Factions+Coalition of Planets+table-of-contents"
  )
  coalition_toc.content = <<~HTML
    <ol>
      <li>[[Games+Butterfly Galaxii+Player+Factions+Major_Factions+Coalition of Planets+Subfactions|Subfactions]]<br>
      {{Games+Butterfly Galaxii+Player+Factions+Major_Factions+Coalition of Planets+Subfactions+table-of-contents|content}}</li>
    </ol>
  HTML
  coalition_toc.save

  # Subfactions TOC
  subfactions_toc = Card.fetch(
    "Games+Butterfly Galaxii+Player+Factions+Major_Factions+Coalition of Planets+Subfactions+table-of-contents"
  )
  subfactions_toc.content = <<~HTML
    <ol>
      <li>[[Games+Butterfly Galaxii+Player+Factions+Major_Factions+Coalition of Planets+Subfactions+Starwatch Peacekeepers|Starwatch Peacekeepers]]</li>
      <li>[[Games+Butterfly Galaxii+Player+Factions+Major_Factions+Coalition of Planets+Subfactions+Diplomatic Corps|Diplomatic Corps]]</li>
    </ol>
  HTML
  subfactions_toc.save

  puts "✓ Coalition subfactions structure complete"
end
```

#### Key Lessons

1. **Always use intermediate container** - Don't make subcultures/subfactions direct children
2. **Container gets own TOC** - The +Subcultures/+Subfactions card has its own table-of-contents child
3. **Parent TOC nests container TOC** - Use `{{Full+Path+table-of-contents|content}}` inclusion
4. **Consistent naming** - Use `+Subcultures` for cultures, `+Subfactions` for factions
5. **Full paths in inclusions** - Avoid relative paths for clarity and reliability

---

### Phase 10: Major Faction Card Structure

**Date Added**: 2025-11-30
**Context**: Standardizing faction player cards to match established pattern with brief main cards and detailed AI cards.

#### The Problem

Initial faction cards (Criminal Elements) were too long - 18,626 chars vs the standard ~4,300 chars for Coalition/Syndicate. Too much detail on the player card makes it overwhelming and breaks the pattern consistency.

#### The Solution: Brief Main Card + Detailed AI Card

**Main Card Target: ~4,500 chars**

Essential sections only:
1. **H1 Title**: Faction name
2. **Brief Intro** (~600 chars): What the faction is, one compelling paragraph
3. **Faction Appeal** (~450 chars): Why join, single paragraph covering key motivations
4. **Associated Species**: 2-4 species with one-sentence descriptions each
5. **Associated Cultures**: 2-5 cultures with one-sentence descriptions each
6. **Factional Relationships**: One sentence per faction (9 other factions)

**AI Card: All Extended Content**

Detailed worldbuilding sections:
1. **Extended Introduction**: Full 3-paragraph intro if needed
2. **Expanded Faction Appeal**: Multiple compelling reasons with detail
3. **Territorial Holdings**: Geography and systems
4. **Notable Worlds & Systems**: Specific locations
5. **Slang**: Faction-specific terminology
6. **Expanded Factional Relationships**: Full paragraphs per faction
7. **Sensory Profile**: Architecture, soundscape, scents
8. **Cultural & Daily Life**: Social structure, work, species composition, technology, leisure

#### Implementation Example: Criminal Elements Restructuring

**Before (Main Card)**:
- 18,626 chars total
- Long intro (1,719 chars)
- Detailed "Why Join" (1,757 chars)
- No Associated Species section
- Species info buried in Cultural & Daily Life
- Detailed Factional Relationships (4,718 chars)

**After (Main Card - 4,807 chars)**:
```ruby
Card::Auth.as_bot do
  criminal = Card.fetch("Games+Butterfly Galaxii+Player+Factions+Major Factions+Criminal Elements")

  new_content = <<~HTML
    <h1>Criminal Elements</h1>
    <p>[[Games+Butterfly Galaxii+Player+Factions+Major_Factions|Major Faction]]</p>

    <p>[Single compelling paragraph intro - ~600 chars]</p>

    <h2>Faction Appeal</h2>
    <p>[Single paragraph covering 3-4 key reasons to join - ~450 chars]</p>

    <h2>Associated Species</h2>
    <p><strong>[[Link|Naxom]]</strong> - One sentence description.</p>
    <p><strong>[[Link|Vyvaskyn]]</strong> - One sentence description.</p>
    <p><strong>[[Link|Zynx]]</strong> - One sentence description.</p>

    <h2>Associated Cultures</h2>
    <p><strong>[[Link|Vesh-Shival]]</strong> - One sentence description.</p>
    <p><strong>[[Link|Zhenmor]]</strong> - One sentence description.</p>
    <p><strong>Criminal Elements Slang</strong> - One sentence description.</p>
    <p><strong>Note</strong>: [Brief diversity note if applicable]</p>

    <h2>Factional Relationships</h2>
    <p><strong>Seventh Syndicate</strong>: One sentence relationship summary.</p>
    <p><strong>Coalition of Planets</strong>: One sentence relationship summary.</p>
    [... 7 more factions, one sentence each]

    <hr>
    <p>{{+table-of-contents|content}}</p>
    <hr>
    <p>{{+AI|closed;title:AI}}</p>
    <p>{{+GM|closed;title:GM}}</p>
    <p>Back to [[Games+Butterfly Galaxii+Player+Factions+Major_Factions|Major Factions]]</p>
  HTML

  criminal.content = new_content
  criminal.save!
end
```

**After (AI Card - 17,326 chars)**:
```ruby
Card::Auth.as_bot do
  richtext_type = Card.fetch("RichText")

  ai_card = Card.fetch(
    "Games+Butterfly Galaxii+Player+Factions+Major Factions+Criminal Elements+AI",
    new: { type_id: richtext_type.id }
  )

  ai_content = <<~HTML
    <h1>Criminal Elements - Extended Lore</h1>

    <p>This card contains extended player-visible lore for the Criminal Elements, providing deeper immersion and worldbuilding details beyond the essential information on the main faction card.</p>

    <h2>Extended Introduction</h2>
    [Full 3-paragraph introduction with all detail]

    <h2>Expanded Faction Appeal</h2>
    [Multiple paragraphs with 4 detailed compelling reasons]

    <h2>Territorial Holdings</h2>
    [Geography across both galaxies]

    <h2>Notable Worlds & Systems</h2>
    [5+ specific locations with descriptions]

    <h2>Slang</h2>
    [Terminology table or list]

    <h2>Expanded Factional Relationships</h2>
    [Full paragraph per faction - 9 factions total]

    <h2>Sensory Profile</h2>
    [Architecture, soundscape, scents sections]

    <h2>Cultural & Daily Life</h2>
    [Social structure, work, species composition, technology, leisure]
  HTML

  ai_card.content = ai_content
  ai_card.save!
end
```

#### Key Lessons

1. **Main card is the hook** - Brief, compelling, essential info only
2. **AI card is the deep dive** - All the rich worldbuilding detail
3. **Associated Species comes before Cultures** - Matches established pattern
4. **One sentence per relationship** - Keep Factional Relationships concise on main card
5. **Move Species Composition** - Extract from Cultural & Daily Life to create Associated Species section
6. **Condense drastically** - Intro from 1,719 → 701 chars, Faction Appeal from 1,757 → 470 chars
7. **Complete sentences always** - Never use bullet points or fragments, but keep prose tight

#### Section Size Targets

**Main Card Sections:**
- Intro: ~600 chars (single compelling paragraph)
- Faction Appeal: ~450 chars (single paragraph, 3-4 key reasons)
- Associated Species: ~300-500 chars (3-4 species, one sentence each)
- Associated Cultures: ~400-600 chars (3-5 cultures, one sentence each + diversity note)
- Factional Relationships: ~1,200-1,500 chars (9 factions × ~150 chars each)

**Total Main Card: ~4,000-5,000 chars**

#### Comparison of Final Results

```
Coalition of Planets:  4,093 chars
Seventh Syndicate:     4,392 chars
Criminal Elements:     4,807 chars ✅
```

All three factions now follow identical structure and similar scope!

---

### Phase 11: Faction Associated Cultures Update Pattern

**Date Added**: 2025-12-01
**Context**: Updating existing faction cards with comprehensive Associated Cultures sections following Coalition/Empire/Syndicate pattern.

#### The Pattern: Structured Cultural Hierarchies

Each faction's Associated Cultures section should explain the faction's cultural philosophy and list cultures organized by function:

**Coalition Pattern** (Democratic Integration):
- Foundation Cultures (4): Core democratic cultures
- Bridge Cultures (5): Intentional diplomatic integration frameworks

**Empire Pattern** (Assimilationist Autocracy):
- Foundation Cultures (3): Imperial languages and noble cultures
- Competing Cultures (2): Suppressed worker resistance
- Bridge Cultures (3): Cross-factional connections

**Syndicate Pattern** (Corporate Capitalism):
- Foundation Cultures (3): Commercial language registers
- Species-Specific (1): Corporate adaptations
- Bridge Cultures (3): Profit-driven connections

#### Implementation Workflow

**Step 1: Read Existing Faction Card**

```bash
ssh -T -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17 \
  'cd /home/ubuntu/magi-archive && set -a && . .env.production && set +a && \
   export PATH=/home/ubuntu/.rbenv/shims:$PATH && script/card runner -' <<'RUBY'
card = Card.fetch("Games+Butterfly Galaxii+Player+Factions+Major Factions+Faction Name")
if card
  puts "=== Current Associated Cultures ==="
  puts card.content[/(<h2>Associated Cultures<\/h2>.*?)(<h2>)/m, 1]
else
  puts "Card not found"
end
RUBY
```

**Step 2: Analyze GM Documentation**

Check for culture details in:
- `magi-knowledge-repo-3/docs/games/butterfly-galaxii/gm/cultures/major-cultures/faction-gm.md`
- `magi-knowledge-repo-3/docs/games/butterfly-galaxii/gm/languages/`
- `magi-knowledge-repo-3/names-registry.md`

**Step 3: Create Update Script**

```ruby
#!/usr/bin/env ruby
# Update Faction Associated Cultures

Card::Auth.as_bot do
  faction = Card.fetch("Games+Butterfly Galaxii+Player+Factions+Major Factions+Faction Name")

  updated_cultures = <<~HTML
    <h2>Associated Cultures</h2>

    <p>[Opening paragraph explaining faction's cultural philosophy and approach to integration/assimilation]</p>

    <h3>[Category Name - e.g., Foundation Cultures]</h3>

    <p><strong>[[Culture Path|Culture Name]]</strong> - [One sentence description focusing on function and factional significance]</p>

    <p><strong>[[Culture Path|Culture Name 2]]</strong> - [One sentence description]</p>

    <h3>[Second Category if needed]</h3>

    <p><strong>[[Culture Path|Bridge Culture]]</strong> - [Description]</p>
  HTML

  # Replace the Associated Cultures section
  current_content = faction.content

  if current_content =~ /(<h2>Associated Cultures<\/h2>.*?)(<h2>Factional Relationships<\/h2>)/m
    before_section = $`
    after_section = $2 + $'

    new_content = before_section + updated_cultures + "\n" + after_section

    faction.content = new_content

    if faction.save
      puts "✓ Updated #{faction.name} Associated Cultures"
    else
      puts "✗ Failed: #{faction.errors.full_messages}"
    end
  else
    puts "✗ Could not find Associated Cultures section"
  end
end
```

**Step 4: Execute via SSH stdin**

```bash
ssh -T -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17 \
  'cd /home/ubuntu/magi-archive && set -a && . .env.production && set +a && \
   export PATH=/home/ubuntu/.rbenv/shims:$PATH && script/card runner -' < /e/tmp/update-faction-cultures.rb
```

**Step 5: Update Names Registry**

Add any new cultures to `magi-knowledge-repo-3/names-registry.md`:

```markdown
### [Culture Type]
- Culture Name (Translation / Meaning)
```

**Step 6: Update Culture TOC Cards**

If new bridge culture categories were created, add table-of-contents cards:

```ruby
Card::Auth.as_bot do
  toc = Card.fetch("Games+Butterfly Galaxii+Player+Cultures+Bridge_Category+table-of-contents", new: {})
  toc.content = <<~CONTENT
    Games+Butterfly Galaxii+Player+Cultures+Bridge_Category+Culture1
    Games+Butterfly Galaxii+Player+Cultures+Bridge_Category+Culture2
  CONTENT
  toc.save
end
```

#### Session Example: Three Factions Updated

**Coalition of Planets** (2025-12-01):
- Added 5 bridge cultures (Kovaraith, Exakova, Thorenkova, Kovanai-Sen, Thoraith)
- Created Tharaneth subculture (Eldarai Peace Galaxy Araithi variant)
- Updated Coalition_Bridges TOC
- Total: 9 cultures (4 foundation + 5 bridges)

**Obsidian Empire** (2025-12-01):
- Created Khar'nax minor culture (Naxom warrior culture)
- Added register breakdown for Itzalaan (4 registers)
- Added cultural competition (Haelaryn, Daresh-Tral)
- Updated Minor_Cultures TOC
- Total: 8 cultures (3 foundation + 2 suppressed + 3 bridges)

**Seventh Syndicate** (2025-12-01):
- Added 3 bridge cultures (Netkai, Tekka-Kode, Raitek)
- Expanded Netsugo register description
- Added Shikkei to names registry
- Total: 7 cultures (3 foundation + 1 species-specific + 3 bridges)

#### Key Principles

1. **Brevity with Comprehensiveness** - Match Coalition/Empire conciseness while covering all cultures
2. **Opening Philosophy** - First paragraph explains faction's cultural approach
3. **Functional Categories** - Group cultures by role (Foundation, Bridges, Species-Specific, etc.)
4. **One-Sentence Descriptions** - Focus on function and factional significance
5. **Cross-Reference Consistency** - Verify culture cards exist before linking
6. **Register Breakdowns** - Explain language stratification systems (Itzalaan, Netsugo)
7. **Bridge Culture Sharing** - Note when bridges apply to multiple factions (e.g., Netkai used by both Altered and Syndicate)
8. **TOC Updates** - Always create/update table-of-contents cards for new culture categories
9. **Names Registry** - Add all new cultures to tracking registry

#### Verification Checklist

After updating faction Associated Cultures:

- [ ] Faction card updated with new cultures section
- [ ] All culture cards referenced actually exist in Decko
- [ ] Names registry updated with any new cultures
- [ ] Culture TOC cards created/updated for new categories
- [ ] Format matches Coalition/Empire/Syndicate brevity
- [ ] Opening paragraph explains cultural philosophy
- [ ] All descriptions focus on function, not just definition
- [ ] Bridge cultures properly attributed (single faction vs shared)
- [ ] Total culture count documented in update script output

#### Common Patterns by Faction Type

**Democratic Factions** (Coalition):
- Foundation: Democratic participation cultures
- Bridges: Intentional diplomatic integration frameworks

**Autocratic Factions** (Empire):
- Foundation: Noble languages (species-restricted)
- Suppressed: Worker resistance cultures
- Bridges: Cross-factional connections

**Corporate Factions** (Syndicate):
- Foundation: Commercial language registers (class-based)
- Species-Specific: Corporate adaptations
- Bridges: Profit-driven connections

**Anarchist Factions** (Altered):
- Foundation: Spontaneous mixing pot
- Bridges: Organic street-level fusion

**Isolationist Factions** (Zenith):
- Foundation: Orthodox subfactions
- Minimal bridges (philosophical purity)

---

### Phase 12: Major Faction Organizational Restructuring

**Date Added**: 2025-12-01
**Context**: Reorganizing major faction cards to move Associated Species, Associated Cultures, and Factional Relationships sections into dedicated organizational subcards with table-of-contents structure.

#### The Problem

Initial faction cards mixed all content in a single flat structure with sections like Associated Species, Associated Cultures, and Factional Relationships embedded directly in the main card. This made cards long and less modular.

#### The Solution: Organizational Subcards with TOCs

Move each major section into dedicated organizational subcards that use intro paragraphs + TOC inclusions. This creates a cleaner hierarchy and allows expansion of each section independently.

**IMPORTANT**: Reference the actual Coalition of Planets cards in Decko as the authoritative source. The examples below are templates - always verify current implementation matches before replicating.

**Main Card Structure** (based on Coalition of Planets as of 2025-12-01):
```html
<h1>Faction Name</h1>
<p>[[_L|Major Faction]]</p>
<div style="text-align:center;">{{+image 1|view:content;type:image;size:large;margin:auto}}</div>
<p>{{+intro|view:content}}</p>
<div style="text-align:center;">{{+image 2|view:content;type:image;size:large;margin:auto}}</div>
<h2>Faction Appeal</h2>
<p>{{+appeal|view:content}}</p>
<div style="text-align:center;">{{+image 3|view:content;type:image;size:large;margin:auto}}</div>
<hr>
<h4>[[+Subfactions|Subfactions]]</h4>
<p>{{+Subfactions+intro|view:content}}</p>
<p>{{+Subfactions+table-of-contents|view:content}}</p>
<hr>
<h4>[[+Relations|Relations]]</h4>
<p>{{+Relations+intro|view:content}}</p>
<p>{{+Relations+table-of-contents|view:content}}</p>
<hr>
<h4>[[+Species|Species]]</h4>
<p>{{+Species+intro|view:content}}</p>
<p>{{+Species+table-of-contents|view:content}}</p>
<hr>
<h4>[[+Cultures|Cultures]]</h4>
<p>{{+Cultures+intro|view:content}}</p>
<p>{{+Cultures+table-of-contents|view:content}}</p>
<hr>
<p> </p>
<p>{{+AI|view:closed;title:AI}}</p>
<p>{{+GM|view:closed;title:GM}}</p>
<p>{{+tags|view:closed;title:Tags;type:pointer}}</p>
<p> </p>
<p>Back to [[_L|Major Factions]]</p>
<p> </p>
```

**Key Changes**:
- Remove Associated Species/Cultures/Relationships sections from main card
- **Intro and Appeal are now separate cards**: `{{+intro|view:content}}` and `{{+appeal|view:content}}`
- **Images interspersed throughout**:
  - Use `<div style="text-align:center;">` or `<p style="text-align:center;">` for centering
  - Image inclusions: `{{+image N|view:content;type:image;size:large;margin:auto}}`
  - Positioned before intro, after intro/before appeal, after appeal
  - **Note**: Images are ongoing work - not all factions have them yet
- Embed each organizational section directly on main card with:
  - `<h4>[[+CardName|Title]]</h4>` (clickable heading linking to full card)
  - `{{+CardName+intro|view:content}}` (intro paragraph inclusion)
  - `{{+CardName+table-of-contents|view:content}}` (TOC list inclusion)
- Use `_L` for relative references (left context)
- +AI/+GM syntax: `view:closed;title:AI` (not just `closed`)
- +tags syntax: `view:closed;title:Tags;type:pointer`

#### Organizational Subcard Pattern

Each organizational subcard (Subfactions, Relations, Species, Cultures) is a **full standalone card** that can be visited directly:

```html
<h4>Faction Name Section Name</h4>
<p>[[_L|Faction Name]]</p>
<p>{{+intro|content}}</p>
<p>{{+table-of-contents|content}}</p>
<p> </p>
<p>{{+AI|view:closed;title:AI}}</p>
<p>{{+GM|view:closed;title:GM}}</p>
<p>{{+tags|view:closed;title:Tags;type:pointer}}</p>
<p> </p>
<p>Back to [[_L|Faction Name]].</p>
```

**Example**: Coalition of Planets+Subfactions becomes:
```html
<h4>Coalition Subfactions</h4>
<p>[[_L|Coalition of Planets]]</p>
<p>{{+intro|content}}</p>
<p>{{+table-of-contents|content}}</p>
<p> </p>
<p>{{+AI|view:closed;title:AI}}</p>
<p>{{+GM|view:closed;title:GM}}</p>
<p>{{+tags|view:closed;title:Tags;type:pointer}}</p>
<p> </p>
<p>Back to [[_L|Coalition of Planets]].</p>
```

**Card Structure**:

**Main Faction Cards**:
- **Main card**: RichText - Embeds all sections via inclusions
- **+intro**: RichText - Faction introduction paragraph
- **+appeal**: RichText - Faction appeal paragraph
- **+image 1, +image 2, +image 3**: Image - Faction imagery (ongoing work)
- **+tags**: Pointer - `Butterfly Galaxii`, `Major Faction`, `[Faction Name]`

**Organizational Cards** (Subfactions, Relations, Species, Cultures):
- **Organizational card** (e.g., `+Subfactions`): RichText - Full standalone card with AI/GM/tags
- **+intro subcard** (e.g., `+Subfactions+intro`): RichText - Enhanced intro paragraph
- **+table-of-contents subcard** (e.g., `+Subfactions+table-of-contents`): RichText - Numbered list of links
- **+AI subcard**: RichText - Extended lore for this organizational section
- **+GM subcard**: RichText - GM notes for this organizational section
- **+tags subcard**: Pointer - `Butterfly Galaxii`, `[Faction Name]`, `[Section Type]`

#### Table-of-Contents Pattern

Each organizational subcard has its own TOC card using **numbered lists with links only** (no descriptions):

```html
<ol>
<li>[[Full+Path+To+Card|Display Name]]</li>
<li>[[Full+Path+To+Card|Display Name]]</li>
</ol>
```

**Critical**: TOCs use numbered `<ol>` lists with plain links. No descriptions or explanations in TOC cards—all context goes in the intro paragraph of the parent organizational subcard.

#### Main TOC Structure

The main faction's table-of-contents lists only actual child cards:

```html
<ol>
  <li>[[...+Subfactions|Subfactions]]<br>
  {{...+Subfactions+table-of-contents|content}}</li>
  <li>[[...+Relations|Relations]]</li>
  <li>[[...+Species|Species]]</li>
  <li>[[...+Cultures|Cultures]]</li>
</ol>
```

**Key Rules**:
- Only **Subfactions** expands its nested TOC in main TOC
- Relations, Species, Cultures are just links (their TOCs appear when you visit those cards)
- +AI and +tags are NOT in main TOC

#### Intro Paragraph Guidelines

##### +Subfactions Intro
- Explain faction's organizational diversity
- Mention 2-3 example subfaction types
- Keep to 1-2 sentences

**Example (Coalition)**:
> Coalition subfactions reflect the organization's diverse missions—from Starwatch Peacekeepers enforcing non-lethal security to Abundance Networks distributing post-scarcity resources, from Frontier Exploration Corps charting unknown space to political movements like the Progressive Alliance and Sovereignty League debating the Coalition's future direction.

##### +Relations Intro
- Open with faction's general diplomatic philosophy
- **Highlight key relationships** (1-3 most important):
  - Strongest alliance
  - Most controversial relationship
  - Primary rival
- Summarize other relationships by theme
- Keep to 3-5 sentences

**Example (Coalition)**:
> The Coalition maintains diverse relationships across both galaxies, balancing idealistic principles against pragmatic compromises necessary for post-war stability. Their strongest alliance is with the Forbidden Foundation—providing political protection in exchange for advanced technology. The most controversial relationship is their tenuous partnership with the Seventh Syndicate, dividing newly discovered worlds between Coalition humanitarian protection and Syndicate resource exploitation (many Coalition citizens view this as betrayal of democratic ideals). The Coalition's primary rival remains the Obsidian Empire in the Galaxy of War, where they communicate via ambassadors but fight via proxies. Other relationships range from sympathetic but limited support (Nova Rebellion, Criminal Elements) to mutual respect despite incompatibility (Zenith of the Beyond, Lost Armada).

##### +Species Intro
- Explain faction's species composition philosophy
- List key species with roles (4-6 species typical)
- Keep to 1-2 sentences

**Example (Coalition)**:
> The Coalition's membership reflects its post-war integration philosophy, bringing together species from across the Galaxy of Peace. Humans provide majority leadership and starship command while Eldarai scholars maintain cultural memory, Chlorosynx engineers design sustainable systems, and Machinax digital specialists find refuge from persecution elsewhere.

##### +Cultures Intro
- Explain faction's cultural integration philosophy
- Summarize culture categories with examples:
  - Foundation cultures (with purposes)
  - Bridge/Integration cultures (with categories if applicable)
  - Species-specific adaptations
- Reference key cultural themes
- Keep to 2-4 sentences

**Example (Coalition)**:
> The Coalition of Planets represents intentional diplomatic integration rather than organic cultural mixing. Foundation cultures provide democratic governance (Kovana), compassionate mentorship (Tharaneth), digital accessibility (Exakom), and peacekeeping discipline (Thoren-Kav). Bridge cultures are institutional frameworks designed post-war to facilitate peaceful integration of diverse species while preserving cultural identity—Democratic Integration Bridges create civic participation protocols (Kovaraith, Exakova, Thorenkova, Kovanai-Sen) while Specialist Integration Bridges serve scholarly and military communities (Reth-Prov, Thoraith). Coalition infrastructure explicitly builds cross-species understanding through structured cultural exchange programs.

#### Implementation Workflow

**CRITICAL FIRST STEP**: Before implementing for any faction, read the actual Coalition of Planets cards to verify current structure:

```bash
# Read Coalition main card
ssh -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17 'cd /home/ubuntu/magi-archive && set -a && . .env.production && set +a && export PATH=/home/ubuntu/.rbenv/shims:$PATH && script/card runner -' <<'RUBY'
puts "=== COALITION MAIN CARD ==="
puts Card.fetch("Games+Butterfly Galaxii+Player+Factions+Major Factions+Coalition of Planets").content

puts "\n=== +RELATIONS CARD ==="
puts Card.fetch("Games+Butterfly Galaxii+Player+Factions+Major Factions+Coalition of Planets+Relations").content

puts "\n=== +SPECIES CARD ==="
puts Card.fetch("Games+Butterfly Galaxii+Player+Factions+Major Factions+Coalition of Planets+Species").content
RUBY
```

**Step 1: Read Current Faction Card**

```bash
ssh -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17 'cd /home/ubuntu/magi-archive && set -a && . .env.production && set +a && export PATH=/home/ubuntu/.rbenv/shims:$PATH && script/card runner -' <<'RUBY'
faction = Card.fetch("Games+Butterfly Galaxii+Player+Factions+Major Factions+Faction Name")
puts "=== CURRENT CONTENT ==="
puts faction.content
RUBY
```

**Step 2: Create Organizational Subcards Script**

```ruby
#!/usr/bin/env ruby
# Reorganize Faction - Create Organizational Subcards

Card::Auth.as_bot do
  richtext_type = Card.fetch("RichText")
  pointer_type = Card.fetch("Pointer")
  base_path = "Games+Butterfly Galaxii+Player+Factions+Major Factions+Faction Name"
  faction_short_name = "Faction Name"  # e.g., "Coalition"

  # ========================================
  # CREATE +RELATIONS CARD, INTRO, AND TOC
  # ========================================

  relations = Card.fetch("#{base_path}+Relations", new: { type_id: richtext_type.id })
  relations.content = <<~HTML
    <h4>#{faction_short_name} Relations</h4>
    <p>[[_L|#{faction_short_name}]]</p>
    <p>{{+intro|content}}</p>
    <p>{{+table-of-contents|content}}</p>
    <p> </p>
    <p>{{+AI|view:closed;title:AI}}</p>
    <p>{{+GM|view:closed;title:GM}}</p>
    <p>{{+tags|view:closed;title:Tags;type:pointer}}</p>
    <p> </p>
    <p>Back to [[_L|#{faction_short_name}]].</p>
    <p> </p>
  HTML
  relations.save

  relations_intro = Card.fetch("#{base_path}+Relations+intro", new: { type_id: richtext_type.id })
  relations_intro.content = "<p>[Enhanced intro paragraph highlighting key relationships]</p>"
  relations_intro.save

  relations_toc = Card.fetch("#{base_path}+Relations+table-of-contents", new: { type_id: richtext_type.id })
  relations_toc.content = <<~HTML
    <ol>
    <li>[[Path+To+Seventh Syndicate|Seventh Syndicate]]</li>
    <li>[[Path+To+Forbidden Foundation|Forbidden Foundation]]</li>
    [... 7 more factions ...]
    </ol>
  HTML
  relations_toc.save

  # ========================================
  # CREATE +SPECIES CARD, INTRO, AND TOC
  # ========================================

  species = Card.fetch("#{base_path}+Species", new: { type_id: richtext_type.id })
  species.content = <<~HTML
    <h4>#{faction_short_name} Species</h4>
    <p>[[_L|#{faction_short_name}]]</p>
    <p>{{+intro|content}}</p>
    <p>{{+table-of-contents|content}}</p>
    <p> </p>
    <p>{{+AI|view:closed;title:AI}}</p>
    <p>{{+GM|view:closed;title:GM}}</p>
    <p>{{+tags|view:closed;title:Tags;type:pointer}}</p>
    <p> </p>
    <p>Back to [[_L|#{faction_short_name}]].</p>
  HTML
  species.save

  species_intro = Card.fetch("#{base_path}+Species+intro", new: { type_id: richtext_type.id })
  species_intro.content = "<p>[Intro paragraph explaining species composition philosophy]</p>"
  species_intro.save

  species_toc = Card.fetch("#{base_path}+Species+table-of-contents", new: { type_id: richtext_type.id })
  species_toc.content = <<~HTML
    <ol>
    <li>[[Path+To+Humans|Humans]]</li>
    <li>[[Path+To+Eldarai|Eldarai]]</li>
    [... species list ...]
    </ol>
  HTML
  species_toc.save

  # ========================================
  # CREATE +CULTURES CARD, INTRO, AND TOC
  # ========================================

  cultures = Card.fetch("#{base_path}+Cultures", new: { type_id: richtext_type.id })
  cultures.content = <<~HTML
    <h4>#{faction_short_name} Cultures</h4>
    <p>[[_L|#{faction_short_name}]]</p>
    <p>{{+intro|content}}</p>
    <p>{{+table-of-contents|content}}</p>
    <p> </p>
    <p>{{+AI|view:closed;title:AI}}</p>
    <p>{{+GM|view:closed;title:GM}}</p>
    <p>{{+tags|view:closed;title:Tags;type:pointer}}</p>
    <p> </p>
    <p>Back to [[_L|#{faction_short_name}]].</p>
    <p> </p>
  HTML
  cultures.save

  cultures_intro = Card.fetch("#{base_path}+Cultures+intro", new: { type_id: richtext_type.id })
  cultures_intro.content = "<p>[Enhanced intro paragraph explaining cultural philosophy and categories]</p>"
  cultures_intro.save

  cultures_toc = Card.fetch("#{base_path}+Cultures+table-of-contents", new: { type_id: richtext_type.id })
  cultures_toc.content = <<~HTML
    <ol>
    <li>[[Path+To+Kovana|Kovana]]</li>
    <li>[[Path+To+Tharaneth|Tharaneth]]</li>
    [... cultures list ...]
    </ol>
  HTML
  cultures_toc.save

  # ========================================
  # UPDATE +SUBFACTIONS CARD AND CREATE +INTRO
  # ========================================

  subfactions = Card.fetch("#{base_path}+Subfactions")
  subfactions.content = <<~HTML
    <h4>#{faction_short_name} Subfactions</h4>
    <p>[[_L|#{faction_short_name}]]</p>
    <p>{{+intro|content}}</p>
    <p>{{+table-of-contents|content}}</p>
    <p> </p>
    <p>{{+AI|view:closed;title:AI}}</p>
    <p>{{+GM|view:closed;title:GM}}</p>
    <p>{{+tags|view:closed;title:Tags;type:pointer}}</p>
    <p> </p>
    <p>Back to [[_L|#{faction_short_name}]].</p>
  HTML
  subfactions.save

  subfactions_intro = Card.fetch("#{base_path}+Subfactions+intro", new: { type_id: richtext_type.id })
  subfactions_intro.content = "<p>[Intro paragraph about subfaction diversity]</p>"
  subfactions_intro.save

  # ========================================
  # CREATE MAIN FACTION +INTRO AND +APPEAL
  # ========================================

  intro = Card.fetch("#{base_path}+intro", new: { type_id: richtext_type.id })
  intro.content = "<p>[Faction introduction paragraph]</p>"
  intro.save

  appeal = Card.fetch("#{base_path}+appeal", new: { type_id: richtext_type.id })
  appeal.content = "<p>[Faction appeal paragraph]</p>"
  appeal.save

  # ========================================
  # CREATE MAIN FACTION +TAGS POINTER
  # ========================================

  tags = Card.fetch("#{base_path}+tags", new: { type_id: pointer_type.id })
  tags.content = <<~CONTENT.strip
    Butterfly Galaxii
    Major Faction
    #{faction_short_name}
  CONTENT
  tags.save

  # ========================================
  # UPDATE ORGANIZATIONAL CARD +TAGS
  # ========================================

  ["Subfactions", "Relations", "Species", "Cultures"].each do |section|
    section_tags = Card.fetch("#{base_path}+#{section}+tags", new: { type_id: pointer_type.id })
    section_tags.content = <<~CONTENT.strip
      Butterfly Galaxii
      #{faction_short_name}
      #{section}
    CONTENT
    section_tags.save
  end

  puts "✓ Created organizational subcards with intros, images, and hierarchical tags"
end
```

**Step 3: Update Main Faction Card**

```ruby
Card::Auth.as_bot do
  faction = Card.fetch("Games+Butterfly Galaxii+Player+Factions+Major Factions+Faction Name")

  faction.content = <<~HTML
    <h1>Faction Name</h1>
    <p>[[_L|Major Faction]]</p>
    <div style="text-align:center;">{{+image 1|view:content;type:image;size:large;margin:auto}}</div>
    <p>{{+intro|view:content}}</p>
    <p style="text-align:center;">{{+image 2|view:content;type:image;size:large;margin:auto}}</p>
    <h2>Faction Appeal</h2>
    <p>{{+appeal|view:content}}</p>
    <p style="text-align:center;">{{+image 3|view:content;type:image;size:large;margin:auto}}</p>
    <hr>
    <h4>[[+Subfactions|Subfactions]]</h4>
    <p>{{+Subfactions+intro|view:content}}</p>
    <p>{{+Subfactions+table-of-contents|view:content}}</p>
    <hr>
    <h4>[[+Relations|Relations]]</h4>
    <p>{{+Relations+intro|view:content}}</p>
    <p>{{+Relations+table-of-contents|view:content}}</p>
    <hr>
    <h4>[[+Species|Species]]</h4>
    <p>{{+Species+intro|view:content}}</p>
    <p>{{+Species+table-of-contents|view:content}}</p>
    <hr>
    <h4>[[+Cultures|Cultures]]</h4>
    <p>{{+Cultures+intro|view:content}}</p>
    <p>{{+Cultures+table-of-contents|view:content}}</p>
    <hr>
    <p> </p>
    <p>{{+AI|view:closed;title:AI}}</p>
    <p>{{+GM|view:closed;title:GM}}</p>
    <p>{{+tags|view:closed;title:Tags;type:pointer}}</p>
    <p> </p>
    <p>Back to [[_L|Major Factions]]</p>
    <p> </p>
  HTML

  faction.save
  puts "✓ Updated main faction card with images and separate intro/appeal"
end
```

**Note**: Image cards (+image 1, +image 2, +image 3) are ongoing work and may not exist for all factions yet. The inclusions will gracefully handle missing images.

**Step 4: Update Main TOC**

```ruby
Card::Auth.as_bot do
  main_toc = Card.fetch("Games+Butterfly Galaxii+Player+Factions+Major Factions+Faction Name+table-of-contents")

  main_toc.content = <<~HTML
    <ol>
      <li>[[Full+Path+Subfactions|Subfactions]]<br>
      {{Full+Path+Subfactions+table-of-contents|content}}</li>
      <li>[[Full+Path+Relations|Relations]]</li>
      <li>[[Full+Path+Species|Species]]</li>
      <li>[[Full+Path+Cultures|Cultures]]</li>
    </ol>
  HTML

  main_toc.save
  puts "✓ Updated main TOC"
end
```

**Step 5: Execute via SSH**

```bash
ssh -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17 'cd /home/ubuntu/magi-archive && set -a && . .env.production && set +a && export PATH=/home/ubuntu/.rbenv/shims:$PATH && script/card runner -' < /e/tmp/reorganize-faction.rb
```

#### Example: Coalition of Planets Restructure (2025-12-01)

**Cards Created**:
1. Coalition of Planets+intro (RichText) - Main faction introduction paragraph
2. Coalition of Planets+appeal (RichText) - Faction appeal paragraph
3. Coalition of Planets+image 1, +image 2, +image 3 (Image) - Faction imagery (ongoing)
4. Coalition of Planets+Relations (RichText) - Full standalone card
5. Coalition of Planets+Relations+intro (RichText) - Enhanced intro paragraph
6. Coalition of Planets+Relations+table-of-contents (RichText) - 9 faction links
7. Coalition of Planets+Relations+tags (Pointer) - `Butterfly Galaxii`, `Coalition of Planets`, `Relations`
8. Coalition of Planets+Species (RichText) - Full standalone card
9. Coalition of Planets+Species+intro (RichText) - Intro paragraph
10. Coalition of Planets+Species+table-of-contents (RichText) - 4 species links
11. Coalition of Planets+Species+tags (Pointer) - `Butterfly Galaxii`, `Coalition of Planets`, `Species`
12. Coalition of Planets+Cultures (RichText) - Full standalone card
13. Coalition of Planets+Cultures+intro (RichText) - Comprehensive intro paragraph
14. Coalition of Planets+Cultures+table-of-contents (RichText) - 10 culture links
15. Coalition of Planets+Cultures+tags (Pointer) - `Butterfly Galaxii`, `Coalition of Planets`, `Cultures`
16. Coalition of Planets+Subfactions+intro (RichText) - Subfaction diversity intro
17. Coalition of Planets+Subfactions+tags (Pointer) - `Butterfly Galaxii`, `Coalition of Planets`, `Subfactions`
18. Coalition of Planets+tags (Pointer) - `Butterfly Galaxii`, `Major Faction`, `Coalition of Planets`

**Cards Updated**:
1. Coalition of Planets (main card) - Embeds sections with clickable headings + intro + TOC inclusions
2. Coalition of Planets+Subfactions - Converted to full standalone card
3. Coalition of Planets+table-of-contents - Lists 4 sections

**Before**:
- Single flat card with all sections embedded
- Associated Species: `<h2>` section with 4 paragraphs
- Associated Cultures: `<h2>` section with 3 `<h3>` categories + 10 cultures
- Factional Relationships: `<h2>` section with 9 paragraphs

**After**:
- Main card: Embeds intro/appeal/images + all sections with `<h4>[[+Card|Title]]</h4>` + inclusions
- +intro: Main faction introduction (separate card for reusability)
- +appeal: Faction appeal paragraph (separate card for reusability)
- +image 1, +image 2, +image 3: Faction imagery with centered layout
- +tags: `Butterfly Galaxii`, `Major Faction`, `Coalition of Planets`
- +Relations: Full standalone card with breadcrumb, intro inclusion, TOC inclusion, AI/GM/tags
- +Relations+intro: 5-sentence enhanced intro paragraph (separate card)
- +Relations+tags: `Butterfly Galaxii`, `Coalition of Planets`, `Relations`
- +Species: Full standalone card with breadcrumb, intro inclusion, TOC inclusion, AI/GM/tags
- +Species+intro: 2-sentence intro paragraph (separate card)
- +Species+tags: `Butterfly Galaxii`, `Coalition of Planets`, `Species`
- +Cultures: Full standalone card with breadcrumb, intro inclusion, TOC inclusion, AI/GM/tags
- +Cultures+intro: 4-sentence comprehensive intro paragraph (separate card)
- +Cultures+tags: `Butterfly Galaxii`, `Coalition of Planets`, `Cultures`
- +Subfactions: Full standalone card with breadcrumb, intro inclusion, TOC inclusion, AI/GM/tags
- +Subfactions+intro: 1-sentence diversity intro (separate card)
- +Subfactions+tags: `Butterfly Galaxii`, `Coalition of Planets`, `Subfactions`

#### Key Lessons

1. **Reference Coalition First**: Always read actual Coalition of Planets cards before implementing for other factions
2. **Separate Intro/Appeal Cards**: Main faction intro and appeal are separate cards (`+intro`, `+appeal`) for reusability
3. **Image Integration**: Use centered images (`<div style="text-align:center;">` or `<p style="text-align:center;">`) interspersed throughout main card
4. **Hierarchical Tagging**:
   - Main faction: `Butterfly Galaxii`, `Major Faction`, `[Faction Name]`
   - Organizational cards: `Butterfly Galaxii`, `[Faction Name]`, `[Section Type]`
   - Game-level tag enables multi-game filtering
5. **Main Card Embedding**: Embed sections directly on main card with `<h4>[[+Card|Title]]</h4>` + intro + TOC inclusions
6. **Intro Subcards**: Create separate +intro subcards (e.g., `+Relations+intro`) for each organizational section
7. **Standalone Organizational Cards**: Each organizational card is a full card with breadcrumbs, AI/GM/tags structure
8. **Relative References**: Use `[[_L|Display Text]]` for left context references (cleaner than full paths)
9. **Inclusion Syntax**: Use `view:content` for inclusions, `view:closed;title:Name` for AI/GM/tags
10. **+tags Syntax**: `{{+tags|view:closed;title:Tags;type:pointer}}` at very bottom
11. **TOC Lists**: Always use numbered `<ol>` lists, never unordered `<ul>`
12. **No Descriptions in TOCs**: Keep TOCs as bare links only, move context to +intro subcards
13. **Main TOC Structure**: Only Subfactions expands nested TOC, others are just links
14. **Intro Paragraph Focus**: Highlight key themes/examples in +intro subcards, not comprehensive lists
15. **Clickable Headings**: Section headings link to full organizational cards for browsability
16. **Content Preservation**: Extract key points from removed descriptions into +intro subcards
17. **Image Cards Ongoing**: Not all factions have images yet - inclusions handle missing gracefully

#### Verification Checklist

After restructuring a faction:

- [ ] **Read Coalition of Planets cards first to verify current structure**
- [ ] +Relations card created as full standalone card with breadcrumbs and AI/GM/tags
- [ ] +Relations+intro card created with enhanced intro paragraph
- [ ] +Relations+table-of-contents created with numbered list (no descriptions)
- [ ] +Species card created as full standalone card with breadcrumbs and AI/GM/tags
- [ ] +Species+intro card created with intro paragraph
- [ ] +Species+table-of-contents created with numbered list (no descriptions)
- [ ] +Cultures card created as full standalone card with breadcrumbs and AI/GM/tags
- [ ] +Cultures+intro card created with enhanced intro paragraph
- [ ] +Cultures+table-of-contents created with numbered list (no descriptions)
- [ ] +Subfactions card updated as full standalone card with breadcrumbs and AI/GM/tags
- [ ] +Subfactions+intro card created with intro paragraph
- [ ] Main faction +tags pointer created with `[[BG Major Faction]]`
- [ ] Main faction card embeds sections with `<h4>[[+Card|Title]]</h4>` headings
- [ ] Main card includes `{{+CardName+intro|view:content}}` for each section
- [ ] Main card includes `{{+CardName+table-of-contents|view:content}}` for each section
- [ ] Main card uses `[[_L|...]]` for relative references
- [ ] +tags at very bottom with `view:closed;title:Tags;type:pointer`
- [ ] AI/GM use `view:closed;title:AI` syntax (not just `closed`)
- [ ] Main TOC lists 4 sections (Subfactions, Relations, Species, Cultures)
- [ ] Only Subfactions expands nested TOC in main TOC
- [ ] +AI and +tags NOT in main TOC
- [ ] All organizational cards have descriptive titles (e.g., "Coalition Subfactions")
- [ ] All +intro cards highlight key themes (not just general statements)
- [ ] Content from removed sections preserved in +intro cards or +AI cards

#### Pattern Application to Other Factions

This pattern applies to all 10 major factions:
1. Coalition of Planets ✓ (prototype complete)
2. Obsidian Empire
3. Seventh Syndicate
4. Criminal Elements
5. Nova Rebellion
6. Eclipser Mercenaries
7. Altered
8. Forbidden Foundation
9. Lost Armada
10. Zenith of the Beyond

Each faction will have the same structure but different intro paragraph content reflecting their unique philosophies and relationships.

---

### Phase 13: Major Species Card Structure (BG_Species Cardtype)

**Date Added**: 2025-12-02
**Context**: Creating BG_Species cardtype and migrating first Major Species (Human) following Phase 12 organizational patterns.

#### The Pattern: Species Organizational Structure

Major Species cards follow the same modular organizational pattern as Major Factions (Phase 12), adapted for species-specific content:

**Main Card Structure**:
- +intro and +appeal (separate reusable cards)
- 3 images interspersed throughout
- Three organizational sections:
  1. **+Subspecies** (biological/environmental adaptations)
  2. **+Factions** (where species has demographic/cultural dominance)
  3. **+Cultures** (which cultures species demographically dominates)

**Key Difference from Factions**: Species focus on biological adaptation and cultural participation rather than diplomatic relations and military structures.

#### Step 1: Create BG_Species Cardtype

```ruby
Card::Auth.as_bot do
  species_type = Card.fetch("BG_Species", new: { type_id: Card.fetch("Cardtype").id })

  if species_type.save
    puts "✓ Created BG_Species cardtype (ID: #{species_type.id})"
  else
    puts "✗ Failed: #{species_type.errors.full_messages.join(', ')}"
  end
end
```

**Result**: Created BG_Species cardtype (ID: 2936)

#### Step 2: Create BG_Species+*default Template

**Template Structure** (no "Species Appeal" header, just +appeal inclusion):

```ruby
Card::Auth.as_bot do
  richtext_type = Card.fetch("RichText")

  default_content = <<~HTML
    <h1>Species Name</h1>
    <p>[[_L|Major Species]]</p>
    <div style="text-align:center;">{{+image 1|view:content;type:image;size:large;margin:auto}}</div>
    <p>{{+intro|view:content}}</p>
    <div style="text-align:center;">{{+image 2|view:content;type:image;size:large;margin:auto}}</div>
    <p>{{+appeal|view:content}}</p>
    <div style="text-align:center;">{{+image 3|view:content;type:image;size:large;margin:auto}}</div>
    <hr>
    <h4>[[+Subspecies|Subspecies]]</h4>
    <p>{{+Subspecies+intro|view:content}}</p>
    <p>{{+Subspecies+table-of-contents|view:content}}</p>
    <hr>
    <h4>[[+Factions|Factions]]</h4>
    <p>{{+Factions+intro|view:content}}</p>
    <p>{{+Factions+table-of-contents|view:content}}</p>
    <hr>
    <h4>[[+Cultures|Cultures]]</h4>
    <p>{{+Cultures+intro|view:content}}</p>
    <p>{{+Cultures+table-of-contents|view:content}}</p>
    <hr>
    <p> </p>
    <p>{{+table-of-contents|view:closed;title:Table of Contents}}</p>
    <p> </p>
    <p>{{+AI|view:closed;title:AI}}</p>
    <p>{{+GM|view:closed;title:GM}}</p>
    <p>{{+tags|view:closed;title:Tags;type:pointer}}</p>
    <p> </p>
    <p>Back to [[_L|Major Species]]</p>
  HTML

  default_card = Card.fetch("BG_Species+*default", new: { type_id: richtext_type.id })
  default_card.content = default_content.strip
  default_card.save
end
```

**Result**: Created BG_Species+*default (ID: 2937, 1,090 chars)

**Key Template Features**:
- NO "Species Appeal" header (unlike factions which have "Faction Appeal")
- Three organizational sections (not five like factions)
- Same modular pattern with separate intro cards
- Centered images using `<div style="text-align:center;">`

#### Step 3: Update Major_Species Parent Card

```ruby
Card::Auth.as_bot do
  major_species = Card.fetch("Games+Butterfly Galaxii+Player+Species+Major Species")

  major_species.content = <<~HTML
    <h1>Major Species</h1>
    <p>{{+table-of-contents|content}}</p>
    <p>Back to [[Games+Butterfly Galaxii+Player+Species|Species]]</p>
  HTML

  major_species.save
end
```

**Pattern**: Matches Major_Factions parent structure (simple h1 + TOC inclusion + back link)

#### Step 4: Migrate First Species (Human)

**Source Material Priority**:
1. **Primary**: `/docs/games/butterfly-galaxii/player/species/major-species/human/intro.md` (10KB)
2. **Secondary**: `/docs/games/butterfly-galaxii/gm/cultures/major-species/human-gm.md` (35KB)
3. **Tertiary**: `/deko-card-drafts/archived/Culture-Human-Majority_Player.md` (subspecies list)
4. **Critical**: Recent culture and faction work takes precedence over old archived files

**Content Extraction Strategy**:
- **+intro**: From "Academic Context" section (brief species overview)
- **+appeal**: From "Why Play a Human?" section (player motivation, 4 paragraphs)
- **+Subspecies**: 10 environmental adaptations from Culture-Human-Majority file
- **+Factions**: List 4 factions where humans have demographic/cultural dominance
- **+Cultures**: List 6 cultures where humans are demographically dominant

#### Human Species Card Structure (36+ Cards Total)

**Main Species Cards (5)**:
1. **Main card** (BG_Species type, 1,054 chars) - Uses template, embeds all sections
2. **+intro** (RichText, 437 chars) - Species description
3. **+appeal** (RichText, 1,388 chars) - Why play this species
4. **+table-of-contents** (RichText) - Lists 3 organizational sections
5. **+tags** (Pointer) - `Butterfly Galaxii`, `Major Species`, `Human`

**Subspecies Section (16 cards)**:
6. **+Subspecies** (RichText) - Full standalone card
7. **+Subspecies+intro** (RichText, 1,509 chars) - Explains biological adaptations and cultural crossover
8. **+Subspecies+table-of-contents** (RichText) - Links to 10 subspecies cards
9. **+Subspecies+AI** (RichText) - Extended lore placeholder
10. **+Subspecies+GM** (RichText) - GM secrets placeholder
11. **+Subspecies+tags** (Pointer) - `Butterfly Galaxii`, `Human`, `Subspecies`
12-21. **+Subspecies+[Name]** (10 RichText cards) - Individual subspecies:
    - Microgravity-Adapted
    - Hypergravity-Adapted
    - High-Radiation-Adapted
    - Low-Radiation-Adapted
    - High-Pressure-Adapted
    - Low-Pressure-Adapted
    - Cryogenic-Adapted
    - Thermal-Adapted
    - Hydro-Adapted
    - Arid-Adapted

**Factions Section (6 cards)**:
22. **+Factions** (RichText) - Full standalone card
23. **+Factions+intro** (RichText, 879 chars) - Emphasizes presence in ALL 10 factions, dominance in 4
24. **+Factions+table-of-contents** (RichText) - Links to 4 dominant factions
25. **+Factions+AI** (RichText) - Extended lore placeholder
26. **+Factions+GM** (RichText) - GM secrets placeholder
27. **+Factions+tags** (Pointer) - `Butterfly Galaxii`, `Human`, `Factions`

**Cultures Section (6 cards)**:
28. **+Cultures** (RichText) - Full standalone card
29. **+Cultures+intro** (RichText, 1,236 chars) - Emphasizes near-universal presence, dominance in 6
30. **+Cultures+table-of-contents** (RichText) - Links to 6 dominant cultures
31. **+Cultures+AI** (RichText) - Extended lore placeholder
32. **+Cultures+GM** (RichText) - GM secrets placeholder
33. **+Cultures+tags** (Pointer) - `Butterfly Galaxii`, `Human`, `Cultures`

**Metadata Cards (3)**:
34. **+AI** (RichText) - Extended species lore placeholder
35. **+GM** (RichText) - GM secrets placeholder
36. **+image 1, +image 2, +image 3** (Image) - Species imagery (ongoing work)

**Total: 36+ cards per species** (26 organizational + 10 subspecies cards)

#### Human Species Content Details

**+intro** (437 chars):
> Humans are the most plentiful species in both galaxies, numbering in the hundreds of trillions. Considered generalists by galactic standards, Humans excel through versatility rather than specialization. Their lifespans and abilities set the baseline average, making them the reference point for newly discovered species. Despite cycles of divergence and collapse, humans maintain their defining characteristic: adaptability.

**+appeal** (1,388 chars - 4 paragraphs):
- **You are everywhere** - Never the outsider, understand unspoken rules
- **You are the bridge** - Translate between specialists, adaptability as superpower
- **You contain multitudes** - Human nature allows all character types
- **Touch the manifold** - Rare psionic abilities make you unpredictable

**+Subspecies+intro** (1,509 chars):
Explains 10 environmental adaptations (Microgravity-Adapted, Hypergravity-Adapted, etc.) with cultural context. Key principle: biological subspecies crosscut cultural affiliations—any subspecies may practice any human culture. Avoids "planet of hats" trope.

**+Factions+intro** (879 chars):
Lists 4 dominant factions (Coalition of Planets, Obsidian Empire, Seventh Syndicate, Nova Rebellion) while emphasizing humans appear in ALL 10 factions. Focuses on where humans have demographic and cultural dominance.

**+Cultures+intro** (1,236 chars):
Lists 6 dominant cultures (Itzalaan, Kovana, Netsugo, Haelaryn, Thoren-Kav, Daresh-Tral) while noting humans participate in virtually all major cultures. Only notable absence: Vesh-Shival (Zynx biological interface culture requiring scent, pheromone, bioluminescence capabilities humans lack).

#### Implementation Workflow

**Step 1: Create Main Species Card**:
```ruby
Card::Auth.as_bot do
  human = Card.fetch(
    "Games+Butterfly Galaxii+Player+Species+Major Species+Human",
    new: { type_id: Card.fetch("BG_Species").id }
  )

  # Apply template content manually (template doesn't auto-populate in Decko)
  human.content = <<~HTML
    <h1>Human</h1>
    <p>[[_L|Major Species]]</p>
    [... full template structure ...]
  HTML

  human.save
end
```

**IMPORTANT**: Unlike cardtypes that auto-populate, BG_Species cards need template content explicitly applied. 0-length content indicates missing template application.

**Step 2: Create +intro and +appeal Cards**:
```ruby
intro = Card.fetch("#{base}+intro", new: { type_id: richtext_type.id })
intro.content = "[species description from intro.md]"
intro.save

appeal = Card.fetch("#{base}+appeal", new: { type_id: richtext_type.id })
appeal.content = "[4 paragraphs from 'Why Play' section]"
appeal.save
```

**Step 3: Create Organizational Sections**:

Each organizational section (Subspecies, Factions, Cultures) follows same pattern:
1. Create full standalone organizational card
2. Create +intro subcard (contextual paragraph)
3. Create +table-of-contents subcard (numbered list, links only)
4. Create +AI and +GM subcards (placeholders)
5. Create +tags subcard (hierarchical pointer)

**Step 4: Create Subspecies Individual Cards**:
```ruby
subspecies_list.each do |name|
  card = Card.fetch("#{base}+Subspecies+#{name}", new: { type_id: richtext_type.id })
  card.content = "<p>#{name} humans are adapted to specific environmental conditions. [Content to be added]</p>"
  card.save
end
```

**Step 5: Create Hierarchical Tags**:
```ruby
# Main species tags
main_tags = Card.fetch("#{base}+tags", new: { type_id: pointer_type.id })
main_tags.content = "Butterfly Galaxii\nMajor Species\nHuman"
main_tags.save

# Organizational section tags
subspecies_tags = Card.fetch("#{base}+Subspecies+tags", new: { type_id: pointer_type.id })
subspecies_tags.content = "Butterfly Galaxii\nHuman\nSubspecies"
subspecies_tags.save
```

#### Key Lessons Learned

**1. Source Material Priority Is Critical**:
- Always check `/docs/` intro files first (most up-to-date player-facing)
- Then GM files for extended lore
- Then archived Culture-Species files for historical reference
- Recent culture/faction work supersedes old archived files

**2. Biological vs. Cultural Distinction**:
- Subspecies are biological/environmental adaptations
- Cultures are practiced traditions (crosscut subspecies)
- AVOID 1:1 correspondence (planet of hats trope)
- Example: Microgravity-Adapted humans may practice Daresh-Tral OR Thoren-Kav cultures

**3. TOC Structure - Links Only**:
- Table-of-contents cards contain ONLY numbered lists with wiki links
- NO inline descriptions or summaries
- ALL context goes in +intro paragraphs
- This keeps TOCs clean and context separate

**4. Dominance vs. Presence**:
- For ubiquitous species (humans), list where they DOMINATE, not where they appear
- Emphasize in intro that they appear everywhere
- Example: Humans in 4 dominant factions (but present in all 10)
- Example: Humans in 6 dominant cultures (but present in nearly all)

**5. Template Content Must Be Applied**:
- BG_Species cardtype doesn't auto-populate main card content
- 0-length content = missing template application (ERROR)
- Must manually apply template HTML to main card after creating with BG_Species type

**6. Subspecies Need Individual Cards**:
- Each subspecies gets its own placeholder card
- TOC links to actual subspecies cards (not just list items)
- Enables future expansion with full subspecies content

**7. Notable Absences Are Valuable**:
- Document where species does NOT appear
- Example: Humans absent from Vesh-Shival (Zynx biological interface culture)
- Absence tells story (biological limitations, cultural restrictions)

#### Pattern Consistency Check

**Matches BG_Faction Pattern**:
| Feature | BG_Faction | BG_Species (Human) |
|---------|-----------|-------------------|
| Cardtype exists | ✅ | ✅ |
| Default template used | ✅ | ✅ |
| +intro separate | ✅ | ✅ |
| +appeal separate | ✅ | ✅ |
| No appeal header | ❌ (has "Faction Appeal") | ✅ (no header) |
| Organizational sections | 5 (Subfactions, Relations, Species, Cultures, +1) | 3 (Subspecies, Factions, Cultures) |
| Each section has +intro | ✅ | ✅ |
| Each section has +TOC | ✅ | ✅ |
| Each section has +AI/+GM | ✅ | ✅ |
| Each section has +tags | ✅ | ✅ |
| Hierarchical tags | ✅ | ✅ |
| Images interspersed | ✅ (3) | ✅ (3) |
| Total organizational cards | 25 | 26 |
| Individual subcards | Subfactions vary | +10 subspecies |
| Total cards per instance | 25+ | 36+ |

**Approved Differences**:
1. ✅ No "Species Appeal" header (just +appeal inclusion)
2. ✅ Three sections instead of five (Subspecies, Factions, Cultures)
3. ✅ +Subspecies instead of +Subfactions
4. ✅ +Factions lists where species dominates (inverse of faction's +Species)
5. ✅ Individual subspecies cards created as placeholders

#### Verification Checklist

After migrating a species:

**Main Card**:
- [ ] Main card has BG_Species type
- [ ] Main card has template content applied (NOT 0-length)
- [ ] +intro card exists with species description
- [ ] +appeal card exists with "Why Play" content
- [ ] +tags pointer exists with hierarchical tags
- [ ] +table-of-contents lists 3 organizational sections

**Subspecies Section**:
- [ ] +Subspecies full standalone card created
- [ ] +Subspecies+intro has contextual paragraph (biological + cultural crossover)
- [ ] +Subspecies+table-of-contents has links to individual subspecies cards
- [ ] Individual subspecies cards created (10+ cards)
- [ ] +Subspecies+tags pointer exists

**Factions Section**:
- [ ] +Factions full standalone card created
- [ ] +Factions+intro emphasizes presence everywhere, dominance in subset
- [ ] +Factions+table-of-contents lists dominant factions only
- [ ] +Factions+tags pointer exists

**Cultures Section**:
- [ ] +Cultures full standalone card created
- [ ] +Cultures+intro emphasizes near-universal presence, dominance in subset
- [ ] +Cultures+table-of-contents lists dominant cultures only
- [ ] +Cultures+intro mentions notable absences (if any)
- [ ] +Cultures+tags pointer exists

**All Sections**:
- [ ] TOCs contain ONLY links (no inline descriptions)
- [ ] ALL context in +intro paragraphs
- [ ] +AI and +GM placeholders created
- [ ] URLs render correctly in production

#### Remaining Species to Migrate (10 Total)

**With Good Documentation**:
1. ✅ Human (complete - 36+ cards)
2. ⏳ Eldarai (has Culture-Eldarai-Species files + intro.md)
3. ⏳ Jinshkar (has Culture-Jinshkar-Species files)
4. ⏳ Machinax (has Culture-Machinax-Species files)
5. ⏳ Inhimisu (has Culture-Inhimisu-Species files)
6. ⏳ Silhouene (has Culture-Silhouene-Species files)

**Need to Locate Source Files**:
7. ⏳ Oathari (check for intro.md or Culture-Oathari files)
8. ⏳ Naxom (check for intro.md or Culture-Naxom files)
9. ⏳ Chlorosynx (check for intro.md)
10. ⏳ Zynx (check for intro.md)

**Additional Species** (check Major_Species TOC for completeness):
11. ⏳ Vyvaskyn (has subspecies folder)

#### Future Enhancement Tasks

**For Human Species**:
1. ⏳ Add images (+image 1, +image 2, +image 3) when available
2. ⏳ Populate +AI card with extended lore from human-gm.md
3. ⏳ Populate +GM card with GM secrets from human-gm.md
4. ⏳ Populate +Subspecies+AI with subspecies lore
5. ⏳ Populate +Factions+AI with factional distribution details
6. ⏳ Populate +Cultures+AI with cultural participation details
7. ⏳ Expand individual subspecies cards with full content

**Pattern Replication**:
- Use Human species as prototype for remaining 10 species
- Adapt content for species-specific biological traits
- Adjust faction/culture dominance lists per species
- Create species-specific subspecies (not all will have 10 environmental adaptations)

#### Production URLs

**Human Species Cards**:
- **Main**: https://magi-archive.fly.dev/Games+Butterfly_Galaxii+Player+Species+Major_Species+Human
- **Subspecies**: https://magi-archive.fly.dev/Games+Butterfly_Galaxii+Player+Species+Major_Species+Human+Subspecies
- **Factions**: https://magi-archive.fly.dev/Games+Butterfly_Galaxii+Player+Species+Major_Species+Human+Factions
- **Cultures**: https://magi-archive.fly.dev/Games+Butterfly_Galaxii+Player+Species+Major_Species+Human+Cultures
- **Microgravity-Adapted**: https://magi-archive.fly.dev/Games+Butterfly_Galaxii+Player+Species+Major_Species+Human+Subspecies+Microgravity-Adapted

**Template Reference**:
- **BG_Species Template**: https://magi-archive.fly.dev/BG_Species+*default

---

**Last Updated**: 2025-12-02
**Author**: AI Agent (Claude Sonnet 4.5)
**Context**: Butterfly Galaxii Major Cultures, Major Factions, and Major Species upload process
