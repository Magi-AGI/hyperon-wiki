"""Find chapter boundaries using context clues."""
import json
import re

JSON_PATH = r"E:/GitHub/Magi-AGI/hyperon-wiki/publication_texts/json/Probabilistic_Logic_Networks.json"
with open(JSON_PATH, "r", encoding="utf-8") as f:
    d = json.load(f)
t = d["full_text"]

# Patterns that likely begin a chapter. Look for "Chapter N:" following page break markers.
# The TOC listed chapters 1..14. Find each "Chapter N:" occurrence's surrounding context.
pat = re.compile(r"Chapter\s+(\d+):\s*([A-Z][^\n]{3,80})")
hits = []
for m in pat.finditer(t):
    s = m.start()
    # skip the TOC block at the very start
    if s < 2500:
        continue
    ctx_before = t[max(0, s-120):s]
    ctx_after = t[s:s+160]
    hits.append((m.group(1), m.group(2).strip(), s, ctx_before.replace("\n"," ")[-60:], ctx_after[:120]))

# Keep only the first occurrence of each chapter number
seen = {}
for num, title, pos, cb, ca in hits:
    if num not in seen:
        seen[num] = (title, pos, cb, ca)

for n in sorted(seen.keys(), key=int):
    title, pos, cb, ca = seen[n]
    print(f"Ch {n} at {pos}: {title[:60]} | before='{cb}' | after='{ca[:80]}'")
