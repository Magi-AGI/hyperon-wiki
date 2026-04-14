# wiki_nav_tree

Server-rendered outline of the wiki using Decko compound names (`Parent+Child`: children are cards whose **left** is the parent). Deeper levels load on demand (slotter).

## Include in the UI

Add to `*sidebar`, the home card, or any layout card:

```text
{{_|view:wiki_nav_tree}}
```

## Environment

| Variable | Meaning |
|----------|---------|
| `WIKI_NAV_ROOT` | Optional. If set (e.g. `Coalition of Planets`), the tree starts with that card’s **direct** children only. |
| `WIKI_NAV_ROOT_LIMIT` | When `WIKI_NAV_ROOT` is unset: max **top-level** simple cards listed (default `150`, max `500`). |
| `WIKI_NAV_CHILD_LIMIT` | Max children per parent (default `250`, max `1000`). |

## What’s included

- Respects read permissions (`Card.search`).
- Omits `Image` and `File`, trashed cards, simple names starting with `*`, and compound cards whose **right** starts with `*` (typical rule fields like `+*read`).

## URLs

- Full page: append `?view=wiki_nav_tree` to any card URL for the same tree (context card is ignored; roots come from env / top-level query).
