"""Topic extraction and classification for conversational content."""

import re
from dataclasses import dataclass, field
from .topics import Topic, find_topics


@dataclass
class Extract:
    """A classified content extract from a conversational source."""
    topic: Topic
    text: str
    extract_type: str   # "technical", "decision", "status", "roadmap", "discussion"
    signal: str         # "high" or "low"
    source_context: str = ""  # e.g. channel name, transcript name


@dataclass
class ExtractionResult:
    """Grouped extracts from a single source, organized by topic."""
    source_name: str
    extracts_by_topic: dict[str, list[Extract]] = field(default_factory=dict)
    unmatched_count: int = 0

    def add(self, extract: Extract):
        key = extract.topic.display_name
        if key not in self.extracts_by_topic:
            self.extracts_by_topic[key] = []
        self.extracts_by_topic[key].append(extract)

    @property
    def total_extracts(self) -> int:
        return sum(len(v) for v in self.extracts_by_topic.values())

    @property
    def high_signal_count(self) -> int:
        return sum(
            1 for exts in self.extracts_by_topic.values()
            for e in exts if e.signal == "high"
        )


# Patterns indicating high-signal content
HIGH_SIGNAL_PATTERNS = [
    re.compile(r'\b(implement|design|architect|decision|decided|chosen|approach)\b', re.I),
    re.compile(r'\b(roadmap|milestone|deadline|release|shipped|merged)\b', re.I),
    re.compile(r'\b(bug|fix|issue|problem|solution|workaround|root cause)\b', re.I),
    re.compile(r'\b(benchmark|performance|speedup|optimization|latency)\b', re.I),
    re.compile(r'\b(paper|publication|arxiv|research|thesis)\b', re.I),
    re.compile(r'\b(api|interface|protocol|specification|spec)\b', re.I),
    re.compile(r'https?://github\.com/', re.I),
]

# Patterns indicating low-signal content
LOW_SIGNAL_PATTERNS = [
    re.compile(r'^\s*(hi|hello|hey|thanks|thank you|ok|okay|sure|np|lol)\s*$', re.I),
    re.compile(r'^\s*\+1\s*$'),
    re.compile(r'^\s*@\w+\s*$'),  # bare mentions
]

# Type classification patterns
TYPE_PATTERNS = {
    "decision": re.compile(r'\b(decided|decision|agreed|consensus|chose|chosen|we will|going to)\b', re.I),
    "roadmap": re.compile(r'\b(roadmap|plan|milestone|timeline|target|goal|next step|todo)\b', re.I),
    "status": re.compile(r'\b(update|progress|status|done|completed|finished|working on|started)\b', re.I),
    "technical": re.compile(r'\b(implement|algorithm|function|module|class|type|struct|compile|execute|runtime)\b', re.I),
}


def _classify_signal(text: str) -> str:
    """Classify whether a text chunk is high or low signal."""
    for pat in LOW_SIGNAL_PATTERNS:
        if pat.search(text):
            return "low"
    for pat in HIGH_SIGNAL_PATTERNS:
        if pat.search(text):
            return "high"
    # Default: high if substantial text, low if short
    return "high" if len(text.split()) > 20 else "low"


def _classify_type(text: str) -> str:
    """Classify the type of content in a text chunk."""
    for type_name, pat in TYPE_PATTERNS.items():
        if pat.search(text):
            return type_name
    return "discussion"


def _split_into_chunks(text: str, chunk_size: int = 500) -> list[str]:
    """Split text into paragraph-level chunks for topic matching.

    Tries to split on double newlines (paragraphs) first, falling back
    to single newlines, then to fixed-size chunks.
    """
    # Split on double newlines (paragraphs)
    paragraphs = re.split(r'\n\s*\n', text)

    chunks = []
    for para in paragraphs:
        para = para.strip()
        if not para:
            continue
        if len(para) <= chunk_size:
            chunks.append(para)
        else:
            # Split long paragraphs on single newlines
            lines = para.split('\n')
            current = []
            current_len = 0
            for line in lines:
                if current_len + len(line) > chunk_size and current:
                    chunks.append('\n'.join(current))
                    current = []
                    current_len = 0
                current.append(line)
                current_len += len(line)
            if current:
                chunks.append('\n'.join(current))

    return chunks


def extract_topics(text: str, source_name: str,
                   min_signal: str = "high") -> ExtractionResult:
    """Extract topic-classified content from raw conversational text.

    Args:
        text: Raw text content (Mattermost messages, transcript, etc.)
        source_name: Name of the source for attribution
        min_signal: Minimum signal level to include ("high" or "low")

    Returns:
        ExtractionResult with extracts grouped by topic
    """
    result = ExtractionResult(source_name=source_name)
    chunks = _split_into_chunks(text)

    for chunk in chunks:
        topics = find_topics(chunk, min_matches=1)
        if not topics:
            result.unmatched_count += 1
            continue

        signal = _classify_signal(chunk)
        if min_signal == "high" and signal == "low":
            continue

        extract_type = _classify_type(chunk)

        # Assign to all matched topics (a chunk can be relevant to multiple)
        for topic, _count in topics:
            extract = Extract(
                topic=topic,
                text=chunk,
                extract_type=extract_type,
                signal=signal,
                source_context=source_name,
            )
            result.add(extract)

    return result


def format_extracts_as_html(extracts: list[Extract], source_name: str) -> str:
    """Format a list of extracts as HTML content for a RawData card."""
    lines = [
        f'<p><strong>Source:</strong> {source_name}</p>',
        f'<p><strong>Extract count:</strong> {len(extracts)}</p>',
        '<hr>',
    ]
    for i, ext in enumerate(extracts, 1):
        badge = f'[{ext.extract_type}]' if ext.extract_type != "discussion" else ""
        lines.append(f'<h4>Extract {i} {badge}</h4>')
        # Escape HTML in the raw text
        safe_text = (ext.text
                     .replace('&', '&amp;')
                     .replace('<', '&lt;')
                     .replace('>', '&gt;'))
        lines.append(f'<pre>{safe_text}</pre>')

    return '\n'.join(lines)
