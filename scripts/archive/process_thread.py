"""
Process Gmail thread JSON into wiki card content.
Usage: python scripts/process_thread.py <input_json> <output_dir> [--thread-id THREADID]

Reads the Gmail MCP response JSON, extracts messages, formats card content,
and saves to output files ready for wiki card creation.
"""
import json
import re
import sys
import os
import html
from datetime import datetime

# Key participants get longer body excerpts (800 chars), others get 300
KEY_PARTICIPANTS = [
    'ben goertzel', 'linas vepstas', 'nil geisweiller',
    'alexey potapov', 'vitaly bogdanov', 'hedra', 'adam vandervorst',
    'cosmo harrigan', 'cassio pennachin', 'joel pitt', 'jade o\'neill',
    'matt ikle', 'deborah duong', 'mike duncan', 'ruiting lian',
    'shujing ke', 'amen belayneh', 'eddie monroe', 'mandebi'
]

MAX_CARD_SIZE = 44000  # Keep under 45KB

def clean_subject(subject):
    """Clean email subject for use as card name."""
    s = subject
    # Remove common prefixes
    for prefix in ['Re: ', 'Fwd: ', 'RE: ', 'FW: ']:
        while s.startswith(prefix):
            s = s[len(prefix):]
    s = s.replace('[opencog-dev]', '').replace('[Link Grammar]', '')
    s = s.replace('[WG]', '').replace('[SIGLEX]', '')
    s = s.strip()
    # Remove characters not allowed in card names
    s = re.sub(r'[<>:"/\\|?*\[\]{}#%&]', '', s)
    s = s.replace('+', 'plus')
    s = re.sub(r'\s+', ' ', s).strip()
    # Cap length
    if len(s) > 80:
        s = s[:77] + '...'
    return s


def clean_body(text, max_len=300):
    """Clean email body text, removing quotes and signatures."""
    if not text:
        return ''

    lines = text.split('\n')
    cleaned = []
    for line in lines:
        # Skip quoted lines
        if line.strip().startswith('>'):
            continue
        # Skip common signature markers
        if line.strip() in ['--', '---', '-- ']:
            break
        # Skip "On ... wrote:" lines
        if re.match(r'^On .+ wrote:$', line.strip()):
            continue
        cleaned.append(line)

    result = '\n'.join(cleaned).strip()
    # Remove excessive whitespace
    result = re.sub(r'\n{3,}', '\n\n', result)

    if len(result) > max_len:
        # Try to cut at a sentence boundary
        cut = result[:max_len]
        last_period = cut.rfind('.')
        last_newline = cut.rfind('\n')
        cut_point = max(last_period, last_newline)
        if cut_point > max_len * 0.5:
            result = result[:cut_point + 1] + ' [...]'
        else:
            result = cut + ' [...]'

    return result


def is_key_participant(sender):
    """Check if sender is a key participant."""
    sender_lower = sender.lower()
    return any(kp in sender_lower for kp in KEY_PARTICIPANTS)


def extract_sender_name(from_header):
    """Extract just the name from a From header."""
    if not from_header:
        return 'Unknown'
    # Remove email address
    match = re.match(r'^"?([^"<]+)"?\s*<', from_header)
    if match:
        return match.group(1).strip().strip('"')
    # Just an email
    match = re.match(r'<?(\S+@\S+)>?', from_header)
    if match:
        return match.group(1)
    return from_header.strip()


def parse_date(date_str):
    """Parse email date string into a readable format."""
    if not date_str:
        return 'Unknown date'
    # Try common formats
    for fmt in [
        '%a, %d %b %Y %H:%M:%S %z',
        '%a, %d %b %Y %H:%M:%S %Z',
        '%a, %d %b %Y %H:%M:%S',
        '%d %b %Y %H:%M:%S %z',
    ]:
        try:
            dt = datetime.strptime(date_str.strip(), fmt)
            return dt.strftime('%Y-%m-%d')
        except ValueError:
            continue
    # Fallback: extract date portion
    match = re.search(r'(\d{1,2}\s+\w{3}\s+\d{4})', date_str)
    if match:
        return match.group(1)
    return date_str[:30]


def extract_messages_from_mcp_response(data):
    """Extract messages from the Gmail MCP response format.

    Format can be:
    1. JSON array with [{type: "text", text: "<json string>"}] (MCP wrapper)
    2. Raw JSON dictionary: {threadId, messages: [...]}
    """
    messages = []

    # Case 1: The MCP response is a JSON array of {type, text} objects
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict) and item.get('type') == 'text':
                text = item['text']
                # Parse the inner JSON
                try:
                    thread_data = json.loads(text)
                    if isinstance(thread_data, dict) and 'messages' in thread_data:
                        for msg in thread_data['messages']:
                            headers = msg.get('headers', {})
                            messages.append({
                                'from': headers.get('From', ''),
                                'date': headers.get('Date', ''),
                                'subject': headers.get('Subject', ''),
                                'body': msg.get('body', ''),
                                'message_id': msg.get('messageId', ''),
                            })
                except json.JSONDecodeError:
                    # Fall back to text parsing
                    current_msg = {}
                    for line in text.split('\n'):
                        if line.startswith('From: '):
                            if current_msg.get('from'):
                                messages.append(current_msg)
                            current_msg = {'from': line[6:].strip(), 'body': ''}
                        elif line.startswith('Date: ') and 'date' not in current_msg:
                            current_msg['date'] = line[6:].strip()
                        elif line.startswith('Subject: ') and 'subject' not in current_msg:
                            current_msg['subject'] = line[9:].strip()
                        elif current_msg.get('from'):
                            current_msg['body'] = current_msg.get('body', '') + line + '\n'
                    if current_msg.get('from'):
                        messages.append(current_msg)
    
    # Case 2: Raw JSON dictionary
    elif isinstance(data, dict) and 'messages' in data:
        for msg in data['messages']:
            headers = msg.get('headers', {})
            messages.append({
                'from': headers.get('From', ''),
                'date': headers.get('Date', ''),
                'subject': headers.get('Subject', ''),
                'body': msg.get('body', ''),
                'message_id': msg.get('messageId', ''),
            })

    return messages


def format_card_content(subject, messages, thread_id):
    """Format messages into wiki card content."""
    if not messages:
        return None

    clean_subj = clean_subject(subject)

    # Determine date range
    dates = [m.get('date', '') for m in messages if m.get('date')]
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

    # Build message content with size tracking
    content = header
    for i, msg in enumerate(messages):
        sender = extract_sender_name(msg.get('from', 'Unknown'))
        date = parse_date(msg.get('date', ''))
        is_key = is_key_participant(sender)
        max_body = 800 if is_key else 300
        body = clean_body(msg.get('body', ''), max_body)

        msg_text = f"\n--- Message {i+1}/{len(messages)} ---\nFrom: {sender}\nDate: {date}\n\n{body}\n"

        if len(content) + len(msg_text) > MAX_CARD_SIZE:
            content += f"\n[... {len(messages) - i} additional messages truncated for size ...]\n"
            break
        content += msg_text

    return content


def process_file(input_path, output_dir, thread_id=None):
    """Process a Gmail thread JSON file into card content."""
    with open(input_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    messages = extract_messages_from_mcp_response(data)

    if not messages:
        print(f"WARNING: No messages extracted from {input_path}", file=sys.stderr)
        return None

    # Get subject from first message or filename
    subject = messages[0].get('subject', '')
    if not subject:
        subject = os.path.basename(input_path).replace('.json', '').replace('.txt', '')

    content = format_card_content(subject, messages, thread_id or 'unknown')

    if content:
        cleaned_subject = clean_subject(subject)
        # Include thread ID in card name to ensure uniqueness
        display_name = f"{cleaned_subject} ({thread_id})" if thread_id else cleaned_subject
        full_card_name = f"RawData+opencog-ml+{display_name}"
        
        safe_filename = re.sub(r'[^\w\s-]', '', cleaned_subject)[:60].strip()
        safe_filename = re.sub(r'\s+', '_', safe_filename)
        
        # Include thread ID in filename to prevent overwriting same-subject threads
        if thread_id:
            safe_filename = f"{safe_filename}_{thread_id}"

        output_path = os.path.join(output_dir, f"card_{safe_filename}.txt")
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(content)

        # Also write metadata
        meta_path = os.path.join(output_dir, f"card_{safe_filename}.meta.json")
        with open(meta_path, 'w', encoding='utf-8') as f:
            json.dump({
                'card_name': full_card_name,
                'subject': subject,
                'thread_id': thread_id,
                'message_count': len(messages),
                'content_file': output_path
            }, f, indent=2)

        print(f"OK: {full_card_name} ({len(messages)} msgs, {len(content)} chars)")
        return output_path

    return None


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input_json> <output_dir> [--thread-id ID]")
        sys.exit(1)

    input_path = sys.argv[1]
    output_dir = sys.argv[2]
    thread_id = None

    if '--thread-id' in sys.argv:
        idx = sys.argv.index('--thread-id')
        if idx + 1 < len(sys.argv):
            thread_id = sys.argv[idx + 1]

    os.makedirs(output_dir, exist_ok=True)
    result = process_file(input_path, output_dir, thread_id)
    if result:
        print(f"Output: {result}")
    else:
        print("FAILED: No content generated", file=sys.stderr)
        sys.exit(1)
