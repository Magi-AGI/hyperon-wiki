#!/bin/bash
# Server-side Mattermost sync — runs entirely on the Hyperon Wiki server.
# No SCP needed since export and ingestion happen on the same machine.
#
# Setup (one-time, on the server):
#   1. pip3 install mattermostdriver
#   2. Copy export_mattermost.py and ingest_mattermost.rb to ~/hyperon-wiki/scripts/
#   3. Set MATTERMOST_TOKEN in ~/hyperon-wiki/.env.mattermost
#   4. Add cron job:
#      crontab -e
#      0 4 * * * /home/ubuntu/hyperon-wiki/scripts/server_sync_mattermost.sh >> /home/ubuntu/logs/mattermost_sync.log 2>&1
#
# Or run manually:
#   ~/hyperon-wiki/scripts/server_sync_mattermost.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WIKI_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$HOME/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$LOG_DIR"

echo "[$TIMESTAMP] Starting Mattermost sync..."

# Load token from env file
if [ -f "$WIKI_DIR/.env.mattermost" ]; then
  set -a && source "$WIKI_DIR/.env.mattermost" && set +a
fi

if [ -z "$MATTERMOST_TOKEN" ]; then
  echo "ERROR: MATTERMOST_TOKEN not set. Create $WIKI_DIR/.env.mattermost with:"
  echo '  MATTERMOST_TOKEN="your-personal-access-token"'
  exit 1
fi

# Step 1: Export from Mattermost API
EXPORT_DIR="$HOME/mattermost_exports/sync_$TIMESTAMP"
echo "[Step 1/3] Exporting from Mattermost..."
python3 "$SCRIPT_DIR/export_mattermost.py" \
  --token "$MATTERMOST_TOKEN" \
  --output "$EXPORT_DIR" \
  --no-files

# Update 'latest' symlink
ln -sfn "$EXPORT_DIR" "$HOME/mattermost_exports/latest"

# Step 2: Run ingestion via Decko card runner
echo "[Step 2/3] Ingesting into wiki database..."
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
eval "$(rbenv init -)"
cd "$WIKI_DIR"
set -a && source .env.production && set +a

MATTERMOST_EXPORT_DIR="$EXPORT_DIR" \
  RAILS_ENV=production bundle exec decko runner "$SCRIPT_DIR/ingest_mattermost.rb"

# Step 3: Cleanup old exports (keep last 7)
echo "[Step 3/3] Cleaning up old exports..."
ls -dt "$HOME/mattermost_exports/sync_"* 2>/dev/null | tail -n +8 | xargs rm -rf

FINISH=$(date +%Y%m%d_%H%M%S)
echo "[$FINISH] Sync complete!"
