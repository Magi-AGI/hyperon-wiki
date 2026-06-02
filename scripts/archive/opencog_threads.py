#!/usr/bin/env python
"""Parse OpenCog mailing list Gmail search results and group messages by thread.

Reads the Gmail API search results JSON, groups messages by threadId,
filters out spam, and writes a thread map to raw_data_exports/.

Usage:
    python scripts/opencog_threads.py
"""

import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path

# ============================================================
# Source data path (Gmail search results exported via MCP)
# ============================================================

SOURCE_FILE = (
    r"C:\Users\Lake\.claude\projects\E--GitHub-Magi-AGI-hyperon-wiki"
    r"\827ed565-5163-4d80-99c5-82951c4f457c\tool-results"
    r"\mcp-claude_ai_Gmail-gmail_search_messages-1775635613963.txt"
)

OUTPUT_DIR = Path(__file__).resolve().parent.parent / "raw_data_exports"
OUTPUT_FILE = OUTPUT_DIR / "opencog_thread_map.json"

# ============================================================
# Spam filtering
# ============================================================

SPAM_SUBJECT_KEYWORDS = [
    r"crack", r"download", r"songs", r"patch", r"pharmaceuticals",
    r"psychedelics", r"sale", r"berlusconi", r"mushroom",
    r"roxicodone", r"methadone", r"oxycontin", r"adderall",
    r"psilocybin", r"dmt\b", r"vape", r"edibles",
    r"chocolate\s+bar",
]

SPAM_SENDERS = [
    "voncaleb60@gmail.com",
]


def is_spam(subject, sender_email):
    """Return True if the message looks like spam."""
    subj_lower = subject.lower()
    for kw in SPAM_SUBJECT_KEYWORDS:
        if re.search(kw, subj_lower):
            return True
    sender_lower = sender_email.lower()
    for addr in SPAM_SENDERS:
        if addr in sender_lower:
            return True
    return False


def parse_sender_email(from_header):
    """Extract bare email address from a From header value."""
    match = re.search(r"<([^>]+)>", from_header)
    if match:
        return match.group(1)
    # Bare address without angle brackets
    match = re.search(r"[\w.\-+]+@[\w.\-]+", from_header)
    if match:
        return match.group(0)
    return from_header


def epoch_ms_to_iso(epoch_ms_str):
    """Convert epoch milliseconds string to ISO 8601 date string."""
    ts = int(epoch_ms_str) / 1000.0
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main():
    # ----------------------------------------------------------
    # 1. Load source data
    # ----------------------------------------------------------
    print(f"Reading source file: {SOURCE_FILE}")
    with open(SOURCE_FILE, "r", encoding="utf-8") as f:
        wrapper = json.load(f)

    # The file is an MCP tool-result wrapper: [{type: "text", text: "<json>"}]
    inner = json.loads(wrapper[0]["text"])
    messages = inner["messages"]
    print(f"Loaded {len(messages)} messages")

    # ----------------------------------------------------------
    # 2. Group messages by threadId
    # ----------------------------------------------------------
    threads = {}
    for msg in messages:
        tid = msg["threadId"]
        if tid not in threads:
            threads[tid] = []
        threads[tid].append(msg)

    print(f"Found {len(threads)} unique threads")

    # ----------------------------------------------------------
    # 3. Filter out spam threads
    # ----------------------------------------------------------
    # A thread is spam if ANY message in it matches spam criteria
    legitimate = {}
    spam_count = 0
    for tid, thread_msgs in threads.items():
        thread_is_spam = False
        for msg in thread_msgs:
            subject = msg["headers"].get("Subject", "")
            from_header = msg["headers"].get("From", "")
            sender_email = parse_sender_email(from_header)
            if is_spam(subject, sender_email):
                thread_is_spam = True
                break
        if thread_is_spam:
            spam_count += 1
        else:
            legitimate[tid] = thread_msgs

    print(f"Filtered out {spam_count} spam threads, {len(legitimate)} legitimate remain")

    # ----------------------------------------------------------
    # 4. Build thread objects
    # ----------------------------------------------------------
    thread_objects = []
    for tid, thread_msgs in legitimate.items():
        # Sort messages by internalDate (ascending) to find earliest/latest
        thread_msgs.sort(key=lambda m: int(m["internalDate"]))

        earliest = thread_msgs[0]
        latest = thread_msgs[-1]

        # Subject from the first (earliest) message
        subject = earliest["headers"].get("Subject", "(no subject)")
        # Strip mailing list prefixes like [opencog-dev], Re:, Fwd:
        clean_subject = re.sub(
            r"^(Re:\s*|Fwd?:\s*|\[[\w\-]+\]\s*)+", "", subject, flags=re.IGNORECASE
        ).strip()
        if not clean_subject:
            clean_subject = subject

        # Collect unique senders
        senders = []
        seen_senders = set()
        for msg in thread_msgs:
            from_header = msg["headers"].get("From", "")
            email = parse_sender_email(from_header)
            if email.lower() not in seen_senders:
                seen_senders.add(email.lower())
                senders.append(from_header.strip())

        thread_obj = {
            "threadId": tid,
            "subject": clean_subject,
            "messageIds": [m["messageId"] for m in thread_msgs],
            "messageCount": len(thread_msgs),
            "dateRange": {
                "earliest": epoch_ms_to_iso(earliest["internalDate"]),
                "latest": epoch_ms_to_iso(latest["internalDate"]),
            },
            "senders": senders,
        }
        thread_objects.append(thread_obj)

    # ----------------------------------------------------------
    # 5. Sort by date (newest first, using latest message date)
    # ----------------------------------------------------------
    thread_objects.sort(
        key=lambda t: t["dateRange"]["latest"],
        reverse=True,
    )

    # ----------------------------------------------------------
    # 6. Write output
    # ----------------------------------------------------------
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(thread_objects, f, indent=2, ensure_ascii=False)

    print(f"\nWrote {len(thread_objects)} threads to {OUTPUT_FILE}")
    print(f"Total messages across legitimate threads: {sum(t['messageCount'] for t in thread_objects)}")

    # Quick summary of top threads by message count
    print("\nTop 10 threads by message count:")
    by_count = sorted(thread_objects, key=lambda t: t["messageCount"], reverse=True)
    for t in by_count[:10]:
        print(f"  [{t['messageCount']:3d} msgs] {t['subject'][:70]}")


if __name__ == "__main__":
    main()
