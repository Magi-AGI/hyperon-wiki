import json
import os
import subprocess
import re

def process_year(year):
    cards_dir = f'raw_data_exports/cards_{year}'
    raw_dir = f'raw_data_exports/gmail_raw_{year}'
    
    if not os.path.exists(raw_dir):
        print(f"Raw directory {raw_dir} does not exist.")
        return []

    if not os.path.exists(cards_dir):
        os.makedirs(cards_dir)

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

    new_tids = [tid for tid in raw_tids if tid not in processed_tids]
    print(f"Year {year}: {len(new_tids)} new raw threads to process.")

    processed_cards = []
    if new_tids:
        for tid in new_tids:
            input_path = os.path.join(raw_dir, f"{tid}.json")
            # The scripts/process_thread.py script might create multiple cards if multiple subjects are in one file,
            # or just one. We need to find the resulting .meta.json files.
            # However, for simplicity, we'll just re-scan the cards_dir after processing.
            subprocess.run(['python', 'scripts/process_thread.py', input_path, cards_dir, '--thread-id', tid], capture_output=True)
        
        # Scan again for the newly created meta files
        for f in os.listdir(cards_dir):
            if f.endswith('.meta.json'):
                with open(os.path.join(cards_dir, f), 'r', encoding='utf-8') as f_in:
                    try:
                        meta = json.load(f_in)
                        if meta.get('thread_id') in new_tids:
                            processed_cards.append(meta)
                    except:
                        pass
    return processed_cards

def main():
    all_new_cards = []
    # We can expand this list as more years are added
    for year in ['2014', '2015']:
        all_new_cards.extend(process_year(year))

    print(f"Total new cards ready for upload: {len(all_new_cards)}")

    if all_new_cards:
        batch_size = 20
        for i in range(0, len(all_new_cards), batch_size):
            batch = all_new_cards[i:i+batch_size]
            batch_ops = []
            for meta in batch:
                content_file = meta['content_file']
                if not os.path.exists(content_file):
                    # Try to fix path if it's relative to raw_data_exports
                    alt_path = os.path.join('raw_data_exports', os.path.basename(content_file))
                    if os.path.exists(alt_path):
                        content_file = alt_path
                    else:
                        print(f"Warning: content file {content_file} not found.")
                        continue

                with open(content_file, 'r', encoding='utf-8') as f_content:
                    content = f_content.read()
                    batch_ops.append({
                        "action": "create",
                        "name": meta['card_name'],
                        "type": "RawData",
                        "content": content,
                        "fetch_or_initialize": True
                    })
            
            if batch_ops:
                filename = f'batch_upload_{i//batch_size}.json'
                with open(filename, 'w', encoding='utf-8') as f_out:
                    json.dump({'operations': batch_ops}, f_out, indent=2)
                print(f"Wrote {len(batch_ops)} operations to {filename}")

if __name__ == "__main__":
    main()
