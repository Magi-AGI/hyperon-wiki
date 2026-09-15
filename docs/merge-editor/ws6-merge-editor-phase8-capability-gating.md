# WS6 Phase 8.1 — Capability-Based Editorial Gating (spec for sign-off)

Status: **DRAFT — awaiting Codex + Gemini quick sign-off before implementation.**
Decision ratified in principle by both reviewers (2026-06-26); this doc pins the
exact code changes + test matrix and surfaces one required conflict resolution.

## 1. Decision (ratified)

Gate WS6's editorial actions on **capability**, not a hard-coded role name:

- The authoritative capability is `parent.ok?(:update)` — "may this user change the
  target article?" In prod, article edit is restricted to the `Editor` role, so this
  resolves to "Editors (and Admins)" with **no role name or role id baked into the mod**.
  It works identically on dev (which has no `Editor` role yet) and on prod, and tracks
  whatever permission model the wiki admins configure.
- Applies to **both** entry points of the merge workflow:
  1. **Legacy bridge** ("Open as proposal") — promoting a `+AI` draft into a `+proposal`
     starts an administrative merge workflow, so it requires the same editorial
     capability as applying it.
  2. **Merge-apply** (write parent) — already gated; keep authoritative.

Rationale (both reviewers): hard-coding role names/ids is an environment-portability
anti-pattern; `parent.ok?(:update)` leverages Decko's native dynamic permission system.

## 2. Code changes

### 2.1 Bridge — UI gate (`set/right/ai_draft.rb`)
`ai_draft_can_bridge?` currently returns only `ok?(:create)` on the `+proposal`
(which resolves to `*all+*create → "Anyone Signed In"` — too loose). Require **both**
parent-update capability AND create permission (Codex: "require both"):

```ruby
def ai_draft_can_bridge?(parent)
  parent.ok?(:update) &&
    Card.new(name: "#{parent.name}+proposal", type_id: parent.type_id).ok?(:create)
rescue StandardError
  false
end
```
Button is already hidden when `ai_draft_can_bridge?` is false — no other UI change.

### 2.2 Bridge — SERVER-SIDE gate (`set/right/proposal.rb`) — **required; UI gating alone is insufficient**
A crafted POST with `legacy_bridge_from` must not create a bridged proposal unless the
actor can update the parent. Add a guard event in the same stage as (and ordered before)
`seed_legacy_proposal`:

```ruby
event :guard_legacy_bridge, :prepare_to_validate, on: :create,
      when: proc { Env.params[:legacy_bridge_from].present? } do
  parent = left
  unless parent&.ok?(:update)
    errors.add(:legacy_bridge_from,
               "you do not have permission to start a merge on #{parent&.name}")
  end
end
```
A validation error here aborts the create — no `+proposal`, `+base`, or `+provenance`
cards are written. (Note: a user could still create `<Parent>+proposal` *directly* if
proposal card-creation permits it; that is the documented v2 "anyone may propose" seam
and is governed separately. This guard covers only the legacy-bridge promotion path.)

### 2.3 Apply — no change (`set/right/merge_draft.rb:186`)
`next merge_apply_reject(...) unless parent.ok?(:update)` is already the authoritative
gate (gate 1 of the four-fold apply gate). Keep as-is; add explicit tests (§4).

## 3. REQUIRED conflict resolution — blunt "Merge AI Draft → Parent" button

**Blocker discovered during Phase 8 drafting.** The merge from `origin/main` (`cbfc859`)
brought in `set/all/ai_draft_aware.rb`, whose `view :ai_draft_link` renders a
**"Merge AI Draft → Parent"** button (lines 30–36):

```ruby
merge_button = if card.ok?(:update)
                 link_to_card card.name, "Merge AI Draft &rarr; Parent",
                              path: { action: :update,
                                      card: { content: ai_draft.content },
                                      merge_draft: "true" },
                              class: "btn btn-primary btn-sm"
               end
```

This POSTs the AI draft's content **directly onto the parent** (`action: :update` on
`card.name`), bypassing the WS6 3-way workbench and the verifying apply gate entirely.
It is the one-click blunt overwrite that WS6 explicitly removed from `ai_draft.rb`
(the mutual-exclusion change), reintroduced in the file the other agent added. It is
reachable from Published `:core` and the IndexSubtopic/IndexSection structures.

**Effect:** on the integrated branch the WS6 mutual-exclusion invariant (Phase 7.4 —
"only `apply_merge_draft` writes a parent through the governance gate") is undermined.
The 7.4 regression test did not catch it because it exercised the old
`?merge_draft=true` *event* path, not a standard direct parent-update action.

**This is the other agent's code — NOT to be resolved unilaterally** (reviewers' standing
rule). Proposed resolution options, for Lake + the other agent + reviewers to choose:

- **(A) Redirect the button to the workbench (preferred).** Replace the blunt
  `action: :update` button with a link to the WS6 workbench / "Open as proposal" bridge,
  so "Merge AI Draft → Parent" routes through the governance gate instead of overwriting.
  Preserves the other agent's entry-point UX; restores mutual exclusion.
- **(B) Remove the merge_button**, keep only "Review AI Draft →".
- **(C) Accept the blunt path as an intentional editor convenience** and formally
  retire the WS6 mutual-exclusion invariant — requires re-opening the Khellar-call
  human-approval-gate agreement (not recommended).

Whichever is chosen, the Phase 7.4 invariant test must be extended to cover the
direct parent-update path (currently a gap).

## 4. Test matrix (Codex)

Runner + RSpec, for both bridge and apply:
- **signed-in, NO parent-update capability** (e.g. plain `Anyone Signed In`):
  bridge button hidden; server bridge POST rejected (no `+proposal` created); apply rejected.
- **editor / has parent-update capability**: bridge allowed (proposal created, base stamped);
  apply allowed.
- **admin**: allowed — *because admin has the capability*, not via any admin special-case.
- **mutual exclusion (extended 7.4)**: the resolved "Merge AI Draft → Parent" path does
  not write the parent outside `apply_merge_draft`.

## 5. Sequencing

1. Sign-off on this spec (esp. §3 resolution choice) by Codex + Gemini + Lake.
2. Implement §2 (capability gating) as the core security commit of Phase 8.
3. Implement the chosen §3 resolution (coordinate with the other agent for `ai_draft_aware.rb`).
4. Extend tests (§4) incl. the 7.4 direct-update gap.
5. Review Queue (prod Search card 715) union query is a **post-deploy** DB step — not part
   of this code change (see Phase 8 release notes).
