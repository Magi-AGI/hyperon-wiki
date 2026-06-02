#!/usr/bin/env python3
"""Clean Decko URI-chunk auto-linker artifacts from stored card content.

Mirrors the Ruby fix in mod/url_fixes/lib/url_linkifier.rb but applied
to RAW STORED content (one-shot per card) instead of at render time.

Two cleanups:
1. Unwrap nested same-href anchors. Decko's URI chunk processor wraps
   URL-shaped text inside an authored <a> with another <a class=
   "external-link"> on every render. Each render pass adds a layer
   over time; some cards are 10-deep.
2. Unwrap filename pseudo-URLs. Source-file references like nace.py /
   MorkDB.cc:268 are matched as bare-domain URLs and wrapped as
   <a href="http://nace.py">nace.py</a>. Replace with their text.

Regex-only (no HTML parser) so blank lines, code-tag entities, and
attribute order are preserved exactly. Patterns are anchored on the
specific shape Decko emits: target="_blank" class="external-link" href.

Usage:
    python clean_autolinker_artifacts.py < input.html > output.html
"""

import re
import sys

FILENAME_EXTENSION_GROUP = (
    r"(?:py|rs|cc|cpp|c|h|hpp|hh|cxx"
    r"|md|txt|rst|json|yml|yaml|toml|cfg|conf|ini|log"
    r"|ts|tsx|js|jsx|mjs|cjs|coffee"
    r"|go|rb|erb|scm|ss|lisp|cl|lean|idr|metta"
    r"|erl|hs|ml|mli|sh|bash|zsh|fish"
    r"|java|kt|kts|scala|swift|dart"
    r"|sql|svg|scss|sass|less"
    r"|pl|pm|tex|bib|nim|zig)"
)

NESTED_RE = re.compile(
    r'<a target="_blank" class="external-link" href="(?P<href>[^"]+)">'
    r'<a target="_blank" class="external-link" href="(?P=href)">'
    r"(?P<text>[^<]*)"
    r"</a></a>",
    re.IGNORECASE,
)

FILENAME_ANCHOR_RE = re.compile(
    r'<a target="_blank" class="external-link" '
    r'href="https?://[^"/?#]+\.' + FILENAME_EXTENSION_GROUP + r'(?::[^"]*)?">'
    r"(?P<text>[^<]*)"
    r"</a>",
    re.IGNORECASE,
)


def clean(html):
    nested_count = 0
    filename_count = 0

    # Iterate on nested unwrap until no more matches (handles arbitrary depth).
    for _ in range(15):
        new, n = NESTED_RE.subn(lambda m: m.group("text"), html)
        nested_count += n
        if n == 0:
            break
        html = new

    # Then unwrap any remaining single-anchor filename pseudo-URLs.
    html, filename_count = FILENAME_ANCHOR_RE.subn(
        lambda m: m.group("text"), html
    )

    sys.stderr.write(
        f"[clean] unwrapped {nested_count} nested-matching anchors, "
        f"{filename_count} filename-pseudo-URL anchors\n"
    )
    return html


if __name__ == "__main__":
    sys.stdout.write(clean(sys.stdin.read()))
