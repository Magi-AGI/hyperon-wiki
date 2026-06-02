"""Source readers for the raw data pipeline.

Connectors to pull content directly from source platforms.
The Mattermost connector wraps the existing MattermostExporter from
the magi-archive repo.
"""

import json
import subprocess
import sys
from pathlib import Path
from datetime import datetime
from typing import Optional


# ---------------------------------------------------------------------------
# Mattermost — wraps existing MattermostExporter from magi-archive repo
# ---------------------------------------------------------------------------

MAGI_ARCHIVE_REPO = Path(__file__).resolve().parents[2].parent / "magi-archive"

# Channels relevant to the Hyperon Wiki
HYPERON_CHANNELS = [
    "Hyperon", "hyperon-agi-meetup", "MeTTaLog", "MeTTa-tutorials",
    "MeTTa-Lang Scratchpad", "metta-convergence", "MeTTa vibe coding",
    "AGI-24 OC Hyperon Workshop planning", "DEEP Funding -  hyperon round",
    "PLN", "Desi's Hyperon memory",
]


def _get_mattermost_exporter():
    """Import and return the MattermostExporter class from magi-archive."""
    exporter_path = MAGI_ARCHIVE_REPO / "mattermost_export.py"
    if not exporter_path.exists():
        raise FileNotFoundError(
            f"MattermostExporter not found at {exporter_path}. "
            f"Expected the magi-archive repo at {MAGI_ARCHIVE_REPO}"
        )
    # Add magi-archive to path so we can import
    if str(MAGI_ARCHIVE_REPO) not in sys.path:
        sys.path.insert(0, str(MAGI_ARCHIVE_REPO))
    from mattermost_export import MattermostExporter
    return MattermostExporter


def fetch_mattermost_channels(
    token: str,
    host: str = "chat.singularitynet.io",
    channel_filter: Optional[list[str]] = None,
    after: Optional[datetime] = None,
    output_dir: Optional[Path] = None,
) -> list[dict]:
    """Fetch channels from Mattermost and return raw JSON data.

    Args:
        token: MMAUTHTOKEN for authentication
        host: Mattermost server hostname
        channel_filter: If provided, only export channels whose display_name
                       contains one of these strings (case-insensitive)
        after: Only fetch posts after this datetime
        output_dir: Where to save JSON exports. Defaults to
                   mattermost_exports/hyperon_wiki_{timestamp}

    Returns:
        List of channel export dicts (same format as mattermost_export.py)
    """
    Exporter = _get_mattermost_exporter()

    exporter = Exporter(host=host, token=token)
    exporter.initialize_user_data()

    if output_dir is None:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_dir = Path("mattermost_exports") / f"hyperon_wiki_{timestamp}"
    output_dir.mkdir(parents=True, exist_ok=True)

    teams = exporter.list_teams()
    results = []

    for team in teams:
        channels = exporter.list_channels(team["id"])

        if channel_filter:
            filter_lower = [f.lower() for f in channel_filter]
            channels = [
                c for c in channels
                if any(f in c["display_name"].lower() for f in filter_lower)
            ]

        for channel in channels:
            try:
                exporter.export_channel(
                    channel, output_dir,
                    download_files=False,  # Skip files for raw data cards
                    after=after,
                )
                # Read back the exported JSON
                channel_name = channel["display_name"].replace("/", "_").replace("\\", "_")
                json_files = list(output_dir.rglob(f"*{channel_name}*.json"))
                if json_files:
                    data = json.loads(json_files[0].read_text(encoding="utf-8"))
                    results.append(data)
            except Exception as e:
                print(f"  Error exporting {channel['display_name']}: {e}")

    return results


def mattermost_channel_to_raw_text(channel_data: dict) -> str:
    """Convert a Mattermost channel export dict to complete raw text.

    Preserves ALL content — no filtering, no truncation.
    Includes thread structure with indented replies.
    """
    channel = channel_data.get("channel", {})
    posts = channel_data.get("posts", [])
    threads = channel_data.get("threads", {})

    lines = [
        f"# {channel.get('display_name', 'Unknown Channel')}",
        f"Type: {channel.get('type', '?')}",
        f"Exported: {channel.get('exported_at', 'unknown')}",
        f"Posts: {channel.get('post_count', len(posts))}",
        f"Threads: {channel.get('thread_count', len(threads))}",
        f"Purpose: {channel.get('purpose', '')}",
        f"Header: {channel.get('header', '')}",
        "",
        "---",
        "",
    ]

    for post in posts:
        if post.get("is_reply"):
            continue  # Replies are shown under their parent via threads

        lines.append(f"**{post.get('username', '?')}** ({post.get('created', '?')})")
        lines.append(post.get("message", ""))

        # Add thread replies inline
        post_id = post.get("id", "")
        if post_id in threads:
            for reply in threads[post_id]:
                lines.append(f"  > **{reply.get('username', '?')}** ({reply.get('created', '?')})")
                for reply_line in reply.get("message", "").split("\n"):
                    lines.append(f"  > {reply_line}")
                lines.append("")

        lines.append("")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Google Doc
# ---------------------------------------------------------------------------

MASTER_DOC_ID = "1keyCp-gOPBBuhRJhhtSd5kSJccidG-CAokg8Xq37wtU"


def fetch_google_doc(doc_id: str) -> str:
    """Fetch a Google Doc as plain text via export URL."""
    url = f"https://docs.google.com/document/d/{doc_id}/export?format=txt"
    try:
        result = subprocess.run(
            ["curl", "-s", "-L", url],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0:
            return result.stdout
    except subprocess.TimeoutExpired:
        pass
    return ""


# ---------------------------------------------------------------------------
# GitHub
# ---------------------------------------------------------------------------

def fetch_github_readme(org: str, repo: str, branch: str = "main") -> str:
    """Fetch a GitHub repository README."""
    for b in [branch, "master"]:
        url = f"https://raw.githubusercontent.com/{org}/{repo}/{b}/README.md"
        try:
            result = subprocess.run(
                ["curl", "-s", "-L", "-f", url],
                capture_output=True, text=True, timeout=15
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout
        except subprocess.TimeoutExpired:
            continue
    return ""


# ---------------------------------------------------------------------------
# Generic web fetch
# ---------------------------------------------------------------------------

def fetch_web_page(url: str) -> str:
    """Fetch a web page and return its raw content."""
    try:
        result = subprocess.run(
            ["curl", "-s", "-L", url],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0:
            return result.stdout
    except subprocess.TimeoutExpired:
        pass
    return ""
