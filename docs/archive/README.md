# Archive

Completed phase records, point-in-time status reports, and shipped-fix write-ups.

**These documents are historical.** They describe work that finished. They may read as
current — check the date before acting on anything here. They are kept because the record
of what was believed, and when, has repeatedly turned out to be worth more than a tidy
directory.

Nothing in the newcomer path points here. Start at [`../../ONBOARDING.md`](../../ONBOARDING.md),
and use [`../DOCUMENTATION-MAP.md`](../DOCUMENTATION-MAP.md) to find current documentation.

| Document | What it records |
|---|---|
| `MCP-PHASE-1.1-FIXES.md`, `MCP-PHASE-2-PLAN.md`, `MCP-PHASE-2-COMPLETE.md`, `TESTING-PHASE-2.md` | The `mcp_api` mod build-out: phase plans, completion notes, phase-2 testing guide |
| `usability-inventory-2026-05-08.md`, `usability-pass-checklist-2026-05-08.md`, `usability-pass-log-2026-05-08.md` | A May 2026 content usability pass — inventory, checklist, audit log. Useful as a worked example of a review pass |
| `RIGHT-COLUMN-IMPLEMENTATION-PLAN.md` | Implementation plan for the right-hand column / sidebar |
| `URL_PARSING_DEBUG_NOTES.md`, `URL_PARSING_FIX_SUMMARY.md` | URL parsing fix and the debugging behind it. Relates to the `url_fixes` mod |
| `DECKO-FILE-UPLOAD-BUG.md` | A file-upload bug investigation and its fix. **The fix may still be load-bearing** — check before removing anything it describes |
| `ws6-merge-editor-pr25-summary.md` | Summary of one merge-editor pull request |
| `AWS-DEPLOYMENT.md` | A generic EC2 and RDS deployment walkthrough inherited from a sibling deck, fully placeholdered. **Retired, not current operational instructions** — it describes standing up a new deployment from scratch on a platform this wiki already runs on. For operations, see [`../OPERATIONS.md`](../OPERATIONS.md) |

**`SCRIPTS-RESEARCH-ARCHIVE.md` used to live here and does not any more.** It describes a
*current* boundary — what the gitignored `scripts/archive/` corpus at the repository root is
and why it sits outside the handoff — rather than recording something that finished, so it
belongs with the current documentation. It is now
[`../SCRIPTS-RESEARCH-ARCHIVE.md`](../SCRIPTS-RESEARCH-ARCHIVE.md).

Two further records — an MCP deployment-status snapshot and an email-verification fix
summary — were **removed from this branch rather than archived**: both documented a sibling
deck's production server and carried its host, service account, and key details. They are
not recoverable from this docs branch; they survive only in git history and in that deck's
own repository.

Sibling-deck identifiers that survived in the files kept above (deck name, JWT issuer, deck
root, hostnames) have been replaced with `<placeholder>` values, and a few links to
documents that no longer exist here were converted to plain text. These are historical
records: the placeholders mark what *was* configured at the time, not what you should
configure now.
