# Ingestion Workflows

How source material becomes **RawData** cards in the Hyperon Wiki: which scripts exist,
what each one handles, and what an operator must supply out-of-band.

This is the tooling detail behind **Stage A** in [`../ONBOARDING.md`](../ONBOARDING.md) §4.
Read that first for the editorial model; this document assumes it.

---

## The model: human-triggered, not a scheduled pipeline

Ingestion is **run on demand by a person**. Someone decides a body of source material
should be brought in and runs the relevant scripts. There is no continuously scheduled
importer watching the sources, and nothing here starts itself.

Describing this as an automated pipeline overstates it. The machinery is scripted; the
decision to run it is human, and so is the review of what comes out.

The **RawData fidelity rule** governs everything below: RawData preserves the source
verbatim. Ingestion does not clean up, summarize, or correct what a source said. Editorial
commentary belongs in synthesis cards, never in the raw body.

## Two stages, two trust boundaries

Almost every source family follows the same shape, and the split matters because the two
halves need different credentials:

| Stage | Runs where | Needs | Produces |
|---|---|---|---|
| **Export / fetch** | An operator's machine | Credentials for the *source* service (chat token, transcript API key, account login) | JSON or text files on local disk |
| **Ingest** | The wiki host, via `decko runner` | The wiki's own environment — database credentials, `RAILS_ENV`, and a role permitted to create RawData | RawData cards in the wiki database |

The `sync_*.sh` scripts chain both halves across SSH for convenience. They are a
convenience wrapper, not a separate mechanism — if you want to inspect what will be written
before it is written, run the two stages separately.

---

## Script inventory

All paths are relative to the repository root. The groupings are by source family.

### Chat archives (Mattermost)

| Script | What it does |
|---|---|
| `scripts/mattermost_exporter.py` | The exporter itself: connect, list teams and channels, export a channel to JSON with thread structure, code blocks, and attachments. Non-interactive by design — no prompting, no cookie scraping, no credential persistence. |
| `scripts/export_mattermost.py` | Non-interactive export of channels via token auth. Writes JSON. |
| `scripts/ingest_mattermost.rb` | Reads those JSON exports and creates RawData cards. Run under `decko runner`. |
| `scripts/extract_mattermost_papers.py` | Extracts text from PDF attachments found in chat exports, emitting JSON for the publication ingester. |
| `scripts/sync_mattermost.sh` | Chains export → upload → ingest. |
| `scripts/server_sync_mattermost.sh` | Server-side variant, intended to be driven from a scheduled job if an operator chooses to set one up. |

### Meeting transcripts

Three transcript providers are supported, each with its own export path, all converging on
one ingester.

| Script | What it does |
|---|---|
| `scripts/export_transcripts.py` | Pulls transcripts from the Fireflies GraphQL API; writes JSON. |
| `scripts/export_otter.py` | Pulls transcripts from Otter.ai via an unofficial client (see `scripts/otterai/`). |
| `scripts/ingest_otter_export.py` | Converts *manually* exported Otter `.txt`/`.srt` files into the standard JSON format. Use this when API export is unavailable. |
| `scripts/parse_readai_reports.py` | Parses Read.ai meeting report data into the same JSON format. |
| `scripts/ingest_transcripts.rb` | Reads transcript JSON and creates RawData cards. Run under `decko runner`. |
| `scripts/sync_transcripts.sh` | Chains export → upload → ingest for the Fireflies path. |

### Publications and books

| Script | What it does |
|---|---|
| `scripts/fetch_publication_texts.py` | Downloads PDFs from open links, extracts text, writes JSON. |
| `scripts/fetch_goertzel_books.py` | Fetches book-length source texts for the same path. |
| `scripts/ingest_publications.rb` | Reads publication JSON and creates RawData cards. Run under `decko runner`. |

### Shared libraries

| Path | What it is |
|---|---|
| `scripts/tests/` | Offline regression coverage. `test_mattermost_exporter.py` stubs the Mattermost client and drives the exporter from fixtures; `verify_ssh_quoting.sh` proves the sync wrappers preserve paths containing spaces using fake `ssh`/`scp` shims. Neither touches a network, a credential, or the wiki. |
| `scripts/pipeline/` (8 files: `__init__`, `__main__`, `cli`, `extractor`, `sources`, `topics`, `transcript_sources`, `writer`) | The Python raw-data pipeline package — source adapters, extraction, topic handling, and the writer. Has its own CLI: `python -m scripts.pipeline.cli`. |
| `scripts/otterai/` (3 files: `__init__`, `exceptions`, `otterai`) | A vendored client for Otter.ai's internal API, used by `export_otter.py`. Third-party in origin. |

The production reconciliation below covered 25 tracked script candidates. This branch adds
one more file — `scripts/mattermost_exporter.py` — so the Mattermost path no longer depends
on a checkout outside this repository. See *Self-containment* below.

---

## Production reconciliation (2026-09-08)

There was an open question about whether some ingestion scripts existed **only** on the
production server and would therefore be missing from a repository handoff. That has been
checked and the answer is no.

A read-only inventory of the deployed repository on the production host, covering
ingestion, export, sync, transcript, chat, publication, and pipeline script candidates —
**including untracked files** — found 25 candidates. All 25 are git-tracked, and all 25 are
present in this repository. Content matches on all 25 once line endings are normalized;
the raw hashes differ only because the working copies here use CRLF and the server uses LF.

Adjacent deployment roots on the same host (the MCP server, the AtomSpace mirror sidecar,
and two other decks) were also checked: **zero** ingestion-pattern scripts. Apparent
scheduled-job matches there were false positives — a certbot comment, `/bin/sync`, and a
time-sync unit.

**Conclusion: the ingestion tooling is fully contained in this repository. No
production-only Hyperon Wiki ingestion script source was found.**

### Self-containment

The reconciliation surfaced one real gap. The Mattermost path used to import its exporter
class from a **sibling repository checkout** — code that was never part of this repository
and would not have travelled with a handoff. The Mattermost half of ingestion would have
arrived broken.

That dependency is now removed. `scripts/mattermost_exporter.py` is this repository's own
exporter, and both consumers — `scripts/export_mattermost.py` and
`scripts/pipeline/sources.py` — import it locally. It is deliberately non-interactive: no
prompting, no browser-cookie scraping, and no credential persistence. The token arrives as
an argument or an environment variable and is never written to disk.

**Nothing under `scripts/` now reaches outside this repository.**

### Host and key configuration

The `sync_*.sh` wrappers used to hardcode a production host and SSH key filename. They now
read them from the environment and fail immediately with a clear message if unset:

| Variable | Required | Meaning |
|---|---|---|
| `HYPERON_WIKI_HOST` | yes | SSH host for the wiki server |
| `HYPERON_WIKI_SSH_KEY` | yes | Path to the SSH private key |
| `HYPERON_WIKI_SSH_USER` | no | SSH user (default `ubuntu`) |
| `HYPERON_WIKI_REMOTE_DIR` | no | Deck root on the host (default `~/hyperon-wiki`) |

Values come from the server-access handoff. The `.rb` ingesters carry placeholder-only
usage examples in their header comments.

### Deploying to the wiki host

Deploy the **full repository checkout**. The server-side Mattermost sync needs
`export_mattermost.py`, `mattermost_exporter.py`, and `ingest_mattermost.rb` together;
copying files piecemeal and omitting the exporter module fails at import on the first run.

### Running the offline tests

Neither of these contacts a network or needs credentials:

```bash
python -m unittest discover -s scripts/tests
bash scripts/tests/verify_ssh_quoting.sh
```

They pin three defects worth knowing about, because each was a silent failure rather than
an error:

- **Export path.** `export_channel` strips punctuation when naming the output directory, so
  a channel called `Q&A / general` does not round-trip. Callers must use the path
  `export_channel` returns; rediscovering it by globbing the display name returns nothing
  and the channel is skipped without a warning.
- **Orphan replies.** A date filter can exclude a thread root while keeping its replies.
  Both renderers show replies only underneath a retained root, so those replies used to
  disappear. They are now promoted to top level, flagged `orphan_reply` with their
  `root_id` kept, counted in `orphan_reply_count`, and labelled in the rendered output.
- **Path quoting.** The sync wrappers build `ssh`/`scp` invocations as argument arrays, so a
  key path or deck root containing spaces stays one argument.

---

## What an operator must supply out-of-band

None of the following is in this repository, and none of it should ever be added:

- **Source-service credentials** — the chat access token, the transcript API keys, and the
  transcript-account login used by the export scripts. Each script documents which
  environment variable it reads; the values come from a secrets manager.
- **Wiki runtime environment** — database credentials and `RAILS_ENV`, supplied by the
  deployment's environment file. See the server-access handoff (the Administrator card and
  its children) for how to reach the host and load that environment.
- **A wiki account with sufficient role** — RawData is restricted. Under the permission
  matrix documented in [`ROLES-AND-PERMISSIONS.md`](ROLES-AND-PERMISSIONS.md) §4, creating
  RawData cards currently requires **Administrator**: `RawData+*type+*create`, `*update`,
  and `*delete` all resolve to Administrator. The `Raw Data Analyst` role grants **read**
  access to RawData, not create/update/delete. Check §4 before assuming an analyst account
  can run the ingest stage, and re-read the live rule cards if the decision matters. For
  the wider operator context, see `../ONBOARDING.md` §7.
- **Export and staging directories** — where exports land and where the ingesters read
  from. Several scripts take these as environment variables or flags with defaults.
- **Target RawData parent naming** — the convention for where cards land
  (`RawData+transcripts`, `RawData+mattermost`, `RawData+Publications`, and similar). Confirm
  the current convention on the wiki before a first run; these scripts write into a live
  content hierarchy.

## What must never enter the repository or the docs

- Source payloads: transcripts, chat archives, meeting reports, downloaded PDFs, and any
  other exported content. These are the *inputs*, not the tooling.
- RawData card contents, database dumps, and application logs.
- Any credential, token, API key, password, private key, `.env` file, or connection string.

The scripts are part of the handoff. The data and the secrets are not.

## Safe first-run posture

For a team taking this over, in order:

1. **Read the script you are about to run.** Each has a usage docstring naming its inputs,
   its environment variables, and its output location.
2. **Start with a read-only or listing mode where one exists** — several export scripts
   accept a `--list` flag that enumerates what is available without downloading it.
3. **Run the export stage alone**, and inspect the JSON on local disk. This is the last
   point before anything touches the wiki.
4. **Run the ingest stage only with an authorized operator present**, under an account with
   the right role, and on a deliberately small first batch.
5. **Verify in the wiki** that cards landed under the expected parents with the expected
   content, before running a full batch.

Ingestion writes to a live content database. Treat a first run as a change to production,
because it is one.

---

## Related documents

- [`../ONBOARDING.md`](../ONBOARDING.md) §4 — the editorial workflow these cards enter.
- [`../ONBOARDING.md`](../ONBOARDING.md) §7 — roles, including who may create and read RawData.
- [`operations/DECKO-DATABASE-ACCESS.md`](operations/DECKO-DATABASE-ACCESS.md) — the `decko runner` remote-console
  procedure the `.rb` ingesters rely on.
