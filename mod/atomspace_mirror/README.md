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
- `lib/atomspace_mirror/engine.rb` — `Rails::Engine` that appends the mod's `db/migrate` to the
  app migration path (required for `decko update` to run the migration; see below).
- `lib/card/mod/atomspace_mirror.rb` — Decko mod entry; auto-required at boot, requires the engine
  then `lib/atomspace_mirror.rb` (see "Loading & migration path" below).

## Loading & migration path

Follows the repo's local-mod convention (cf. `mod/mcp_api`):

- `lib/card/mod/atomspace_mirror.rb` is the entry Decko auto-requires for mods shipping Ruby under
  `lib/card/mod/`. It requires the engine, then `lib/atomspace_mirror.rb` (the models +
  read-consistency). Decko does not autoload mod `lib/`, so the require chain is explicit.
- `lib/atomspace_mirror/engine.rb` (`AtomspaceMirror::Engine < Rails::Engine`) appends the mod's
  `db/migrate` to the application migration path (`app.config.paths["db/migrate"]` +
  `ActiveRecord::Migrator.migrations_paths`). **This is required:** Decko does NOT auto-discover a
  mod's `db/migrate` — without the engine append, the deck's migration path is only the deck-root
  `db/migrate` (verified on the dev box 2026-06-15; `mod/mcp_api`'s own `db/migrate` never ran for
  exactly this reason — its engine omits the append). With the append, `decko update` /
  `rake db:migrate` run the migration and it tracks in the standard `schema_migrations` table.

**Verification (dev box, 2026-06-15):** the migration DDL was applied on dev (against PG 17.9) and
**all schema checks passed** — 4 tables, 6 indexes (correct partials/uniques), 3 CHECK constraints,
single seeded `mirror_state` row (`draining_enabled=false`), and a rejected second-row insert — then
rolled back to pristine. The engine-append discovery path is the fix for `decko update` pickup.

## Deferred (NOT in Slice 1)

- **ReadConsistencyPort binding** — wiring `ReadConsistency` into Lane C's
  `Atomspace::ReadConsistencyPort` is the **integration glue step** (Lane C's port lives in
  `mod/mcp_api`, which is not on this branch). Added when Lane A and Lane C combine.
- **Drain worker / integrate hook / bootstrap / reconcile execution** — Slices 2–3.
  In particular (**OQ#15**, Slice 3): the drain worker must independently reject structurally
  invalid queued rows; `superseded_by_later_or_reconcile?` returning `false` must **not** be read
  as "safe to apply" at the write path.
