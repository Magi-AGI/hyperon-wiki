#!/bin/bash
# Full transcript sync: export from Fireflies API, upload to server, ingest into wiki.
#
# Usage:
#   ./scripts/sync_transcripts.sh [--filter MEETING_NAME]
#
# THIS SCRIPT WRITES TO THE LIVE WIKI and must be opted into explicitly:
#   TRANSCRIPT_SYNC_CONFIRM=1 ./scripts/sync_transcripts.sh
#
# Without that variable it stops before exporting anything. Running it is a
# production change: step 3 ingests into the live Decko database with writes
# enabled. Preview first with the dry-run/delta planner, which never writes:
#
#   # on the deck host, against an already-uploaded export
#   TRANSCRIPT_INGEST=1 TRANSCRIPT_INGEST_DRY_RUN=1 TRANSCRIPT_INGEST_DELTA=1 \
#     TRANSCRIPT_INGEST_REPORT=/tmp/transcript_delta.json \
#     RAILS_ENV=production bundle exec decko runner scripts/ingest_transcripts.rb
#
# Prerequisites:
#   - TRANSCRIPT_SYNC_CONFIRM=1 (explicit opt-in; this script writes to prod)
#   - FIREFLIES_API_KEY env var set (or will prompt)
#   - Connection details for the wiki host, from the server-access handoff:
#       HYPERON_WIKI_HOST      SSH host (required)
#       HYPERON_WIKI_SSH_KEY   SSH private-key path (required)
#       HYPERON_WIKI_SSH_USER  SSH user (optional, default: ubuntu)
#       HYPERON_WIKI_REMOTE_DIR  deck root on the host (optional, default: ~/hyperon-wiki)
#   - Python 3.8+ (no extra pip dependencies — uses curl)
#
# This script:
#   1. Runs export_transcripts.py to pull full transcripts from Fireflies.ai
#   2. Uploads the export to the Hyperon Wiki server
#   3. Runs ingest_transcripts.rb via Decko runner to write to the DB

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Explicit opt-in gate. This wrapper performs a real production ingest, so it
# must never run as a side effect of being invoked by a scheduler, a wrapper
# script, a shell-history recall or an agent sweeping the scripts directory.
if [ "${TRANSCRIPT_SYNC_CONFIRM:-}" != "1" ]; then
  cat >&2 <<'MSG'
Refusing to run: sync_transcripts.sh writes to the LIVE Hyperon Wiki.

It exports from Fireflies, uploads to the deck host, and runs
ingest_transcripts.rb with database writes ENABLED.

To preview without writing anything, run the planner on the deck host instead:

  TRANSCRIPT_INGEST=1 TRANSCRIPT_INGEST_DRY_RUN=1 TRANSCRIPT_INGEST_DELTA=1 \
    TRANSCRIPT_INGEST_REPORT=/tmp/transcript_delta.json \
    RAILS_ENV=production bundle exec decko runner scripts/ingest_transcripts.rb

To proceed with the real write:

  TRANSCRIPT_SYNC_CONFIRM=1 ./scripts/sync_transcripts.sh
MSG
  exit 1
fi

: "${HYPERON_WIKI_HOST:?Set HYPERON_WIKI_HOST to the wiki SSH host}"
: "${HYPERON_WIKI_SSH_KEY:?Set HYPERON_WIKI_SSH_KEY to the SSH private-key path}"
HYPERON_WIKI_SSH_USER="${HYPERON_WIKI_SSH_USER:-ubuntu}"
HYPERON_WIKI_REMOTE_DIR="${HYPERON_WIKI_REMOTE_DIR:-~/hyperon-wiki}"

SSH_KEY="$HYPERON_WIKI_SSH_KEY"
SSH_TARGET="${HYPERON_WIKI_SSH_USER}@${HYPERON_WIKI_HOST}"

# Arrays, not a string: a key path or remote dir containing spaces must stay a
# single argument. `$SSH_CMD ...` would word-split it.
SSH_CMD=(ssh -T -i "$SSH_KEY" "$SSH_TARGET")
SCP_CMD=(scp -i "$SSH_KEY")

# Single-quote the remote deck path so the remote shell treats it as one word.
# `~` is left outside the quotes so the remote shell still expands it.
case "$HYPERON_WIKI_REMOTE_DIR" in
  "~/"*) REMOTE_DIR_Q="~/'${HYPERON_WIKI_REMOTE_DIR#\~/}'" ;;
  *)     REMOTE_DIR_Q="'${HYPERON_WIKI_REMOTE_DIR}'" ;;
esac

# Parse args
FILTER=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --filter) FILTER="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Check API key
if [ -z "$FIREFLIES_API_KEY" ]; then
  echo "FIREFLIES_API_KEY not set."
  echo "Get it from: https://app.fireflies.ai/integrations/custom/fireflies"
  read -p "Enter API key: " FIREFLIES_API_KEY
  export FIREFLIES_API_KEY
fi

echo "=================================================="
echo " Hyperon Wiki Transcript Sync (Fireflies.ai)"
echo "=================================================="

# Step 1: Export from Fireflies
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EXPORT_DIR="$REPO_DIR/transcript_exports/fireflies_$TIMESTAMP"

echo ""
echo "[Step 1/3] Exporting from Fireflies.ai..."
if [ -n "$FILTER" ]; then
  python "$SCRIPT_DIR/export_transcripts.py" \
    --key "$FIREFLIES_API_KEY" \
    --output "$EXPORT_DIR" \
    --filter "$FILTER"
else
  python "$SCRIPT_DIR/export_transcripts.py" \
    --key "$FIREFLIES_API_KEY" \
    --output "$EXPORT_DIR"
fi

TRANSCRIPT_COUNT=$(find "$EXPORT_DIR" -name "*.json" ! -name "export_summary.json" | wc -l)
echo "  Exported $TRANSCRIPT_COUNT transcripts to $EXPORT_DIR"

if [ "$TRANSCRIPT_COUNT" -eq 0 ]; then
  echo "No transcripts to sync."
  exit 0
fi

# Step 2: Upload exports to server
echo ""
echo "[Step 2/3] Uploading to server..."
"${SSH_CMD[@]}" "mkdir -p ~/transcript_exports"
"${SCP_CMD[@]}" -r "$EXPORT_DIR" "$SSH_TARGET:~/transcript_exports/"

# Create a 'latest' symlink.
# The target is relative on purpose: `latest` and the export directory are
# siblings in ~/transcript_exports, so a bare basename resolves correctly.
# An absolute '~/...' target would have to be quoted for spaces, and quoting
# the leading ~ stops the remote shell expanding it — leaving a dangling link
# whose target is the literal string "~/transcript_exports/...".
EXPORT_BASENAME="$(basename "$EXPORT_DIR")"
"${SSH_CMD[@]}" "ln -sfn '$EXPORT_BASENAME' ~/transcript_exports/latest"
echo "  Uploaded and linked as ~/transcript_exports/latest"

# Step 3: Run ingestion
# TRANSCRIPT_INGEST=1 is required: ingest_transcripts.rb refuses to run when it
# is merely loaded, so the runner has to opt in. Without it this step would
# stream the script over stdin and silently do nothing.
echo ""
echo "[Step 3/3] Running ingestion on server..."
cat "$SCRIPT_DIR/ingest_transcripts.rb" | "${SSH_CMD[@]}" \
  "export PATH=\"\$HOME/.rbenv/bin:\$HOME/.rbenv/shims:\$PATH\" && eval \"\$(rbenv init -)\" && cd $REMOTE_DIR_Q && set -a && source .env.production && set +a && TRANSCRIPT_INGEST=1 RAILS_ENV=production bundle exec decko runner -"

echo ""
echo "=================================================="
echo " Sync complete!"
echo "=================================================="
