import json
import os

dir_path = 'raw_data_exports/cards_2015'
raw_dir = 'raw_data_exports/gmail_raw_2015'

meta_files = [f for f in os.listdir(dir_path) if f.endswith('.meta.json')]
tid_to_meta = {}
for f in meta_files:
    with open(os.path.join(dir_path, f), 'r', encoding='utf-8') as f_in:
        try:
            meta = json.load(f_in)
            tid = meta.get('thread_id', 'unknown')
            if tid not in tid_to_meta:
                tid_to_meta[tid] = []
            tid_to_meta[tid].append(f)
        except:
            pass

print(f"Total meta files: {len(meta_files)}")
print(f"Unique thread IDs in meta files: {len(tid_to_meta)}")

multi_meta = {tid: files for tid, files in tid_to_meta.items() if len(files) > 1}
print(f"Thread IDs with multiple meta files: {len(multi_meta)}")

raw_files = [f for f in os.listdir(raw_dir) if f.endswith('.json')]
raw_tids = {f.replace('.json', '') for f in raw_files}
print(f"Total raw JSON files in gmail_raw_2015: {len(raw_tids)}")

not_in_raw = [tid for tid in tid_to_meta if tid != 'unknown' and tid not in raw_tids]
print(f"Thread IDs in meta but NOT in raw dir: {len(not_in_raw)}")

if not_in_raw:
    print("Example IDs in meta but not raw dir:")
    for tid in not_in_raw[:5]:
        print(f"  {tid} ({len(tid_to_meta[tid])} files: {tid_to_meta[tid][0]})")
