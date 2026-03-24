#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../../mcp/.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC2046
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

if [ -z "${BROWSER_MCP_SERVER:-}" ]; then
  echo "BROWSER_MCP_SERVER not set. Edit docs/mcp/.env or set env var." >&2
  exit 1
fi

echo "Starting Browser Control MCP server..."
echo " node $BROWSER_MCP_SERVER"
exec node "$BROWSER_MCP_SERVER"

