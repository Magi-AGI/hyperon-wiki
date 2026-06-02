import json
import os

tid_to_files = {}
for d in ['raw_data_exports/cards_2014', 'raw_data_exports/cards_2014_b2']:
    if os.path.exists(d):
        for f in os.listdir(d):
            if f.endswith('.meta.json'):
                with open(os.path.join(d, f), 'r', encoding='utf-8') as f_in:
                    try:
                        meta = json.load(f_in)
                        tid = meta.get('thread_id', 'unknown')
                        if tid not in tid_to_files:
                            tid_to_files[tid] = []
                        tid_to_files[tid].append(os.path.join(d, f))
                    except:
                        pass

for tid, files in tid_to_files.items():
    if len(files) > 1:
        print(f"TID {tid}: {len(files)} files")
        for f in files[:5]:
            print(f"  {f}")
