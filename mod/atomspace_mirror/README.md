# atomspace_mirror (Lane A)

Decko mod implementing the **AtomSpace Mirror** engine — the write-through mirror from
Decko/Postgres to the Hyperon Space (Phase 4 of the SingularityNET RFP).

Canonical design: **Card 17120 — AtomSpace Mirror System Integration Plan** (Sections 1–12).
Build contract: **Card 17161 — Implementation Plan** (Levels 1–11).

## Slice 1 (this scaffold)

Self-contained engine foundation — **no drain / no sidecar I/O yet**:

- `db/migrate/20260614000001_create_atomspace_mirror_tables.rb` — the four tables
  (`mirror_state`, `mirror_outbox`, `mirror_bootstrap_runs`, `mirror_reconcile_runs`) exactly per
  §1 (Bootstrap) + §3 (Reconciliation), with the 2026-06-14 amendments:
  - **OQ#9** — `mirror_state` singleton: `singleton_guard` + UNIQUE index + `CHECK (singleton_guard = true)`.
  - **OQ#12** — `mirror_outbox` action_id structural invariants (two CHECK constraints, implication form).
- `lib/mirror_state.rb`, `lib/mirror_outbox.rb`, `lib/mirror_bootstrap_run.rb`,
  `lib/mirror_reconcile_run.rb` — ActiveRecord models. Tables are singular, so each sets
  `self.table_name` explicitly (Rails would otherwise pluralize).
- `lib/mirror_outbox.rb` also carries the shared **`superseded_by_later_or_reconcile?`** class
  method (§10 helper; used by the §10 drain guard, §3 reset rake, and L7 readiness).
- `lib/read_consistency.rb` — `ReadConsistency.check_event_ready(event_id)` (L7 / §4). Dispatches
  by `event_kind` first; fails closed (`:integrity_error`) on any corrupt combination.
- `lib/atomspace_mirror.rb` — require chain for the above (mod `lib/` is not autoloaded).
- `lib/card/mod/atomspace_mirror.rb` — Decko mod entry; auto-required at boot, requires
  `lib/atomspace_mirror.rb` (see "Loading & migration path" below).

## Loading & migration path

Follows the repo's local-mod convention (cf. `mod/mcp_api`, whose migration is live in production):

- `lib/card/mod/atomspace_mirror.rb` is the entry Decko auto-requires for mods shipping Ruby under
  `lib/card/mod/`. It requires `lib/atomspace_mirror.rb`, which loads the models + read-consistency
  (Decko does not autoload mod `lib/`, so the require chain is explicit).
- Migrations in `db/migrate/` are run by Decko's mod-migration system via **`decko update`** — the
  same mechanism that ran `mod/mcp_api/db/migrate`.

**Verification note:** this local checkout has neither the deck's gems nor a database, so end-to-end
`decko update` execution is verified on the dev server (as with the Lane C dev capstone), not
locally. Local verification covers `ruby -c` on all files plus a stubbed-model logic harness for
`check_event_ready` (23/23 paths).

## Deferred (NOT in Slice 1)

- **ReadConsistencyPort binding** — wiring `ReadConsistency` into Lane C's
  `Atomspace::ReadConsistencyPort` is the **integration glue step** (Lane C's port lives in
  `mod/mcp_api`, which is not on this branch). Added when Lane A and Lane C combine.
- **Drain worker / integrate hook / bootstrap / reconcile execution** — Slices 2–3.
  In particular (**OQ#15**, Slice 3): the drain worker must independently reject structurally
  invalid queued rows; `superseded_by_later_or_reconcile?` returning `false` must **not** be read
  as "safe to apply" at the write path.
