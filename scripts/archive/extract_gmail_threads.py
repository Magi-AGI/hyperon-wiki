#!/usr/bin/env python3
"""Extract Gmail thread data from MCP tool-result files into simplified JSON.

Reads files in the [{type: "text", text: "<json>"}] format, extracts messages,
cleans bodies, and writes simplified JSON to the output directory.

Usage: python scripts/extract_gmail_threads.py
"""
import json
import re
import sys
import os

KEY_PARTICIPANTS = [
    'ben goertzel', 'linas vepstas', 'nil geisweiller',
    'alexey potapov', 'vitaly bogdanov', 'cosmo harrigan',
    'cassio pennachin', 'joel pitt', 'jade o\'neill',
    'matt ikle', 'deborah duong', 'mike duncan', 'ruiting lian',
    'shujing ke', 'amen belayneh', 'eddie monroe', 'mandebi',
    'hedra', 'adam vandervorst', 'lake watkins', 'david hart'
]


def is_key_participant(sender):
    lower = sender.lower()
    return any(kp in lower for kp in KEY_PARTICIPANTS)


def clean_body(text, max_len=300):
    """Remove quoted text, signatures, boilerplate and truncate."""
    if not text:
        return ''
    lines = text.replace('\r\n', '\n').split('\n')
    cleaned = []
    for line in lines:
        stripped = line.strip()
        # Skip quoted lines
        if stripped.startswith('>'):
            continue
        # Stop at signature markers
        if stripped in ['--', '---', '-- ']:
            break
        # Skip "On ... wrote:" lines
        if re.match(r'^On .+ wrote:$', stripped):
            continue
        # Stop at Google Groups boilerplate
        if 'You received this message because' in line:
            break
        if 'To unsubscribe from this group' in line:
            break
        if 'To post to this group' in line:
            break
        if '-- \nYou received this' in line:
            break
        cleaned.append(line)

    result = '\n'.join(cleaned).strip()
    # Collapse excessive newlines
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


def extract_sender_name(from_header):
    """Extract display name from From header."""
    if not from_header:
        return 'Unknown'
    match = re.match(r'^"?([^"<]+)"?\s*<', from_header)
    if match:
        return match.group(1).strip().strip('"')
    match = re.match(r'<?(\S+@\S+)>?', from_header)
    if match:
        return match.group(1)
    return from_header.strip()


def process_file(input_path, output_dir):
    """Read MCP tool-result file, extract thread, write simplified JSON."""
    print(f"Reading: {input_path}")
    with open(input_path, 'r', encoding='utf-8') as f:
        raw = json.load(f)

    # The file is [{type: "text", text: "<json>"}]
    thread_data = None
    if isinstance(raw, list):
        for item in raw:
            if isinstance(item, dict) and item.get('type') == 'text':
                thread_data = json.loads(item['text'])
                break
    elif isinstance(raw, dict):
        thread_data = raw

    if not thread_data:
        print(f"ERROR: Could not extract thread data from {input_path}", file=sys.stderr)
        return None

    thread_id = thread_data.get('threadId', 'unknown')
    messages = thread_data.get('messages', [])
    print(f"  Thread ID: {thread_id}, Messages: {len(messages)}")

    # Build simplified messages
    simplified_messages = []
    for msg in messages:
        # Extract headers - could be in 'headers' dict or top-level 'payload.headers' list
        headers = msg.get('headers', {})
        if isinstance(headers, list):
            # Convert list of {name, value} to dict
            hdr_dict = {}
            for h in headers:
                hdr_dict[h.get('name', '')] = h.get('value', '')
            headers = hdr_dict

        from_val = headers.get('From', '')
        date_val = headers.get('Date', '')
        subject_val = headers.get('Subject', '')

        # Get body text
        body = msg.get('body', '')

        # Determine max length based on sender
        sender_name = extract_sender_name(from_val)
        max_len = 800 if is_key_participant(sender_name) else 300

        cleaned_body = clean_body(body, max_len)

        simplified_messages.append({
            'messageId': msg.get('messageId', ''),
            'headers': {
                'From': from_val,
                'Date': date_val,
                'Subject': subject_val
            },
            'body': cleaned_body
        })

    simplified = {
        'threadId': thread_id,
        'messages': simplified_messages
    }

    # Write output
    os.makedirs(output_dir, exist_ok=True)
    out_path = os.path.join(output_dir, f'{thread_id}.json')
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(simplified, f, ensure_ascii=False)

    file_size = os.path.getsize(out_path)
    print(f"  Written: {out_path} ({file_size} bytes, {len(simplified_messages)} messages)")
    return thread_id


if __name__ == '__main__':
    INPUT_FILES = [
        r"C:\Users\Lake\.claude\projects\E--GitHub-Magi-AGI-hyperon-wiki\edd60485-0ff4-49af-97b8-5eb2fa69580a\tool-results\mcp-claude_ai_Gmail-gmail_read_thread-1775768593006.txt",
        r"C:\Users\Lake\.claude\projects\E--GitHub-Magi-AGI-hyperon-wiki\edd60485-0ff4-49af-97b8-5eb2fa69580a\tool-results\mcp-claude_ai_Gmail-gmail_read_thread-1775768593413.txt",
        r"C:\Users\Lake\.claude\projects\E--GitHub-Magi-AGI-hyperon-wiki\edd60485-0ff4-49af-97b8-5eb2fa69580a\tool-results\mcp-claude_ai_Gmail-gmail_read_thread-1775768594191.txt",
        r"C:\Users\Lake\.claude\projects\E--GitHub-Magi-AGI-hyperon-wiki\edd60485-0ff4-49af-97b8-5eb2fa69580a\tool-results\mcp-claude_ai_Gmail-gmail_read_thread-1775768594121.txt",
    ]
    OUTPUT_DIR = r"E:\GitHub\Magi-AGI\hyperon-wiki\raw_data_exports\gmail_raw_2015"

    thread_ids = []
    for fpath in INPUT_FILES:
        tid = process_file(fpath, OUTPUT_DIR)
        if tid:
            thread_ids.append(tid)

    print(f"\nExtracted {len(thread_ids)} threads: {thread_ids}")
