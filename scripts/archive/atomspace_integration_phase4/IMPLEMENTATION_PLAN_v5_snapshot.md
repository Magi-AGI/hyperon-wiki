# Hyperon Wiki AtomSpace Mirror -- Implementation Plan

*Phase 4 of the SingularityNET RFP cognitive-stack roadmap. Published 2026-05-08. Card 17120 v9 remains the canonical design-decision record; this plan translates the locked decisions into engineer-facing build contracts for the implementation team (Lanes A / B / C; see File Map).*

## Overview

This plan describes the implementation of a write-through mirror from the *Magi Archive* Decko wiki (PostgreSQL source of truth) to a Hyperon Space (in-memory AtomSpace) running in a sidecar process. Decko cards become atoms via three new atom types; every non-draft card mutation produces a row in a Postgres outbox table that a singleton drain worker forwards to the sidecar over a stable JSON IPC contract. The mirror is unidirectional in Phase 4: Decko writes flow to the Space; the Space exposes read-only queries through an extended Ruby MCP server. Phase 5+ adds bidirectional sync, durable substrate, and an agent atom-write surface.

Components:

- **Mirror Mod** -- Rails engine `mod/atomspace_mirror/` subscribing to Decko's `integrate_with_delay` event hook and recording atom-events to the outbox.
- **Outbox** -- Postgres table `mirror_outbox` carrying serialized atom-event payloads, status, and reconciliation linkage.
- **Encoder** -- pure-Ruby module emitting `DeckoCard` (14 fields), `DeckoReference` (5 fields, 4-code), and `DeckoProvenance` (20 fields = Source 5's 16 + Source 6's 4 agent-identity additions) atom shapes.
- **Sidecar** -- Python long-running process holding the `SpaceRef` and a registered space observer; consumes the outbox indirectly via the IPC contract. The sidecar does not access Postgres.
- **IPC Contract** -- stable JSON over HTTP/Unix-socket between Ruby drain worker and Python sidecar. Source 5 V5-PROTOCOL-3: `delayed_jobs` is the Rails-side queue, NOT the IPC contract.
- **Read API** -- eight-tool read surface on the existing Ruby `hyperon-wiki-mcp`, gated by Decko's read-rule filter via `Card::Auth.as(current_account.name)`.
- **Drift Pipeline** -- periodic detection (tail-lag, coverage-gap, contiguous-watermark diagnostic, SHA256 full-projection) and reconciliation (per-class remediation primitives with explicit `source_reconcile_event_id` linkage).

## Reference Implementations

- *atomspace-bridge* -- `https://github.com/trueagi-io/atomspace-bridge` -- read-only PostgreSQL to AtomSpace import. Phase 4 supersedes for the write-through track; bridge remains a reference for the Phase 3 read-only fallback.
- *hyperon-experimental* -- `c/src/space.rs:464-468` -- extern "C" `space_register_observer`. PATCH-1 adds the missing pybind11 binding.
- *hyperon-space* -- Phase 4 substrate (in-memory, single-process).
- Source 5 reconciliation -- `scripts/archive/atomspace_integration_phase4/source5_decko_semantics/findings_reconciled_crossmodel.txt` -- locks DeckoCard 14-field shape (Q6), 16-field D3-1 envelope (Q7), POLICY-B trash semantics (Q8), HTTP/Unix-socket IPC primary (Q9).
- Source 6 reconciliation -- `scripts/archive/atomspace_integration_phase4/source6_agent_mcp_surface/findings_reconciled_crossmodel.txt` -- locks 8-tool read surface (Q5), polling-first subscription model (Q4), 20-field D3-1 envelope (Q3, extends Source 5 with `agent_session_id`, `agent_kind`, `origin_system`, `origin_request_id`).
- Source 7 reconciliation -- `scripts/archive/atomspace_integration_phase4/source7_magus_plan_reconciliation/findings_reconciled_crossmodel.txt` -- locks V7-1 auth-on-read mirror (Source 5 read-side filter, NOT public projection).
- Card 17120 -- `Neoterics+Magus+Atomspace_Layer_-_Wiki_Integration_Plan+AtomSpace_Mirror_System_Integration_Plan` -- design-decision record for sections 1-11.

## Lanes

The build is divided into three lanes that run semi-independently after the Lane A / Lane B IPC contract is locked in week 1.

| Lane | Owner | Scope | Levels |
|---|---|---|---|
| A | Chris | Decko/Ruby Mirror Mod -- Rails engine `mod/atomspace_mirror/`: integrate hook, outbox table, drain worker, encoder, reconciler, helper, migrations, drift detection cron. Rails / ActiveRecord / Postgres territory. | 1, 2, 4, 5, 6, 8 |
| B | Alex | Sidecar + PATCH-1 upstream -- Python `sidecar/` holding the Hyperon Space, IPC server, observer wiring, apply semantics; plus the pybind11 binding for `space_register_observer` in `hyperon-experimental`. Rust/Python boundary plus the upstream PR. | 3 + upstream PR |
| C | Lake | Read API + Tests + Observability -- eight-tool read surface on `hyperon-wiki-mcp`, the integration test matrix, observability adapters, deployment runbook, agent-facing docs. | 7, 9, 10, 11 |

Coupling points:

- **Lane A / Lane B:** the IPC contract (stable JSON over HTTP/Unix-socket); lock the JSON schema for `POST /apply` payloads in week 1.
- **Lane B / Lane C:** the sidecar's apply-confirmation latency feeds Level 7's `check_event_ready` polling.
- **All three lanes:** the `superseded_by_later_or_reconcile?` helper (Invariant 8) is shared library code, not per-lane.

## Invariants

The following invariants apply across all Levels.

1. **Unidirectional mirror.** Decko is the source of truth. Three authorized Space mutation paths: bulk-load during Bootstrap, drain-worker forwarding during steady state, admin quarantine during reconciliation. All other Space mutation surfaces are disabled at the deployment boundary. (Card 17120 Section 5 v3.)
2. **Single Space handle.** The sidecar holds exactly one `SpaceRef`. No raw REPL, no MeTTa-write tools, no agent atom-write tools in Phase 4.
3. **Cardtype-agnostic encoding.** `DeckoCard` shape is fixed at 14 fields regardless of cardtype. PATCH-4 must not branch on cardtype. (Card 17120 Section 7 v2.)
4. **POLICY-B faithful-mirror trash.** Decko delete (`trash=true`) maps to `Replace(old_atom, new_atom_with_Trash_true)`, never live `Remove`. Atom-presence is invariant under trash transitions. (Source 5 Q8 [POLICY-B-FAITHFUL-MIRROR-CONFIRMED].)
5. **A_start is an `action_id`, not a timestamp.** `A_start := SELECT MAX(id) FROM card_actions WHERE draft IS NOT TRUE`. All bootstrap classification predicates use `action_id <= A_start`. Timestamp comparisons are rejected. (Card 17120 Section 1 Rider C v2.)
6. **Sidecar IPC boundary.** The sidecar consumes JSON payloads emitted by the Ruby drain worker over HTTP/Unix-socket. The sidecar has no Postgres connection. Cold-start replay is the drain worker's responsibility. (Source 5 Q9, V5-PROTOCOL-3.)
7. **`source_reconcile_event_id` linkage is the reconciliation primitive.** Two-phase release SQL filters by `WHERE source_reconcile_event_id = :reconcile_event_id`, never by id arithmetic. (Card 17120 Section 3 v9.)
8. **Helper `superseded_by_later_or_reconcile?(row)` is load-bearing.** Used at three sites: drain apply guard (L8), drain-lag reset rake (L6), `check_event_ready` (L7). Manual outbox writes that bypass the helper risk same-card stale overwrites.
9. **Auth-on-read at PATCH-5 = option (e).** Read tools filter through `Card::Auth.as(current_account.name) { Card.fetch(atom.card_id)&.ok?(:read) }`. Full internal mirror (every card the integrate hook fired on, including restricted) plus read-time filter. (Card 17120 Section 6, locked 2026-05-05.)
10. **`event_schema_version` is a string tag on the D3-1 envelope.** Value `"decko-spaceevent-v1"` per Source 5 line 393-397. Numeric versioning is rejected. The version tag lives on `DeckoProvenance`, not on `DeckoCard`. (Card 17120 Section 8 v3.)
11. **Drain has no action-id cursor.** The drain query is `MirrorOutbox.where(status: 'queued').order(:id).first`. No filter on `action_id`. The `mirror_state.last_drained_action_id` column is diagnostic / lag-cursor only (Section 2 Mechanism 2), NOT a drain cursor. (Card 17120 Section 10 v9.)
12. **Sidecar restart = full bootstrap re-run.** Phase 4 in-memory Space dies with the sidecar process; drain-worker tail replay cannot reconstruct bulk-loaded atoms (which have no outbox rows by design). Operator runbook treats sidecar restart as a Section 1 maintenance window. (Card 17120 Section 10 sidecar-availability lock.)
13. **Reconcile-INSERT-before-awaiting (single transaction).** Case (b) reconciliation INSERTs the reconcile event row FIRST within a single transaction, then INSERTs the linked `awaiting_reconcile` rows referencing the reconcile event's `event_id` via `source_reconcile_event_id`. Awaiting-first ordering is rejected because it strands awaiting rows if the reconcile is delivered before they exist. (Card 17120 Section 10 cross-reference: "Case (b) reconcile-INSERT-before-awaiting invariant unblocks the linked-release path.")
14. **Helper bails on reconcile rows.** `superseded_by_later_or_reconcile?(row)` returns `false` immediately if `row.event_kind == 'reconcile'`. Reconcile rows are never marked `superseded_by_later`; the helper does not attempt `action_id > nil` arithmetic on reconcile inputs. (Card 17120 Section 10 v9 helper, first guard.)
15. **Quarantine drift class is Space-but-not-Postgres.** Mechanism 3 `drift_space_only` triggers quarantine for atoms whose `card_id` has no corresponding `cards` row in PostgreSQL. NOT for atoms whose `card_id` lacks a `mirror_outbox` row (bulk-loaded atoms have no outbox row by design and are not orphans). (Card 17120 Section 3 quarantine semantics.)

## Level 1 -- Encoder

### Goal

Convert a Decko card revision into an ordered list of atom-events suitable for outbox insertion. Pure function, no I/O, no Decko model writes.

### Tasks

1. Create `mod/atomspace_mirror/lib/card_atom_encoder.rb` exposing `CardAtomEncoder.encode(action)` returning a list of atom-event hashes.
2. Implement `DeckoCard` emission with the 14-field arity locked in Source 5 Q6: `Id`, `Name`, `Key`, `Codename`, `TypeId`, `TypeName`, `LeftId`, `RightId`, `Content`, `Trash`, `CreatedAt`, `UpdatedAt`, `CreatorId`, `UpdaterId`. `Codename` reads from current state (NOT in `card_changes` `TRACKED_FIELDS` per V5-PROTOCOL-2); `NoCodename` sentinel when null. `LeftId` / `RightId` use `NoLeft` / `NoRight` sentinels when null.
3. Implement `DeckoReference` emission with the 5-field arity locked in Source 5 Q6: `RefererId`, `RefereeKey`, `RefereeId` (or `Unresolved`), `RefType` in `{I, L, Q, P}`, `IsPresent`. One atom per row in `card_references` for the affected card; rebuilt on every save/delete via Decko's reference machinery (NOT carried in `card_changes`).
4. Implement `DeckoProvenance` emission as a companion atom keyed by `event_id`. 20 fields total = Source 5's 16-field D3-1 envelope (Q7) + Source 6's 4 agent-identity extensions (Q3): `source` (constant `"decko"`), `event_schema_version` (constant `"decko-spaceevent-v1"`), `event_id` (`"decko:action:{action_id}"`), `action_id`, `act_id`, `super_action_id`, `action`, `draft`, `card_id`, `card_key`, `actor_id`, `auth_current_id`, `auth_as_id`, `acted_at`, `ip_address` (privacy-policy-gated), `stage` (constant `"integrate_with_delay"`), `changes` (array from `card_changes` joined with pre-state), `agent_session_id`, `agent_kind`, `origin_system`, `origin_request_id`. Source 6 fields read from request thread-local; canonical-null when the action originates outside an MCP request.
5. Reject draft actions at encoder entry: `action.draft? -> []`. Matches the `integrate_with_delay` filter (drafts do not fire integrate).
6. Old-state caching for Replace: encoder consults a pre-state snapshot per action OR the sidecar queries the Hyperon Space for the existing atom keyed on `Id` before emitting Replace. Encoder layer is stateless; pre-state lookup is the worker's responsibility (encoder receives the pre-state in the action context).

### Acceptance

- 14-field `DeckoCard` arity preserved across a fixture suite spanning all production cardtypes; field order matches Source 5 Q6 exactly.
- 5-field `DeckoReference` arity; `RefType` always one of `{I, L, Q, P}`.
- 20-field `DeckoProvenance` carries Source 5's 16 fields plus Source 6's 4 agent-identity fields; `event_schema_version == "decko-spaceevent-v1"` on every event.
- `Codename` field present in every `DeckoCard` event; `NoCodename` sentinel emitted when source value is null.
- Encoder emits zero events for `action.draft? == true`.
- Encoder is referentially transparent: same `(action, pre_state, request_context)` produces byte-identical output across runs.

## Level 2 -- Mirror Mod

### Goal

Subscribe to Decko's `integrate_with_delay` event hook on `%i[create update delete]`. Encode each non-draft action via `CardAtomEncoder`, INSERT atom-events into `mirror_outbox` with `status: 'queued'`. Idempotent on `event_id`. Late pre-`A_start` integrate-jobs INSERT directly as `'superseded_by_bootstrap'`.

### Tasks

1. Create Rails engine `mod/atomspace_mirror/`. Engine boots with the Decko host application.
2. Add ActiveRecord migrations for `mirror_state`, `mirror_outbox`, `mirror_bootstrap_runs`, `mirror_reconcile_runs`. Schemas verbatim from Card 17120 (see Canonical Encodings).
3. Register `integrate_with_delay` event in `mod/atomspace_mirror/set/all/atomspace_mirror.rb` on `%i[create update delete]`. Guard: `next if action&.draft`.
4. Implement integrate-job INSERT discipline. Inside transaction:
   - Acquire `state = MirrorState.lock.first` (`SELECT FOR UPDATE`).
   - If `state.bootstrap_a_start.nil?`, INSERT outbox rows with `status: 'queued'` (pre-bootstrap; the worker is paused via `draining_enabled = false`).
   - Else if `action.id <= state.bootstrap_a_start`, INSERT with `status: 'superseded_by_bootstrap'` (late pre-A_start row; sweep already covered this card).
   - Else INSERT with `status: 'queued'` (post-A_start; drains naturally).
5. Catch `ActiveRecord::RecordNotUnique` on the `event_id` UNIQUE index as a no-op (idempotent retry-safe).
6. Recursion guard: skip the hook entirely when the triggering action is on a card whose codename is in the mirror's own set (e.g., bootstrap-completion `mirror_state` UPDATE must not produce a recursive integrate-job). Implement via early `return` in the event handler before encoder invocation.
7. The `mirror_state` row is the singleton anchor; enforced at application layer via `MirrorState.lock.first`. Initialize via migration: `INSERT INTO mirror_state (last_drained_action_id, draining_enabled) VALUES (NULL, false)`.

### Acceptance

- Non-draft `create` / `update` / `delete` produces exactly one `mirror_outbox` row with deterministic `event_id`.
- Draft actions produce zero outbox rows.
- Concurrent integrate-jobs against the same `action_id` produce exactly one row; `RecordNotUnique` is caught silently.
- Pre-`A_start` integrate-jobs INSERT as `'superseded_by_bootstrap'`; post-`A_start` integrate-jobs INSERT as `'queued'`. Verified via the race-behavioral test `late_integrate_job_serializes_with_bootstrap_completion` (Card 17120 Section 1 Rider C v2).
- The mirror's own writes to `mirror_state` / `mirror_outbox` / `mirror_bootstrap_runs` do not re-trigger the hook (recursion guard).
- Engine boots cleanly on a fresh deck; migration creates the four tables and seeds the singleton `mirror_state` row.

## Level 3 -- Sidecar

### Goal

Long-running Python process holding a `SpaceRef`. Consumes atom-events via the IPC contract. Registers a space observer for diagnostic emission. The sidecar has no Postgres connection. Phase 4 in-memory Space dies with the sidecar process; restart requires a full Section 1 bootstrap re-run.

### Tasks

1. **PATCH-1 (upstream-blocking, mockable).** Add pybind11 binding for `space_register_observer` in `hyperon-experimental/python/hyperonpy.cpp`. Reference: extern "C" interface at `c/src/space.rs:464-468`. Until merged, the sidecar uses a Python-side polling shim against the C ABI directly; the apply path does not depend on the observer.
2. Create sidecar entry point `sidecar/atomspace_mirror_sidecar.py`. Loads `SpaceRef` from a sealed singleton factory; rejects multi-instance via filesystem lock at `RUN_DIR/sidecar.pid`.
3. Implement IPC server: HTTP on `127.0.0.1:$SIDECAR_PORT` (default 9407) and Unix-socket at `RUN_DIR/sidecar.sock`. Both expose identical JSON API:
   - `POST /apply` -- one or many atom-events; response includes per-event apply status and `applied_at` timestamp.
   - `POST /bulk_load` -- batched bulk-load atoms (no DeckoProvenance companion); used during Bootstrap sweep.
   - `GET /health/watermark` -- returns sidecar diagnostic state (Unix-socket only).
   - `GET /space_stats` -- atom counts per kind.
   - `POST /admin/list_card_scoped_atoms?card_id=C` (admin-only, Unix-socket only) -- catastrophic-rebuild endpoint.
   - `POST /admin/quarantine_card_scoped_atoms?card_id=C` (admin-only, Unix-socket only) -- reconciliation endpoint.
4. Implement `apply(event)` semantics:
   - Decode atom-event JSON against the locked schemas.
   - For `event_kind = 'decko_action'`: dispatch on action type. `create` / `update` -> if atom keyed on `Id` exists, emit `Replace(old, new)`; else emit `Add(new)`. `delete` -> `Replace(old, new_with_Trash_true)` per POLICY-B; never `Remove`.
   - For `event_kind = 'reconcile'`: synthesized "update-from-current-state" event; apply via `Replace` semantics.
5. Idempotency on the sidecar: keyed on `event_id`. Re-applying the same `event_id` is a no-op (atom Replace with identical fields is structurally idempotent in the Hyperon Space).
6. Register space observer on startup (via PATCH-1 binding or polling shim). Observer emits diagnostic events to `RUN_DIR/observer.log` (JSON-structured) for L10 consumption. The observer has no control-plane behavior.
7. **Sidecar restart semantics (Phase 4).** The Phase 4 Space is in-memory; the entire atom set dies with the sidecar process. Bulk-loaded atoms (from Section 1 sweep) have NO `mirror_outbox` rows by design, so the drain worker cannot reconstruct them. Sidecar restart therefore requires a full Section 1 bootstrap re-run (operator runbook procedure: stop sidecar; truncate Space-side state if any persisted; set `mirror_state.draining_enabled = false`, `last_drained_action_id = NULL`; restart sidecar; re-run `decko atomspace_mirror:bootstrap`). Sidecar idempotency on `event_id` ensures replay-safety for the forward path during steady-state re-applies, but is NOT a recovery primitive for restart. Phase 5+ persistent substrate (atomspace-rocks) lifts this constraint.
8. `/health/watermark` returns sidecar-known state only: `{last_applied_action_id, last_applied_event_id, observer_running, sidecar_uptime_seconds}`. The sidecar has no Postgres connection (Invariant 6) and cannot compute outbox-side state. The Rails-side `/api/mcp/health/mirror` endpoint (L10) computes lag by combining the action-id-space Postgres query `MirrorOutbox.where(event_kind: 'decko_action').maximum(:action_id)` with the sidecar's `last_applied_action_id` from this IPC. Both operands are in action-id space; reconcile rows (action_id NULL) are excluded. Unix-socket only; not exposed via Nginx.

### Acceptance

- Sidecar applies a fixture stream of 10k atom-events without divergence between sidecar Space state and outbox-replay reference state.
- Sidecar restart leaves the Space empty until Section 1 bootstrap is re-run; drain-worker tail replay is NOT used as a restart-recovery primitive (verified by integration test that asserts `space_stats()` returns `{atom_count: 0}` after sidecar restart prior to bootstrap re-run).
- Observer log emits exactly one entry per Space mutation (excluding bulk-load batch).
- `/health/watermark` returns within 50ms p99 over a Unix-socket benchmark.
- Multi-instance launch attempt fails fast with `EADDRINUSE` or filesystem-lock error.
- Sidecar has zero Postgres connection strings or libpq dependencies (verified via static analysis).
- PATCH-1 mock is interface-compatible with the upstream binding once merged: zero sidecar code changes required at PATCH-1 cutover.

## Level 4 -- Bootstrap

### Goal

First-time mirror population. Hybrid sweep with hook-attached-and-paused: hook attaches first and accumulates events into the outbox while the worker stays paused; sweep covers the `<= A_start` tail; queue drains the `> A_start` head once the worker is unpaused. No race window; bounded work.

### Tasks

The procedure is load-bearing: Initialize -> Hook attach -> A_start snapshot -> Run row -> Sweep -> Completion -> Activate.

1. **Initialize.** `decko atomspace_mirror:bootstrap` rake task entry. Migrations have already created the four tables and the singleton `mirror_state` row with `last_drained_action_id = NULL` and `draining_enabled = false`. Observers NOT subscribed. Agent-MCP read surface NOT exposed. Forward worker NOT draining.
2. **Attach the integrate hook.** Subscribe `integrate_with_delay` event (idempotent if already subscribed). From this moment forward, every committed Decko action emits a row into `mirror_outbox`. The worker stays paused; rows accumulate.
3. **Snapshot A_start.** Inside transaction: `A_start := SELECT MAX(id) FROM card_actions WHERE draft IS NOT TRUE`. The `draft IS NOT TRUE` filter matches the integrate hook's own filter. This is the cutoff between sweep coverage and forward coverage.
4. **Insert run row.** `INSERT INTO mirror_bootstrap_runs (a_start, started_at, actor) VALUES (:A_start, NOW(), :current_actor)`. Cursor `last_card_id_swept` updates per batch for resumability.
5. **Sweep.** `Card.where(trash: [true, false]).find_each(batch_size: 500)` -- iterate every card regardless of trash state. For each batch, encode atoms via PATCH-4 (faithful shape; bulk-load atoms omit DeckoProvenance) and POST to sidecar `/bulk_load`. Each batch updates `mirror_bootstrap_runs.last_card_id_swept = MAX(id)` in the same transaction as the HTTP success.
6. **Completion (single transaction).**

   ```sql
   UPDATE mirror_outbox
      SET status = 'superseded_by_bootstrap'
    WHERE status   = 'queued'
      AND action_id <= :A_start;

   UPDATE mirror_state
      SET last_drained_action_id = :A_start,
          bootstrap_a_start      = :A_start,
          draining_enabled       = true;

   UPDATE mirror_bootstrap_runs
      SET completed_at = NOW(),
          cards_swept  = (SELECT COUNT(*) FROM cards WHERE id <= :last_card_id_swept)
    WHERE id = :run_id;
   ```

   The `superseded_by_bootstrap` mark prevents the forward worker, once unpaused, from re-applying events the sweep already covered. Events with `action_id > :A_start` remain `'queued'` and drain naturally.
7. **Activate.** Subscribe observers; expose agent-MCP read surface; flip `draining_enabled = true`. The forward worker resumes draining `mirror_outbox` rows where `status = 'queued'` (no `action_id` cursor; pre-A_start rows were marked `superseded_by_bootstrap` in Completion and are no longer `queued`). Post-A_start integrate-job rows continue draining naturally.

### Race protection

Attaching the hook BEFORE the A_start snapshot eliminates the race window. If the hook attached after the snapshot, any action committed between snapshot and hook-attach would not appear in `mirror_outbox` AND would not be guaranteed in the sweep (the watermark trusts `action_id` ordering, but a card mutated post-snapshot but pre-hook-attach is invisible to both paths). The pause-then-drain pattern (hook attached first, worker paused) is what makes the guarantee hold.

### Acceptance

- Race-test `late_integrate_job_serializes_with_bootstrap_completion` (Card 17120 Section 1 Rider C v2): spawn slow integrate-job; concurrently bootstrap completion runs and sets `bootstrap_a_start = A_start`, flips `draining_enabled = true`. Integrate-job's INSERT executes after completion. **Assert**: if integrate-job's `action_id <= A_start`, the row lands at `status='superseded_by_bootstrap'`; if `action_id > A_start`, status is `'queued'`.
- No duplicate atoms in the Space (verified via L5 Mechanism 3 SHA256 projection).
- `mirror_bootstrap_runs` shows exactly one completed row per deck (initial bootstrap) plus zero or more catastrophic-rebuild rows.
- Bootstrap is non-resumable from a partial state: a sidecar crash mid-bootstrap requires re-running `decko atomspace_mirror:bootstrap`. Phase 4 sidecar restart at any time (mid-bootstrap or post-bootstrap) requires a full Section 1 bootstrap re-run because the in-memory Space dies with the process. (Card 17120 Section 10 sidecar-availability lock.)
- Hook-attach-before-A_start verified by static analysis: the rake task ordering is the canonical ordering.

## Level 5 -- Drift Detection

### Goal

Periodic detection of mirror divergence. Four mechanisms running on independent schedules; each emits a structured diagnostic to L10.

### Tasks

1. **Mechanism 1a -- Hook generation tail-lag.** Cron job every 30s. **Pure Postgres query**, no sidecar call (this measures hook-generation lag, not drain lag). Implement the locked Card 17120 Section 2 SQL verbatim:

   ```sql
   COALESCE(
     (SELECT MAX(id) FROM card_actions
       WHERE id > :a_start AND draft IS NOT TRUE),
     :a_start
   )
   -
   COALESCE(
     (SELECT MAX(action_id) FROM mirror_outbox
       WHERE action_id > :a_start
         AND event_kind = 'decko_action'),
     :a_start
   )
   ```

   Both subqueries scope to `action_id > :a_start` (bootstrap pre-A_start tail is irrelevant) and fall back to `:a_start` when empty (a fresh post-bootstrap mirror with no forward events shows zero lag, not a NULL-arithmetic crash). The `event_kind = 'decko_action'` filter scopes to the linear action stream; reconcile rows are out-of-band and excluded. Both operands are in action-id space; subtraction is well-defined. **Threshold (configurable):** alert if > 10 actions OR > 60s. Detects: tail-stalled hook, detached hook, encoder exceptions swallowing the most recent rows.
2. **Mechanism 1b -- Coverage-gap.** Cron job every 5m. Query for `card_actions.id` values where `draft IS NOT TRUE AND id > :a_start` that are absent from `mirror_outbox.action_id WHERE event_kind = 'decko_action'`. Emit `{gap_count, gap_action_ids[..10]}`. Non-zero count triggers L6 hook-lag remediation.
3. **Mechanism 2 -- Contiguous watermark (DIAGNOSTIC).** Cron job every 1m. **Implement the locked Card 17120 Section 2 SQL verbatim**; do not paraphrase. The formula computes the contiguous terminal-status prefix -- the highest `action_id` such that everything below it is in a terminal-advance status (no holes). Holes (queued / failed / awaiting_reconcile rows below the max terminal) hold the watermark down even if newer rows ahead of the hole have delivered.

   ```sql
   GREATEST(
     COALESCE(
       -- (1) one less than the lowest non-terminal action_id (the hole)
       (SELECT MIN(action_id) - 1 FROM mirror_outbox
         WHERE event_kind = 'decko_action'
           AND status NOT IN (
             'delivered',
             'superseded_by_bootstrap',
             'superseded_by_later',
             'superseded_by_reconcile')
           AND action_id > :a_start),
       -- (2) max action_id over ALL terminal-advance statuses (fallback if no holes)
       (SELECT MAX(action_id) FROM mirror_outbox
         WHERE event_kind = 'decko_action'
           AND status IN (
             'delivered',
             'superseded_by_bootstrap',
             'superseded_by_later',
             'superseded_by_reconcile')
           AND action_id > :a_start),
       :a_start
     ),
     :a_start
   ) AS last_contiguous_drained_action_id
   ```

   The two enum lists mirror each other: `NOT IN` the four advance statuses = "hole"; `IN` the four = "advance-past." `awaiting_reconcile` is a hole until the corresponding reconcile event delivers; `superseded_by_reconcile` is set in the same transaction as that delivery (linked via `source_reconcile_event_id`; see L6), transitioning the linked rows from hole to advance-past atomically. The outer `GREATEST(..., :a_start)` clamp guards against future query-edit drift. The `event_kind = 'decko_action'` filter scopes to the linear action stream; reconcile rows are out-of-band and excluded. **This SQL is a diagnostic / lag cursor only** (Card 17120 Section 2; Rider C v2, v9 lock); it is NOT a drain cursor and NOT a read-your-writes correctness primitive. Paraphrased simplifications are rejected because the IN/NOT IN status enum lists, the COALESCE fallback chain, and the `:a_start` clamps are individually load-bearing for correctness of the diagnostic.
4. **Mechanism 3 -- Full-projection SHA256.** Cron job daily (configurable). Compute `SHA256(canonical_serialize(sidecar_atoms_for_card(card_id)))` for each card and compare against Decko-side projection. Emit `{cards_pg_only, cards_space_only, cards_mismatch}`. Non-zero count triggers L6 reconciliation-sweep remediation; results recorded in `mirror_reconcile_runs`.
5. Schedule via `mod/atomspace_mirror/config/initializers/drift_schedule.rb` registering with `Rufus::Scheduler` or host-application equivalent. Threshold for Mechanism 2: alert if drain lag > 50 actions OR > 300s.

### Acceptance

- Artificial drift injection (delete one row from `mirror_outbox`) is detected by Mechanism 1b within 5m.
- Artificial atom corruption in the sidecar (manually mutate one atom) is detected by Mechanism 3 within 24h.
- Mechanism 2 watermark output never used as a correctness primitive (verified via static analysis: no consumers gate writes or reads on the watermark value).
- All four mechanisms emit JSON-structured logs consumable by L10.
- Cron failures are observable: a missed run produces a `mechanism_run_skipped` signal.

## Level 6 -- Drift Reconciliation

### Goal

Heal detected drift without violating same-card ordering. Per-class remediation primitives. Hook-lag with later-delivered uses Case (a) immediate supersede; hook-lag with later-card_action-but-none-delivered uses Case (b) `awaiting_reconcile` plus reconcile event with explicit `source_reconcile_event_id` linkage. Two-phase release fires when the linked reconcile event is delivered.

### Tasks

1. Implement `mod/atomspace_mirror/lib/reconciler.rb` exposing `Reconciler.run!(detection_run_id)`. Records progress in `mirror_reconcile_runs`.
2. **Hook-lag tail case** (gap action_id N exists in `card_actions`, no later `card_actions` for the same card): synthesize outbox row from `card_actions`; INSERT with `status: 'queued'`; standard drain. Idempotency key: `decko:action:N`.
3. **Hook-lag Case (a)** (later same-card delivered+applied row exists): Space already reflects post-N state. INSERT outbox row with `status: 'superseded_by_later'`. Watermark advances past N immediately.
4. **Hook-lag Case (b)** (later same-card `card_actions` exist, none delivered+applied): Space is NOT current for C. Cannot replay (encoder would lie about action_id). Cannot mark superseded yet (Space lacks post-N state). **Reconcile-INSERT-before-awaiting (Invariant 13):** within a single transaction, INSERT the reconcile event row FIRST (`event_kind = 'reconcile'`, `status = 'queued'`, `event_id = "reconcile:card:C:run_id"`, idempotent on `event_id` UNIQUE), then INSERT the linked `awaiting_reconcile` rows referencing that reconcile event (`status: 'awaiting_reconcile'`, `source_reconcile_event_id = "reconcile:card:C:run_id"`). Multiple awaiting rows for C in this run all link to the same reconcile event. The single-transaction guarantee makes both rows visible to the drain atomically; the in-transaction insertion order ensures every awaiting row's `source_reconcile_event_id` references a reconcile that already exists at INSERT time. Awaiting-first ordering is rejected because it strands awaiting rows if the reconcile is delivered before they exist (cross-transaction case).
5. **Two-phase superseded transition (Case (b) release).** When the worker delivers the reconcile event, in the same transaction as marking the reconcile row delivered:

   ```sql
   UPDATE mirror_outbox
      SET status = 'superseded_by_reconcile'
    WHERE event_kind                = 'decko_action'
      AND status                    = 'awaiting_reconcile'
      AND source_reconcile_event_id = :reconcile_event_id
   ```

   This precisely matches: only the awaiting rows that reference THIS reconcile event are released. Awaiting rows linked to other reconcile runs stay held. The watermark advances past the released rows because `superseded_by_reconcile` is a terminal-advance status (Section 2 Mechanism 2). **No id arithmetic; the linkage is explicit.**
6. **Drain-lag reset rake.** `decko atomspace_mirror:requeue_failed`. For each `mirror_outbox` row with `status = 'failed'`, consult `superseded_by_later_or_reconcile?(row)` (Invariant 8). If true, mark the row `'superseded_by_later'` and let `check_event_ready` prove readiness through the same helper at read time. Otherwise reset `attempts = 0`, `status = 'queued'`. **The helper consultation is load-bearing**; bypassing it risks same-card stale overwrites. Note: `superseded_by_reconcile` is reserved for the L6 task 5 two-phase release path (linked release via `source_reconcile_event_id`); a failed row that happens to have a later same-card reconcile delivered is structurally `superseded_by_later` (the helper's branch (b) covers it), not `superseded_by_reconcile`.
7. **Quarantine.** For Mechanism 3 `drift_space_only` (atoms in Space whose `card_id` has no corresponding `cards` row in PostgreSQL), the operator invokes `POST /admin/quarantine_card_scoped_atoms?card_id=C` on the sidecar (Unix-socket only; admin-only). Auto-removal is rejected. Note: bulk-loaded atoms have no `mirror_outbox` row by design; absence of an outbox row is NOT an orphan signal. The orphan condition is "atom present in Space, card absent from PostgreSQL." (Invariant 15.)
8. **Catastrophic rebuild.** For mass divergence, wipe Space and re-run Section 1 bootstrap. `mirror_state` resets `last_drained_action_id` to NULL. Same maintenance-window cost as initial bootstrap.
9. Implement the load-bearing helper. **The first guard bails on reconcile rows** (Invariant 14): reconcile events have `action_id = NULL`, so the (a) check would attempt `action_id > nil` arithmetic; reconcile events are also never semantically superseded by older actions (current-state payload supersedes anything older).

   ```ruby
   # mod/atomspace_mirror/lib/mirror_outbox_helpers.rb
   def self.superseded_by_later_or_reconcile?(row)
     return false if row.event_kind == 'reconcile'

     # (a) Later same-card delivered decko_action (action_id ordering).
     return true if MirrorOutbox.where(
       card_id: row.card_id, event_kind: 'decko_action', status: 'delivered'
     ).where("action_id > ?", row.action_id).exists?
     # (b) Same-card later-inserted delivered reconcile (id ordering).
     return true if MirrorOutbox.where(
       card_id: row.card_id, event_kind: 'reconcile', status: 'delivered'
     ).where("id > ?", row.id).exists?
     false
   end
   ```

### Acceptance

- Coverage-gap injected on a single card is healed by the next reconciliation pass; the resulting Space state matches a fresh full-projection.
- Case (b) two-phase release: every `awaiting_reconcile` row with `source_reconcile_event_id = X` transitions to `superseded_by_reconcile` exactly when row X reaches `delivered`. Verified by SQL trace.
- The drain-lag reset rake never re-queues a row for which `superseded_by_later_or_reconcile?` returns true; verified by 6 unit tests covering both branches of the helper plus boundary cases.
- Quarantined atoms are visible via the admin endpoint and require explicit operator action to delete.
- Reconciliation is idempotent: running the rake twice on the same `detection_run_id` produces no additional rows.
- Constraints preserved: `card_actions` retention covers the `>= A_start` window (Phase 4 assumption: indefinite or at minimum to A_start; Phase 5+ open for explicit SLA).

## Level 7 -- Read-Side Staleness

### Goal

Read-your-writes for agents: a write submitted via Decko is observable via the Read API (L9) within bounded latency, with a per-event status check that does not depend on watermark arithmetic and that requires explicit proof for `superseded_by_later` and `superseded_by_reconcile`.

### Tasks

1. Implement `mod/atomspace_mirror/lib/read_consistency.rb` exposing `ReadConsistency.check_event_ready(event_id)`.
2. Algorithm (from Card 17120 Section 4 v9 Rider C v2):

   ```ruby
   def check_event_ready(event_id)
     row = MirrorOutbox.find_by(event_id: event_id)
     return :not_yet_inserted unless row

     case row.status
     when 'delivered'                     then :ready
     when 'superseded_by_bootstrap'       then :ready    # structurally proven by Section 1
     when 'superseded_by_reconcile'
       # Proof: the linked reconcile event must be delivered.
       reconcile = MirrorOutbox.find_by(event_id: row.source_reconcile_event_id)
       (reconcile && reconcile.status == 'delivered') ? :ready : :not_yet
     when 'superseded_by_later'
       # Proof via shared helper (also used at Section 10 drain apply guard
       # and Section 3 drain-lag reset rake): later same-card delivered
       # decko_action OR same-card later-inserted delivered reconcile.
       MirrorOutbox.superseded_by_later_or_reconcile?(row) ? :ready : :not_yet
     when 'queued', 'awaiting_reconcile'  then :not_yet
     when 'failed'                        then :failed
     end
   end
   ```

3. Expose via L9 read tools: `query_atoms` and `get_card_atom` accept optional `wait_for_event_id` parameter; tool polls `check_event_ready` until `:ready`, `:failed`, or timeout (default 5s).
4. Deprecate watermark arithmetic as a correctness primitive. Static-analysis audit: no production read path consumes `last_drained_action_id` as a gating value.
5. Document the contract in `docs/AGENT-READ-YOUR-WRITES.md`: agent submits write (Phase 5+ via PATCH-6; Phase 4 via direct Decko HTTP), receives `event_id` in the response, polls read tool with `wait_for_event_id`.

### Acceptance

- `check_event_ready` returns `:ready` within 1s p99 of the underlying status transition, against a 100-event/s synthetic load.
- For `superseded_by_reconcile`: returns `:not_yet` until the linked reconcile row's status is `'delivered'`; verified by injecting a queued reconcile and asserting `:not_yet`.
- For `superseded_by_later`: returns `:not_yet` if the helper finds no proof (despite the row's status label); returns `:ready` only once helper confirms a later delivered same-card `decko_action` OR a later-inserted delivered reconcile exists.
- A read tool call with `wait_for_event_id` for an event that never lands times out cleanly with a structured error after the configured timeout.
- Static analysis confirms no production read path consumes `last_drained_action_id` or Mechanism 2 watermark output as a gating value.

## Level 8 -- Multi-Replica Drain

### Goal

Singleton drain across multiple Decko replicas. Per-iteration advisory lock; `mirror_outbox`-direct query (no `card_actions` cursor); same-card stale-overwrite guard at apply time via the load-bearing helper.

### Tasks

1. Implement `mod/atomspace_mirror/lib/drain_worker.rb`. Runs in the sidecar's co-located Rails process (one drain worker per replica, but only one acquires the lock per iteration).
2. Acquire advisory lock per iteration:

   ```ruby
   MIRROR_DRAIN_LOCK_ID = 0xA705_BEEF_DEAD_F00D
   ActiveRecord::Base.connection.execute(
     "SELECT pg_try_advisory_lock(#{MIRROR_DRAIN_LOCK_ID})"
   )
   ```

   If `false`, sleep `DRAIN_BACKOFF_SECONDS` (default 1) and retry.
3. Within the lock, fetch the next event. **No action-id cursor** (Invariant 11): the drain reads `mirror_outbox` directly with no filter on `action_id` and no consultation of `mirror_state.last_drained_action_id`.

   ```ruby
   state = MirrorState.first
   return true unless state.draining_enabled

   next_event = MirrorOutbox
     .where(status: 'queued')
     .order(:id)
     .first
   ```

   The `mirror_outbox.id` ordering is an optimization heuristic for visible queued work, not a commit-order proof. Same-card stale-overwrite correctness is enforced by the apply-time guard (task 4), not by ordering.
4. **Same-card stale-overwrite guard.** Before forwarding a decko_action `next_event` to the sidecar, call the helper. The guard runs only for decko_action rows; reconcile rows bypass (their NULL `action_id` and current-state payload mean they always supersede older state by construction):

   ```ruby
   if next_event.event_kind == 'decko_action' &&
      MirrorOutbox.superseded_by_later_or_reconcile?(next_event)
     MirrorOutbox.transaction do
       next_event.update!(status: 'superseded_by_later')
       MirrorState.update!(
         last_drained_action_id: Mirror.compute_contiguous_watermark
       )
     end
     return false
   end
   ```

   Decoupling correctness from any sequence-allocation proof. (Card 17120 Section 10 v9.)
5. Forward via IPC `POST /apply` to the sidecar. On `200 OK`:

   ```ruby
   MirrorOutbox.transaction do
     next_event.update!(status: 'delivered', last_attempt_at: Time.current)

     if next_event.event_kind == 'reconcile'
       # Section 3 two-phase release: linked awaiting_reconcile rows transition
       # in the same transaction as reconcile delivery.
       MirrorOutbox.where(
         event_kind:                'decko_action',
         status:                    'awaiting_reconcile',
         source_reconcile_event_id: next_event.event_id,
       ).update_all(status: 'superseded_by_reconcile')
     end

     MirrorState.update!(
       last_drained_action_id: Mirror.compute_contiguous_watermark
     )
   end
   ```

6. On sidecar failure (5xx, network error, timeout): increment `attempts`, set `last_attempt_at`, `error`, `status = 'failed'`. Surface via L10 signal class 2.
7. Release lock at end of iteration. Sleep AFTER lock release; never sleep while holding the lock.
8. Forward worker and sidecar are co-located on the same host (single systemd unit boundary). Cross-host IPC is not a Phase 4 deployment topology.

### Acceptance

- Two-replica deployment under synthetic load: total atom-events forwarded equals total queued outbox rows; no double-application observed in the sidecar.
- Lock-contention test: starting 4 drain workers concurrently produces sequential drain order (verified via per-row `last_attempt_at` monotonicity).
- Stale-overwrite test: inject an out-of-order row (older `action_id` arriving after newer `action_id` already delivered for the same card). Drain marks the older row `'superseded_by_later'` and does not forward.
- Reconcile-delivery transition test: when a reconcile row reaches `delivered`, all linked `awaiting_reconcile` rows transition to `superseded_by_reconcile` in the same transaction.
- Lock is held for <= 5s p99 per iteration; sleep duration is observed only between lock releases.

## Level 9 -- Read API

### Goal

Eight-tool agent-facing read surface on the existing Ruby `hyperon-wiki-mcp`. Auth-on-read via the Decko read-rule filter at the tool boundary (Source 7 V7-1; option (e) per Card 17120 Section 6). Polling-first subscription model; subscribe-stream is a Phase 5+ deferral pending upstream `mcp` gem support.

### Tasks

1. Add a tool registry module `hyperon-wiki-mcp/lib/atomspace_mirror_tools.rb` exposing eight tools per Source 6 Q5. **Signatures are locked verbatim from Source 6**; the `wait_for_event_id` parameter (read-your-writes extension per Section 4 v9) is added on top of the locked signatures, not in place of locked parameters:

   | Tool | Returns |
   |---|---|
   | `query_atoms(pattern, limit, include_trash=false, wait_for_event_id=nil)` | atoms matching MeTTa pattern, post-auth-filter |
   | `get_card_atom(card_id, include_trash=false, wait_for_event_id=nil)` | DeckoCard atom for card, post-auth-filter |
   | `get_card_provenance(card_id=nil, event_id=nil, action_id_range=nil, wait_for_event_id=nil)` | list of DeckoProvenance atoms, post-auth-filter |
   | `list_references(card_id, ref_type=nil, include_trash=false, wait_for_event_id=nil)` | DeckoReference atoms (4-code `ref_type` set: `I` / `L` / `Q` / `P`), post-auth-filter |
   | `list_atoms_by_type(type_name, limit, include_trash=false, wait_for_event_id=nil)` | atoms of a given `TypeName` (DeckoCard / DeckoReference / DeckoProvenance / etc.), post-auth-filter |
   | `atom_types()` | list of TypeName values present in the Space |
   | `atom_count_by_type()` | `{TypeName: count}` |
   | `space_stats()` | atom counts, types, mirror-lag indicator |

   Per Source 6 Q5: no generic `get_atom(id)` tool. Phase 4 stable identities are `card_id`, `event_id`, `action_id`, and DeckoReference targets (`referer_id` / `referee_key` / `referee_id`); these four are sufficient for the read surface. ([CONSENSUS-NO-GET-ATOM-ID].)

2. Implement auth filter at the tool boundary using the local MCP precedent (`mod/mcp_api/app/controllers/api/mcp/cards_controller.rb`):

   ```ruby
   def filter_by_auth(atoms, current_account)
     Card::Auth.as(current_account.name) do
       atoms.select do |atom|
         next true if atom.card_id.nil?  # provenance for null-card events (rare)
         card = Card.fetch(atom.card_id)
         card && card.ok?(:read)
       end
     end
   end
   ```

3. Thread JWT identity into provenance origin fields (consumed by L1 task 4 via thread-local):
   - `agent_session_id <- jwt.jti`
   - `agent_kind <- "agent" | "human" | "service"` per JWT `agent_kind` claim
   - `origin_system <- jwt.iss`
   - `origin_request_id <- request.uuid`

4. Polling-first subscription stubs: `subscribe(pattern)` returns 501 with body `{error: "subscriptions deferred to PATCH-5 v2 pending upstream mcp gem support"}`. Document polling pattern in `docs/AGENT-READ-API.md`.

5. Admin endpoints for L6 quarantine review:
   - `GET /api/mcp/atomspace_mirror/quarantine` (admin-auth-only).
   - `POST /api/mcp/atomspace_mirror/quarantine/:id/delete` (admin-auth-only).

### Acceptance

- All eight tools return data within 200ms p99 against a 100k-atom mirror.
- Restricted cards (`+*read` rule blocks current account) are filtered from every read-tool's output that scopes to a `card_id`. Verified via test fixtures with three account roles (anon, member, admin).
- Provenance atoms emitted during a JWT-authenticated MCP request carry the JWT's `jti` in `agent_session_id`.
- Subscription tools return 501; polling pattern documented and tested.
- Quarantine admin endpoints reject non-admin JWTs with 403.
- Auth filter uses `Card::Auth.as(current_account.name) { ... }` matching the existing `mod/mcp_api` precedent; no `Card::Auth.as_bot` in agent read paths.

## Level 10 -- Observability

### Goal

Seven signal classes emitted via interface-deferred adapters. JSON-structured logs always-on. Concrete ops-stack tooling (CloudWatch, Prometheus, Loki, PagerDuty, SNS) deferred to deployment-time runbook.

### Tasks

1. Define adapter interfaces in `mod/atomspace_mirror/lib/observability/`:
   - `MetricsAdapter` (counters, gauges, histograms)
   - `LogAdapter` (structured JSON)
   - `AlertAdapter` (severity, signal class, payload)
2. Ship default adapters: `NullMetricsAdapter`, `NullAlertAdapter`, `LogOnlyMetricsAdapter` (writes to `Rails.logger` as JSON). `LogOnly` is the Phase 4 default; `Null` is used in tests.
3. Implement seven signal classes:

   | Class | Trigger |
   |---|---|
   | 1 -- Hook lag | L5 Mechanism 1a `lag_threshold_breached` |
   | 2 -- Drain failures | L8 row marked `'failed'` |
   | 3 -- Sidecar apply failures | L3 `POST /apply` returns non-200 |
   | 4 -- Drift mismatches | L5 Mechanism 1b or 3 non-zero count |
   | 5 -- Auth observability | raw-sidecar-access (admin endpoint hit), NOT normal `card.ok?(:read)` filtering |
   | 6 -- Mirror state transitions | `mirror_state` row insert/update |
   | 7 -- Sidecar apply-confirmation reachability + latency | round-trip latency from drain `POST /apply` to sidecar response, p50/p95/p99 |

4. Add `/api/mcp/health/mirror` route with two-layer enforcement:
   - Controller-level: reuse existing MCP admin authorization helper/pattern from `mod/mcp_api`; do NOT hard-code `current_account.role == 'admin'`.
   - Nginx-level: allowlist `127.0.0.1` and `::1`; deny all else. Configured in `nginx/conf.d/health-mirror.conf`.

   Returns `{outbox_max_action_id, sidecar_last_applied_action_id, lag_actions, lag_seconds, sidecar_running, last_drain_at, last_bootstrap_at, last_drift_check_at, status}`. Lag computation stays in action-id space on both sides: `outbox_max_action_id` from `MirrorOutbox.where(event_kind: 'decko_action').maximum(:action_id)` (Postgres query); `sidecar_last_applied_action_id` from sidecar `/health/watermark` (IPC query); `lag_actions = COALESCE(outbox_max_action_id, mirror_state.bootstrap_a_start) - COALESCE(sidecar_last_applied_action_id, mirror_state.bootstrap_a_start)` (parallel to Mechanism 1a's `:a_start` clamps; a fresh post-bootstrap mirror with no forward events shows `lag_actions = 0`, not a NULL-arithmetic crash). `lag_seconds` from the matching `last_attempt_at` Postgres lookup. `status` is `initializing` while `mirror_state.bootstrap_a_start IS NULL` (pre-bootstrap), `healthy` when `lag_actions == 0`, `degraded` otherwise. Do NOT subtract `mirror_outbox.id` (BIGSERIAL) from `last_applied_action_id` -- they are different ID domains and not comparable; reconcile rows have `action_id = NULL` and are excluded from this metric.
5. `/health/watermark` on the sidecar Unix-socket only; not exposed via Nginx.
6. Document the deployment runbook in `docs/ATOMSPACE-MIRROR-DEPLOYMENT.md`: which signal classes route to CloudWatch / Prometheus / Loki / PagerDuty / SNS, with concrete configuration examples. Filled in at deployment time per the existing AWS topology (`docs/AWS-DEPLOYMENT.md`); CloudWatch / SNS deployment-state is currently undocumented and verified only at runbook time.

### Acceptance

- All seven signal classes emit at least one event under the L11 test matrix.
- `LogOnly` adapter produces JSON-structured logs consumable by `jq` without parse errors.
- `/api/mcp/health/mirror` returns 200 from `127.0.0.1`; returns 403 from any other source IP (verified via Nginx allowlist test).
- Auth signal class 5 fires on raw sidecar admin-endpoint access; does not fire on every read-tool `card.ok?(:read)` invocation.
- The deployment runbook is reviewable: the document exists, has concrete configuration blocks, and explicitly states which sections are deployment-state-dependent.

## Level 11 -- Test Matrix

### Goal

Approximately 130 tests across Layers 1-5 of the implementation, paired to the locked operational contracts. Behavioral over implementation-text. Layer 6 smoke tests are L10-owned and non-blocking for L1-L9 ship.

### Tasks

1. **Layer 1 -- Encoder unit (RSpec).** ~30 tests against `CardAtomEncoder`. Fixture cards spanning all production cardtypes; assertion of 14-field DeckoCard arity, 5-field DeckoReference arity, 20-field DeckoProvenance arity, codename canonical-null sentinel, `event_schema_version` on D3-1 (not on DeckoCard), draft rejection.
2. **Layer 2 -- Mirror Mod unit (RSpec).** ~25 tests against the integrate-job INSERT discipline. Race tests: hook-attach-vs-A_start, RecordNotUnique idempotency, recursion guard, late pre-A_start row marked `superseded_by_bootstrap`, late post-A_start row marked `queued`.
3. **Layer 3 -- Sidecar unit (pytest).** ~20 tests against the apply semantics, idempotency on `event_id`, observer registration. Mock `SpaceRef`. Includes `policy_b_delete_atom_carries_trash_true` test (delete event payload encodes the card with `Trash=true`, NOT a raw atom removal).
4. **Layer 4 -- Helper unit (RSpec).** ~6 tests on `superseded_by_later_or_reconcile?` covering branch (a) (later same-card delivered decko_action) and branch (b) (same-card later-inserted delivered reconcile), boundary cases (empty outbox, single-row outbox, same-id reconcile).
5. **Layer 5 -- Integration system specs (RSpec + ephemeral sidecar subprocess).** ~50 tests:
   - Bootstrap race vs late integrate-jobs (L4 acceptance).
   - Drain singleton across replicas (L8 acceptance).
   - Coverage-gap detection and reconciliation roundtrip (L5 + L6 acceptance).
   - Two-phase release linkage: `awaiting_reconcile` rows with `source_reconcile_event_id = X` transition to `superseded_by_reconcile` exactly when row X reaches `delivered`.
   - Read-your-writes per-event polling with proof checks (L7 acceptance).
   - Auth filter across roles (L9 acceptance).
6. **Layer 6 -- Smoke tests (L10-owned, non-blocking).** ~5 tests against the deployment runbook adapters; deferred until deployment-stack tooling is concretely picked.
7. Behavioral assertions over implementation text: e.g., race-test the bootstrap completion vs late integrate-job serialization rather than asserting the SQL string contains `SELECT FOR UPDATE`.
8. Schema-presence assertions (Card 17120 Section 11):
   - `decko_action_partial_unique_index_present`: migration creates `mirror_outbox_decko_action_unique` index.
   - `event_id_unique_index_present`.
   - `card_id_indexed`: `mirror_outbox.card_id` is indexed (not just `payload->>'card_id'`).
   - `source_reconcile_event_id_indexed_partial`: partial index on `source_reconcile_event_id WHERE NOT NULL`.
   - `mirror_state_bootstrap_a_start_present`.
   - `policy_b_delete_atom_carries_trash_true`.
9. Sidecar-crash test phrased as two separable assertions:
   - **A**: After sidecar crash mid-apply, the `mirror_outbox` row remains in `'queued'` or `'delivered'` (never partial). Drain is non-terminal.
   - **B**: After sidecar restart, the Space is empty and the read API returns no atoms. The Space remains empty until an operator re-runs Section 1 bootstrap; drain-worker tail replay is NOT a restart-recovery primitive (Invariant 12). Test asserts `space_stats()` returns `{atom_count: 0}` immediately post-restart and pre-bootstrap-rerun, then equals the post-bootstrap atom count after operator re-runs `decko atomspace_mirror:bootstrap`.

### Acceptance

- Total test count: 125-135 tests across Layers 1-5; CI runs in under 15 minutes.
- All 15 invariants from the Invariants section have at least one test that would fail if the invariant is violated.
- Layer 6 tests gated behind `RUN_DEPLOYMENT_SMOKE=1` env var; default CI does not run them.
- Test suite catches the historical reviewer-found bugs from card 17120 design pass: lost forward events from late hook-attach, sparse-gap detection failure, schema mismatch between linear actions and reconcile events, watermark fallback skipping superseded statuses, unsafe replay of older actions when later actions already applied, `card_actions.card_id` not `left_id`, hash-on-DeckoCard-only missing reference drift.

## Canonical Encodings

### `DeckoCard` atom (14 fields, Source 5 Q6)

| Field | Type | Source | Sentinel for null |
|---|---|---|---|
| `Id` | int64 | `cards.id` | n/a |
| `Name` | string | `cards.name` | n/a |
| `Key` | string | `cards.key` | n/a |
| `Codename` | symbol | `cards.codename` (current state) | `NoCodename` |
| `TypeId` | int64 | `cards.type_id` | n/a |
| `TypeName` | string | resolved from TypeId | n/a |
| `LeftId` | int64 | `cards.left_id` | `NoLeft` |
| `RightId` | int64 | `cards.right_id` | `NoRight` |
| `Content` | string | `cards.db_content` | n/a |
| `Trash` | bool | `cards.trash` | n/a |
| `CreatedAt` | iso8601 | `cards.created_at` | n/a |
| `UpdatedAt` | iso8601 | `cards.updated_at` | n/a |
| `CreatorId` | int64 | `cards.creator_id` | n/a |
| `UpdaterId` | int64 | `cards.updater_id` | n/a |

Note: `event_schema_version` is NOT a DeckoCard field. It lives on the `DeckoProvenance` companion atom (V5-PROTOCOL-2).

Example:

```
(DeckoCard
  (Id          17120)
  (Name        "Neoterics+Magus+Atomspace Layer - Wiki Integration Plan+AtomSpace Mirror System Integration Plan")
  (Key         "neoterics_magus_atomspace_layer_-_wiki_integration_plan_atomspace_mirror_system_integration_plan")
  (Codename    NoCodename)
  (TypeId      6)
  (TypeName    "RichText")
  (LeftId      11448)
  (RightId     17119)
  (Content     "<h2>Section 1 Bootstrap...</h2>...")
  (Trash       False)
  (CreatedAt   "2026-05-04T18:22:01Z")
  (UpdatedAt   "2026-05-06T17:58:58Z")
  (CreatorId   3)
  (UpdaterId   3))
```

### `DeckoReference` atom (5 fields, Source 5 Q6)

| Field | Type | Notes |
|---|---|---|
| `RefererId` | int64 | the card whose content references the target |
| `RefereeKey` | string | normalized key of the target |
| `RefereeId` | int64 | resolved target id; `Unresolved` sentinel for unresolved |
| `RefType` | enum | `I` (inclusion), `L` (link), `Q` (query), `P` (pointer) |
| `IsPresent` | bool | true if the reference target currently exists |

Examples:

```
(DeckoReference
  (RefererId   17120)
  (RefereeKey  "neoterics_magus_atomspace_layer_-_wiki_integration_plan_atomspace_mirror_event-mechanism_spec")
  (RefereeId   17117)
  (RefType     L)
  (IsPresent   True))

(DeckoReference
  (RefererId   17120)
  (RefereeKey  "phantom_target_card")
  (RefereeId   Unresolved)
  (RefType     L)
  (IsPresent   False))
```

### `DeckoProvenance` atom (20 fields = Source 5 Q7's 16 + Source 6 Q3's 4)

| Field | Type | Source |
|---|---|---|
| `source` | string | constant `"decko"` |
| `event_schema_version` | string | constant `"decko-spaceevent-v1"` |
| `event_id` | string | `"decko:action:{action_id}"` |
| `action_id` | int64 \| null | `card_actions.id` (null for reconcile events) |
| `act_id` | int64 | `card_acts.id` |
| `super_action_id` | int64 \| null | `card_actions.super_action_id` |
| `action` | enum | `:create` \| `:update` \| `:delete` |
| `draft` | bool | always false in Phase 4 (integrate filters) |
| `card_id` | int64 | `card_actions.card_id` |
| `card_key` | string | `cards.key` (current state) |
| `actor_id` | int64 | `card_acts.actor_id` |
| `auth_current_id` | int64 \| null | `Card::Auth.serialize.current_id` (dual-actor) |
| `auth_as_id` | int64 \| null | `Card::Auth.serialize.as_id` (dual-actor) |
| `acted_at` | iso8601 | `card_acts.acted_at` |
| `ip_address` | string \| null | `card_acts.ip_address` (privacy-policy-gated) |
| `stage` | string | constant `"integrate_with_delay"` |
| `changes` | array | `[{field, old_value, new_value}, ...]` from `card_changes` joined with pre-state |
| `agent_session_id` | string \| null | JWT `jti` claim or MCP session id |
| `agent_kind` | enum \| null | `human` \| `bot` \| `external_mcp_agent` \| `scheduled` \| ... |
| `origin_system` | enum \| null | `decko` \| `mcp` \| `sidecar` \| `agent` |
| `origin_request_id` | string \| null | stable idempotency key per write |

Example (a card update from an MCP-authenticated agent):

```
(DeckoProvenance
  (source                "decko")
  (event_schema_version  "decko-spaceevent-v1")
  (event_id              "decko:action:129552")
  (action_id             129552)
  (act_id                81234)
  (super_action_id       NoSuper)
  (action                update)
  (draft                 False)
  (card_id               17120)
  (card_key              "neoterics_magus_atomspace_layer_-_wiki_integration_plan_atomspace_mirror_system_integration_plan")
  (actor_id              3)
  (auth_current_id       3)
  (auth_as_id            3)
  (acted_at              "2026-05-06T17:58:58Z")
  (ip_address            NoIP)
  (stage                 "integrate_with_delay")
  (changes               [{db_content "<old>" "<new>"}])
  (agent_session_id      "jwt-jti-7f3c2a")
  (agent_kind            external_mcp_agent)
  (origin_system         mcp)
  (origin_request_id     "req-2026-05-06-17:58:58-abc123"))
```

### `mirror_state` schema (Card 17120 Section 1 Rider C v2)

```ruby
create_table :mirror_state do |t|
  t.bigint   :last_drained_action_id        # diagnostic / lag cursor (Section 2 Mechanism 2);
                                            # NOT a drain cursor (Rider C v2, v9 lock)
  t.bigint   :bootstrap_a_start              # persisted bootstrap anchor; consulted
                                            # by integrate-job INSERTs to dispatch
                                            # late pre-A_start rows directly to
                                            # 'superseded_by_bootstrap'
  t.boolean  :draining_enabled, null: false, default: false
  t.timestamps
end
# Singleton row enforced at application layer via MirrorState.lock.first.
```

### `mirror_outbox` schema (Card 17120 Section 1 Rider A v3)

```ruby
create_table :mirror_outbox do |t|
  t.string    :event_id,                  null: false   # primary idempotency key
  t.string    :event_kind,                null: false, default: 'decko_action'
  t.bigint    :action_id                                # null for reconcile events
  t.bigint    :card_id,                   null: false   # indexed; not payload->>'card_id'
  t.string    :status,                    null: false, default: 'queued'
              # queued | delivered | failed
              # | superseded_by_bootstrap   (advance-past)
              # | superseded_by_later       (advance-past -- later same-card delivered)
              # | awaiting_reconcile        (HOLE -- reconcile event still queued)
              # | superseded_by_reconcile   (advance-past -- reconcile delivered)
  t.string    :source_reconcile_event_id, null: true    # links awaiting_reconcile rows
                                                        # to the reconcile event that
                                                        # releases them (see Section 3)
  t.integer   :attempts,                  null: false, default: 0
  t.datetime  :last_attempt_at
  t.text      :error
  t.json      :payload
  t.timestamps
end
add_index :mirror_outbox, :event_id, unique: true
add_index :mirror_outbox, :action_id,
          where: "action_id IS NOT NULL"
add_index :mirror_outbox, :action_id,
          unique: true,
          where: "event_kind = 'decko_action'",
          name: 'mirror_outbox_decko_action_unique'
add_index :mirror_outbox, [:card_id, :action_id]
add_index :mirror_outbox, [:event_kind, :status, :action_id]
add_index :mirror_outbox, :source_reconcile_event_id,
          where: "source_reconcile_event_id IS NOT NULL"
```

### `mirror_bootstrap_runs` schema (Card 17120 Section 1)

```ruby
create_table :mirror_bootstrap_runs do |t|
  t.bigint    :a_start,            null: false
  t.bigint    :last_card_id_swept
  t.datetime  :started_at
  t.datetime  :completed_at
  t.string    :actor
  t.integer   :cards_swept,        default: 0
end
```

### `mirror_reconcile_runs` schema (Card 17120 Section 3)

```ruby
create_table :mirror_reconcile_runs do |t|
  t.string    :status                                # running | completed | aborted
  t.datetime  :started_at
  t.datetime  :completed_at
  t.integer   :drift_pg_only,    default: 0
  t.integer   :drift_space_only, default: 0
  t.integer   :drift_mismatch,   default: 0
  t.integer   :remediated,       default: 0
  t.text      :report_path                           # per-card drift report file
end
```

## File Map

| Path | Lane | Owner | Purpose |
|---|---|---|---|
| `mod/atomspace_mirror/atomspace_mirror.gemspec` | A | Chris | Engine declaration |
| `mod/atomspace_mirror/lib/card_atom_encoder.rb` | A | Chris | L1 |
| `mod/atomspace_mirror/lib/bootstrap.rb` | A | Chris | L4 |
| `mod/atomspace_mirror/lib/reconciler.rb` | A | Chris | L6 |
| `mod/atomspace_mirror/lib/drain_worker.rb` | A | Chris | L8 |
| `mod/atomspace_mirror/lib/mirror_outbox_helpers.rb` | A | Chris | helper (load-bearing across L6/L7/L8) |
| `mod/atomspace_mirror/lib/read_consistency.rb` | C | Lake | L7 |
| `mod/atomspace_mirror/lib/observability/` | C | Lake | L10 adapters |
| `mod/atomspace_mirror/set/all/atomspace_mirror.rb` | A | Chris | integrate hook |
| `mod/atomspace_mirror/db/migrate/*.rb` | A | Chris | four locked schemas |
| `mod/atomspace_mirror/config/initializers/drift_schedule.rb` | A | Chris | L5 |
| `mod/atomspace_mirror/spec/` | A + C | Chris + Lake | L11 Layers 1-2, 4 |
| `sidecar/atomspace_mirror_sidecar.py` | B | Alex | L3 |
| `sidecar/space_observer.py` | B | Alex | L3 observer |
| `sidecar/ipc.py` | B | Alex | L3 IPC server |
| `sidecar/tests/` | B | Alex | L11 Layer 3 |
| `hyperon-experimental/python/hyperonpy.cpp` | B | Alex | PATCH-1 upstream |
| `hyperon-wiki-mcp/lib/atomspace_mirror_tools.rb` | C | Lake | L9 |
| `hyperon-wiki-mcp/spec/atomspace_mirror_tools_spec.rb` | C | Lake | L11 Layer 5 (auth) |
| `nginx/conf.d/health-mirror.conf` | C | Lake | L10 Nginx allowlist |
| `docs/ATOMSPACE-MIRROR-DEPLOYMENT.md` | C | Lake | L10 deployment runbook |
| `docs/AGENT-READ-API.md` | C | Lake | L9 agent docs |
| `docs/AGENT-READ-YOUR-WRITES.md` | C | Lake | L7 agent docs |

## Open Questions

1. **PATCH-1 upstream timeline.** When does the pybind11 binding for `space_register_observer` land in `hyperon-experimental`? Lane B can mock against the C ABI in the interim, but the production deployment requires the binding. Owner: Alex (Lane B) coordinating with TrueAGI maintainers.
2. **Concrete ops-stack tooling.** L10 ships interface-deferred adapters; the deployment runbook specifies which signal classes route to CloudWatch / Prometheus / Loki / PagerDuty / SNS. The current AWS topology (`docs/AWS-DEPLOYMENT.md`) does not document the operational stack as deployed; needs verification before runbook completion. Owner: Lake.
3. **Sidecar host topology.** L8 task 8 locks forward worker and sidecar as co-located on a single host. Multi-host sidecar topology (e.g., one sidecar per replica) is rejected for Phase 4. Reconfirm at Phase 5+ design pass: does atomspace-rocks durable substrate change this constraint? Owner: deferred to Phase 5+.
4. **Phase 5+ schema migration trigger.** Mechanism A (companion derived atoms) and Mechanism B (versioned atom kinds) are locked design mechanisms; the first concrete Phase 5+ schema change is unspecified. Phase 4 does not introduce `mirror_state.schema_version` or `mirror_schema_migrations` tables; the first concrete Phase 5+ requirement triggers them. Owner: deferred.
5. **PATCH-2 MeTTa replace-atom! upstream.** Phase 4 does not require this patch. The sidecar implements delete via `Replace(old, new_with_Trash_true)` per POLICY-B at the Python binding level. Phase 5+ may require the grounded MeTTa operator if MeTTa-side query patterns need to express trash transitions natively. Owner: Alex (Lane B), low priority.
6. **`card_actions` retention SLA.** Phase 4 assumes `card_actions` retention covers the `>= A_start` window (indefinite or at minimum to A_start). Phase 5+: explicit retention SLA for the mirror's recovery window. Owner: deferred.

## CHANGELOG

- **2026-05-08** -- Initial publication. Ported from Card 17120 Sections 1-11 v9 locks; style follows Alex Peake spec template (per `Notes+AI Workflow+Writing Specifications in Alex Peake's Style`).

  Iterations during preparation (recorded for traceability of how the document arrived at its locked state):

  - **v5** -- Mechanism 1a (L5 task 1) replaced with verbatim Card 17120 Section 2 SQL: pure-Postgres action-id-space subtraction `MAX(card_actions.id WHERE draft IS NOT TRUE) - MAX(mirror_outbox.action_id WHERE event_kind='decko_action')` with `:a_start` clamps. L10 `/api/mcp/health/mirror` and L3 `/health/watermark` cross-reference updated to use `outbox_max_action_id` (action-id space) for lag computation; `lag_actions` adopts COALESCE-to-`bootstrap_a_start` pattern parallel to Mechanism 1a; `mirror_outbox.id` (BIGSERIAL) is explicitly non-comparable to `last_applied_action_id`; reconcile rows excluded. Cosmetic: invariant count corrected to 15; footer version updated.
  - **v4** -- L11 Layer 5 sidecar-restart test rewritten to assert empty Space post-restart and pre-bootstrap-rerun (consistent with Invariant 12). L5 Mechanism 2 watermark formula replaced with verbatim Card 17120 Section 2 SQL (GREATEST / COALESCE / IN+NOT IN status enum lists / `:a_start` clamps); paraphrased simplifications rejected because each piece is individually load-bearing for diagnostic correctness. L3 `/health/watermark` schema corrected to sidecar-known state only (no `outbox_max_id`); Rails-side `/api/mcp/health/mirror` does the lag computation. L6 task 6 status assignment clarified: `superseded_by_reconcile` reserved for the L6 task 5 two-phase linked release path; failed rows superseded by helper-proven later state become `superseded_by_later`.
  - **v3** -- L8 drain query stripped of `action_id > last_drained_action_id` cursor; now `MirrorOutbox.where(status:'queued').order(:id).first`. L3 sidecar restart corrected to require full Section 1 re-bootstrap (Phase 4 in-memory Space dies with the process; drain-worker tail replay cannot reconstruct bulk-loaded atoms). L6 Case (b) ordering corrected to reconcile-INSERT-before-awaiting in single transaction (Invariant 13). Helper gains `return false if row.event_kind == 'reconcile'` guard as first clause. L6 quarantine framing corrected to Space-but-not-Postgres (`drift_space_only` direction). L4 step 7 reworded to remove drain-cursor implication. L9 tool signatures replaced with verbatim Source 6 Q5 (`include_trash=false`, `ref_type=nil`, `action_id_range`) with `wait_for_event_id` as additive extension. Remaining UTF-8 punctuation replaced with ASCII for cross-environment robustness. Invariants 11-15 added.
  - **v2** -- DeckoCard shape replaced with Source 5 Q6 14-field arity. DeckoProvenance arity unified at 20 fields (Source 5's 16 + Source 6's 4). Bootstrap A_start corrected to `action_id` anchor (was: timestamp). Sidecar IPC boundary enforced (was: sidecar reading `mirror_outbox` directly on cold start). POLICY-B Replace-only enforced. Reconciliation two-phase release uses `source_reconcile_event_id` linkage (was: id arithmetic). `check_event_ready` gains explicit proof clauses for `superseded_by_later` / `superseded_by_reconcile`. Auth code sketch corrected to `Card::Auth.as(current_account.name) { Card.fetch(atom.card_id)&.ok?(:read) }`. Archive paths corrected to `source5_decko_semantics` / `source6_agent_mcp_surface` / `source7_magus_plan_reconciliation`. `mirror_state` columns `last_drained_action_id` and `draining_enabled` added. `mirror_outbox` / `mirror_bootstrap_runs` / `mirror_reconcile_runs` schemas corrected to verbatim Card 17120 locked schemas. Bootstrap procedure restructured to 7-step paused-queue model. Em-dashes and arrows replaced with ASCII.
  - **v1** -- Initial draft.

---

*Card 17120 remains the canonical design-decision record; this document is the engineer-facing build contract for Lanes A / B / C. The wiki copy of this document lives at `Neoterics+Magus+Atomspace Layer - Wiki Integration Plan+Hyperon Wiki AtomSpace Mirror -- Implementation Plan` with Levels 1-11 and the trailing sections as `+`-children.*
