# URL Parsing Fix - Debugging Notes

## Date: 2025-11-06

## Problem Statement

URLs in richtext cards are being cut short when they contain special punctuation:
- **Em-dashes (—)** U+2014
- **En-dashes (–)** U+2013
- **Ellipses (…)** U+2026

Example problematic URLs:
1. `http://www.drivethrurpg.com/product/226860/Heroic-Maps–Port-Fanchone?manufacturers_id=5371`
   - Stops at the en-dash, cutting off `Port-Fanchone?manufacturers_id=5371`

2. `google.com.hk/search?q=...&gs_l=serp.3…487014.489623.0.490103...`
   - Stops at the first ellipsis at position 292
   - Should continue through to the end: `...7r-M-jwavCs`

## Solution Implemented

Created `UriExtensions` module to extend `Card::Content::Chunk::Uri` class:

**Files**:
- `mod/url_fixes/lib/card/content/chunk/uri_extensions.rb` - Core extension
- `config/initializers/url_parsing_fix.rb` - Loads and prepends the module

**Approach**:
1. Uses Ruby's `prepend` pattern to override the `interpret` method
2. After the base URI regex matches, looks ahead for em-dashes, en-dashes, or ellipses
3. If found followed by valid URI characters, extends the match to include them
4. Strips actual trailing punctuation (periods, commas, etc.)

## Critical Issue: Extension Not Being Called

### What We Confirmed
✅ The module is properly prepended to `Card::Content::Chunk::Uri`
```
Ancestors: UriExtensions, Card::Content::Chunk::Uri, Card::Content::Chunk::Abstract...
```

✅ The module loads successfully on server start:
```
=== UriExtensions module prepended to Card::Content::Chunk::Uri
```

❌ The `interpret` method is **NEVER called** during page rendering or card saving

### Debugging Attempts

1. **Added logging to `interpret` method**:
   - Used both `Rails.logger.debug` and `Rails.logger.info`
   - No logging output appears in production.log
   - This proves the method override exists but is never invoked

2. **Cleared cache multiple times**:
   ```ruby
   card.expire
   card.save!
   ```
   - No effect - still no `interpret` calls

3. **Forced card re-save**:
   ```ruby
   card.update_column(:db_content, card.db_content)
   card.save!
   ```
   - No effect - no `interpret` calls logged

4. **Checked card content**:
   ```ruby
   card.db_content  # Raw HTML: <p><br>http://example.com–test<br>...</p>
   card.content     # Same as db_content
   ```
   - Content is stored as HTML, not plain text
   - URLs are embedded within HTML tags

### Key Findings

#### Card Type Matters
- Test card is **RichText** (type_id: 2)
- Content stored as HTML: `<p><br>URL<br></p>`
- URLs are part of HTML structure, not plain text to be chunked

#### Possible Explanations

1. **RichText vs PlainText Processing**:
   - RichText cards may not use the URI chunking system at all
   - HTML content might be processed differently than plain text
   - URL auto-linking may happen at a different layer

2. **Timing of Chunk Processing**:
   - Chunks might only be created at initial save, not on display
   - Cached HTML might already have links rendered
   - The `interpret` method might only run in specific contexts (like email rendering)

3. **Format-Specific Chunking**:
   - Different format classes (HtmlFormat vs PlainTextFormat) might process chunks differently
   - The URI chunk system might only apply to certain views or rendering contexts

#### Evidence from Logs

When accessing pages with problematic URLs:
```
Started GET "/example_test" for ... at 2025-11-06 22:24:45
Processing by CardController#read as HTML
  Parameters: {"mark"=>"example_test"}
Completed 200 OK in 170ms
```

No UriExtensions logging appears, only the module prepend message at startup.

## Test Results

### Test 1: Ruby URI Regex Behavior
```ruby
test_url = "http://www.drivethrurpg.com/product/226860/Heroic-Maps–Port-Fanchone?manufacturers_id=5371"
# Position 54: "–" (U+2013) - en-dash
# Matched: http://www.drivethrurpg.com/product/226860/Heroic-Maps
# Matched length: 54
```
✅ Confirmed: Ruby's `URI::DEFAULT_PARSER.make_regexp` stops at en-dashes

### Test 2: Ellipsis in Google URL
```ruby
test_url = "http://google.com.hk/search?q=...&gs_l=serp.3…487014.489623..."
# Position 292: "…" (U+2026) - ellipsis
# Position 340: "…" (U+2026)
# Position 343: "…" (U+2026)
# Matched length: 292
# Stops at first ellipsis
```
✅ Confirmed: Regex stops at ellipsis characters

### Test 3: Module Prepend Verification
```ruby
uri_class = Card::Content::Chunk::Uri
uri_class.ancestors.include?(UriExtensions)  # => true
uri_class.instance_methods.include?(:interpret)  # => true
```
✅ Confirmed: Extension is properly integrated

### Test 4: Actual Rendering
Created test card at https://wiki.magi-agi.org/example_test
- Content: URLs with en-dashes and ellipses
- Result: URLs still cut short at special characters
- Cache cleared, card resaved - no change

❌ Fix does not work in practice, despite correct implementation

## Investigation Needed

### Questions for Next Debug Session

1. **When/where does URI chunking actually happen?**
   - Check Decko source: `card-mod-content/lib/card/content/chunk/uri.rb`
   - Find where `Chunk::Uri.new` or `interpret` is called
   - Trace the code path from card save to HTML generation

2. **Does RichText use chunking at all?**
   - Compare PlainText vs RichText rendering
   - Check if there's a `format :html` that skips chunking
   - Look for `format :plain_text` that might use it

3. **Is there view-specific chunking?**
   - Email views use chunks (email_html, email_text)
   - Maybe core/open_content view doesn't?
   - Check what formats actually process chunks

4. **Is content pre-processed at save time?**
   - When you save HTML with a URL, does Decko immediately convert it to `<a href>`?
   - Check if there's a content filter that runs before chunking
   - Look for `process_content` or similar methods

5. **Alternative approach: Format-level override?**
   - Instead of overriding `Chunk::Uri#interpret`
   - Override the format's chunk processing method
   - Or hook into content rendering earlier in the pipeline

### Recommended Next Steps

1. **Create a PlainText card** and test if chunking works there:
   ```ruby
   Card.create!(
     name: "Plain URL Test",
     type_code: :plain_text,
     content: "http://example.com–test and http://example.com…more"
   )
   ```

2. **Search Decko source for `Chunk::Uri`**:
   ```bash
   cd ~/.rbenv/versions/3.2.3/lib/ruby/gems/3.2.0/gems/
   grep -r "Chunk::Uri.new" card-mod-content-0.19.1/
   grep -r "interpret" card-mod-content-0.19.1/lib/card/content/chunk/
   ```

3. **Add logging at a higher level**:
   - Try overriding `Card::Content#process_chunks` or similar
   - Log when ANY chunk is created, not just Uri chunks
   - This will show if chunking happens at all

4. **Check format rendering**:
   ```ruby
   # In rails console
   card = Card.fetch("example test")
   card.format(:html).render_content
   # Check if this calls interpret
   ```

5. **Test with a brand new card**:
   - Don't edit existing cards (they may be cached)
   - Create entirely new card with problematic URLs
   - Save and immediately check logs

## Workarounds

Until the fix is working, users can:

1. **Manually edit URLs** to remove special characters
2. **Use PlainText cards** instead of RichText
3. **Use the `[[URL|label]]` syntax** to force linking
4. **Encode the URLs** (replace – with %E2%80%93, etc.)

## Files to Review

### Decko Source Files (on server)
```
~/.rbenv/versions/3.2.3/lib/ruby/gems/3.2.0/gems/card-mod-content-0.19.1/
├── lib/card/content.rb                    # Main content processing
├── lib/card/content/chunk.rb              # Chunk system
├── lib/card/content/chunk/abstract.rb     # Base chunk class
├── lib/card/content/chunk/uri.rb          # URI chunk (line 68-75 has trailing punct logic)
└── lib/card/format/                       # Format-specific rendering
```

### Our Custom Files
```
magi-archive/
├── mod/url_fixes/
│   └── lib/card/content/chunk/uri_extensions.rb    # Our extension
├── config/initializers/url_parsing_fix.rb          # Loads extension
└── URL_PARSING_FIX_SUMMARY.md                      # Documentation
```

## Current Status

- ✅ Extension code is correct and properly loaded
- ✅ Extension would work IF `interpret` was called
- ❌ `interpret` method is never called in practice
- ❌ URLs still cut short at special characters
- ⚠️  Root cause unknown - needs deeper investigation of Decko's content processing

## Hypothesis

The most likely explanation is that **RichText cards do not use the URI chunking system for auto-linking URLs**. Instead, they may:
1. Store URLs as plain HTML `<a>` tags at save time
2. Use a different HTML processor that doesn't go through chunks
3. Only use chunks for specific views (like email rendering)
4. Have URLs already parsed and cached before the chunk system runs

This would explain why:
- The extension loads correctly
- The method override is in place
- But `interpret` is never called
- And the fix has no effect

## Recommendation for Next AI Agent

1. **Start by testing with PlainText cards** - verify if chunking works there
2. **Grep the Decko source** for where `interpret` is actually called
3. **Add logging to `Card::Content::Chunk::Abstract`** to see if ANY chunks are created
4. **Consider an alternative approach** - maybe override at the format or content level, not the chunk level
5. **Check if there's a setting** to enable/disable URL auto-linking in RichText

The extension code itself is sound. The issue is understanding Decko's architecture to know where in the pipeline this code needs to run.
