import json
import os

with open('raw_data_exports/opencog_2014_threads.json', 'r', encoding='utf-8') as f:
    tids_2014 = json.load(f)

raw_dir = 'raw_data_exports/gmail_raw_2015'
raw_files = [f for f in os.listdir(raw_dir) if f.endswith('.json')]
raw_tids = {f.replace('.json', '') for f in raw_files}

found = [tid for tid in tids_2014 if tid in raw_tids]
print(f"2014 TIDs found in gmail_raw_2015: {len(found)}")
