import json
import os

missing_tids = [
  '14b0bb2ae7fcbc60',
  '14bc047348910a44',
  '150f3d2a690792ac',
  '14ef703affb8f0c4',
  '14b493f0a166d8fe',
  '150e0d81a9e108a4',
  '14b19ace61412b0a',
  '15013a1de089933f',
  '150b357c75b814cf'
]

raw_dir = 'raw_data_exports/gmail_raw_2015'
for tid in missing_tids:
    path = os.path.join(raw_dir, f"{tid}.json")
    if os.path.exists(path):
        with open(path, 'r', encoding='utf-8') as f:
            try:
                data = json.load(f)
                # messages[0]['headers']['Subject']
                if 'messages' in data and len(data['messages']) > 0:
                    subj = data['messages'][0].get('headers', {}).get('Subject', 'No Subject')
                    print(f"{tid}: {subj}")
                elif isinstance(data, list) and len(data) > 0 and 'messages' in data[0]:
                    subj = data[0]['messages'][0].get('headers', {}).get('Subject', 'No Subject')
                    print(f"{tid}: {subj}")
                else:
                    print(f"{tid}: Unexpected structure")
            except:
                print(f"{tid}: Error reading")
