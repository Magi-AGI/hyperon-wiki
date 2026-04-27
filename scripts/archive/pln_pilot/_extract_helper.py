"""Helper to slice the PLN JSON full_text for manual extraction."""
import json
import sys

JSON_PATH = r"E:/GitHub/Magi-AGI/hyperon-wiki/publication_texts/json/Probabilistic_Logic_Networks.json"


def load_text():
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        d = json.load(f)
    return d["full_text"]


def slice_text(start, end):
    t = load_text()
    return t[start:end]


def find_all(pattern, max_hits=200):
    t = load_text()
    import re
    hits = []
    for m in re.finditer(pattern, t, flags=re.IGNORECASE):
        hits.append(m.start())
        if len(hits) >= max_hits:
            break
    return hits


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "slice":
        s = int(sys.argv[2])
        e = int(sys.argv[3])
        out = slice_text(s, e)
        sys.stdout.buffer.write(out.encode("utf-8", errors="replace"))
    elif mode == "find":
        pat = sys.argv[2]
        hits = find_all(pat)
        print(hits)
    elif mode == "len":
        print(len(load_text()))
