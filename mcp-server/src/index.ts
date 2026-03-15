#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { registerTools } from "./tools.js";

async function main(): Promise<void> {
  const server = new McpServer({
    name: "screenshottool",
    version: "1.0.0",
  });

  // Register all screenshot tools
  registerTools(server);

  // Connect via stdio transport (used by Claude Code, Cursor, etc.)
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  console.error("Fatal error starting ScreenshotTool MCP server:", error);
  process.exit(1);
});
