import { readFileSync, existsSync } from "fs";
import { homedir } from "os";
import { join } from "path";

// Types for API communication

interface ApiConfig {
  port: number;
  pid: number;
}

export interface Region {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface ScreenshotResponse {
  image_base64: string;
  width: number;
  height: number;
  timestamp: string;
  file_path: string;
}

export interface GifResponse {
  image_base64: string;
  duration_seconds: number;
  frame_count: number;
  file_path: string;
}

export interface DiffResponse {
  image_base64: string;
  change_percentage: number;
  changed_regions: Region[];
  file_path: string;
}

export interface Target {
  id: string;
  name: string;
  type: "desktop" | "ios" | "android";
  connected: boolean;
  resolution?: { width: number; height: number };
}

export interface StatusResponse {
  running: boolean;
  version: string;
  recording_gif: boolean;
  diff_pending: boolean;
  connected_targets: number;
}

export class ScreenshotToolClient {
  private baseUrl: string;

  constructor() {
    const configPath = join(homedir(), ".screenshottool", "api.json");

    if (!existsSync(configPath)) {
      throw new Error(
        `ScreenshotTool API config not found at ${configPath}. ` +
          "Please ensure ScreenshotTool is running. " +
          "Launch the ScreenshotTool app first, then retry."
      );
    }

    let config: ApiConfig;
    try {
      config = JSON.parse(readFileSync(configPath, "utf-8")) as ApiConfig;
    } catch (e) {
      throw new Error(
        `Failed to parse ScreenshotTool API config at ${configPath}: ${e instanceof Error ? e.message : String(e)}`
      );
    }

    this.baseUrl = `http://127.0.0.1:${config.port}`;
  }

  private async request<T>(
    method: string,
    path: string,
    body?: Record<string, unknown>
  ): Promise<T> {
    const url = `${this.baseUrl}${path}`;

    let response: Response;
    try {
      response = await fetch(url, {
        method,
        headers: body ? { "Content-Type": "application/json" } : undefined,
        body: body ? JSON.stringify(body) : undefined,
      });
    } catch (e) {
      throw new Error(
        `Cannot connect to ScreenshotTool at ${this.baseUrl}. ` +
          "Is the app running? " +
          `Error: ${e instanceof Error ? e.message : String(e)}`
      );
    }

    if (!response.ok) {
      const text = await response.text().catch(() => "unknown error");
      throw new Error(
        `ScreenshotTool API error (${response.status}): ${text}`
      );
    }

    return (await response.json()) as T;
  }

  async screenshot(
    targetId?: string,
    region?: Region
  ): Promise<ScreenshotResponse> {
    const body: Record<string, unknown> = {};
    if (targetId) body.target_id = targetId;
    if (region) body.region = region;

    return this.request<ScreenshotResponse>("POST", "/api/screenshot", body);
  }

  async gifStart(
    targetId?: string,
    fps?: number,
    region?: Region
  ): Promise<void> {
    const body: Record<string, unknown> = {};
    if (targetId) body.target_id = targetId;
    if (fps !== undefined) body.fps = fps;
    if (region) body.region = region;

    await this.request<{ ok: boolean }>("POST", "/api/gif", { ...body, action: "start" });
  }

  async gifStop(): Promise<GifResponse> {
    return this.request<GifResponse>("POST", "/api/gif", { action: "stop" });
  }

  async diffBefore(targetId?: string, region?: Region): Promise<void> {
    const body: Record<string, unknown> = {};
    if (targetId) body.target_id = targetId;
    if (region) body.region = region;

    await this.request<{ ok: boolean }>("POST", "/api/diff/before", body);
  }

  async diffAfter(targetId?: string, region?: Region): Promise<DiffResponse> {
    const body: Record<string, unknown> = {};
    if (targetId) body.target_id = targetId;
    if (region) body.region = region;

    return this.request<DiffResponse>("POST", "/api/diff/after", body);
  }

  async getLatest(): Promise<ScreenshotResponse> {
    return this.request<ScreenshotResponse>("GET", "/api/latest");
  }

  async listTargets(): Promise<Target[]> {
    return this.request<Target[]>("GET", "/api/targets");
  }

  async status(): Promise<StatusResponse> {
    return this.request<StatusResponse>("GET", "/api/status");
  }
}
