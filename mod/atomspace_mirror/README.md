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
- `lib/atomspace_mirror.rb` — require chain for the models + read-consistency.
- **`config/initializers/atomspace_mirror.rb`** (deck-level, not in this mod dir) — the wiring that
  actually loads the mod and registers its migration path. See below.

## Loading & migration path

**Decko does not auto-load a deck-local mod's Ruby, and `decko update` does NOT run a mod's
`db/migrate`** (verified on the dev box 2026-06-15: a `lib/card/mod/<name>.rb` entry + a
`Rails::Engine` are never loaded at boot, and `decko update`'s schema-migration step ignores
ActiveRecord's migration path — which is why `mod/mcp_api`'s own migration never ran). Deck-local
mods in this deck are wired by **explicit requires in the deck config** (e.g. `mcp_api` in
`config/routes.rb`).

So this mod is wired by the deck-level **`config/initializers/atomspace_mirror.rb`**, which:
1. `require`s `mod/atomspace_mirror/lib/atomspace_mirror` (models + read-consistency) so they load
   at boot (Decko does not autoload mod `lib/`);
2. appends `mod/atomspace_mirror/db/migrate` to **`config.paths["db/migrate"]`** (the source
   `rake db:migrate` actually reads) and to `ActiveRecord::Migrator.migrations_paths`, so a
   standard Rails migration run picks up the schema migration.

## Deploy

The migration runs via **`rake db:migrate`**, not `decko update`.

```bash
# preflight: confirm Rails.env + DB host/db identity (dev vs prod)
RAILS_ENV=production bundle exec ruby -e 'require "./config/environment"; \
  c=ActiveRecord::Base.connection_db_config.configuration_hash; puts "env=#{Rails.env} host=#{c[:host]} db=#{c[:database]}"'

# snapshot the DB first (RDS console snapshot, or a version-matched pg_dump)

# pre-check: record schema_migrations count; confirm 20260614000001 not yet applied
RAILS_ENV=production bundle exec ruby -e 'require "./config/environment"; \
  v=ActiveRecord::Base.connection.select_values("SELECT version FROM schema_migrations"); \
  puts "count=#{v.size} has=#{v.include?(%q{20260614000001})}"'

# apply (targeted is safest; the initializer must be present so the path is registered)
RAILS_ENV=production bundle exec rake db:migrate:up VERSION=20260614000001

# post-check: count +1, version present, four mirror_* tables exist
```

**Rollback** (additive + exactly reversible — touches no existing table):
```bash
RAILS_ENV=production bundle exec ruby -e 'require "./config/environment"; c=ActiveRecord::Base.connection; \
  c.execute("DROP TABLE IF EXISTS mirror_reconcile_runs, mirror_bootstrap_runs, mirror_outbox, mirror_state CASCADE"); \
  c.execute("DELETE FROM schema_migrations WHERE version = " + c.quote("20260614000001"))'
```

> **Note:** the dev box's `pg_dump` (v14) is older than the RDS server (PG 17) — `pg_dump` and the
> MCP `admin_backup` fail with a version mismatch. Use an RDS console snapshot until the client is
> upgraded (separate maintenance task).

## Deferred (NOT in Slice 1)

- **ReadConsistencyPort binding** — wiring `ReadConsistency` into Lane C's
  `Atomspace::ReadConsistencyPort` is the **integration glue step** (Lane C's port lives in
  `mod/mcp_api`, which is not on this branch). Added when Lane A and Lane C combine.
- **Drain worker / integrate hook / bootstrap / reconcile execution** — Slices 2–3.
  In particular (**OQ#15**, Slice 3): the drain worker must independently reject structurally
  invalid queued rows; `superseded_by_later_or_reconcile?` returning `false` must **not** be read
  as "safe to apply" at the write path.
