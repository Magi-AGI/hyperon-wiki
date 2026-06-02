#!/bin/bash
# Full transcript sync: export from Fireflies API, upload to server, ingest into wiki.
#
# Usage:
#   ./scripts/sync_transcripts.sh [--filter MEETING_NAME]
#
# Prerequisites:
#   - FIREFLIES_API_KEY env var set (or will prompt)
#   - SSH key at ~/.ssh/hyperon-key.pem
#   - Python 3.8+ (no extra pip dependencies — uses curl)
#
# This script:
#   1. Runs export_transcripts.py to pull full transcripts from Fireflies.ai
#   2. Uploads the export to the Hyperon Wiki server
#   3. Runs ingest_transcripts.rb via Decko card runner to write to the DB

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SERVER_IP="54.183.80.144"
SSH_KEY="$HOME/.ssh/hyperon-key.pem"
SSH_CMD="ssh -T -i $SSH_KEY ubuntu@$SERVER_IP"

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
$SSH_CMD "mkdir -p ~/transcript_exports"
scp -i "$SSH_KEY" -r "$EXPORT_DIR" "ubuntu@$SERVER_IP:~/transcript_exports/"

# Create a 'latest' symlink
REMOTE_DIR="~/transcript_exports/$(basename $EXPORT_DIR)"
$SSH_CMD "ln -sfn $REMOTE_DIR ~/transcript_exports/latest"
echo "  Uploaded and linked as ~/transcript_exports/latest"

# Step 3: Run ingestion
echo ""
echo "[Step 3/3] Running ingestion on server..."
cat "$SCRIPT_DIR/ingest_transcripts.rb" | $SSH_CMD \
  'export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH" && eval "$(rbenv init -)" && cd ~/hyperon-wiki && set -a && source .env.production && set +a && RAILS_ENV=production bundle exec decko runner -'

echo ""
echo "=================================================="
echo " Sync complete!"
echo "=================================================="
