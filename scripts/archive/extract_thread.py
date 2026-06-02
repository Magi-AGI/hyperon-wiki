import json, re

filepath = r'C:/Users/Lake/.claude/projects/E--GitHub-Magi-AGI-hyperon-wiki/edd60485-0ff4-49af-97b8-5eb2fa69580a/tool-results/mcp-claude_ai_Gmail-gmail_read_thread-1775765869584.txt'

with open(filepath, 'r', encoding='utf-8') as f:
    raw = f.read()

data = json.loads(raw)
text_str = data[0]['text']
if isinstance(text_str, str):
    thread = json.loads(text_str)
else:
    thread = text_str

KEY_PARTICIPANTS = ['ben goertzel', 'linas vepstas', 'nil geisweiller']

def is_key_participant(from_header):
    fl = from_header.lower()
    return any(kp in fl for kp in KEY_PARTICIPANTS)

def clean_body(body_text, from_header):
    text = body_text.replace('\r\n', '\n').replace('\r', '\n')

    # Remove "You received this message because..." boilerplate
    text = re.split(r'\nYou received this message because', text)[0]
    text = re.split(r'\n---\n', text)[0]

    # Remove signature blocks (lines after -- on its own line)
    text = re.split(r'\n-- ?\n', text)[0]

    # Remove "Ben Goertzel, PhD" style signatures
    text = re.split(r'\nBen Goertzel, PhD', text)[0]

    # Remove quoted lines (lines starting with >)
    lines = text.split('\n')
    cleaned = []
    for line in lines:
        if line.strip().startswith('>'):
            continue
        cleaned.append(line)
    text = '\n'.join(cleaned)

    # Remove "On ... wrote:" lines (various date formats)
    text = re.sub(r'On [A-Z][a-z]{2},.*?wrote:\s*', '', text, flags=re.DOTALL)
    text = re.sub(r'On \d{2}/\d{2}/\d{4}.*?wrote:\s*', '', text, flags=re.DOTALL)

    # Remove URLs
    text = re.sub(r'https?://\S+', '', text)

    # Remove --linas, --Nil, etc sign-offs
    text = re.sub(r'\n--\s*linas\s*$', '', text, flags=re.IGNORECASE)
    text = re.sub(r'\nNil\s*$', '', text, flags=re.IGNORECASE)
    text = re.sub(r'\n--\s*$', '', text)

    # Collapse multiple blank lines
    text = re.sub(r'\n{3,}', '\n\n', text)

    # Remove leading/trailing whitespace
    text = text.strip()

    # Truncate
    limit = 800 if is_key_participant(from_header) else 300
    if len(text) > limit:
        text = text[:limit] + '...'

    return text

simplified = []
for msg in thread['messages']:
    hdrs = msg.get('headers', [])
    if isinstance(hdrs, list):
        headers = {h['name']: h['value'] for h in hdrs}
    else:
        headers = hdrs

    from_h = headers.get('From', '?')
    date_h = headers.get('Date', '?')
    subj_h = headers.get('Subject', '?')

    body_obj = msg.get('body', '')
    if isinstance(body_obj, dict):
        body = body_obj.get('text', body_obj.get('data', ''))
    else:
        body = str(body_obj)

    clean = clean_body(body, from_h)

    simplified.append({
        "messageId": msg["messageId"],
        "headers": {"From": from_h, "Date": date_h, "Subject": subj_h},
        "body": clean
    })

# Output
print(f'THREAD_ID: {thread["threadId"]}')
print(f'MESSAGE_COUNT: {len(thread["messages"])}')
print(f'SUBJECT: {simplified[0]["headers"]["Subject"]}')

compact = json.dumps(simplified, separators=(',', ':'))
print(f'TOTAL_JSON_LEN: {len(compact)}')

# Print each message for review
for i, s in enumerate(simplified):
    print(f'\n=== MSG {i} from {s["headers"]["From"][:40]} body_len={len(s["body"])} ===')
    print(s["body"][:600])

# Write compact JSON to stdout as final output
print('\n\n=== COMPACT JSON ===')
print(compact)
