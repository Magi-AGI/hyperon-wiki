import json, re, sys

filepath = r'C:/Users/Lake/.claude/projects/E--GitHub-Magi-AGI-hyperon-wiki/edd60485-0ff4-49af-97b8-5eb2fa69580a/tool-results/mcp-claude_ai_Gmail-gmail_read_thread-1775765869584.txt'

with open(filepath, 'r', encoding='utf-8') as f:
    raw = f.read()

data = json.loads(raw)
text_str = data[0]['text']

if isinstance(text_str, str):
    thread = json.loads(text_str)
else:
    thread = text_str

print(f'threadId: {thread["threadId"]}')
print(f'message count: {len(thread["messages"])}')

for i, msg in enumerate(thread['messages']):
    hdrs = msg.get('headers', [])
    if isinstance(hdrs, list):
        headers = {h['name']: h['value'] for h in hdrs}
    else:
        headers = hdrs
    frm = headers.get('From', '?')
    date = headers.get('Date', '?')
    subj = headers.get('Subject', '?')
    body_obj = msg.get('body', '')
    if isinstance(body_obj, dict):
        body = body_obj.get('text', body_obj.get('data', ''))
    else:
        body = str(body_obj)
    print(f'--- Message {i} ---')
    print(f'  messageId: {msg["messageId"]}')
    print(f'  From: {frm}')
    print(f'  Date: {date}')
    print(f'  Subject: {subj}')
    print(f'  Body length: {len(body)}')
    print(f'  Body first 200: {repr(body[:200])}')
