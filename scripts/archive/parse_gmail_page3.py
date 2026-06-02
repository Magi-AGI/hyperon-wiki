import json, datetime, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

f=open(r'C:\Users\Lake\.claude\projects\E--GitHub-Magi-AGI-hyperon-wiki\2e62ad5b-bb03-4718-8dec-21ca9743ff6a\tool-results\mcp-claude_ai_Gmail-gmail_search_messages-1775668060630.txt','r',encoding='utf-8')
data=json.load(f)
inner=json.loads(data[0]['text'])
msgs=inner['messages']

# Build thread info
threads = {}
for m in msgs:
    tid = m['threadId']
    ts = int(m['internalDate'])/1000
    dt = datetime.datetime.fromtimestamp(ts, tz=datetime.timezone.utc)
    subj = m['headers'].get('Subject','(no subject)')
    if tid not in threads:
        threads[tid] = {'count':0, 'earliest': dt, 'latest': dt, 'subject': subj}
    threads[tid]['count'] += 1
    if dt < threads[tid]['earliest']:
        threads[tid]['earliest'] = dt
        threads[tid]['subject'] = subj
    if dt > threads[tid]['latest']:
        threads[tid]['latest'] = dt

# Sort by latest date descending
sorted_threads = sorted(threads.items(), key=lambda x: x[1]['latest'], reverse=True)

print('TOTAL MESSAGES:', len(msgs))
print('TOTAL UNIQUE THREADS:', len(threads))
print('DATE RANGE:', sorted_threads[-1][1]['earliest'].strftime('%Y-%m-%d'), 'to', sorted_threads[0][1]['latest'].strftime('%Y-%m-%d'))
print('nextPageToken:', inner.get('nextPageToken','NONE'))
print('resultSizeEstimate:', inner.get('resultSizeEstimate','NONE'))
print()
print('ALL THREADS SORTED BY DATE (newest first):')
print('threadId         | msg_count | latest_date | subject (first 80 chars)')
print('-'*130)
for tid, info in sorted_threads:
    subj = info['subject'][:80]
    print(f'{tid} | {info["count"]:>3} | {info["latest"].strftime("%Y-%m-%d")} | {subj}')

print()
print('TOP 10 THREADS BY MESSAGE COUNT:')
print('threadId         | msg_count | latest_date | subject (first 80 chars)')
print('-'*130)
by_count = sorted(threads.items(), key=lambda x: x[1]['count'], reverse=True)[:10]
for tid, info in by_count:
    subj = info['subject'][:80]
    print(f'{tid} | {info["count"]:>3} | {info["latest"].strftime("%Y-%m-%d")} | {subj}')
