"""Card writer for creating/updating RawData cards on the Hyperon Wiki."""

import json
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path


def _wiki_api(method: str, path: str, data: dict = None) -> dict | None:
    """Make an API call to the Hyperon Wiki Decko instance.

    Uses curl with the Decko JSON API. For large payloads, writes to a
    temp file to avoid Windows command-line length limits.
    """
    url = f"https://wiki.hyperon.dev/{path}"
    cmd = ["curl", "-s", "-L"]

    if method == "GET":
        cmd.append(url + ".json")
    elif method in ("POST", "PUT", "PATCH"):
        cmd.extend(["-X", method.upper()])
        cmd.extend(["-H", "Content-Type: application/json"])
        if data:
            # Write data to temp file to avoid command-line length limits
            with tempfile.NamedTemporaryFile(
                mode='w', suffix='.json', delete=False, encoding='utf-8'
            ) as f:
                json.dump(data, f, ensure_ascii=False)
                tmpfile = f.name
            cmd.extend(["-d", f"@{tmpfile}"])
        cmd.append(url + ".json")

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if result.returncode == 0 and result.stdout.strip():
            return json.loads(result.stdout)
    except (subprocess.TimeoutExpired, json.JSONDecodeError):
        pass
    finally:
        # Clean up temp file if created
        if data and 'tmpfile' in locals():
            try:
                Path(tmpfile).unlink(missing_ok=True)
            except OSError:
                pass

    return None


def card_exists(card_name: str) -> bool:
    """Check if a card exists on the Hyperon Wiki."""
    url_name = card_name.replace(' ', '_').replace('+', '+')
    result = _wiki_api("GET", url_name)
    return result is not None and "error" not in str(result).lower()


def create_raw_data_card(card_name: str, content: str) -> bool:
    """Create a new RawData card on the Hyperon Wiki.

    Args:
        card_name: Full card name (e.g. "Raw Data+mattermost+PLN")
        content: HTML content for the card

    Returns:
        True if created successfully
    """
    data = {
        "card": {
            "name": card_name,
            "type": "RawData",
            "content": content,
        }
    }
    result = _wiki_api("POST", "", data)
    return result is not None


def update_raw_data_card(card_name: str, new_content: str,
                         append: bool = True) -> bool:
    """Update an existing RawData card.

    Args:
        card_name: Full card name
        new_content: New HTML content
        append: If True, append to existing content with a separator.
                If False, replace entirely.

    Returns:
        True if updated successfully
    """
    url_name = card_name.replace(' ', '_').replace('+', '+')

    if append:
        existing = _wiki_api("GET", url_name)
        if existing and "content" in existing:
            timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
            separator = f'\n<hr>\n<p><strong>Updated:</strong> {timestamp}</p>\n'
            new_content = existing["content"] + separator + new_content

    data = {"card": {"content": new_content}}
    result = _wiki_api("PATCH", url_name, data)
    return result is not None


def write_raw_data(source_type: str, topic_name: str, content: str) -> str:
    """Write a RawData card, creating or appending as needed.

    Args:
        source_type: Source category (e.g. "mattermost", "transcripts", "github")
        topic_name: Topic display name (e.g. "PLN", "ECAN")
        content: HTML content to write

    Returns:
        The card name that was written to
    """
    card_name = f"Raw Data+{source_type}+{topic_name}"

    if card_exists(card_name):
        update_raw_data_card(card_name, content, append=True)
    else:
        create_raw_data_card(card_name, content)

    return card_name
