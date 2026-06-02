#!/usr/bin/env python
"""
Parse Read.ai meeting report data and create JSON files for wiki ingestion.

Creates JSON files in publication_texts/readai_reports/ that can be ingested
into the Hyperon Wiki as RawData transcript cards via ingest_transcripts.rb.

Usage:
    python scripts/parse_readai_reports.py
"""

import json
import os
from datetime import datetime, timezone

# Output directory
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "publication_texts", "readai_reports")

# ---------------------------------------------------------------------------
# Hardcoded Read.ai meeting report data (extracted from Gmail)
# ---------------------------------------------------------------------------

REPORTS = [
    {
        "date": "2026-04-03",
        "summary": (
            "The meeting convened to share recent tooling updates, developer "
            "experiences, and runtime improvements across Meta, PETA, Hyperon, "
            "and related extensions."
        ),
        "chapters": [
            "Data-structure features/REPRA",
            "Example applications",
            "Supporting libraries",
            "LLM/ChromaDB updates",
            "Configuration/interop",
            "Mork/PETA interleaving",
            "Live demo",
            "Zarathustra experiments",
            "Command-line args",
            "Language-spec feedback",
            "Feature requests/CETA",
            "LSP implementations",
            "Debugging output ordering",
            "PETA release activity",
            "VS Code extension",
        ],
        "action_items": [
            "Suzanne find VS Code extension",
            "Zarathustra explore MM2/PETA interleaving",
            "Implement import tracking",
            "Add static input detection",
            "Zarathustra continue CETA work",
            "Patrick show PRs",
        ],
        "key_questions": [
            "How should MM2/PETA interleaving be handled?",
            "Why is println ordering inconsistent in debugging output?",
            "What progress has been made on Meta experimentation?",
            "What is the current status of CETA progress?",
        ],
        "top_talkers": [
            {"name": "Patrick Hammer", "percentage": 50},
            {"name": "Matthew Ikle", "percentage": 14},
            {"name": "Zarathustra Goertzel", "percentage": 11},
        ],
    },
    {
        "date": "2026-02-20",
        "summary": (
            "The meeting reviewed recent work on inference tooling and ontology "
            "representations for MeTTa-related projects, including a technical "
            "demo and conceptual discussion of type-theoretic subtyping for "
            "service composition."
        ),
        "chapters": [
            "Tooling/Peta discussion",
            "Generated proof demo",
            "LLMs/ontologies",
            "Ontology/subtypes/PLN",
            "Scaling symbols/inheritance",
            "Proofs/coercion",
            "Automating subtypes",
            "Backward chainer demo",
            "Synthesis/ontology provenance",
            "Subtyping axioms",
            "Types/AI service composition",
        ],
        "action_items": [],
        "key_questions": [
            "How should ontology handling be approached in MeTTa?",
            "What inference-control rules are needed for proof generation?",
            "Can you show concrete proof examples from the demo?",
        ],
        "top_talkers": [
            {"name": "Robert Wunsche", "percentage": 73},
            {"name": "Nil Geisweiller", "percentage": 18},
            {"name": "Sebastiaan Wiechers", "percentage": 8},
        ],
    },
    {
        "date": "2026-02-06",
        "summary": (
            "The discussion centered on various computational tools and "
            "libraries that enhance the efficiency of long-running computations "
            "and the integration of large language models."
        ),
        "chapters": [
            "Serialization updates",
            "Snapshot library",
            "Snapshot management",
            "Current projects",
            "Local VLM library",
            "LLM function generation",
            "Metafiles/LLM",
            "OpenClaw/OpenCLR integration",
            "Neurological systems/semantic parsing",
        ],
        "action_items": [
            "Khellar express needs to Greg",
            "Patrick inform Greg about serialization",
            "Khellar discuss M-Labs milestones",
            "Patrick demo snapshot library",
        ],
        "key_questions": [],
        "top_talkers": [
            {"name": "Patrick Hammer", "percentage": 54},
            {"name": "Nil", "percentage": 11},
            {"name": "Matthew Ikle", "percentage": 11},
        ],
    },
    {
        "date": "2026-01-23",
        "summary": (
            "The session focused on the integration of MetaMath with TrueAI, "
            "with Nil Geisweiller presenting his progress on a project "
            "involving a subset of the set theory corpus."
        ),
        "chapters": [
            "Type checking Prolog/Meta",
            "Meta language features",
            "Future tutorials",
            "MetaMath/TrueAI updates",
            "Proof discovery in propositional calculus",
            "LLM integration/mathematical reasoning",
            "Data collection",
        ],
        "action_items": [
            "Nil run program over weekend",
            "Patrick setup meta-study sessions",
            "Peter schedule type checking call",
            "Nil update TrueAI repo",
        ],
        "key_questions": [],
        "top_talkers": [
            {"name": "Nil Geisweiller", "percentage": 48},
            {"name": "Douglas Miles", "percentage": 29},
            {"name": "Patrick Hammer", "percentage": 18},
        ],
    },
    {
        "date": "2026-01-09",
        "summary": (
            "The group focused on updates and developments related to the "
            "MeTTa project, with Nil Geisweiller discussing his coding efforts "
            "in collaboration with Peter and addressing several issues for "
            "Patrick."
        ),
        "chapters": [
            "Dataset development",
            "Core functions/logic",
            "Progress updates",
            "Backward chaining/proof construction",
            "Backward chaining/proof abstraction",
        ],
        "action_items": [
            "Sebastiaan share Hugging Face dataset",
            "Sebastiaan improve dataset",
            "Nil show backward chaining",
            "Matthew talk to Keller",
        ],
        "key_questions": [],
        "top_talkers": [
            {"name": "Nil Geisweiller", "percentage": 46},
            {"name": "Sebastiaan Wiechers", "percentage": 36},
            {"name": "Matthew Ikle", "percentage": 12},
        ],
    },
    {
        "date": "2025-12-12",
        "summary": (
            "The session focused on the MeTTa Study Group, where participants "
            "introduced themselves and discussed various technical aspects "
            "related to the development of Meta and its implementations."
        ),
        "chapters": [
            "Prolog optimization",
            "Code generation issues",
            "Participant introductions",
            "Meta/Prolog implementations",
            "Meta/PETA programming",
            "PETA/Metatron development",
        ],
        "action_items": [
            "Matthew share PETA repo link",
            "Matthew leave chat open",
            "Shivaji explore PETA repo",
        ],
        "key_questions": [],
        "top_talkers": [
            {"name": "Matthew Ikle", "percentage": 35},
            {"name": "Alexey Potapov", "percentage": 17},
            {"name": "Zarathustra Goertzel", "percentage": 12},
        ],
    },
    {
        "date": "2025-11-28",
        "summary": (
            "The discussion centered on the private status of the "
            "documentation source code for the metal Glenn site, with Ivan "
            "expressing a desire to correct typos."
        ),
        "chapters": [
            "Hyperion Experimental/Beta specs",
            "Atom evaluation",
            "Minimal Meta/Meta-interpreter",
            "Variable evaluation",
            "Documentation/atom space design",
            "Atom matching/data visualization",
        ],
        "action_items": [
            "Vitaly send email to Ivan",
            "Vitaly write documentation paragraphs",
            "Vitaly raise PR for docs",
            "Vitaly ask about making repo public",
        ],
        "key_questions": [],
        "top_talkers": [
            {"name": "Vitaly Bogdanov", "percentage": 53},
            {"name": "Patrick Hammer", "percentage": 21},
            {"name": "Ivan Karlovich", "percentage": 19},
        ],
    },
    {
        "date": "2025-11-14",
        "summary": (
            "The discussion focused on updates and collaborative projects "
            "related to the MeTTa programming language and its implementation, "
            "Hyperion Experimental."
        ),
        "chapters": [
            "Updates/technical challenges",
            "MeTTa/Hyperion training",
            "PETA/future discussions",
        ],
        "action_items": [
            "Matthew look into STEM project",
            "Colleen inform about Delphi",
            "Vitaly finish Hyperion spec",
        ],
        "key_questions": [],
        "top_talkers": [
            {"name": "Matthew Ikle", "percentage": 60},
            {"name": "Vitaly Bogdanov", "percentage": 27},
            {"name": "Colleen Pridemore", "percentage": 6},
        ],
    },
    {
        "date": "2025-10-31",
        "summary": (
            "The discussion focused on the quoting mechanism in Heparin "
            "Experimental, with Patrick Hammer questioning the rationale "
            "behind the quote remaining unevaluated alongside the expression."
        ),
        "chapters": [
            "Quoting/mapping/lambda functions",
        ],
        "action_items": [
            "Alexey look at map atom/lambda issues",
            "Patrick try running PETA code",
        ],
        "key_questions": [],
        "top_talkers": [
            {"name": "Patrick Hammer", "percentage": 59},
            {"name": "Alexey Potapov", "percentage": 41},
        ],
    },
]


def format_full_text(report):
    """Build the full_text field as clean readable text."""
    date = report["date"]
    lines = []

    lines.append("MeTTa Study Group - Read.ai Meeting Report")
    lines.append(f"Date: {date}")
    lines.append("")

    # Summary
    lines.append("SUMMARY")
    lines.append(report["summary"])
    lines.append("")

    # Chapters & Topics
    lines.append("CHAPTERS & TOPICS")
    for i, chapter in enumerate(report["chapters"], 1):
        lines.append(f"  {i}. {chapter}")
    lines.append("")

    # Action Items
    if report["action_items"]:
        lines.append("ACTION ITEMS")
        for item in report["action_items"]:
            lines.append(f"  - {item}")
        lines.append("")

    # Key Questions
    if report["key_questions"]:
        lines.append("KEY QUESTIONS")
        for q in report["key_questions"]:
            lines.append(f"  - {q}")
        lines.append("")

    # Speaker Analytics
    lines.append("SPEAKER ANALYTICS")
    for talker in report["top_talkers"]:
        lines.append(f"  - {talker['name']}: {talker['percentage']}%")
    lines.append("")

    return "\n".join(lines)


def count_words(text):
    """Count words in a text string."""
    return len(text.split())


def build_json(report):
    """Build the JSON object for a single report."""
    date = report["date"]
    meeting_name = f"MeTTa Study Group Read.ai {date}"
    card_name = f"Raw Data+transcripts+MeTTa Study Group Read.ai+{date}"
    full_text = format_full_text(report)

    return {
        "meeting_name": meeting_name,
        "card_name": card_name,
        "date": date,
        "source_service": "read.ai",
        "transcript_url": "read.ai",
        "summary": report["summary"],
        "action_items": report["action_items"],
        "key_questions": report["key_questions"],
        "chapters": report["chapters"],
        "top_talkers": report["top_talkers"],
        "participants": [t["name"] for t in report["top_talkers"]],
        "full_text": full_text,
        "word_count": count_words(full_text),
    }


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print(f"Generating Read.ai report JSON files")
    print(f"Output directory: {OUTPUT_DIR}")
    print(f"Reports to create: {len(REPORTS)}")
    print()

    created = []
    for report in REPORTS:
        data = build_json(report)
        date = report["date"]
        filename = f"{date}_MeTTa_Study_Group_ReadAI.json"
        filepath = os.path.join(OUTPUT_DIR, filename)

        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)

        word_count = data["word_count"]
        text_len = len(data["full_text"])
        print(f"  Created: {filename} ({word_count} words, {text_len} chars)")
        created.append(filepath)

    # Write a summary file
    summary = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "total_reports": len(created),
        "files": [os.path.basename(f) for f in created],
    }
    summary_path = os.path.join(OUTPUT_DIR, "export_summary.json")
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2, ensure_ascii=False)

    print()
    print(f"Done. Created {len(created)} JSON files + export_summary.json")
    print(f"Output: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
