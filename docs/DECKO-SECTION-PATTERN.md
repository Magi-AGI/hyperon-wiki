# Decko Hierarchical Section Pattern

**Created**: 2025-10-28
**Status**: Production Pattern
**Examples**: Neoterics, Notes sections

---

## Overview

This document describes the standardized pattern for creating hierarchical documentation sections in the Decko wiki. The pattern uses Decko's inclusion syntax to create nested, navigable sections with automatic table-of-contents generation.

---

## Card Naming Convention

Hierarchical cards use the `+` separator to indicate parent-child relationships:

```
Section Name                    (top-level section)
├── Section Name+intro          (introduction content)
├── Section Name+table-of-contents
├── Section Name+Subsection     (child section)
│   ├── Section Name+Subsection+intro
│   ├── Section Name+Subsection+table-of-contents
│   └── Section Name+Subsection+Content Item  (actual content)
└── Section Name+Another Subsection
```

**Example from Notes section:**
```
Notes
├── Notes+intro
├── Notes+table-of-contents
├── Notes+AI Chats
│   ├── Notes+AI Chats+intro
│   ├── Notes+AI Chats+table-of-contents
│   └── Notes+AI Chats+Arch Empress Virelya Summary
└── Notes+Web Links
    ├── Notes+Web Links+intro
    ├── Notes+Web Links+table-of-contents
    └── Notes+Web Links+DnD 5E Links
```

---

## Card Type Requirements

Different cards in the hierarchy require specific Decko card types:

| Card Purpose | Type | Type ID | Reason |
|-------------|------|---------|--------|
| Section cards (containers) | **RichText** | 2 | Must support inclusion syntax |
| Table-of-contents cards | **RichText** | 2 | Must support inclusion syntax and HTML |
| Intro cards | **Markdown** | 65 | Static content, can be markdown |
| Content cards (leaf nodes) | **Markdown** | 65 | Actual documentation content |

### Why RichText for Sections?

Section and TOC cards use Decko's inclusion syntax (`{{+card|view}}`), which only works with RichText type. Using Markdown type will cause the inclusion syntax to be rendered as literal text instead of being processed.

---

## Section Card Pattern

**Content structure for section cards:**

```
{{+intro|content}}

{{+table-of-contents|content}}
```

**Important:**
- NO markdown headers (like `# Section Name`)
- NO other content
- Just the two inclusion statements separated by a blank line
- Must be RichText type (2)

**Example:**
```ruby
Card::Auth.as_bot do
  Card.create!(
    name: "My Section",
    content: "{{+intro|content}}\n\n{{+table-of-contents|content}}",
    type_id: 2  # RichText
  )
end
```

---

## Table-of-Contents Card Pattern

**Content structure:**

```html
<ol>
<li>[[Section+Subsection|Display Name]]<br>{{Section+Subsection+table-of-contents|content}}</li>
<li>[[Section+Another|Another Name]]<br>{{Section+Another+table-of-contents|content}}</li>
<li>[[Section+Leaf Content|Leaf Item]]</li>
</ol>
```

**Key points:**
- Use HTML `<ol>` ordered list (NOT markdown numbered lists)
- Each subsection has TWO parts:
  1. `[[Link|Display Text]]` - clickable link to subsection
  2. `{{Subsection+table-of-contents|content}}` - nested TOC inclusion
- Separate with `<br>` tag
- Leaf content items only need the link (no nested TOC)
- Must be RichText type (2)

**Example from Notes+table-of-contents:**
```html
<ol>
<li>[[Notes+AI Chats|AI Chats]]<br>{{Notes+AI Chats+table-of-contents|content}}</li>
<li>[[Notes+Web Links|Web Links]]<br>{{Notes+Web Links+table-of-contents|content}}</li>
<li>[[Notes+Web3|Web3]]</li>
</ol>
```

---

## Intro Card Pattern

Intro cards contain static descriptive text about the section.

**Content:**
- Can use markdown formatting
- Typically 1-3 paragraphs describing the section
- Should be Markdown type (65)

**Example:**
```ruby
Card::Auth.as_bot do
  Card.create!(
    name: "Notes+intro",
    content: "Collection of miscellaneous notes, AI conversations, and web resources...",
    type_id: 65  # Markdown
  )
end
```

### Markdown content cards and titles

- Markdown intro and content cards should **not** repeat the card title as a top‑level `#` heading. Decko already renders the card name above the body, so adding a `# Title` line at the top of the content will duplicate the heading.
- For longer research documents (for example, MAGUS research cards under `Notes+MAGUS Research`), treat the Decko card as a Markdown mirror of a canonical `.md` file in `magi-knowledge-repo` when possible. Maintaining the primary copy in a file makes it easier to preserve newlines, code fences, and headings, and to restore formatting if it is ever damaged.

---

## Complete Example: Creating a New Section

### Step 1: Create Section Structure

```ruby
Card::Auth.as_bot do
  # Main section card
  section = Card.create!(
    name: "Research",
    content: "{{+intro|content}}\n\n{{+table-of-contents|content}}",
    type_id: 2  # RichText
  )

  # Section intro
  Card.create!(
    name: "Research+intro",
    content: "This section contains research papers and analysis.",
    type_id: 65  # Markdown
  )

  # Section table-of-contents
  Card.create!(
    name: "Research+table-of-contents",
    content: <<~HTML,
      <ol>
      <li>[[Research+Papers|Papers]]<br>{{Research+Papers+table-of-contents|content}}</li>
      <li>[[Research+Reports|Reports]]<br>{{Research+Reports+table-of-contents|content}}</li>
      </ol>
    HTML
    type_id: 2  # RichText
  )
end
```

### Step 2: Create Subsections

```ruby
Card::Auth.as_bot do
  # Subsection: Papers
  Card.create!(
    name: "Research+Papers",
    content: "{{+intro|content}}\n\n{{+table-of-contents|content}}",
    type_id: 2  # RichText
  )

  Card.create!(
    name: "Research+Papers+intro",
    content: "Academic papers and research documents.",
    type_id: 65  # Markdown
  )

  Card.create!(
    name: "Research+Papers+table-of-contents",
    content: <<~HTML,
      <ol>
      <li>[[Research+Papers+Machine Learning|Machine Learning]]</li>
      <li>[[Research+Papers+Quantum Computing|Quantum Computing]]</li>
      </ol>
    HTML
    type_id: 2  # RichText
  )
end
```

### Step 3: Add Content

```ruby
Card::Auth.as_bot do
  # Actual content cards
  Card.create!(
    name: "Research+Papers+Machine Learning",
    content: File.read("path/to/ml-paper.md"),
    type_id: 65  # Markdown
  )

  Card.create!(
    name: "Research+Papers+Quantum Computing",
    content: File.read("path/to/quantum-paper.md"),
    type_id: 65  # Markdown
  )
end
```

### Step 4: Update Main TOC

```ruby
Card::Auth.as_bot do
  toc = Card.fetch("table-of-contents")
  toc.update!(
    content: <<~HTML
      <ol>
      <li>[[Neoterics]]<br>{{Neoterics+table-of-contents|content}}</li>
      <li>[[Notes]]<br>{{Notes+table-of-contents|content}}</li>
      <li>[[Research]]<br>{{Research+table-of-contents|content}}</li>
      </ol>
    HTML
  )
end
```

---

## Common Mistakes to Avoid

### ❌ Using Markdown Lists in TOC Cards

**Wrong:**
```markdown
1. [[Section+Item|Item]]
2. [[Section+Another|Another]]
```

**Right:**
```html
<ol>
<li>[[Section+Item|Item]]</li>
<li>[[Section+Another|Another]]</li>
</ol>
```

### ❌ Adding Headers to Section Cards

**Wrong:**
```
# My Section

{{+intro|content}}

{{+table-of-contents|content}}
```

**Right:**
```
{{+intro|content}}

{{+table-of-contents|content}}
```

### ❌ Using Wrong Card Type

**Wrong:**
```ruby
Card.create!(
  name: "Section",
  content: "{{+intro|content}}\n\n{{+table-of-contents|content}}",
  type_id: 65  # Markdown - WRONG!
)
```

**Right:**
```ruby
Card.create!(
  name: "Section",
  content: "{{+intro|content}}\n\n{{+table-of-contents|content}}",
  type_id: 2  # RichText
)
```

### ❌ Forgetting Nested TOC Inclusion

**Wrong:**
```html
<ol>
<li>[[Section+Subsection|Subsection]]</li>
</ol>
```

**Right:**
```html
<ol>
<li>[[Section+Subsection|Subsection]]<br>{{Section+Subsection+table-of-contents|content}}</li>
</ol>
```

---

## Verification Checklist

After creating a new section, verify:

- [ ] Section card is RichText type (2)
- [ ] Section card uses inclusion syntax pattern
- [ ] All TOC cards are RichText type (2)
- [ ] All TOC cards use `<ol>` HTML lists
- [ ] Subsections include both link AND nested TOC
- [ ] Intro cards are Markdown type (65)
- [ ] Content cards are Markdown type (65)
- [ ] Section appears in main table-of-contents
- [ ] Navigation works in web UI

---

## Ruby Verification Script

```ruby
# Run via: script/card runner /path/to/verify_section.rb

section_name = "Research"  # Change to your section

Card::Auth.as_bot do
  puts "=== Verifying #{section_name} Section ==="

  # Check section card
  section = Card.fetch(section_name)
  puts "\n1. Section Card:"
  puts "   Type: #{section.type_name} (#{section.type_id}) - Should be RichText (2)"
  puts "   Content: #{section.content}"

  # Check TOC card
  toc = Card.fetch("#{section_name}+table-of-contents")
  puts "\n2. TOC Card:"
  puts "   Type: #{toc.type_name} (#{toc.type_id}) - Should be RichText (2)"
  puts "   Uses <ol>: #{toc.content.include?('<ol>')}"

  # Check intro card
  intro = Card.fetch("#{section_name}+intro")
  puts "\n3. Intro Card:"
  puts "   Type: #{intro.type_name} (#{intro.type_id}) - Can be Markdown (65)"

  puts "\n✓ Verification complete"
end
```

---

## Migration Template

Use this template when migrating documentation from file-based systems:

```ruby
#!/usr/bin/env ruby
# Migration script template

Card::Auth.as_bot do
  section_name = "NewSection"

  # 1. Create section structure
  Card.create!(
    name: section_name,
    content: "{{+intro|content}}\n\n{{+table-of-contents|content}}",
    type_id: 2
  )

  Card.create!(
    name: "#{section_name}+intro",
    content: "Description of this section...",
    type_id: 65
  )

  # 2. Build TOC content (will update after subsections)
  toc_items = []

  # 3. Create subsections
  subsections = ["Subsection1", "Subsection2"]
  subsections.each do |sub|
    full_name = "#{section_name}+#{sub}"

    Card.create!(
      name: full_name,
      content: "{{+intro|content}}\n\n{{+table-of-contents|content}}",
      type_id: 2
    )

    Card.create!(
      name: "#{full_name}+intro",
      content: "Description...",
      type_id: 65
    )

    # Build subsection TOC items list (from file system)
    sub_items = Dir["path/to/#{sub}/*.md"].map do |file|
      name = File.basename(file, ".md").split.map(&:capitalize).join(' ')
      "  <li>[[#{full_name}+#{name}|#{name}]]</li>"
    end

    Card.create!(
      name: "#{full_name}+table-of-contents",
      content: "<ol>\n#{sub_items.join("\n")}\n</ol>",
      type_id: 2
    )

    # Add to parent TOC
    toc_items << "<li>[[#{full_name}|#{sub}]]<br>{{#{full_name}+table-of-contents|content}}</li>"
  end

  # 4. Update section TOC
  Card.create!(
    name: "#{section_name}+table-of-contents",
    content: "<ol>\n#{toc_items.join("\n")}\n</ol>",
    type_id: 2
  )

  # 5. Migrate content files (implement based on your needs)
  # ...

  puts "✓ Section structure created"
end
```

---

## References

- **Decko Inclusion Syntax**: https://decko.org/Include
- **Card Types**: https://decko.org/Card+type
- **Example Sections**:
  - `Neoterics` (production)
  - `Notes` (production)

---

## Change Log

- 2025-10-28: Initial documentation of hierarchical section pattern
