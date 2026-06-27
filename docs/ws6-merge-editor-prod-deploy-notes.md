# WS6 — Production Deploy & Migration Notes

For deploying `feature/ws6-merge-editor` (PR #25) to **wiki.hyperon.dev** after merge to
`main`. Prod EC2 `54.183.80.144`; app `~/hyperon-wiki`; Ruby 3.2.3 (rbenv); Decko on :3000
behind nginx. Both prod and dev run `RAILS_ENV=production`.

Shell preamble (run once per session):
```bash
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"; eval "$(rbenv init -)"
cd ~/hyperon-wiki && set -a && source .env.production && set +a
```

## 1. Required database seeds (codename registration)

WS6 right-sets bind only if their codenames exist in the prod DB. `mod/editorial_review/
data/real.yml` registers them; **`decko update` loads them**:

- **`proposal`** → binds `set/right/proposal.rb` (base stamping, type alignment, hash refresh).
- **`merge draft` / `merge_draft`** → binds `set/right/merge_draft.rb` (rederive, audit, apply).

Lifecycle tags: `ai generated`, `needs review`, etc. are already codenamed in `real.yml`.
The **`merged`** tag added on apply is a plain pointer value (auto-created card on first
apply) — no codename required; pre-creating a `merged` card is optional cosmetic cleanup.

> The Right-set events are `:finalize`/`:integrate`; without the codenames the sets never
> resolve and the events silently no-op. Registration is mandatory, not optional.

## 2. Deploy steps

```bash
# (preamble above)
git pull                                              # main now includes WS6
bundle install
RAILS_ENV=production bundle exec decko update          # registers proposal + merge_draft codenames
RAILS_ENV=production bundle exec rake decko:mod:symlink # publish mod assets (if any)
sudo systemctl restart hyperon-wiki.service hyperon-wiki-worker.service
```
Health: `curl -s -o /dev/null -w "%{http_code}\n" https://wiki.hyperon.dev/` → `200`.

**Cache note:** `Rails.cache` is a persistent on-disk `FileStore` that survives restarts.
If any stale viewer-dependent render appears after deploy, clear it once:
`RAILS_ENV=production bundle exec rails runner 'Card::Cache.reset_all; Rails.cache.clear'`.

## 3. Behavioral changes shipping in this deploy

- **Blunt merge path removed/rerouted.** The old `merge_ai_draft` event (`?merge_draft=true`
  parent overwrite) is gone from `ai_draft.rb`; the `ai_draft_aware.rb` "Merge AI Draft →
  Parent" button now routes to the merge workbench / legacy bridge instead of overwriting.
- **Parent writes only via `apply_merge_draft`** — the single audited, gated path.
- **Capability gate:** starting a legacy bridge AND applying a merge both require
  `parent.ok?(:update)` (UI + server-side). No role name is hard-coded — this resolves to
  whatever role prod restricts article edits to (e.g. `Editor`).
- **Audit model:** `+merge draft+audit` carries an **immutable `assembled_hash`** (selection
  origin proof) and a **`polished_hash`** refreshed on each save; apply verifies against
  `polished_hash`. `+merge audit` records the completed apply (`ws6-merge-apply/1`).

## 4. Post-deploy smoke test

Run as an **update-capable (editor) account**:
1. Create/find a Published article with an AI proposal; open
   `/<Article>+proposal?view=merge_workbench&layout=none`.
2. Assemble & polish → lands in the native editor on `+merge draft`; save.
3. Apply to parent → article updates; confirm `<Article>+proposal+merge audit` exists with
   `merged_by` = you, and the proposal content is unchanged (immutable).
4. Reload the workbench → **locked "already merged"** view; re-apply gives 409.
5. Confirm **no blunt path**: the "Merge AI Draft → Parent" button links to the
   workbench/bridge (no direct `card[content]`/`merge_draft` overwrite).

**Permission smoke (Codex caveat — important if prod perms differ from dev):** with a
**signed-in non-editor** account (cannot edit the article), confirm the "Open as proposal"
bridge button is hidden and a crafted bridge/apply POST is rejected with no parent write.
Prod has a real `Editor` role and may gate article edits differently than dev; the gate
tracks prod's config automatically, but verify once with a non-editor.

## 5. Review Queue (post-deploy, manual)

The `Review Queue` Search card (prod id 715) is seeded by `real.yml` as
`{"type":"draft","sort":"create","dir":"asc"}` and `decko update` will **not** overwrite the
existing card's content. To also surface published articles with an open proposal, edit
card 715 to the union:
```json
{"or":{"type":"draft","right_plus":"proposal"},"sort":"create","dir":"asc"}
```
**Outstanding-only refinement:** to hide proposals already merged (those carry a
`+proposal+merge audit` and a `merged` tag), exclude merged ones — simplest is a
tag-based filter on the proposal's `+tag` (not "merged"), since a single CQL negation across
the grandchild `+merge audit` is awkward. Finalize the exact CQL at deploy time against the
real prod tag/audit data. (Optional: also update the `real.yml` seed content so fresh
installs get the union query.)

## 6. Rollback (thin, 1-step)

WS6 is confined to `mod/editorial_review`. To revert behavior without a full redeploy:
```bash
git checkout <pre-WS6-ref> -- mod/editorial_review     # e.g. the commit before the PR #25 merge
RAILS_ENV=production bundle exec decko update
sudo systemctl restart hyperon-wiki.service hyperon-wiki-worker.service
```
The `proposal` / `merge_draft` codename cards persist in the DB after rollback — benign
(their sets simply won't load). No data migration is required to roll back; `+proposal` /
`+merge draft` / audit cards created while live remain as inert content cards.

## 7. Deferred / not in this deploy

- Review Queue union query (manual, §5).
- Bulk accept/reject (Q3) and live 4th-pane TinyMCE editor (Q1) — future.
- Wiring `spec/integration/` into CI — out of WS6 scope.
