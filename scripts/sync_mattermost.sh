#!/bin/bash
# Full Mattermost sync: export from API, upload to server, ingest into wiki.
#
# Usage:
#   ./scripts/sync_mattermost.sh [--channel FILTER]
#
# Prerequisites:
#   - MATTERMOST_TOKEN env var set (or will prompt)
#   - Connection details for the wiki host, from the server-access handoff:
#       HYPERON_WIKI_HOST      SSH host (required)
#       HYPERON_WIKI_SSH_KEY   SSH private-key path (required)
#       HYPERON_WIKI_SSH_USER  SSH user (optional, default: ubuntu)
#       HYPERON_WIKI_REMOTE_DIR  deck root on the host (optional, default: ~/hyperon-wiki)
#   - Python with mattermostdriver: pip install mattermostdriver
#
# This script:
#   1. Runs export_mattermost.py to pull channels from chat.singularitynet.io
#   2. Uploads the export to the Hyperon Wiki server
#   3. Runs ingest_mattermost.rb via Decko card runner to write to the DB

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

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
CHANNEL_FILTER=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --channel) CHANNEL_FILTER="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Check token
if [ -z "$MATTERMOST_TOKEN" ]; then
  echo "MATTERMOST_TOKEN not set."
  echo "Get it from: chat.singularitynet.io → F12 → Application → Cookies → MMAUTHTOKEN"
  read -p "Enter token: " MATTERMOST_TOKEN
  export MATTERMOST_TOKEN
fi

echo "=================================================="
echo " Hyperon Wiki Mattermost Sync"
echo "=================================================="

# Step 1: Export from Mattermost
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EXPORT_DIR="$REPO_DIR/mattermost_exports/sync_$TIMESTAMP"

echo ""
echo "[Step 1/3] Exporting from Mattermost..."
PYTHONIOENCODING=utf-8 python "$SCRIPT_DIR/export_mattermost.py" \
  --token "$MATTERMOST_TOKEN" \
  --output "$EXPORT_DIR" \
  --no-files

CHANNEL_COUNT=$(find "$EXPORT_DIR" -name "*.json" ! -name "export_summary.json" | wc -l)
echo "  Exported $CHANNEL_COUNT channels to $EXPORT_DIR"

# Step 2: Upload exports to server
echo ""
echo "[Step 2/3] Uploading to server..."
"${SSH_CMD[@]}" "mkdir -p ~/mattermost_exports"
"${SCP_CMD[@]}" -r "$EXPORT_DIR" "$SSH_TARGET:~/mattermost_exports/"

# Create a 'latest' symlink.
# The target is relative on purpose: `latest` and the export directory are
# siblings in ~/mattermost_exports, so a bare basename resolves correctly.
# An absolute '~/...' target would have to be quoted for spaces, and quoting
# the leading ~ stops the remote shell expanding it — leaving a dangling link
# whose target is the literal string "~/mattermost_exports/...".
EXPORT_BASENAME="$(basename "$EXPORT_DIR")"
"${SSH_CMD[@]}" "ln -sfn '$EXPORT_BASENAME' ~/mattermost_exports/latest"
echo "  Uploaded and linked as ~/mattermost_exports/latest"

# Step 3: Run ingestion
echo ""
echo "[Step 3/3] Running ingestion on server..."
cat "$SCRIPT_DIR/ingest_mattermost.rb" | "${SSH_CMD[@]}" \
  "export PATH=\"\$HOME/.rbenv/bin:\$HOME/.rbenv/shims:\$PATH\" && eval \"\$(rbenv init -)\" && cd $REMOTE_DIR_Q && set -a && source .env.production && set +a && RAILS_ENV=production bundle exec decko runner -"

echo ""
echo "=================================================="
echo " Sync complete!"
echo "=================================================="
