# Browser Control MCP – Integration Guide

This guide shows how to install the Browser Control MCP server and wire it into MCP‑aware CLIs (Codex, Claude Desktop, etc.), plus a quick health check.

## Prerequisites
- Node.js 22+
- Firefox (or Developer Edition)
- The Browser Control repo: E:\GitHub\browser-control-mcp (adjust paths if different)

## Install and Build
1) Build server + extension
   - In `E:\GitHub\browser-control-mcp`:
     - `npm install`
     - `npm run build`
2) Install the Firefox extension
   - AMO: see repository README, or load temporary add‑on via `about:debugging` → Load `firefox-extension/manifest.json`
   - Copy the extension secret from its options page

## Configure MCP Server (stdio)
- Command: `node`
- Args: `E:\GitHub\browser-control-mcp\mcp-server\dist\server.js`
- Env:
  - `EXTENSION_SECRET`: value from the extension options page
  - `EXTENSION_PORT`: `8089` (optional, default 8089)

Examples are provided in:
- `docs/mcp/clients/codex.mcp.example.json`
- `docs/mcp/clients/claude_desktop_config.example.json`

## Health Check (optional)
Use `docs/mcp/scripts/health-check.mjs` to spawn the server and call `get-list-of-open-tabs`.
- Edit the placeholders (server path, secret) and run:
  - `node docs/mcp/scripts/health-check.mjs`

Port already in use?
- If Claude Desktop is running with the Browser Control MCP configured, it may already have spawned the server and bound the port (default 8089).
- Options:
  - Close Claude Desktop and re-run the health check; or
  - Set a different `EXTENSION_PORT` in `docs/mcp/.env` and update the Firefox extension options to match, then re-run.

Tool calls time out but server connects?
- Symptoms:
  - Script prints "Starting WebSocket server ..." and "WebSocket connection established", tools are listed, but `get-list-of-open-tabs` (and others) time out.
- Checks:
  - Ensure the Firefox extension Options page has the same `Secret` value as `EXTENSION_SECRET` in `.env` (no stray spaces/newlines).
  - Ensure the extension `Port` matches `EXTENSION_PORT` (default 8089).
  - Keep at least one normal browser window/tab open (not only private windows).
  - Open `about:debugging` → This Firefox → Inspect the extension → Console: look for messages like "Invalid message signature" or errors.
  - If a tab opens when calling `open-browser-tab` but the client still times out, update/rebuild the extension and server from the same repo commit to ensure message schema alignment (`npm install && npm run build` in the browser-control repo) and reload the extension.

Firefox shows `can't establish a connection to ws://localhost:8089`?
- What it means: the Firefox extension cannot open the WebSocket back to the Browser Control MCP server; nothing is listening on the chosen port (or the port is blocked).
- Fixes:
  - Launch the server manually so you can see its logs: `bash docs/mcp/scripts/start-server.sh` (macOS/Linux) or `pwsh -File docs/mcp/scripts/start-server.ps1` (Windows). You should see `Starting WebSocket server on 0.0.0.0:8089`. Stop it with Ctrl+C once confirmed.
  - If you expect Codex/Claude Desktop to auto-start the server, double-check the path in `docs/mcp/clients/*.json` is real and that the env block includes your actual `EXTENSION_SECRET`. A bad path/env means the server never spawns, so the extension keeps logging the WebSocket error.
  - Make sure `EXTENSION_PORT` in `.env`, the Firefox extension options, and any MCP client configs all match. If Claude Desktop is already bound to 8089, either quit it or pick another port (e.g., `8095`) everywhere.
  - Look for another process occupying the port (`netstat -ano | find "8089"` on Windows, `lsof -i :8089` on macOS/Linux). Kill the stale process or bump the port.
  - Firewalls/VPNs can also block loopback WebSockets; add an allow rule for `node.exe`/`node` if needed and retry the health check.

## Notes
- The server only connects locally to the Firefox extension using a shared secret.
- Reading page content requires explicit per‑domain consent in the extension.
- For Docker usage and DXT packaging, follow the browser-control repository README.

## Quick Start Wrappers

- Copy `docs/mcp/.env.example` to `docs/mcp/.env` and set:
  - `EXTENSION_SECRET`, optional `EXTENSION_PORT`, and `BROWSER_MCP_SERVER`
- Windows PowerShell:
  - `pwsh -File docs/mcp/scripts/start-server.ps1`
  - `pwsh -File docs/mcp/scripts/health-check.ps1` (loads `.env`, then runs the Node health‑check)
- macOS/Linux:
  - `bash docs/mcp/scripts/start-server.sh`
  - `node docs/mcp/scripts/health-check.mjs`
