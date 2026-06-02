#!/usr/bin/env python
"""Batch save Gmail thread data from a JSON array of thread responses.

Usage: python scripts/batch_save_threads.py < threads_batch.json
Input: JSON array of thread objects, each with threadId and messages.
"""
import json
import sys
import os

def main():
    output_dir = "raw_data_exports/opencog_threads"
    os.makedirs(output_dir, exist_ok=True)

    raw = sys.stdin.buffer.read().decode('utf-8')
    threads = json.loads(raw)

    if isinstance(threads, dict):
        threads = [threads]

    for thread in threads:
        tid = thread.get("threadId", "unknown")
        path = os.path.join(output_dir, f"{tid}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(thread, f, indent=2, ensure_ascii=False)
        msg_count = len(thread.get("messages", []))
        subject = ""
        if thread.get("messages"):
            subject = thread["messages"][0].get("headers", {}).get("Subject", "")[:60]
        print(f"  Saved {tid} ({msg_count} msgs): {subject}")

    print(f"\nTotal: {len(threads)} threads saved")

if __name__ == "__main__":
    main()
