import json
import os

dir_path = 'raw_data_exports/cards_2015'
tid_to_files = {}

for f in os.listdir(dir_path):
    if f.endswith('.meta.json'):
        with open(os.path.join(dir_path, f), 'r', encoding='utf-8') as f_in:
            try:
                meta = json.load(f_in)
                tid = meta.get('thread_id', 'unknown')
                if tid not in tid_to_files:
                    tid_to_files[tid] = []
                tid_to_files[tid].append(f)
            except:
                pass

for tid, files in tid_to_files.items():
    if len(files) > 1:
        print(f"TID {tid}: {len(files)} files")
        for f in files[:5]:
            print(f"  {f}")
