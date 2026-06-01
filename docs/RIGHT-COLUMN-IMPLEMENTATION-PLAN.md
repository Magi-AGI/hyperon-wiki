# Right Column Implementation Plan — Hyperon Wiki

**Status**: DRAFT 2026-05-09
**Inspiration**: parallels the AtomSpace Mirror Implementation Plan (Magi Archive card 17161, parent `Neoterics+Magus+Atomspace Layer - Wiki Integration Plan`).
**Stub state**: Sandra-style two-panel right column shipped 2026-05-09 (`*sidebar_right` HTML card + JS handlers in `Left Sidebar Layout`). Stub gives the visual surface; this plan covers the real backend build.

---

## Goal

Replace the stub right-column interactions with two real services running as sidecar processes alongside Decko/Rails:

1. **MeTTa Playground sidecar** — accept MeTTa source from the textarea, evaluate via Hyperon Python bindings inside a sandbox, return output (or runtime error) to the browser.
2. **Wiki Assistant agent** — proxy chat input to a Claude (Anthropic API) agent equipped with the existing `hyperon-wiki-mcp` tools, returning streamed responses. Agent system prompt funnels deep questions to ASI Create as a deliberate scope cap (per `project_hyperon_wiki_lovable_engagement_2026_05_04.md`).

Both endpoints sit behind the same Nginx that fronts Decko, scoped under `/api/playground/*` and `/api/assistant/*`.

## Non-goals (defer past 2026-05-23 contract delivery)

- Real-time multi-user collaboration on the playground.
- Persistent conversation memory across page reloads (stateless V1).
- Direct AtomSpace queries from the assistant (waits on the AtomSpace Mirror plan's PATCH-5 read tools — see [AUTH-ON-READ-MIRROR] gate, V7-1).
- MeTTa-via-Decko: code execution stays out-of-process; do NOT run user MeTTa inside the Rails worker.
- LLM-generated wiki edits initiated from the chat (read-only for V1).

## Invariants

I-1. **Decko is the source of truth.** Neither sidecar writes to PostgreSQL; both are read-only consumers via existing MCP tools.
I-2. **No untrusted code in the Rails process.** MeTTa eval runs in a separate Python worker; the worker can be killed without affecting the wiki.
I-3. **Agent → MCP only via the published `hyperon-wiki-mcp` server.** No direct DB or filesystem access from the agent process.
I-4. **Stateless V1.** No session storage; the chat history lives in the browser tab. Page reload → empty history.
I-5. **Per-request resource ceilings.** MeTTa eval: hard 5s wall clock + 256MB memory cap. Agent call: hard 30s wall clock + 16k token cap.
I-6. **Funnel intent preserved.** The assistant's system prompt must include the ASI Create CTA wording; unmatched / out-of-scope queries return that CTA, not a confidently-wrong answer.
I-7. **No PII collection.** Chat input is not logged with user identity. Aggregate metrics only (hit rate, error rate, latency p50/p95).
I-8. **Frontend contract is stable.** The `*sidebar_right` HTML card body matches both the stub and the real backend — only the JS `setupCodePlayground()` / `setupWikiChat()` functions change between them.
I-9. **Deployment is reversible.** Both sidecars can be stopped without taking down the wiki; the JS falls back to the stub canned responses on HTTP error.
I-10. **PLN No-Go theorem applies to the assistant** (per HYPERON_CLUSTER_FINDINGS PLN section). The assistant does not claim to be performing global PLN inference; it is an LLM doing semantic search + summarization over wiki content.

---

## Architecture

```
Browser (*sidebar_right + setupCodePlayground + setupWikiChat)
   │
   ├── POST /api/playground/run    {code: "..."}
   │        ↓
   │   Nginx → Python sidecar (Hyperon runtime) → sandboxed eval → JSON response
   │
   └── POST /api/assistant/chat    {messages: [...]}
            ↓
        Nginx → Node/Python agent sidecar
            ↓
        Anthropic Messages API (claude-sonnet-4-6 default; opus for hard queries)
            ↓ tool_use
        hyperon-wiki-mcp (existing Ruby MCP server) → search_cards / get_card / list_children / get_relationships
            ↑ tool_result
        Anthropic API → assembled response → SSE stream back to browser
```

---

## Lane A — MeTTa Playground sidecar (Backend)

**Owner candidate**: Patrick Hammer or Vitaly Bogdanov (per HAA cluster pilot Sources 1–5: PeTTa is Patrick's; hyperon-experimental is Vitaly's).
**Primary stack**: Python 3.11 + `hyperon` Python bindings (HEAD `3f76dc46` v0.2.10 per MeTTa runtime cluster pilot Source 1) + FastAPI for HTTP.

### Tasks

- **A-1** Decide runtime: hyperon-experimental Python bindings (V1 default — broadest test coverage, per V1-9 [TEST-COVERAGE-ADEQUATE]) vs PeTTa Prolog runtime (faster, but `[PY-PARTIAL-WITH-GAPS]` per V1-7 — defer to V2).
- **A-2** Sandbox: **Docker-per-request** with seccomp profile + read-only rootfs + tmpfs `/tmp` + no network namespace. Resolved 2026-05-10 — accept the ~200ms cold cost for V1 isolation. Use a warm-pool of N=4 paused containers replenished after each request to amortize startup. Image: `hyperon-runtime:0.2.10` (FROM python:3.11-slim, `pip install hyperon==0.2.10`, no extras).
- **A-2.1** **AtomSpace session affinity**: each container instance is keyed by `<auth_id_or_session_id>`. Signed-in users get a long-lived container (idle timeout 30 min) that retains AtomSpace state across `Run` clicks — so users can incrementally `(add-atom ...)` and query later. Anonymous users get an ephemeral container per request (no state retention). The keying preserves Sandra's UX-feel of "the playground remembers what I did" for signed-in users while keeping isolation strict between users. **Cap**: max 100 concurrent signed-in containers; LRU-evict idle ones.
- **A-3** Endpoint: `POST /api/playground/run` body `{code: string, timeout_ms?: int}` → `{status: "ok"|"error"|"timeout", output: string, stdout: string, stderr: string, elapsed_ms: int}`.
- **A-4** Output capture: redirect stdout/stderr; capture `!` query results separately (eval values list).
- **A-5** Idempotent on identical input within a 60s LRU cache (avoid recomputation when user clicks Run twice).
- **A-6** Init-script preamble: load a small standard MeTTa preamble (only `=` / `match` / arithmetic). Do NOT preload PLN / ECAN / MORK — V2 scope.
- **A-7** Memory leak guard: per the `project_hyperon_0210_quirks.md` Q-1 finding (bind!+new-space doesn't reset), spin up a fresh `MeTTa()` instance per request, do NOT reuse across calls.
- **A-8** Error formatting: surface `MeTTa` errors as `output: ""` + `stderr: "<formatted error>"` + `status: "error"`. Frontend renders stderr in red.
- **A-9** Health check: `GET /api/playground/health` returns `{ok: true, hyperon_version: "0.2.10", uptime_s: int}`.
- **A-10** Observability: emit `metta_eval_total{status}`, `metta_eval_duration_seconds`, `metta_eval_memory_mb` Prometheus counters.

### Acceptance

- 100 sequential `Run` clicks of the default example complete with `status:"ok"` and p95 < 800ms.
- A worst-case malicious input (`!(reduce-fn (forever-loop))` style) is killed by the 5s timeout, leaving the worker pool healthy.
- Worker process consuming >256MB is OOM-killed by `resource.setrlimit(RLIMIT_AS, ...)`.
- The 0.2.x quirks (Q-1 / Q-2 / Q-3 from memory) are documented in the README so users hitting them recognize the behavior.

---

## Lane B — Wiki Assistant agent (Backend)

**Owner candidate**: Lake (Anthropic API + MCP integration expertise) with Sandra reviewing the system prompt for Sandra-spec adherence.
**Primary stack**: Node 20 + `@anthropic-ai/sdk` + the existing `hyperon-wiki-mcp` Ruby server reachable via stdio MCP transport. (Node chosen over Python for first-class streaming SSE handling and the agent SDK ecosystem; Python is the fallback if Lake prefers.)
**Repo**: `magi-assistant-wiki` (resolved 2026-05-10) — sibling to `hyperon-wiki`, `hyperon-wiki-mcp`, `hyperon-wiki-ui`. Naming reserves room for future variants (`magi-assistant-archive`, etc.) under a consistent `magi-assistant-*` family.
**Public name**: "Wiki Assistant" for V1. Brand name decision deferred until post-launch usage data.

### Tasks

- **B-1** System prompt (locked V1, edited via the wiki itself for live tuning):
  - Identity: "I am the Hyperon Wiki Assistant. I help readers navigate this wiki and answer factual questions about Hyperon, MeTTa, AtomSpace, PLN, ECAN, MOSES, AIRIS, NACE, AI-DSL, MeTTa-NARS, MetaMo, PRIMUS, and related topics."
  - Funnel: "For deep technical or research questions beyond what the wiki documents, recommend ASI Create at https://create.singularitynet.io/ rather than speculating."
  - Boundary: "I will not generate code, write MeTTa programs, or perform inference. I'm a navigation aid."
  - Tool-use guidance: "Use `search_cards` to find relevant pages first, then `get_card` to read content before answering."
- **B-2** Endpoint: `POST /api/assistant/chat` body `{messages: [{role, content}], model?: string}` → SSE stream of `{type: "delta"|"tool_use"|"done", ...}`.
- **B-3** Default model: `claude-sonnet-4-6` (resolved 2026-05-10 — Sonnet needed for reliable MCP tool-use and multi-step navigation; Haiku underperforms on tool-orchestration). Reject `opus` / `haiku` / unknown via allowlist for V1.
- **B-4** MCP tool surface — V1 allowlist (subset of hyperon-wiki-mcp; per V7-1 [AUTH-ON-READ-MIRROR] gate the agent acts as a public reader, no admin tools):
  - `search_cards` (search_in: name)
  - `get_card` (rendered: false default)
  - `list_children`
  - `get_relationships`
  - **Forbidden** in V1: `update_card`, `create_card`, `delete_card`, `restore_card`, `admin_backup`, `submit_feedback`. The agent is read-only.
- **B-5** Conversation cap: 16k input tokens; if exceeded, drop oldest user/assistant turns and prepend a system note "earlier turns truncated."
- **B-6** Streaming: SSE; the frontend appends each `delta` to the assistant message bubble. On `tool_use`, show a small "(searching the wiki…)" status pill; replace with the next assistant delta.
- **B-7** Rate limit (resolved 2026-05-10 — tiered):
  - Anonymous: 10 chats per IP per minute, 6k token conversation cap.
  - Signed-in (Decko session present): 60 chats per user per minute, 16k token conversation cap.
  - Implementation: Nginx `limit_req_zone` keyed by `$cookie__hyperon_session` first, fallback to `$binary_remote_addr`. The agent endpoint also enforces conversation token cap server-side.
- **B-8** Error path: on Anthropic API failure (timeout, 5xx, rate limit), return a synthetic assistant message "I can't reach the language model right now. The wiki itself is available — try the sidebar nav, or visit ASI Create."
- **B-9** Telemetry: log `{timestamp, message_count, model, tool_calls, latency_ms, status}` to stdout (JSON). NO chat content logged (I-7).
- **B-10** Health check: `GET /api/assistant/health` returns `{ok: true, mcp_connected: bool, anthropic_reachable: bool}`.

### Acceptance

- A "What is MeTTa?" turn returns a 1–3-paragraph answer with at least one `search_cards` + one `get_card` tool call, p95 < 8s.
- An out-of-scope query ("How do I deploy a Cardano smart contract?") returns the ASI Create CTA, not a hallucinated answer.
- An MCP failure (kill the hyperon-wiki-mcp process) yields the I-9 fallback message; the wiki itself stays up.
- 10/min rate limit enforced; the 11th request returns 429 with a friendly message.

---

## Lane C — Frontend integration

**Owner candidate**: Lake (continuing from the stub work) with Sandra reviewing visual changes.
**Files touched**: `*sidebar_right` HTML card body (minimal — IDs and structure already match real-build expectations); `Left Sidebar Layout` `<script>` (replace stub `setupCodePlayground` and `setupWikiChat` with real fetch calls).

### Tasks

- **C-1** Replace `setupCodePlayground` stub with `fetch("/api/playground/run", {method:"POST", body:JSON.stringify({code})})`. Render `output` / `stderr` distinctly. Show "(running…)" while pending.
- **C-2** Replace `setupWikiChat` stub with EventSource-based SSE consumption of `/api/assistant/chat`. Append deltas to the in-progress assistant bubble. Show "(searching the wiki…)" pill on `tool_use` events.
- **C-3** Stub fallback: on any `fetch`/`EventSource` error, fall through to the existing canned-response logic. Log a `console.warn` for debugging but show no error UI to the user (graceful degradation, I-9).
- **C-4** Markdown-light rendering for assistant messages: convert `**bold**`, `[text](url)`, and `\n\n` paragraph breaks to HTML. Reject `<script>` / `<iframe>` (defense-in-depth even though the agent is system-prompted not to emit them).
- **C-5** Keep the message bubbles + input layout identical to the stub — Sandra has already approved that.
- **C-6** Chat history is in-memory only (I-4). Page reload empties it. (V2 considers `sessionStorage`.)

### Acceptance

- Click Run → real MeTTa output appears within 1s on the default example.
- Type "What is PeTTa?" → assistant streams a real Claude-generated answer that includes the GitHub link from the wiki (verified by URL in answer).
- Stop the playground sidecar → click Run still produces the canned `[Result of …]` output (graceful degradation).

---

## Phasing

- **R1 — Spec lock-in (1 week)**: this doc reviewed, sandbox option chosen for Lane A, system prompt drafted for Lane B.
- **R2 — MeTTa sidecar MVP (1 week)**: Lane A endpoints A-3 / A-4 / A-5 / A-7 / A-9 wired against hyperon-experimental v0.2.10. Manual `curl` tests pass.
- **R3 — Assistant agent MVP (1 week)**: Lane B endpoints B-2 / B-4 / B-6 wired against `claude-sonnet-4-6` and `hyperon-wiki-mcp`. Manual `curl` tests pass against canned questions.
- **R4 — Frontend hookup (3 days)**: Lane C C-1 / C-2 / C-3 swap stubs for real calls. Sandra-style chrome unchanged.
- **R5 — Production hardening (1 week)**: rate limits, observability, error fallbacks, sandbox migration to (b) if any (c) escape was observed in R2.
- **R6 — AtomSpace mirror integration (post-Phase 4 close)**: when the AtomSpace Mirror Plan ships PATCH-5 read tools, add `query_atoms` / `get_card_atom` to the V1 allowlist as B-4 V2.

R1–R4 fits the post-2026-05-23 contract window; R5–R6 are post-launch. R1 ideally starts the day after stub demo to Khellar/Sandra so we can iterate on system prompt during R2 build time.

---

## Resolutions (2026-05-10)

1. **Sandbox V1 pick**: Docker-per-request with seccomp + read-only rootfs + tmpfs `/tmp` + no network namespace. Warm-pool of 4 containers. AtomSpace session affinity tied to `<auth_id_or_session_id>` — signed-in users keep state across `Run` clicks (30 min idle timeout, max 100 concurrent), anonymous users get ephemeral per-request containers. See A-2 / A-2.1.
2. **Model default**: `claude-sonnet-4-6`. Haiku is rejected for V1 — the assistant needs reliable MCP tool-orchestration (multi-step search → read → synthesize), and Haiku has been observed to underperform on agentic tool-use. Cost is acceptable given the rate-limited surface.
3. **Publish target**: this doc → mirrored into Magi Archive as a card cluster, sibling to the AtomSpace Mirror plan under `Neoterics+Magus`. The local doc remains the editing source; published cards reflect locked content.
4. **Naming**: Public V1 name is "Wiki Assistant" (deliberately understated, funnel-aligned). Repo for Lane B is `magi-assistant-wiki` (sibling to `hyperon-wiki`, `hyperon-wiki-mcp`, `hyperon-wiki-ui`). Brand name decision deferred until post-launch usage data.
5. **Auth tiering**: signed-in users get higher rate limit (60/min vs 10/min) and conversation cap (16k vs 6k tokens). Detection via Decko session cookie at the Nginx layer. See B-7.

---

## Cross-references

- `project_atomspace_mirror_implementation_plan_2026_05_08.md` — sibling AtomSpace plan, same Alex Peake spec style. Card 17161 in Magi Archive.
- `project_hyperon_wiki_lovable_engagement_2026_05_04.md` — Lovable port context; Sandra's funnel-to-ASI-Create intent is documented there.
- `project_metta_runtime_pilot_source1_2026_05_08.md` — Hyperon runtime HEAD `3f76dc46` v0.2.10 pinning; 0.2.x quirks for A-7.
- `project_atomspace_phase4_pilot_2026_05_05.md` — V7-1 [AUTH-ON-READ-MIRROR] read-tool gate; PATCH-5 8-tool read surface.
- `feedback_phase4_implementation_scope.md` — separate research vs. implementation workstreams; this plan is implementation track.
- `feedback_decko_native_first.md` — chat bridge identified as a place where mods/sidecars are needed (no Decko-native equivalent for LLM agents).
