#!/usr/bin/env python
"""Fetch full text of Ben Goertzel's books from goertzel.org HTML versions.

Scrapes chapter-by-chapter HTML, strips tags, and outputs JSON files
ready for ingestion as RawData cards.

Usage:
    python scripts/fetch_goertzel_books.py [--output DIR]
"""

import json
import re
import sys
import time
import urllib.request
from html.parser import HTMLParser
from pathlib import Path
from datetime import datetime, timezone


# ============================================================
# Book definitions with chapter URLs
# ============================================================

BASE = "https://goertzel.org/books"

BOOKS = [
    {
        "title": "The Structure of Intelligence",
        "author": "Ben Goertzel",
        "year": 1993,
        "publisher": "Springer-Verlag",
        "base_url": f"{BASE}/intel",
        "chapters": [
            ("Introduction", "introduction.htm"),
            ("Ch. 1: Mind and Computation", "chapter_one.htm"),
            ("Ch. 2: Optimization", "chapter_two.html"),
            ("Ch. 3: Quantifying Structure", "chapter_three.html"),
            ("Ch. 4: Intelligence and Mind", "chapter_four.htm"),
            ("Ch. 5: Induction", "chapter_five.html"),
            ("Ch. 6: Analogy", "chapter_six.htm"),
            ("Ch. 7: Long-Term Memory", "chapter_seven.htm"),
            ("Ch. 8: Deduction", "chapter_eight.html"),
            ("Ch. 9: Perception", "chapter_nine.htm"),
            ("Ch. 10: Motor Learning", "chapter_ten.html"),
            ("Ch. 11: Consciousness and Computation", "chapter_eleven.html"),
            ("Ch. 12: The Master Network", "chapter_twelve.htm"),
        ],
    },
    {
        "title": "The Evolving Mind",
        "author": "Ben Goertzel",
        "year": 1993,
        "publisher": "Gordon and Breach",
        "base_url": f"{BASE}/mind",
        "chapters": [
            ("Introduction", "introduction.html"),
            ("Ch. 1: Pattern, Complexity and Computation", "chapter_one.htm"),
            ("Ch. 2: The New Immunology", "chapter_two.html"),
            ("Ch. 3: Self-Organizing Evolution", "chapter_three.html"),
            ("Ch. 4: Neural Networks", "chapter_four.htm"),
            ("Ch. 5: Genetic Optimization", "chapter_five.htm"),
            ("Ch. 6: The Ecosystem of Ideas", "chapter_six.html"),
            ("Ch. 7: The Natural History of Mind", "chapter_seven.html"),
            ("References", "references.htm"),
        ],
    },
    {
        "title": "Chaotic Logic",
        "author": "Ben Goertzel",
        "year": 1994,
        "publisher": "Plenum",
        "base_url": f"{BASE}/logic",
        "chapters": [
            ("Ch. 1: Introduction", "chapter_one.htm"),
            ("Ch. 2: Pattern and Prediction", "chapter_two.htm"),
            ("Ch. 3: The Structure of Thought", "chapter_three.html"),
            ("Ch. 4: Psychology and Logic", "chapter_four.html"),
            ("Ch. 5: Linguistic Systems", "chapter_five.htm"),
            ("Ch. 6: Crucial Connections", "chapter_six.html"),
            ("Ch. 7: Self-Generating Systems", "chapter_seven.htm"),
            ("Ch. 8: The Cognitive Equation", "chapter_eight.html"),
            ("Ch. 9: Belief Systems", "chapter_nine.htm"),
            ("Ch. 10: Biological Metaphors of Belief", "chapter_ten.html"),
            ("Ch. 11: Mind and Reality", "chapter_eleven.htm"),
            ("Ch. 12: Dissociative Dynamics", "chapter_twelve.html"),
        ],
    },
    {
        "title": "From Complexity to Creativity",
        "author": "Ben Goertzel",
        "year": 1997,
        "publisher": "Plenum",
        "base_url": f"{BASE}/complex",
        "chapters": [
            ("Introduction", "introduction.htm"),
            ("Ch. 1: Dynamics, Evolution, Autopoiesis", "ch1.htm"),
            ("Ch. 2: The Psynet Model", "ch2.htm"),
            ("Ch. 3: A Model of Cortical Dynamics", "ch3.html"),
            ("Ch. 4: Perception and Mindspace Curvature", "ch4.html"),
            ("Ch. 5: Dynamics and Pattern", "ch5.html"),
            ("Ch. 6: Evolution and Dynamics", "ch6.html"),
            ("Ch. 7: Magician Systems", "ch7.html"),
            ("Ch. 8: The Structure of Consciousness", "ch8.html"),
            ("Ch. 9: Fractals and Sentence Production", "ch9.html"),
            ("Ch. 10: Dream Dynamics", "ch10.htm"),
            ("Ch. 11: Artificial Selfhood", "ch11.html"),
            ("Ch. 12: Subself Dynamics", "ch12.html"),
            ("Ch. 13: Aspects of Human Personality Dynamics", "ch13.html"),
            ("Ch. 14: On the Dynamics of Creativity", "ch14.html"),
            ("References", "ref.html"),
        ],
    },
    {
        "title": "Wild Computing",
        "author": "Ben Goertzel",
        "year": 2001,
        "publisher": "Electronic book",
        "base_url": f"{BASE}/wild",
        "chapters": [
            ("Introduction", "Introduction.html"),
            ("Ch. 1: The Network is the Computer is the Mind", "chapNC.html"),
            ("Ch. 2: Mind as Network and Emergence", "chapMind.html"),
            ("Ch. 3: The Psynet Model of Mind", "chapPsynet.html"),
            ("Ch. 4: A Fourfold Model of Information Space", "chap4fold.html"),
            ("Ch. 5: The Internet Economy as a Complex System", "chapEcon.html"),
            ("Ch. 6: The Emerging Global Brain", "chapWWB.html"),
            ("Ch. 7: The Webmind Architecture", "chapWebmind.html"),
            ("Ch. 8: Semiotics and Autonomy", "chapSymbol.html"),
            ("Ch. 9: Toward an Agent Interaction Protocol", "chapAIP.html"),
            ("References", "References.html"),
        ],
    },
]


# ============================================================
# HTML to text converter
# ============================================================

class HTMLTextExtractor(HTMLParser):
    """Simple HTML tag stripper that preserves paragraph breaks."""

    def __init__(self):
        super().__init__()
        self.result = []
        self.skip = False

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'):
            self.skip = True
        elif tag in ('p', 'br', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
                      'li', 'tr', 'blockquote'):
            self.result.append('\n')

    def handle_endtag(self, tag):
        if tag in ('script', 'style'):
            self.skip = False
        elif tag in ('p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
                      'li', 'tr', 'blockquote', 'table'):
            self.result.append('\n')

    def handle_data(self, data):
        if not self.skip:
            self.result.append(data)

    def get_text(self):
        text = ''.join(self.result)
        # Clean up excessive whitespace
        text = re.sub(r'\n{3,}', '\n\n', text)
        text = re.sub(r'[ \t]+', ' ', text)
        return text.strip()


def html_to_text(html_content):
    """Convert HTML to plain text."""
    extractor = HTMLTextExtractor()
    extractor.feed(html_content)
    return extractor.get_text()


def fetch_url(url):
    """Fetch URL content with retries."""
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={
                'User-Agent': 'Mozilla/5.0 (HyperonWiki/1.0)'
            })
            with urllib.request.urlopen(req, timeout=30) as resp:
                # Try multiple encodings
                content = resp.read()
                for encoding in ['utf-8', 'latin-1', 'cp1252']:
                    try:
                        return content.decode(encoding)
                    except UnicodeDecodeError:
                        continue
                return content.decode('utf-8', errors='replace')
        except Exception as e:
            if attempt < 2:
                print(f"    Retry {attempt + 1}: {e}")
                time.sleep(2)
            else:
                print(f"    FAILED: {e}")
                return None


# ============================================================
# Main
# ============================================================

def main():
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("publication_texts/json")
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Fetching {len(BOOKS)} books from goertzel.org")
    print(f"Output: {output_dir}\n")

    for book in BOOKS:
        title = book["title"]
        base = book["base_url"]
        chapters = book["chapters"]

        print(f"\n{'=' * 60}")
        print(f"Book: {title} ({book['year']}, {book['publisher']})")
        print(f"{'=' * 60}")

        all_text = []
        all_text.append(f"{title}\nby {book['author']}\n{book['publisher']}, {book['year']}\n")

        for ch_title, ch_file in chapters:
            url = f"{base}/{ch_file}"
            print(f"  {ch_title}...", end=" ", flush=True)

            html = fetch_url(url)
            if not html:
                continue

            text = html_to_text(html)
            word_count = len(text.split())
            print(f"{word_count} words")

            all_text.append(f"\n{'=' * 40}\n{ch_title}\n{'=' * 40}\n\n{text}")
            time.sleep(0.5)  # Be polite

        full_text = '\n'.join(all_text)
        total_words = len(full_text.split())
        print(f"\n  TOTAL: {total_words} words, {len(full_text)} chars")

        # Save JSON
        safe_name = re.sub(r'[^\w\-]', '_', title)
        record = {
            "card_name": f"Raw Data+publications+{title}",
            "publication_card": f"Publications+{title}",
            "source_url": f"{base}/contents.html",
            "type": "book",
            "full_text": full_text,
            "fetched_at": datetime.now(timezone.utc).isoformat(),
            "word_count": total_words,
            "author": book["author"],
            "year": book["year"],
            "publisher": book["publisher"],
        }
        json_path = output_dir / f"{safe_name}.json"
        json_path.write_text(
            json.dumps(record, indent=2, ensure_ascii=False),
            encoding='utf-8',
        )
        print(f"  Saved: {json_path}")

    print(f"\n{'=' * 60}")
    print("All books fetched!")
    print(f"{'=' * 60}")


if __name__ == "__main__":
    main()
