#!/usr/bin/env python3
"""Save Gmail thread JSON data to a file.
Usage: echo '<json>' | python scripts/save_thread.py
Or: python scripts/save_thread.py < file.json
"""
import json
import sys
import os

def save_thread(data, output_dir="raw_data_exports/opencog_threads"):
    """Save thread data to a JSON file named by threadId."""
    os.makedirs(output_dir, exist_ok=True)

    if isinstance(data, str):
        data = json.loads(data)

    thread_id = data.get("threadId", "unknown")
    output_path = os.path.join(output_dir, f"{thread_id}.json")

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    msg_count = len(data.get("messages", []))
    subject = ""
    if data.get("messages"):
        subject = data["messages"][0].get("headers", {}).get("Subject", "")
    print(f"Saved {thread_id} ({msg_count} msgs): {subject[:60]}")
    return output_path

if __name__ == "__main__":
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
        save_thread(data)
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON: {e}", file=sys.stderr)
        sys.exit(1)
