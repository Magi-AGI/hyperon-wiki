#!/usr/bin/env python3
"""Process raw Gmail MCP thread response JSON into card text files.

Usage: python scripts/process_gmail_response.py <input_json> <output_dir>

Input: JSON file containing the direct Gmail MCP response dict with:
  {threadId, messages: [{headers: {From, Date, Subject}, body, ...}]}
"""
import json
import re
import sys
import os
from datetime import datetime

KEY_PARTICIPANTS = [
    'ben goertzel', 'linas vepstas', 'nil geisweiller',
    'alexey potapov', 'vitaly bogdanov', 'cosmo harrigan',
    'cassio pennachin', 'joel pitt', 'jade o\'neill',
    'matt ikle', 'deborah duong', 'mike duncan', 'ruiting lian',
    'shujing ke', 'amen belayneh', 'eddie monroe', 'mandebi',
    'hedra', 'adam vandervorst', 'lake watkins', 'david hart'
]
MAX_CARD_SIZE = 44000


def clean_subject(subject):
    s = subject
    for prefix in ['Re: ', 'Fwd: ', 'RE: ', 'FW: ']:
        while s.startswith(prefix):
            s = s[len(prefix):]
    s = s.replace('[opencog-dev]', '').replace('[Link Grammar]', '')
    s = s.replace('[WG]', '').replace('[SIGLEX]', '').replace('[opencog]', '')
    s = s.strip()
    s = re.sub(r'[<>:"/\\|?*\[\]{}#%&]', '', s)
    s = re.sub(r'\s+', ' ', s).strip()
    if len(s) > 80:
        s = s[:77] + '...'
    return s


def safe_filename(name):
    safe = re.sub(r'[^\w\s-]', '', name)[:60].strip()
    return re.sub(r'\s+', '_', safe)


def extract_sender_name(from_header):
    if not from_header:
        return 'Unknown'
    match = re.match(r'^"?([^"<]+)"?\s*<', from_header)
    if match:
        return match.group(1).strip().strip('"')
    match = re.match(r'<?(\S+@\S+)>?', from_header)
    if match:
        return match.group(1)
    return from_header.strip()


def parse_date(date_str):
    if not date_str:
        return 'Unknown date'
    for fmt in [
        '%a, %d %b %Y %H:%M:%S %z',
        '%a, %d %b %Y %H:%M:%S %Z',
        '%a, %d %b %Y %H:%M:%S',
        '%d %b %Y %H:%M:%S %z',
        '%a, %d %b %Y %H:%M:%S %z (%Z)',
    ]:
        try:
            dt = datetime.strptime(date_str.strip(), fmt)
            return dt.strftime('%Y-%m-%d')
        except ValueError:
            continue
    match = re.search(r'(\d{1,2}\s+\w{3}\s+\d{4})', date_str)
    if match:
        return match.group(1)
    return date_str[:30]


def is_key(sender):
    return any(kp in sender.lower() for kp in KEY_PARTICIPANTS)


def clean_body(text, max_len=300):
    if not text:
        return ''
    lines = text.replace('\r\n', '\n').split('\n')
    cleaned = []
    for line in lines:
        if line.strip().startswith('>'):
            continue
        if line.strip() in ['--', '---', '-- ']:
            break
        if re.match(r'^On .+ wrote:$', line.strip()):
            continue
        if 'You received this message because' in line:
            break
        if 'To unsubscribe from this group' in line:
            break
        cleaned.append(line)
    result = '\n'.join(cleaned).strip()
    result = re.sub(r'\n{3,}', '\n\n', result)
    if len(result) > max_len:
        cut = result[:max_len]
        last_period = cut.rfind('.')
        last_newline = cut.rfind('\n')
        cut_point = max(last_period, last_newline)
        if cut_point > max_len * 0.5:
            result = result[:cut_point + 1] + ' [...]'
        else:
            result = cut + ' [...]'
    return result


def process_gmail_response(data, output_dir):
    """Process a direct Gmail MCP response dict."""
    thread_id = data.get('threadId', 'unknown')
    messages = data.get('messages', [])
    if not messages:
        print(f"WARNING: No messages in thread {thread_id}", file=sys.stderr)
        return None

    # Get subject
    subject = messages[0].get('headers', {}).get('Subject', 'Unknown')
    clean_subj = clean_subject(subject)

    # Date range
    dates = [m.get('headers', {}).get('Date', '') for m in messages]
    first_date = parse_date(dates[0]) if dates else 'Unknown'
    last_date = parse_date(dates[-1]) if dates else 'Unknown'

    # Build header
    header = f"""OpenCog Mailing List Thread: {clean_subj}
Messages: {len(messages)}
Date range: {first_date} to {last_date}
Source: opencog@googlegroups.com
Thread ID: {thread_id}

============================================================
"""
    content = header
    for i, msg in enumerate(messages):
        headers = msg.get('headers', {})
        sender = extract_sender_name(headers.get('From', 'Unknown'))
        date = parse_date(headers.get('Date', ''))
        max_body = 800 if is_key(sender) else 300
        body = clean_body(msg.get('body', ''), max_body)

        msg_text = f"\n--- Message {i+1}/{len(messages)} ---\nFrom: {sender}\nDate: {date}\n\n{body}\n"

        if len(content) + len(msg_text) > MAX_CARD_SIZE:
            content += f"\n[... {len(messages) - i} additional messages truncated for size ...]\n"
            break
        content += msg_text

    # Write files
    os.makedirs(output_dir, exist_ok=True)
    fname = safe_filename(clean_subj)
    txt_path = os.path.join(output_dir, f"card_{fname}.txt")
    meta_path = os.path.join(output_dir, f"card_{fname}.meta.json")

    with open(txt_path, 'w', encoding='utf-8') as f:
        f.write(content)

    with open(meta_path, 'w', encoding='utf-8') as f:
        json.dump({
            'card_name': f'RawData+opencog-ml+{clean_subj}',
            'subject': subject,
            'thread_id': thread_id,
            'message_count': len(messages),
            'content_file': txt_path.replace('\\', '/')
        }, f, indent=2)

    print(f"OK: {clean_subj} ({len(messages)} msgs, {len(content)} chars) -> {txt_path}")
    return txt_path


def process_dir(input_dir, output_dir):
    """Process all JSON files in a directory."""
    count = 0
    for fname in sorted(os.listdir(input_dir)):
        if not fname.endswith('.json'):
            continue
        path = os.path.join(input_dir, fname)
        try:
            with open(path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            # Handle both direct format and MCP wrapper format
            if isinstance(data, dict) and 'messages' in data:
                result = process_gmail_response(data, output_dir)
            elif isinstance(data, list):
                # MCP wrapper: [{type: "text", text: "..."}]
                for item in data:
                    if isinstance(item, dict) and item.get('type') == 'text':
                        inner = json.loads(item['text'])
                        if 'messages' in inner:
                            result = process_gmail_response(inner, output_dir)
                            break
            if result:
                count += 1
        except Exception as e:
            print(f"ERROR processing {fname}: {e}", file=sys.stderr)
    return count


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input_json_or_dir> <output_dir>")
        sys.exit(1)

    input_path = sys.argv[1]
    output_dir = sys.argv[2]

    if os.path.isdir(input_path):
        count = process_dir(input_path, output_dir)
        print(f"\nProcessed {count} threads")
    else:
        with open(input_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        # Strip MCP metadata
        if '_mcp_structured' in data:
            del data['_mcp_structured']
        result = process_gmail_response(data, output_dir)
        if not result:
            sys.exit(1)
