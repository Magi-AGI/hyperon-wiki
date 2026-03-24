// Minimal health check that spawns the Browser Control MCP server via stdio
// and calls the `get-list-of-open-tabs` tool.
//
// Usage:
//   1) Edit EXTENSION_SECRET and SERVER_PATH below.
//   2) Run:  node docs/mcp/scripts/health-check.mjs
//
// Requires: npm i @modelcontextprotocol/sdk zod

import { Client as McpClient } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

// EDIT THESE FOR YOUR MACHINE
const EXTENSION_SECRET = process.env.EXTENSION_SECRET || "<paste_secret_from_firefox_extension>";
const EXTENSION_PORT = process.env.EXTENSION_PORT || "8089";
const SERVER_PATH = process.env.BROWSER_MCP_SERVER || "E:/GitHub/browser-control-mcp/mcp-server/dist/server.js";

async function main() {
  if (!EXTENSION_SECRET || EXTENSION_SECRET.startsWith("<paste_")) {
    console.error("Please set EXTENSION_SECRET env var or edit this file.");
    process.exit(1);
  }

  const transport = new StdioClientTransport({
    command: "node",
    args: [SERVER_PATH],
    env: {
      EXTENSION_SECRET,
      EXTENSION_PORT,
    },
  });

  const client = new McpClient({ name: "magi-archive-health-check", version: "0.1.0" });
  try {
    await client.connect(transport, { timeout: 180_000 });
  } catch (e) {
    if (String(e?.message || e).includes("port 8089 is already in use") || String(e).includes("already in use")) {
      console.error("Port in use: EXTENSION_PORT", EXTENSION_PORT, "appears busy (e.g., Claude Desktop running). Close the other process or set a different EXTENSION_PORT and update the extension.");
    }
    throw e;
  }

  const tools = await client.listTools();
  console.log("Available tools:", tools.tools.map((t) => t.name));

  async function tryListTabs(label = "get-list-of-open-tabs") {
    const res = await client.callTool("get-list-of-open-tabs", {}, { timeout: 60_000 });
    console.log(label + " result:");
    for (const c of res.content) {
      if (c.type === "text") console.log("-", c.text);
    }
    return res;
  }

  try {
    await tryListTabs();
  } catch (err) {
    console.warn("list-tabs timed out; attempting to open a tab then retry...");
    await client.callTool("open-browser-tab", { url: "https://example.org" }, { timeout: 40_000 });
    // brief pause before retry
    await new Promise((r) => setTimeout(r, 1500));
    await tryListTabs("get-list-of-open-tabs (after open)");
  }

  await client.close();
}

main().catch((err) => {
  console.error("Health check failed:", err);
  process.exit(1);
});
