#!/usr/bin/env python
"""Extract text from Mattermost PDF attachments for ingestion as RawData cards.

Dynamically identifies Tier 1 papers (Goertzel/SNET authored, not yet ingested),
extracts text via pypdf, and outputs JSON files for ingest_publications.rb.

Usage:
    python scripts/extract_mattermost_papers.py [--output DIR] [--tier 1|2|all]
"""

import json
import os
import re
import sys
from pathlib import Path
from datetime import datetime, timezone

import pypdf


# ============================================================
# Already-ingested publication keywords (for dedup)
# ============================================================

EXISTING_PUBLICATIONS = [
    'meta-probabilistic-programming', 'actpc-chem discrete active',
    'actpc-geom towards scalable', 'building better minds',
    'combinatorial decision dags', 'cost-based intuitionist',
    'distinction graphs graphtropy', 'economic attention networks',
    'quantum-safe homomorphic encryption', 'embedding vector differences',
    'engineering general intelligence vol', 'folding and unfolding on metagraphs',
    'general theory of general intelligence', 'generative ai vs agi cognitive',
    'grounding occam razor', 'grounding possible worlds semantics',
    'guiding symbolic natural language grammar', 'homomorphic encryption intuitionistic logic',
    'humanoid robots agents consciousness', 'info-evo information geometry',
    'integrative agi minecraft', 'intensional inheritance concepts',
    'maximal algorithmic caliber', 'meta-metta operational semantics',
    'metagoals endowing self-modifying', 'metalearning feature selection',
    'nlp architecture embodied agi', 'nonlinear dynamical attention information geometry',
    'opencog hyperon framework agi', 'opencog ns hybrid neural-symbolic',
    'opencogbot virtual agent control', 'opencogprime cognitive synergy',
    'openpsi cognitive model', 'pln and nars often yield',
    'paraconsistent foundations quantum probability',
    'paraconsistent foundations probabilistic reasoning',
    'patterns of cognition cognitive algorithms galois',
    'pragmatic path linguistic agi', 'probabilistic logic networks',
    'program representation agi', 'real world reasoning',
    'reflective metagraph rewriting', 'solomonoff universal induction',
    'symbol grounding chaining morphisms', 'hidden pattern',
    'uncertain linear logic fibring', 'uncertain spatiotemporal logic',
    'what kind programming language suits',
    'p neq np non-relativizing',
    # New books just ingested
    'structure of intelligence', 'evolving mind', 'chaotic logic',
    'from complexity to creativity', 'wild computing', 'consciousness explosion',
]

# Keywords indicating core Goertzel/SNET research
HIGH_VALUE_KEYWORDS = [
    r'actpc', r'predictive.coding', r'metta', r'hyperon', r'opencog',
    r'pln', r'mork', r'metagraph', r'atomspace', r'cogprime',
    r'agi[\s\-]', r'paraconsistent', r'quantale', r'weakness',
    r'causal.coding', r'info.evo', r'symbol.grounding',
    r'intensional', r'homomorphic.*logic',
    r'goertzel', r'geisweiller', r'openpsi', r'ecan',
    r'cognitive.synergy', r'neural.symbolic', r'metagoal', r'graphtropy',
    r'fabric.?pc', r'subrep', r'minecraft.*agi',
    r'blending', r'galois.connection', r'rewriting',
    r'mettaclaw', r'omegaclaw', r'mettasoul',
    r'bytflow', r'shardzipper', r'scalable.*metta',
    r'cenf', r'metamo', r'quantum.*cognition',
    r'moses.*mork', r'geodesic.*inference', r'incremental.*compress',
    r'symbolic.*transformer', r'vibe.*engineering',
    r'bridge.*learning', r'incompressible.*fluid',
    r'hott.*semantics', r'origin.*of.*life',
    r'nunet', r'pymetta', r'petta',
]

# Skip these patterns (non-papers)
SKIP_PATTERNS = [
    r'image', r'screenshot', r'canvas \d', r'board$',
    r'invoice', r'receipt', r'booking', r'flight', r'travel risk',
    r'password', r'vpn', r'multi factor', r'request invoicing',
    r'5 things to do', r'dfr3', r'df csv', r'flyer',
    r'state of rfps', r'dev circle', r'bgi.*media.*wall',
    r'howto connect', r'edits experts', r'zero.*shadow',
    r'istanbul', r'florianopolis', r'cornflower', r'chimera.*vouwen',
    r'demand.*two.*page', r'devoptima', r'jam.*galaxy',
    r'group rooming', r'authentication', r'voting guide',
    r'town hal dffg', r'deep funding$', r'rooming list',
]


def clean_title(filename):
    """Derive a clean card title from filename."""
    name = re.sub(r'^\d+_', '', filename)
    name = re.sub(r'^F[A-Z0-9]{10,}_+', '', name)
    name = re.sub(r'\.pdf$', '', name, flags=re.I)
    name = name.replace('_', ' ').replace('-', ' ').strip()
    name = re.sub(r'\s+', ' ', name)
    # Title case for readability
    if name == name.upper() or name == name.lower():
        name = name.title()
    return name


def is_already_ingested(title):
    low = title.lower().replace('-', ' ').replace('_', ' ')
    for kw in EXISTING_PUBLICATIONS:
        words = kw.split()
        matches = sum(1 for w in words if w in low)
        if len(words) > 0 and matches / len(words) > 0.6:
            return True
    return False


def is_high_value(title):
    low = title.lower().replace('_', ' ').replace('-', ' ')
    return any(re.search(kw, low) for kw in HIGH_VALUE_KEYWORDS)


def should_skip(title):
    low = title.lower()
    return any(re.search(p, low) for p in SKIP_PATTERNS)


def extract_text(pdf_path):
    """Extract text from PDF using pypdf."""
    try:
        reader = pypdf.PdfReader(str(pdf_path))
        parts = []
        for page in reader.pages:
            text = page.extract_text()
            if text:
                text = text.replace('\x00', '')
                parts.append(text)
        return '\n\n'.join(parts)
    except Exception as e:
        return f"ERROR: {e}"


def main():
    export_dir = Path("mattermost_exports/with_files")
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("publication_texts/mattermost_papers")
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Scanning {export_dir} for Tier 1 papers...\n")

    # Find all PDFs
    candidates = []
    for root, dirs, files in os.walk(export_dir):
        for f in files:
            if not f.lower().endswith('.pdf'):
                continue
            path = Path(root) / f
            size = path.stat().st_size
            if size < 50000:  # Skip tiny files
                continue
            channel = Path(root).name
            title = clean_title(f)
            if should_skip(title):
                continue
            if is_already_ingested(title):
                continue
            if is_high_value(title):
                candidates.append((channel, f, title, path, size))

    # Deduplicate by title similarity
    seen = {}
    unique = []
    for ch, fn, title, path, size in candidates:
        key = re.sub(r'[^a-z0-9]', '', title.lower())[:40]
        if key in seen:
            # Keep larger file
            if size > seen[key][4]:
                idx = next(i for i, u in enumerate(unique) if u[2] == seen[key][2])
                unique[idx] = (ch, fn, title, path, size)
                seen[key] = (ch, fn, title, path, size)
        else:
            seen[key] = (ch, fn, title, path, size)
            unique.append((ch, fn, title, path, size))

    unique.sort(key=lambda x: x[2])
    print(f"Found {len(unique)} Tier 1 papers to extract\n")

    success = 0
    failed = 0
    total_words = 0

    for i, (channel, filename, title, pdf_path, size) in enumerate(unique, 1):
        print(f"[{i}/{len(unique)}] {title} ({size // 1024}K)...", end=" ", flush=True)

        text = extract_text(pdf_path)
        if text.startswith("ERROR:") or len(text) < 100:
            print(f"FAILED: {text[:60]}")
            failed += 1
            continue

        word_count = len(text.split())
        total_words += word_count
        print(f"{word_count} words")

        safe_name = re.sub(r'[^\w\-]', '_', title)[:80]
        record = {
            "meeting_name": title,
            "card_name": f"Raw Data+publications+{title}",
            "transcript_url": f"mattermost://{channel}/{filename}",
            "source_url": f"mattermost://{channel}/{filename}",
            "type": "paper",
            "full_text": text,
            "fetched_at": datetime.now(timezone.utc).isoformat(),
            "word_count": word_count,
            "source_channel": channel,
        }
        json_path = output_dir / f"{safe_name}.json"
        json_path.write_text(
            json.dumps(record, indent=2, ensure_ascii=False),
            encoding='utf-8',
        )
        success += 1

    print(f"\n{'=' * 60}")
    print(f"Extracted: {success}/{len(unique)} papers")
    print(f"Failed: {failed}")
    print(f"Total words: {total_words:,}")
    print(f"Output: {output_dir}")
    print(f"{'=' * 60}")


if __name__ == "__main__":
    main()
