import json
import os

cards_dir = 'raw_data_exports/cards_2015'
raw_dir = 'raw_data_exports/gmail_raw_2015'

processed_tids = set()
for f in os.listdir(cards_dir):
    if f.endswith('.meta.json'):
        with open(os.path.join(cards_dir, f), 'r', encoding='utf-8') as f_in:
            try:
                meta = json.load(f_in)
                tid = meta.get('thread_id')
                if tid:
                    processed_tids.add(tid)
            except:
                pass

raw_files = [f for f in os.listdir(raw_dir) if f.endswith('.json')]
raw_tids = {f.replace('.json', '') for f in raw_files}

missing = [tid for tid in raw_tids if tid not in processed_tids]
print(f"Total raw files: {len(raw_tids)}")
print(f"Total processed TIDs: {len(processed_tids)}")
print(f"Missing meta files for TIDs: {len(missing)}")

if missing:
    print("Missing TIDs:")
    for tid in missing:
        print(f"  {tid}")
