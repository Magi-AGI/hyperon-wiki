import json
import os

TRACKER_FILE = 'uploaded_tids.json'
BATCH_TIDS_FILE = 'batch_tids.json'
FAILED_TID = '14aebed6f893acd8'

if os.path.exists(TRACKER_FILE):
    with open(TRACKER_FILE, 'r', encoding='utf-8') as f:
        tracker = set(json.load(f))
else:
    tracker = set()

if os.path.exists(BATCH_TIDS_FILE):
    with open(BATCH_TIDS_FILE, 'r', encoding='utf-8') as f:
        batch = json.load(f)
    for tid in batch:
        if tid != FAILED_TID:
            tracker.add(tid)

with open(TRACKER_FILE, 'w', encoding='utf-8') as f:
    json.dump(list(tracker), f, indent=2)

print(f"Updated tracker. Total uploaded: {len(tracker)}")
