import json
import os

tids = set()
for d in ['raw_data_exports/cards_2014', 'raw_data_exports/cards_2014_b2']:
    if os.path.exists(d):
        for f in os.listdir(d):
            if f.endswith('.meta.json'):
                with open(os.path.join(d, f), 'r', encoding='utf-8') as f_in:
                    try:
                        meta = json.load(f_in)
                        tid = meta.get('thread_id')
                        if tid:
                            tids.add(tid)
                    except:
                        pass

print(f"Total 2014 unique TIDs: {len(tids)}")
