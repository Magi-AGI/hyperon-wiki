# AtomSpace Mirror — Phase 5 Deployment & Operations Runbook

Operational runbook for taking the Decko/Postgres → Hyperon AtomSpace write-through mirror to
production (GAIA / SingularityNET RFP). Canonical design: **Card 17120** (System Integration Plan)
+ **Card 17161** (Implementation Plan). This doc is the deploy/ops counterpart to those cards.

> **This packet is source-level only.** Nothing here activates the mirror. Activation is a separate,
> user-approved operation performed against prod by an operator following the sequence below.

## Topology (Phase 5, same-user)

All three long-running processes and the Rails web process run as the **same Unix user
(`<app-user>` — the account the Decko app already runs as)**, co-located on the prod app host. This is the approved Phase-5 topology and needs no shared-group work:
the sidecar creates its run dir `0700` and its socket `0600`, and every peer (web read client, drain
worker) is the same user, so it can traverse and connect. If org policy later forces distinct users,
the sidecar's hardcoded `os.chmod(run_dir, 0o700)` must become configurable (a sidecar code change) —
out of scope here.

- **Sidecar** (`atomspace-mirror-sidecar.service`) — `python3 -m atomspace_mirror_sidecar`, holds the
  in-memory PyListSpace, serves `127.0.0.1:9407` + `$SIDECAR_RUN_DIR/sidecar.sock`.
- **Drain worker** (`atomspace-mirror-drain.service`) — `rake atomspace_mirror:drain`, the singleton
  forward-drain loop (Postgres advisory lock).
- **Drift monitors** (`atomspace-mirror-drift.service`) — `rake atomspace_mirror:drift_schedule`,
  report-only Section-2 stream monitors.
- **Web** — the existing Decko/Puma process, which loads the mirror mod + read surface.

Unit + env templates live in `deploy/systemd/`. Copy each `*.service.example` to
`/etc/systemd/system/<name>.service`, copy `atomspace-mirror.env.example` to
`<ops-env-file>` (`chmod 0600`, owned by `<app-user>`), `systemctl daemon-reload`.

> Concrete values for `<app-user>`, `<deck-root>`, `<ops-env-file>`, and `<rbenv-shims>`
> come from the server-access handoff (the Administrator card and its children), not from
> this file.

**Two env files, distinct roles (Codex C1):**
- **App env** `<deck-root>/.env.production` — the existing file the web/jobs units
  already source: `DB_USERNAME`, `DATABASE_PASSWORD`, `DB_HOST`, `SECRET_KEY_BASE`, `RAILS_ENV`, and
  (at activation) the **`ATOMSPACE_MIRRORING_ENABLED` master gate**. The drain + drift units source it
  too (they need DB credentials). This is where the activation gate lives — the web hook reads it, not
  the atomspace file.
- **Ops env** `<ops-env-file>` (the `atomspace-mirror.env` file created above) — sidecar/drift
  tunables only (`SIDECAR_*`, `ATOMSPACE_DRIFT_READ_TIMEOUT`, RYW bounds). No DB creds, no app secrets.

**Ruby is rbenv on the deployed host** — confirm the shim path through the server-access
handoff before activation, since this repository records no concrete paths. The units call
`<rbenv-shims>/bundle` and
put `<rbenv-shims>` (and `<rbenv-bin>`) on `PATH` — `/usr/bin/env bundle` would miss the
rbenv-managed Ruby.

**Do NOT `systemctl enable` the sidecar or drain units** (they intentionally ship without
`[Install]`): a host reboot must never auto-start an empty in-memory Space or resume the drain into it.
Both are started only by the activation / coordinated-rebuild runbook. The drift unit is safe to enable
(report-only, sidecar-independent).

## Hard safety gates (apply to every step)

- **`ATOMSPACE_MIRRORING_ENABLED`** must be exactly the string `true` to activate; anything else is
  dormant (save hook no-ops, read-consistency port stays unbound). Do not set it until the activation
  step, and only after the mirror tables exist.
- **Pin the DB host** and run **`RAILS_ENV=production`** on every DB command (dev and prod both run
  the production env; the DB host distinguishes them). Preflight-print `env`, `host`, `db` before any
  DDL (README one-liner in `mod/atomspace_mirror/README.md`).
- **Migrate via `rake db:migrate:up VERSION=<v>`**, never `decko update` (it ignores the mod's
  migration path). Three migrations, applied in order: `20260614000001`, `20260623000001`,
  `20260624000001`.
- **RDS console snapshot before migrate** (the app host `pg_dump` v14 vs RDS PG17 mismatch makes
  local `pg_dump` / `admin_backup` fail).
- **No broad `pkill`** (e.g. `pkill -f atomspace_mirror_sidecar`) — stop via `systemctl` / the
  pidfile; a stray pattern kill can hit a partner process. The sidecar self-guards double-start via a
  socket liveness probe.
- **No branch switch on prod/dev** — path-checkout only after `git fetch`.
- **No read exposure before readiness** — the read surface fails closed `503 mirror_not_ready` until
  the mirror is enabled + migrated + bootstrapped + backed by a reachable, non-empty sidecar (see
  Readiness gate). Do not grant `mcp:atomspace:read` to agents until go-live is verified.
  **POLICY REV4 caveat:** the scope is no longer purely an allowlist knob — admin and
  `Raw Data Analyst` principals now receive it automatically at token mint (see
  [Read-scope policy](#read-scope-policy-rev4)), so "not granted yet" means *those principals must
  not mint tokens against the L9 surface yet*, not merely "`ATOMSPACE_READ_GRANTS` is empty". The
  readiness gate (503 `mirror_not_ready`) remains the real fail-closed protection here.
- A **WS6/page-attribution agent** may be active on the prod tree — keep ops narrow, do not clobber
  its staged/untracked work.

## Activation sequence (operator, prod)

Env is set **before** bootstrap so the save hook captures the forward tail while the drain stays
paused (the §1 race-protection assumes the hook is attached; under the deploy gate "attached" =
`ATOMSPACE_MIRRORING_ENABLED=true`). Setting env *after* bootstrap would silently drop every card
save that occurs during the ~27s sweep. Alternative: run the whole sequence in a write-quiescent
window; either way reads stay gated by the readiness check.

1. **Preflight (read-only).** Print `env=production host=<PROD DB> db=<name>`; confirm 0/3 mirror
   migrations applied; confirm `ATOMSPACE_MIRRORING_ENABLED` is not `true`; confirm system `python3`
   + `hyperon==0.2.10` importable (prod venv lacks ensurepip → `pip install --user hyperon==0.2.10`);
   confirm `rufus-scheduler` bundled; confirm no live sidecar pidfile/socket.
2. **RDS snapshot.** Take + confirm an RDS console snapshot. No migrate until it completes.
3. **Migrate (still dormant).** `RAILS_ENV=production bundle exec rake db:migrate:up VERSION=20260614000001`
   then `…20260623000001` then `…20260624000001`. Verify four `mirror_*` tables, the `status`/`stable`
   columns, and exactly one seeded `mirror_state` row (`draining_enabled=false`). Mirror still dormant.
4. **Start the sidecar (empty Space).** `systemctl start atomspace-mirror-sidecar`. Verify
   `GET /space_stats` `atom_count == 0` and `/health/watermark` reachable over the Unix socket.
5. **Activate the hook, drain still paused.** Set `ATOMSPACE_MIRRORING_ENABLED=true` in the **app env
   file** `<deck-root>/.env.production` (the file web/jobs actually source — NOT the ops env
   `atomspace-mirror.env`), then restart **web** and **every write-capable worker** (any
   delayed_job/jobs/runner/cron unit that can save a card). Do NOT start the drain yet. The save hook
   now enqueues forward `mirror_outbox` rows; the read-consistency port binds. Reads still fail closed
   `mirror_not_ready` (bootstrap not complete).
   **Env coverage (Codex C1):** every write-capable Rails process must receive
   `ATOMSPACE_MIRRORING_ENABLED=true` before the a_start snapshot in step 6, or its writes are dropped
   from the mirror. On this deck the integrate hook runs INLINE in the web request
   (`Cardio.config.delaying=false`), so web is the primary writer; still enumerate + restart any
   separate worker/cron units in preflight. Confirm with `systemctl show -p Environment <unit>` (or
   `cat /proc/<pid>/environ`) that each writer's live env has the gate set.
6. **Bootstrap.** With the drain **not** running: `RAILS_ENV=production bundle exec rake
   atomspace_mirror:bootstrap`. It pauses draining, asserts the Space is empty, snapshots
   `a_start = MAX(non-draft card_actions.id)`, bulk-loads ~9663 cards (~27s), then in one txn
   supersedes pre-`a_start` queued rows and sets `bootstrap_a_start` + `draining_enabled=true`. Verify
   run `completed`, `cards_swept ≈ 9663`, `/space_stats ≈ 16958` atoms.
7. **Memory guard.** Immediately after bootstrap, measure the sidecar RSS and `/space_stats`. Expected
   ~358MB RSS / ~17K atoms. **Abort activation** (stop sidecar, investigate) if RSS or atom_count is
   unexpectedly high — the box is 3.7Gi and also runs Decko/Postgres client + drain + drift.
8. **Start the drain worker.** `systemctl start atomspace-mirror-drain`. Queued post-`a_start` rows
   drain to `delivered`; `mirror_state.last_drained_action_id` advances; drain lag → 0.
9. **Start drift monitors.** `systemctl start atomspace-mirror-drift`. Schedule the Mechanism-3 sweep
   (`atomspace_mirror:drift_sweep`) off-hours via a systemd timer or cron.
10. **Verify + expose reads.** Save a card, poll the L9 read path (`:ready` after drain), run one
    drift sweep (expect `stable`, zero drift). Only then grant `mcp:atomspace:read` to agents —
    under REV4 that means: only then hand out tokens minted for admin / `Raw Data Analyst`
    principals, and only then add service-key entries to `ATOMSPACE_READ_GRANTS`.

## Read-scope policy (REV4)

`mcp:atomspace:read` is minted by `McpApi::AtomspaceGrants` (`mod/mcp_api/lib/mcp_api/`) for:

| Principal | Auto-granted? | Source |
|---|---|---|
| Decko **admin** user | yes | `Mcp::UserAuthenticator.check_admin_status` |
| Decko role **`Raw Data Analyst`** | yes | `Mcp::UserAuthenticator.get_user_roles` (case/separator-folded) |
| Anything in `ATOMSPACE_READ_GRANTS` | yes | ENV allowlist, matched against the JWT `sub` |
| **API-key** principals (`key:<id>`) | **no** — allowlist only | role on a key token is caller-asserted; the legacy `MCP_API_KEY` is permitted every role |

REV4 supersedes REV3's "explicit allowlist only, never role-derived": the mirror *is* the
raw-data surface, admins already bypass Decko read rules, and `Raw Data Analyst` is the role
designed for full raw-data access. Unchanged by REV4:

- **`mcp:admin` is a separate scope.** Read scope never implies it, so quarantine
  (`mcp:atomspace:read` + `mcp:admin`) stays closed to a non-admin `Raw Data Analyst`.
- **Card-scoped responses are still filtered per atom** through Decko read rules
  (`AtomspaceReadFilter`). REV4 widens who may *call* the L9 surface, not what any caller may
  *see*. A `Raw Data Analyst` sees exactly what their `+*read` rules already allow — if analysts
  are expected to read all `RawData+…` content, that is a Decko read-rule configuration task, not
  a token-scope one.
- Aggregate tools (`atom_types`, `atom_count_by_type`, `space_stats`) are gate-only and carry no
  card-scoped payload, so they expose counts/type names to any read-scoped principal.

Each step's rollback: unset `ATOMSPACE_MIRRORING_ENABLED` in `.env.production` + restart the writers
(hook no-ops, port unbinds → reads 503). The migration rollback is additive and exactly reversible
(it touches no existing table) — run this exact SQL against the pinned prod DB (or the equivalent
`down` migrations):

```sql
-- drop the four mirror tables (named explicitly; CASCADE clears their own FKs/indexes only)
DROP TABLE IF EXISTS mirror_reconcile_runs, mirror_bootstrap_runs, mirror_outbox, mirror_state CASCADE;

-- remove the three mirror schema_migrations rows so a later re-migrate re-applies cleanly
DELETE FROM schema_migrations
 WHERE version IN ('20260614000001', '20260623000001', '20260624000001');
```

A pre-applied migration at preflight = **HALT and inventory** the prior state, not auto-rollback.

## Read-readiness gate

`Atomspace::MirrorReadiness.check` (`mod/mcp_api/lib/atomspace/mirror_readiness.rb`) is a fail-closed
predicate consulted by `AtomspaceMirrorController#require_mirror_ready!` on **every** read action —
card-scoped (including no-wait), aggregate, and admin quarantine. It closes the gap where only
`wait_for_event_id` paths consulted `ReadConsistencyPort`. Ready requires: mirroring enabled → mirror
tables available → a completed bootstrap (`bootstrap_a_start` + `draining_enabled` + a `completed`
run) → no `running` bootstrap (mid-rebuild) → sidecar reachable **and populated to the bootstrap
baseline**. Any failure → `503 mirror_not_ready` with a `reason` (`mirroring_disabled` /
`mirror_tables_unavailable` / `mirror_not_bootstrapped` / `mirror_rebuild_in_progress` /
`sidecar_unreachable` / `sidecar_empty_post_restart` / `sidecar_below_expected` /
`readiness_probe_error:*`).

**The population check is a baseline threshold, not a bare non-empty check (Codex C2).** The gate reads
the sidecar's **DeckoCard** count (from the ReadClient's normalized `space_stats.types` map) and
requires it to be **≥ the last completed bootstrap's `cards_swept`**. A bare `atom_count > 0` check
would false-green a partial post-restart Space the moment the drain applied even one row;
`sidecar_below_expected` catches that. The baseline holds because the forward path is additive within a
bootstrap generation (POLICY-B upsert + trash-not-remove + new cards), so a faithful Space never drops
below its bootstrap DeckoCard count. `sidecar_empty_post_restart` is the fully-empty crash-restart
guard; `sidecar_below_expected` is the partial-Space guard.

**Hard-purge caveat (false-red).** If cards are *hard-purged* from Postgres (not the normal trash flow),
the live DeckoCard count can legitimately fall below the recorded `cards_swept`, holding reads at
`sidecar_below_expected`. The fix is to **re-bootstrap** (coordinated rebuild), which writes a new
completed run whose `cards_swept` becomes the new, correct baseline. Do not lower the threshold to
paper over a purge — re-establish the baseline.

## Fail-closed restart / rebuild

**There is no bare auto-restart into serving.** The sidecar unit is `Restart=no`: the Phase-5 Space is
in-memory, so a crash/OOM restart returns EMPTY while Postgres still says bootstrapped/draining. The
drain `BindsTo` the sidecar, so a sidecar exit stops the drain (it can never apply forward rows into a
rebuilding Space), and the readiness gate makes reads fail closed. Recovery is the **coordinated
rebuild**, operator-run:

1. `systemctl stop atomspace-mirror-drain` (BindsTo already stopped it; confirm).
2. `systemctl restart atomspace-mirror-sidecar` → fresh **empty** Space; confirm `space_stats`
   `atom_count == 0`.
3. `rake atomspace_mirror:bootstrap` (Option A: fresh Space; the sweep is not idempotent).
4. Verify: `/space_stats` back to ~17K, memory guard, then one `atomspace_mirror:drift_sweep` `stable`.
5. `systemctl start atomspace-mirror-drain`. Reads recover to ready automatically.

### Fast-rebuild scope (Phase 5) — provenance is NOT restart-durable

The bootstrap sweep (`/bulk_load`) restores **DeckoCard + DeckoReference** atoms only — it emits **no
DeckoProvenance**. Forward `/apply` provenance atoms (the in-Space audit log powering
`get_card_provenance`) are therefore **lost on a sidecar restart** and are **not** restored by the fast
rebuild, even though the `mirror_outbox` rows still read `delivered`. This is an accepted Phase-5
limitation:

- **Postgres remains the durable audit source** (`card_actions` / `mirror_outbox` retain full
  history); only the *in-Space* provenance projection is non-durable across restart.
- The readiness gate prevents serving a *misleadingly empty* Space (`sidecar_empty_post_restart`), but
  once rebuilt, `get_card_provenance` returns only post-rebuild provenance until a future
  outbox-replay or persistent-backend track lands. Treat in-Space `get_card_provenance` as
  best-effort/non-durable in Phase 5 and prefer the Postgres audit trail for authoritative history.
- Future options (out of scope here): provenance-replay rebuild (re-drive `delivered` outbox rows
  through `/apply` instead of `bulk_load`), or a persistent backend (DAS / MORK / atomspace-rocks /
  source-patched native Space). Do **not** block Phase-5 go-live on either.

## Observability

Report-only in Phase 5. Stream monitors (`atomspace-mirror-drift.service`) emit structured JSON to
`Rails.logger`: hook-tail-lag (30s), coverage-gap (300s, 2-run debounce), drain-lag/watermark (60s),
plus the missed-run watchdog (`mechanism_run_skipped`). The Mechanism-3 sweep records a
`mirror_reconcile_runs` row (`stable` + `pg_only`/`space_only`/`mismatch`). Alert seams:
`DriftRunner#emitter`, `DrainWorker#alerter`, `Atomspace::Observability.alert` — wire a real
metric/pager adapter at deploy time. **Watermark caveat:** after `bulk_load` the sidecar
`last_applied_action_id` is `nil` and the DB `last_drained_action_id` advances on safe-skip statuses
the sidecar never applied — so the two are not expected to be equal. Valid signals: sidecar watermark
must never *exceed* the DB watermark (integrity alarm); drain lag is measured DB-side; true PG↔Space
equivalence is the Mechanism-3 sweep, not watermark equality.
