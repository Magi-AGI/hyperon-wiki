import json
import os

cards_dir = 'raw_data_exports/cards_2015'
raw_dir = 'raw_data_exports/gmail_raw_2015'

raw_files = [f for f in os.listdir(raw_dir) if f.endswith('.json')]
meta_files = [f for f in os.listdir(cards_dir) if f.endswith('.meta.json')]

print(f"Raw files: {len(raw_files)}")
print(f"Meta files: {len(meta_files)}")

processed_tids = set()
for f in meta_files:
    with open(os.path.join(cards_dir, f), 'r', encoding='utf-8') as f_in:
        try:
            meta = json.load(f_in)
            tid = meta.get('thread_id')
            if tid:
                processed_tids.add(tid)
        except:
            pass

print(f"Unique TIDs in meta: {len(processed_tids)}")

missing = [f for f in raw_files if f.replace('.json', '') not in processed_tids]
print(f"Missing TIDs count: {len(missing)}")
if missing:
    print(f"Example missing: {missing[:5]}")
