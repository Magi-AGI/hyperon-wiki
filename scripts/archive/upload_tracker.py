import json
import os

TRACKER_FILE = 'uploaded_tids.json'

def load_tracker():
    if os.path.exists(TRACKER_FILE):
        with open(TRACKER_FILE, 'r', encoding='utf-8') as f:
            return set(json.load(f))
    return set()

def save_tracker(tids):
    with open(TRACKER_FILE, 'w', encoding='utf-8') as f:
        json.dump(list(tids), f, indent=2)

def main():
    tracker = load_tracker()
    cards_dir = 'raw_data_exports/cards_2015'
    new_to_upload = []
    
    if os.path.exists(cards_dir):
        for f in os.listdir(cards_dir):
            if f.endswith('.meta.json'):
                with open(os.path.join(cards_dir, f), 'r', encoding='utf-8') as f_in:
                    try:
                        meta = json.load(f_in)
                        tid = meta.get('thread_id')
                        if tid and tid not in tracker:
                            new_to_upload.append(meta)
                    except:
                        pass
    
    print(f"New threads to upload: {len(new_to_upload)}")
    
    if new_to_upload:
        batch_size = 20
        # Just prepare the first batch for now
        batch = new_to_upload[:batch_size]
        batch_ops = []
        for meta in batch:
            with open(meta['content_file'], 'r', encoding='utf-8') as f_content:
                content = f_content.read()
                batch_ops.append({
                    "action": "create",
                    "name": meta['card_name'],
                    "type": "RawData",
                    "content": content,
                    "fetch_or_initialize": True
                })
        
        with open('batch_to_upload.json', 'w', encoding='utf-8') as f_out:
            json.dump({'operations': batch_ops}, f_out, indent=2)
        print(f"Wrote {len(batch_ops)} operations to batch_to_upload.json")
        
        # We'll update the tracker AFTER successful upload in the main loop
        # For now, just print the TIDs in this batch
        batch_tids = [meta['thread_id'] for meta in batch]
        with open('batch_tids.json', 'w', encoding='utf-8') as f_tids:
            json.dump(batch_tids, f_tids)

if __name__ == "__main__":
    main()
