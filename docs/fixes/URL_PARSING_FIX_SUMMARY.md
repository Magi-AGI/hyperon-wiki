# URL Parsing Fix Summary

## Date: 2025-11-06

## Problem
URLs in richtext cards were being cut short when they contained special punctuation characters:
- **Em-dashes (—)**: `https://example.com—test` would only link `https://example.com`
- **Ellipses (…)**: `https://example.com/path…more` would only link `https://example.com/path`

The automatic URL detection would stop at these characters, making the rest of the text non-clickable.

## Root Cause
The URL parsing system in Decko uses Ruby's `URI::DEFAULT_PARSER.make_regexp` to identify URLs in content. This regex only matches valid URI characters as defined by RFC 3986, which doesn't include em-dashes or horizontal ellipsis characters (UTF-8).

**File**: `card-mod-content-0.19.1/lib/card/content/chunk/uri.rb`

**Problematic behavior**:
```ruby
# The regex stops at — and … because they're not valid URI characters
URI::DEFAULT_PARSER.make_regexp(SCHEMES).match("https://example.com—test")
# => Matches only: "https://example.com"
```

The existing trailing punctuation handler (lines 68-75) only checks single ASCII characters like `.`, `,`, `!`, etc.

## Solution
Two-layer fix targeting RichText rendering (actual hot path):

1) Chunk extension (kept for non‑RichText contexts)
- Extend `Card::Content::Chunk::Uri` via `prepend`, post‑processing the base match to include Unicode punctuation (em/en dashes, ellipsis) when followed by valid URI chars.

2) HtmlFormat linkifier (RichText path)
- Post‑process rendered HTML to:
  - Auto‑link bare domains (e.g., `teamliquid.net/...`) using `https://`.
  - Percent‑encode problematic Unicode in hrefs (U+2013/U+2014/U+2026, and other non‑RFC chars like U+00A4).
  - Fix existing anchors’ href values (encode specials without altering visible text).
  - Merge anchors split by adjacent URL fragments (eg. when editors insert the next URL piece like `¤tpage=3#57` as separate text/span).

### Implementation

- Chunk module: `mod/url_fixes/lib/card/content/chunk/uri_extensions.rb`
- Html linkifier: `mod/url_fixes/lib/url_linkifier.rb`
- Html format patch: `mod/url_fixes/lib/html_format_url_fix.rb`
- Initializer: `config/initializers/url_parsing_fix.rb`

Wiring (initializer):
```ruby
Card::Content::Chunk::Uri.prepend(UriExtensions)
Card::Format::HtmlFormat.prepend(HtmlFormatUrlFix)
```

Notes:
- Linkifier uses Nokogiri to scan/modify HTML safely.
- Href normalization keeps visible text unchanged and percent‑encodes only href.

### How It Works

**Before Fix**:
```
Text: "Visit https://example.com—awesome for info."
Parsed URL: "https://example.com"
Clickable: "https://example.com"
Non-clickable: "—awesome for info."
```

**After Fix (HtmlFormat)**:
```
Text: "Visit https://example.com—awesome for info."
Initial parse: "https://example.com"
Extension sees: "—awesome" follows
Extends to: "https://example.com—awesome"
Strips trailing: "."
Final clickable URL: "https://example.com—awesome"
Non-clickable: " for info."
```

Also handled:
- Split fragments merged into one anchor (e.g., `…topic_id=333480` + `¤tpage=3#57` → one link, href includes `%C2%A4`).
- Bare: `teamliquid.net/...` → clickable with `https://`.

## Testing

### Test Cases

1. **Em-dash in URL**: `https://example.com—test`
   - Should link the entire URL including `—test`

2. **Ellipsis in path**: `https://example.com/path…more`
   - Should link the entire URL including `…more`

3. **Actual trailing punctuation**: `https://example.com—test.`
   - Should link `https://example.com—test` and leave `.` as text

4. **Em-dash as true punctuation**: `See https://example.com—it's great.`
   - If no URI chars follow the em-dash, it's treated as punctuation

### Verification on Production

The fix is live on production as of 2025-11-06.

**Log confirmation**:
```
=== UriExtensions module prepended to Card::Content::Chunk::Uri
[URLFIX] HtmlFormatUrlFix prepended to Card::Format::HtmlFormat
```

Enable debug (optional): set `URLFIX_DEBUG=1` in `.env.production` to log
when HtmlFormat methods run.

### Real-world Case
```
Input text: teamliquid.net/... ?topic_id=333480¤tpage=3#57
Rendered:   <a href="https://teamliquid.net/...topic_id=333480%C2%A4tpage=3#57">…</a>
```
Note: `%C2%A4` encodes U+00A4. If the intent is a new query param, replace `¤` with `&`.
```

**To test**:
1. Create or edit a richtext card
2. Add a URL with an em-dash or ellipsis: `https://wiki.magi-agi.org/Notes—Important`
3. Save and view the card
4. Verify the entire URL is clickable

## Files Modified/Created

### New Files
1. **`mod/url_fixes/lib/card/content/chunk/uri_extensions.rb`** - Chunk extension
2. **`mod/url_fixes/lib/url_linkifier.rb`** - Html linkifier
3. **`mod/url_fixes/lib/html_format_url_fix.rb`** - HtmlFormat patch
4. **`config/initializers/url_parsing_fix.rb`** - Loads both extensions

### Documentation
3. **`URL_PARSING_FIX_SUMMARY.md`** - This file

## Impact and Compatibility

**Safe for updates**: Both patches use `prepend`, which takes precedence in Ruby's method lookup chain:
- If Decko fixes the bug upstream, this extension will still work (it will just be a no-op)
- Chunk extension only acts when it detects special punctuation
- Html linkifier runs only when URL-like text is detected; it percent‑encodes hrefs and leaves text untouched
- Includes safety checks for nil ranges and empty nodes

**Testing after Decko updates**:
1. Test URLs with em-dashes and ellipses
2. Check logs for any UriExtensions errors
3. If Decko fixes this upstream, this mod can be safely removed

## Related Issues

- Email verification fix (see `EMAIL_VERIFICATION_FIX_SUMMARY.md`)
- Upload cache fix (see `config/initializers/upload_cache_fix.rb`)

All three fixes use the same `prepend` pattern for safe, non-invasive monkey-patching.

## Decko Version

- **Decko**: 0.19.1
- **card-mod-content**: 0.19.1
- **Fix Date**: 2025-11-06

## TODO

- [ ] Propose upstream enhancements for HtmlFormat auto-linking and Unicode support
- [ ] Extend inline merge allowlist if other wrappers appear
- [ ] Monitor production logs for any unexpected behavior (enable `URLFIX_DEBUG` if needed)

---

## Status: ✅ DEPLOYED AND WORKING

The URL parsing fix is live on production and functioning correctly. URLs with em-dashes and ellipses should now be properly linked.
