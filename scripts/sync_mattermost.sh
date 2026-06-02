#!/bin/bash
# Full Mattermost sync: export from API, upload to server, ingest into wiki.
#
# Usage:
#   ./scripts/sync_mattermost.sh [--channel FILTER]
#
# Prerequisites:
#   - MATTERMOST_TOKEN env var set (or will prompt)
#   - SSH key at ~/.ssh/hyperon-key.pem
#   - Python with mattermostdriver: pip install mattermostdriver
#
# This script:
#   1. Runs mattermost_export.py to pull channels from chat.singularitynet.io
#   2. Uploads the export to the Hyperon Wiki server
#   3. Runs ingest_mattermost.rb via Decko card runner to write to the DB

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
MAGI_ARCHIVE_DIR="$(dirname "$REPO_DIR")/magi-archive"
SERVER_IP="54.183.80.144"
SSH_KEY="$HOME/.ssh/hyperon-key.pem"
SSH_CMD="ssh -T -i $SSH_KEY ubuntu@$SERVER_IP"

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
$SSH_CMD "mkdir -p ~/mattermost_exports"
scp -i "$SSH_KEY" -r "$EXPORT_DIR" "ubuntu@$SERVER_IP:~/mattermost_exports/"

# Create a 'latest' symlink
REMOTE_DIR="~/mattermost_exports/$(basename $EXPORT_DIR)"
$SSH_CMD "ln -sfn $REMOTE_DIR ~/mattermost_exports/latest"
echo "  Uploaded and linked as ~/mattermost_exports/latest"

# Step 3: Run ingestion
echo ""
echo "[Step 3/3] Running ingestion on server..."
cat "$SCRIPT_DIR/ingest_mattermost.rb" | $SSH_CMD \
  'export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH" && eval "$(rbenv init -)" && cd ~/hyperon-wiki && set -a && source .env.production && set +a && RAILS_ENV=production bundle exec decko runner -'

echo ""
echo "=================================================="
echo " Sync complete!"
echo "=================================================="
