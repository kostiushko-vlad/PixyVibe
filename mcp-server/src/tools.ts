import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import {
  ScreenshotToolClient,
  type Region,
  type ScreenshotResponse,
} from "./client.js";

/**
 * Helper: lazily create a client instance, returning an error message
 * string if ScreenshotTool is not available.
 */
function getClient(): ScreenshotToolClient {
  return new ScreenshotToolClient();
}

/**
 * Build a Region object from optional numeric params.
 */
function buildRegion(
  x?: number,
  y?: number,
  width?: number,
  height?: number
): Region | undefined {
  if (
    x !== undefined &&
    y !== undefined &&
    width !== undefined &&
    height !== undefined
  ) {
    return { x, y, width, height };
  }
  return undefined;
}

/**
 * Format a screenshot response as MCP tool content (image + text metadata).
 */
function screenshotContent(res: ScreenshotResponse) {
  return [
    {
      type: "image" as const,
      data: res.image_base64,
      mimeType: "image/png",
    },
    {
      type: "text" as const,
      text: `Screenshot captured: ${res.width}x${res.height} at ${res.timestamp}\nSaved to: ${res.file_path}`,
    },
  ];
}

/**
 * Registers all ScreenshotTool MCP tools on the given server.
 */
export function registerTools(server: McpServer): void {
  // ── take_screenshot ───────────────────────────────────────────────
  server.tool(
    "take_screenshot",
    "Capture a screenshot of the desktop or a connected mobile device. " +
      "Returns the image as base64 PNG with metadata.",
    {
      target_id: z
        .string()
        .optional()
        .describe(
          "ID of the target device to capture. Omit for the default (desktop) target."
        ),
      region_x: z
        .number()
        .int()
        .optional()
        .describe("X coordinate of the capture region (pixels)."),
      region_y: z
        .number()
        .int()
        .optional()
        .describe("Y coordinate of the capture region (pixels)."),
      region_width: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Width of the capture region (pixels)."),
      region_height: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Height of the capture region (pixels)."),
    },
    async ({ target_id, region_x, region_y, region_width, region_height }) => {
      try {
        const client = getClient();
        const region = buildRegion(
          region_x,
          region_y,
          region_width,
          region_height
        );
        const res = await client.screenshot(target_id, region);
        return { content: screenshotContent(res) };
      } catch (e) {
        return {
          isError: true,
          content: [
            {
              type: "text" as const,
              text: `Error taking screenshot: ${e instanceof Error ? e.message : String(e)}`,
            },
          ],
        };
      }
    }
  );

  // ── record_gif ────────────────────────────────────────────────────
  server.tool(
    "record_gif",
    "Record a short GIF of the screen or a connected device. " +
      "Starts recording, waits for the specified duration, then stops and returns the GIF.",
    {
      target_id: z
        .string()
        .optional()
        .describe("ID of the target device. Omit for the default target."),
      duration_seconds: z
        .number()
        .positive()
        .default(5)
        .describe("Duration of the recording in seconds (default: 5)."),
      fps: z
        .number()
        .int()
        .positive()
        .default(10)
        .describe("Frames per second for the GIF (default: 10)."),
      region_x: z.number().int().optional().describe("X coordinate of the capture region."),
      region_y: z.number().int().optional().describe("Y coordinate of the capture region."),
      region_width: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Width of the capture region."),
      region_height: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Height of the capture region."),
    },
    async ({
      target_id,
      duration_seconds,
      fps,
      region_x,
      region_y,
      region_width,
      region_height,
    }) => {
      try {
        const client = getClient();
        const region = buildRegion(
          region_x,
          region_y,
          region_width,
          region_height
        );

        // Start recording
        await client.gifStart(target_id, fps, region);

        // Wait for the specified duration
        await new Promise((resolve) =>
          setTimeout(resolve, duration_seconds * 1000)
        );

        // Stop recording and retrieve the GIF
        const res = await client.gifStop();

        return {
          content: [
            {
              type: "image" as const,
              data: res.image_base64,
              mimeType: "image/gif",
            },
            {
              type: "text" as const,
              text:
                `GIF recorded: ${res.duration_seconds.toFixed(1)}s, ` +
                `${res.frame_count} frames\n` +
                `Saved to: ${res.file_path}`,
            },
          ],
        };
      } catch (e) {
        return {
          isError: true,
          content: [
            {
              type: "text" as const,
              text: `Error recording GIF: ${e instanceof Error ? e.message : String(e)}`,
            },
          ],
        };
      }
    }
  );

  // ── capture_diff ──────────────────────────────────────────────────
  server.tool(
    "capture_diff",
    "Capture a before/after visual diff. " +
      'Call with state="before" to capture the baseline, then make changes, ' +
      'then call with state="after" to get a diff image and change percentage.',
    {
      state: z
        .enum(["before", "after"])
        .describe(
          '"before" captures the baseline image. "after" captures the current state and compares.'
        ),
      target_id: z
        .string()
        .optional()
        .describe("ID of the target device. Omit for the default target."),
      region_x: z.number().int().optional().describe("X coordinate of the capture region."),
      region_y: z.number().int().optional().describe("Y coordinate of the capture region."),
      region_width: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Width of the capture region."),
      region_height: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Height of the capture region."),
    },
    async ({
      state,
      target_id,
      region_x,
      region_y,
      region_width,
      region_height,
    }) => {
      try {
        const client = getClient();
        const region = buildRegion(
          region_x,
          region_y,
          region_width,
          region_height
        );

        if (state === "before") {
          await client.diffBefore(target_id, region);
          return {
            content: [
              {
                type: "text" as const,
                text: 'Baseline "before" image captured. Make your changes, then call capture_diff with state="after".',
              },
            ],
          };
        }

        // state === "after"
        const res = await client.diffAfter(target_id, region);
        return {
          content: [
            {
              type: "image" as const,
              data: res.image_base64,
              mimeType: "image/png",
            },
            {
              type: "text" as const,
              text:
                `Visual diff complete: ${res.change_percentage.toFixed(2)}% of pixels changed.\n` +
                `Changed regions: ${res.changed_regions.length}\n` +
                `Saved to: ${res.file_path}`,
            },
          ],
        };
      } catch (e) {
        return {
          isError: true,
          content: [
            {
              type: "text" as const,
              text: `Error capturing diff: ${e instanceof Error ? e.message : String(e)}`,
            },
          ],
        };
      }
    }
  );

  // ── get_latest_screenshot ─────────────────────────────────────────
  server.tool(
    "get_latest_screenshot",
    "Retrieve the most recently captured screenshot. " +
      "Returns the image as base64 PNG with metadata.",
    {},
    async () => {
      try {
        const client = getClient();
        const res = await client.getLatest();
        return { content: screenshotContent(res) };
      } catch (e) {
        return {
          isError: true,
          content: [
            {
              type: "text" as const,
              text: `Error getting latest screenshot: ${e instanceof Error ? e.message : String(e)}`,
            },
          ],
        };
      }
    }
  );

  // ── list_targets ──────────────────────────────────────────────────
  server.tool(
    "list_targets",
    "List all connected capture targets (desktop, iOS, Android devices). " +
      "Returns JSON with device IDs, names, types, and connection status.",
    {},
    async () => {
      try {
        const client = getClient();
        const targets = await client.listTargets();

        if (targets.length === 0) {
          return {
            content: [
              {
                type: "text" as const,
                text: "No capture targets found. The desktop target should always be available if ScreenshotTool is running.",
              },
            ],
          };
        }

        const summary = targets
          .map((t) => {
            const res = t.resolution
              ? ` (${t.resolution.width}x${t.resolution.height})`
              : "";
            const status = t.connected ? "connected" : "disconnected";
            return `  - ${t.name} [${t.id}] (${t.type}, ${status})${res}`;
          })
          .join("\n");

        return {
          content: [
            {
              type: "text" as const,
              text: `Connected targets:\n${summary}\n\nFull data:\n${JSON.stringify(targets, null, 2)}`,
            },
          ],
        };
      } catch (e) {
        return {
          isError: true,
          content: [
            {
              type: "text" as const,
              text: `Error listing targets: ${e instanceof Error ? e.message : String(e)}`,
            },
          ],
        };
      }
    }
  );
}
