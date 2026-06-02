#!/usr/bin/env python3
"""Fetch full text from free PDF/arXiv links for Hyperon Wiki publications.

Downloads PDFs, extracts text, and outputs JSON files ready for
ingestion as RawData cards via the wiki's MCP tools.

Usage:
    python scripts/fetch_publication_texts.py [--output DIR]
"""

import json
import re
import subprocess
import sys
from pathlib import Path
from datetime import datetime


# All publications with free PDF/arXiv links
PUBLICATIONS = [
    {
        "card_name": "The Hidden Pattern",
        "url": "http://www.goertzel.org/HiddenPattern_march_4_06.pdf",
        "type": "book",
    },
    {
        "card_name": "Probabilistic Logic Networks",
        "url": "http://goertzel.org/PLN_BOOK_6_27_08.pdf",
        "type": "book",
    },
    {
        "card_name": "General Theory of General Intelligence",
        "url": "https://arxiv.org/pdf/2103.15100v3",
        "type": "paper",
    },
    {
        "card_name": "OpenCogPrime Cognitive Synergy",
        "url": "http://goertzel.org/dynapsyc/2009/OpenCogPrime.pdf",
        "type": "paper",
    },
    {
        "card_name": "OpenCog Software Framework",
        "url": "http://www.agiri.org/OpenCog_AGI-08.pdf",
        "type": "paper",
    },
    {
        "card_name": "Nonlinear Dynamical Attention via Information Geometry",
        "url": "http://goertzel.org/ECAN_v3.pdf",
        "type": "paper",
    },
    {
        "card_name": "Economic Attention Networks",
        "url": "http://agi-conf.org/2009/papers/paper_63.pdf",
        "type": "paper",
    },
    {
        "card_name": "Uncertain Spatiotemporal Logic",
        "url": "http://agi-conf.org/2010/wp-content/uploads/2009/06/paper_12.pdf",
        "type": "paper",
    },
    {
        "card_name": "Grounding Possible Worlds Semantics",
        "url": "http://agi-conf.org/2010/wp-content/uploads/2009/06/paper_55.pdf",
        "type": "paper",
    },
    {
        "card_name": "Probabilistic Quantifier Logic",
        "url": "http://www.agiri.org/IndefiniteProbabilities.pdf",
        "type": "paper",
    },
    {
        "card_name": "OpenPsi Cognitive Model",
        "url": "http://goertzel.org/OpenPsi_agi_11.pdf",
        "type": "paper",
    },
    {
        "card_name": "Cognitive Synergy in Animated Agents",
        "url": "http://goertzel.org/Goertzel_AAAI11.pdf",
        "type": "paper",
    },
    {
        "card_name": "Integrative AGI in Minecraft",
        "url": "http://goertzel.org/goertzel_bica_11.pdf",
        "type": "paper",
    },
    {
        "card_name": "Compositional Spatiotemporal Deep Learning",
        "url": "http://goertzel.org/cognitive_systems_2011.pdf",
        "type": "paper",
    },
    {
        "card_name": "NLP Architecture for Embodied AGI",
        "url": "http://agi-conf.org/2010/wp-content/uploads/2009/06/paper_15.pdf",
        "type": "paper",
    },
    {
        "card_name": "OpenCogBot Virtual Agent Control",
        "url": "http://goertzel.org/ICAI_CogSyn_paper.pdf",
        "type": "paper",
    },
    {
        "card_name": "OpenCog NS Hybrid Neural-Symbolic",
        "url": "http://goertzel.org/neurosym.pdf",
        "type": "paper",
    },
    {
        "card_name": "Pragmatic Path to Linguistic AGI",
        "url": "http://www.goertzel.org/new_research/WCCI_AGI.pdf",
        "type": "paper",
    },
    {
        "card_name": "Inferential Dynamics for Virtual Animals",
        "url": "http://novamente.net/AISB08_Goertzel.pdf",
        "type": "paper",
    },
    {
        "card_name": "Teaching Embodied Non-Linguistic Agents",
        "url": "http://www.agiri.org/IRC_Learning.pdf",
        "type": "paper",
    },
    {
        "card_name": "Program Representation for AGI",
        "url": "http://agi-conf.org/2009/papers/paper_69.pdf",
        "type": "paper",
    },
    {
        "card_name": "Solomonoff Universal Induction",
        "url": "http://raysolomonoff.com/publications/chris1.pdf",
        "type": "paper",
    },
    {
        "card_name": "Goedel Incompleteness Theorems",
        "url": "https://monoskop.org/images/9/93/Kurt_G%C3%B6del_On_Formally_Undecidable_Propositions_of_Principia_Mathematica_and_Related_Systems_1992.pdf",
        "type": "paper",
    },
]


def download_pdf(url: str, output_path: Path) -> bool:
    """Download a PDF file using curl."""
    try:
        result = subprocess.run(
            ["curl", "-sL", "-f", "-o", str(output_path), url],
            capture_output=True, timeout=60,
            encoding='utf-8', errors='replace',
        )
        return result.returncode == 0 and output_path.exists() and output_path.stat().st_size > 0
    except subprocess.TimeoutExpired:
        return False


def extract_text_from_pdf(pdf_path: Path) -> str:
    """Extract text from a PDF file using pypdf."""
    try:
        import pypdf
        reader = pypdf.PdfReader(str(pdf_path))
        text_parts = []
        for page in reader.pages:
            text = page.extract_text()
            if text:
                text_parts.append(text)
        return '\n\n'.join(text_parts)
    except Exception as e:
        print(f"    PDF extraction error: {e}")
        return ""


def main():
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("publication_texts")
    pdf_dir = output_dir / "pdfs"
    json_dir = output_dir / "json"
    pdf_dir.mkdir(parents=True, exist_ok=True)
    json_dir.mkdir(parents=True, exist_ok=True)

    print(f"Fetching {len(PUBLICATIONS)} publications...")
    print(f"PDFs: {pdf_dir}")
    print(f"JSON: {json_dir}\n")

    results = []
    for i, pub in enumerate(PUBLICATIONS, 1):
        name = pub["card_name"]
        url = pub["url"]
        print(f"  [{i}/{len(PUBLICATIONS)}] {name}...", end=" ", flush=True)

        # Download PDF
        safe_name = re.sub(r'[^\w\-]', '_', name)
        pdf_path = pdf_dir / f"{safe_name}.pdf"

        if pdf_path.exists() and pdf_path.stat().st_size > 0:
            print("(cached)", end=" ")
        else:
            if not download_pdf(url, pdf_path):
                print("DOWNLOAD FAILED")
                continue

        # Extract text
        text = extract_text_from_pdf(pdf_path)
        if not text or len(text) < 100:
            print(f"EXTRACTION FAILED ({len(text)} chars)")
            continue

        word_count = len(text.split())
        print(f"OK ({word_count} words, {len(text)} chars)")

        # Save JSON
        record = {
            "card_name": f"Raw Data+publications+{name}",
            "publication_card": f"Publications+{name}",
            "source_url": url,
            "type": pub["type"],
            "full_text": text,
            "fetched_at": datetime.utcnow().isoformat() + "Z",
            "word_count": word_count,
        }
        json_path = json_dir / f"{safe_name}.json"
        json_path.write_text(
            json.dumps(record, indent=2, ensure_ascii=False),
            encoding='utf-8',
        )
        results.append(record)

    # Summary
    print(f"\n{'='*60}")
    print(f"Fetched {len(results)}/{len(PUBLICATIONS)} publications")
    print(f"Total words: {sum(r['word_count'] for r in results):,}")
    print(f"Output: {output_dir}")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
