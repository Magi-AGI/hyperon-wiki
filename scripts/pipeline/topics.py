"""Topic keyword map and matching logic for Hyperon Wiki content classification."""

import re
from dataclasses import dataclass


@dataclass
class Topic:
    """A wiki topic with its card name and matching keywords."""
    card_name: str        # e.g. "Hyperon AI Algorithms+PLN"
    display_name: str     # e.g. "PLN"
    keywords: list[str]   # case-insensitive keywords/phrases
    # Compiled regex pattern (built at init)
    _pattern: re.Pattern = None

    def __post_init__(self):
        # Build a compiled regex that matches any keyword as a whole word
        escaped = [re.escape(k) for k in self.keywords]
        self._pattern = re.compile(
            r'\b(?:' + '|'.join(escaped) + r')\b',
            re.IGNORECASE
        )

    def matches(self, text: str) -> list[str]:
        """Return all keyword matches found in text."""
        return self._pattern.findall(text)

    def match_count(self, text: str) -> int:
        """Return number of keyword matches in text."""
        return len(self._pattern.findall(text))


# All Hyperon Wiki topics with their keyword patterns
TOPICS = [
    Topic(
        card_name="MeTTa Programming Language",
        display_name="MeTTa",
        keywords=["metta", "meta-type talk", "atomspace", "metagraph",
                  "homoiconic", "language of thought"],
    ),
    Topic(
        card_name="MeTTa Programming Language+Hyperon Experimental",
        display_name="Hyperon Experimental",
        keywords=["hyperon-experimental", "hyperon experimental",
                  "rust implementation", "python integration", "c api"],
    ),
    Topic(
        card_name="MeTTa Programming Language+PeTTa",
        display_name="PeTTa",
        keywords=["petta", "smart dispatch", "metta-wam", "zip vm",
                  "zip virtual machine"],
    ),
    Topic(
        card_name="MeTTa Programming Language+MeTTaTron",
        display_name="MeTTaTron",
        keywords=["mettatron", "metta-compiler", "f1r3fly compiler"],
    ),
    Topic(
        card_name="MeTTa Programming Language+MeTTaLog",
        display_name="MeTTaLog",
        keywords=["mettalog", "logicmoo", "douglas miles"],
    ),
    Topic(
        card_name="MeTTa Programming Language+JeTTa",
        display_name="JeTTa",
        keywords=["jetta"],
    ),
    Topic(
        card_name="MeTTa Programming Language+MeTTa-Morph",
        display_name="MeTTa-Morph",
        keywords=["metta-morph", "chicken scheme"],
    ),
    Topic(
        card_name="ASI Chain Runtime Environment",
        display_name="ASI Chain",
        keywords=["asi chain", "asi:chain", "blockchain of thought", "blockdag"],
    ),
    Topic(
        card_name="ASI Chain Runtime Environment+F1R3FLY",
        display_name="F1R3FLY",
        keywords=["f1r3fly", "rholang", "rspace", "process calculus"],
    ),
    Topic(
        card_name="ASI Chain Runtime Environment+MeTTa-IL",
        display_name="MeTTa-IL",
        keywords=["metta-il", "intermediate layer", "ocaps",
                  "object-capability"],
    ),
    Topic(
        card_name="ASI Chain Runtime Environment+MeTTaCycle",
        display_name="MeTTaCycle",
        keywords=["mettacycle", "ai layer 0", "chromadb"],
    ),
    Topic(
        card_name="Knowledge Representations+DAS",
        display_name="DAS",
        keywords=["distributed atomspace", "attention broker"],
    ),
    Topic(
        card_name="Knowledge Representations+MORK",
        display_name="MORK",
        keywords=["mork", "trie-map", "radix tree", "zipper abstract machine",
                  "morkl", "sinking"],
    ),
    Topic(
        card_name="Hyperon AI Algorithms+PLN",
        display_name="PLN",
        keywords=["pln", "probabilistic logic network", "truth value",
                  "backward chain", "forward chain", "inference rule"],
    ),
    Topic(
        card_name="Hyperon AI Algorithms+ECAN",
        display_name="ECAN",
        keywords=["ecan", "economic attention", "short-term importance",
                  "long-term importance", "hebbian"],
    ),
    Topic(
        card_name="Hyperon AI Algorithms+MetaMo",
        display_name="MetaMo",
        keywords=["metamo", "openpsi", "motivation", "appraisal",
                  "modulator", "psi demand"],
    ),
    Topic(
        card_name="Hyperon AI Algorithms+Semantic Parsing",
        display_name="Semantic Parsing",
        keywords=["semantic parsing", "senf", "nl2pln", "grounded atoms",
                  "elegant normal form"],
    ),
    Topic(
        card_name="Hyperon AI Algorithms+MeTTa-Motto",
        display_name="MeTTa-Motto",
        keywords=["metta-motto", "motto", "langchain", "retrieval agent",
                  "dialogue agent"],
    ),
    Topic(
        card_name="Hyperon AI Algorithms+MeTTa-NARS",
        display_name="MeTTa-NARS",
        keywords=["metta-nars", "non-axiomatic", "aikr",
                  "frequency confidence", "nars-gpt"],
    ),
    Topic(
        card_name="Hyperon AI Algorithms+NACE",
        display_name="NACE",
        keywords=["nace", "causal explorer", "grid world",
                  "curiosity-driven"],
    ),
    Topic(
        card_name="Hyperon AI Algorithms+AI-DSL",
        display_name="AI-DSL",
        keywords=["ai-dsl", "program synthesizer", "combinatory logic",
                  "bluebird", "phoenix combinator"],
    ),
    Topic(
        card_name="Hyperon AI Algorithms+MOSES",
        display_name="MOSES",
        keywords=["moses", "meta-optimizing", "evolutionary search",
                  "deme", "elegant normal form", "enf"],
    ),
    Topic(
        card_name="Hyperon AI Algorithms+AIRIS",
        display_name="AIRIS",
        keywords=["airis", "berick cook", "causal rewrite"],
    ),
    Topic(
        card_name="Cognitive Architectures+PRIMUS",
        display_name="PRIMUS",
        keywords=["primus", "cogprime", "cognitive synergy",
                  "meta-architecture"],
    ),
    Topic(
        card_name="Cognitive Architectures+MeTTaClaw",
        display_name="MeTTaClaw",
        keywords=["mettaclaw", "agent loop", "skill acquisition"],
    ),
    Topic(
        card_name="Cognitive Architectures+HyperClaw",
        display_name="HyperClaw",
        keywords=["hyperclaw", "attention-metaprotocol", "context frame",
                  "module-space"],
    ),
]


def find_topics(text: str, min_matches: int = 1) -> list[tuple[Topic, int]]:
    """Find all topics mentioned in text.

    Returns list of (topic, match_count) tuples sorted by match count
    descending, filtered to topics with at least min_matches.
    """
    results = []
    for topic in TOPICS:
        count = topic.match_count(text)
        if count >= min_matches:
            results.append((topic, count))
    return sorted(results, key=lambda x: x[1], reverse=True)


def primary_topic(text: str) -> Topic | None:
    """Return the single most-matched topic, or None if no matches."""
    matches = find_topics(text, min_matches=1)
    return matches[0][0] if matches else None
