#!/usr/bin/env node
// Claude Octopus Enhanced HUD — Async Statusline with Rate Limits & Agent Tracking
// Requires Claude Code v2.1.33+ (statusline API with context_window data)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Provides rich statusline with:
//   - 5h/7d rate limit tracking (Anthropic OAuth API)
//   - Context window usage with gradient color bar
//   - Session cost with line change counts
//   - Cache hit rate from token usage
//   - Model name + CC version with update check
//   - Active workflow phase with emoji
//   - Provider status indicators
//   - Agent tree with model/elapsed/description
//   - Quality gate status
//   - Configurable column system (~/.claude-octopus/.hud-config.jsonc)
//
// Architecture: Async with Promise.all for concurrent API/transcript/version
// Latency: ~300-500ms cold (parallel API + transcript + version), <10ms cached
// Caching: Rate limits cached 60s, version cached 1h
// Fallback: Outputs empty on error (bash statusline handles it)

import { existsSync, readFileSync, writeFileSync, statSync, openSync, readSync, closeSync, mkdirSync, renameSync, createReadStream } from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";
import { createInterface } from "node:readline";
import https from "node:https";
import { execFileSync } from "node:child_process";

// Remote web sessions default to the lightweight bash statusline path to avoid
// local keychain/OAuth probes and slow terminal-only HUD work.
if (
  (process.env.CLAUDE_CODE_REMOTE === "true" || process.env.OCTOPUS_REMOTE_SESSION === "true") &&
  process.env.OCTOPUS_REMOTE_STATUSLINE !== "full"
) {
  process.exit(0);
}

// ── Section A: Constants + Colors ────────────────────────────────────────────

const HOME = homedir();
const SESSION_FILE = join(HOME, ".claude-octopus", "session.json");
const CACHE_DIR = join(HOME, ".claude-octopus", ".hud-cache");
const USAGE_CACHE_PATH = join(CACHE_DIR, "usage-cache.json");
const VERSION_CACHE_PATH = join(CACHE_DIR, "version-check.json");
const CONFIG_PATH = join(HOME, ".claude-octopus", ".hud-config.jsonc");
const CRED_PATH = join(HOME, ".claude", ".credentials.json");

// Octopus plugin version — read from package.json at startup
const SCRIPT_DIR = dirname(new URL(import.meta.url).pathname);
let OCTO_VERSION = "";
try {
  const pkg = JSON.parse(readFileSync(join(SCRIPT_DIR, "..", "package.json"), "utf-8"));
  OCTO_VERSION = pkg.version || "";
} catch { /* */ }

const OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
const CACHE_TTL_MS = 60_000;           // 60s cache for usage API
const CACHE_TTL_FAILURE_MS = 15_000;   // 15s on failure
const API_TIMEOUT_MS = 8000;
const VERSION_CACHE_TTL_MS = 3_600_000; // 1h cache for npm version check
const MAX_TAIL_BYTES = 512 * 1024;      // 500KB tail read for large transcripts
const MAX_AGENT_MAP = 100;
const STALE_AGENT_MS = 30 * 60_000;     // 30 min = stale agent

// Tailwind-inspired 24-bit color palette
const C = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  dim: "\x1b[2m",
  green: "\x1b[38;2;5;150;105m",       // Emerald-600 (#059669)
  yellow: "\x1b[38;2;217;119;6m",      // Amber-600 (#d97706)
  red: "\x1b[38;2;220;38;38m",         // Red-600 (#dc2626)
  cyan: "\x1b[36m",
  blue: "\x1b[34m",
  magenta: "\x1b[35m",
  white: "\x1b[37m",
  slate600: "\x1b[38;2;100;116;139m",  // Slate-600 (#64748b) — data values
  slate700: "\x1b[38;2;51;65;85m",     // Slate-700 (#334155) — labels
  slate700bold: "\x1b[1;38;2;51;65;85m",
  slate800: "\x1b[38;2;51;65;85m",     // Slate-800 — separators
  slate800bold: "\x1b[1;38;2;51;65;85m",
};

// All configurable columns
const ALL_COLUMNS = [
  "Octo", "5h Usage", "7d Usage", "Context", "Cost", "Cache", "Model",
  "Session", "Changes", "Tokens", "Output Tokens", "API Time", "Version",
  "5h Reset", "7d Reset", "RTK", "Saved",
];

// Default ON/OFF per column
const SECTION_DEFAULTS = {
  "Octo": true,
  "5h Usage": true, "7d Usage": true, "Context": true, "Cost": true, "Model": true,
  "Cache": false, "Version": false,
  "Session": false, "Changes": false, "Tokens": false, "Output Tokens": false,
  "API Time": false, "5h Reset": false, "7d Reset": false, "RTK": false, "Saved": false,
};

// v9.10.2: Named presets for quick config switching
// Set "preset": "developer" in ~/.claude-octopus/.hud-config.jsonc
const PRESETS = {
  minimal: ["Octo", "Model", "Context"],
  developer: ["Octo", "Model", "5h Usage", "7d Usage", "Context", "Cost", "Changes"],
  full: ALL_COLUMNS,
  performance: ["Octo", "Model", "Context", "Tokens", "Output Tokens", "Cache", "API Time", "Session", "RTK", "Saved"],
};

// Phase emoji mapping
const PHASE_EMOJI = {
  probe: "\u{1F50D}",    // magnifying glass
  grasp: "\u{1F3AF}",    // target
  tangle: "\u{1F6E0}",   // wrench
  ink: "\u2705",          // check mark
  complete: "\u{1F419}",  // octopus
  init: "\u{1F419}",
};

// ── Section B: Stdin (async) ─────────────────────────────────────────────────

async function readStdin() {
  if (process.stdin.isTTY) return null;
  const chunks = [];
  try {
    process.stdin.setEncoding("utf8");
    // Race stdin read against a 5s timeout to prevent indefinite hang
    const stdinRead = (async () => {
      for await (const chunk of process.stdin) chunks.push(chunk);
      const raw = chunks.join("");
      return raw.trim() ? JSON.parse(raw) : null;
    })();
    const timeout = new Promise((resolve) => setTimeout(() => resolve(null), 5000));
    return await Promise.race([stdinRead, timeout]);
  } catch {
    return null;
  }
}

// ── Section C: Config System ─────────────────────────────────────────────────

function parseJsonc(text) {
  const stripped = text
    .replace(/("(?:[^"\\]|\\.)*")|\/\/.*/g, (m, str) => str || "")
    .replace(/,(\s*[}\]])/g, "$1");
  return JSON.parse(stripped);
}

// Smart column selection — adapts to context signals
// input: statusline stdin data, usage: rate limit API data, base: optional preset columns
function smartColumns(input, usage, base = null) {
  const cols = base ? [...base] : ["Octo", "Model"]; // Preset or brand + model first
  const has = (id) => cols.includes(id);
  // OAuth subscription: true if usage API returned data OR OAuth credentials exist
  const isOAuth = !!usage || !!getCredentials();
  const cost = input?.cost;
  const contextPct = getContextPercent(input);
  const cacheRate = cacheHitRate(input);
  const added = cost?.total_lines_added ?? 0;
  const removed = cost?.total_lines_removed ?? 0;
  const durationMs = cost?.total_duration_ms ?? 0;

  // Rate limits — always relevant for subscription users
  if (isOAuth) {
    if (!has("5h Usage")) cols.push("5h Usage");
    if (!has("7d Usage")) cols.push("7d Usage");
  }

  // Cost — only for API-key users (not OAuth subscription)
  if (!isOAuth && !has("Cost")) {
    cols.push("Cost");
  }

  // Cache — show when there's meaningful cache activity
  if (cacheRate !== null && cacheRate > 0 && !has("Cache")) {
    cols.push("Cache");
  }

  // Session — show when session has been running > 5 minutes
  if (durationMs > 5 * 60_000 && !has("Session")) {
    cols.push("Session");
  }

  // Changes — show when files are being modified
  if ((added > 0 || removed > 0) && !has("Changes")) {
    cols.push("Changes");
  }

  // Tokens — show when context pressure is building (>40%)
  if (contextPct > 40 && !has("Tokens")) {
    cols.push("Tokens");
  }

  // RTK — show when RTK has meaningful savings data
  const rtkGain = getRtkGain();
  if (rtkGain && rtkGain.totalSaved > 0 && !has("RTK")) {
    cols.push("RTK");
  }

  // Context — always last (most visual, anchors the row)
  if (!has("Context")) cols.push("Context");

  return cols;
}

function readConfig(input, usage) {
  const defaultResult = { columns: ALL_COLUMNS.filter((id) => SECTION_DEFAULTS[id] !== false), layout: "vertical", smart: true };
  try {
    if (!existsSync(CONFIG_PATH)) {
      // No config file → smart mode by default
      return { columns: smartColumns(input, usage), layout: "vertical", smart: true };
    }
    const cfg = parseJsonc(readFileSync(CONFIG_PATH, "utf-8"));
    const layout = cfg.layout === "horizontal" ? "horizontal" : "vertical";
    const presetName = cfg.preset || null;

    // v9.10.2: Preset support — named config profiles
    if (presetName && PRESETS[presetName]) {
      const presetCols = [...PRESETS[presetName]];
      if (cfg.smart !== false) {
        return { columns: smartColumns(input, usage, presetCols), layout, smart: true, preset: presetName };
      }
      return { columns: presetCols, layout, smart: false, preset: presetName };
    }

    // Smart mode: auto-detect columns based on context
    if (cfg.smart !== false) {
      const base = smartColumns(input, usage);
      // Apply explicit overrides from config on top of smart defaults
      const overridden = base.filter((id) => cfg[id] !== false);
      // Add any explicitly enabled columns not in smart set
      for (const id of ALL_COLUMNS) {
        if (cfg[id] === true && !overridden.includes(id)) {
          overridden.push(id);
        }
      }
      return { columns: overridden.length > 0 ? overridden : base, layout, smart: true };
    }

    // Manual mode: explicit column selection
    const enabled = ALL_COLUMNS.filter((id) => {
      if (id in cfg) return cfg[id] !== false;
      return SECTION_DEFAULTS[id] !== false;
    });
    return { columns: enabled.length > 0 ? enabled : ALL_COLUMNS, layout, smart: false };
  } catch {
    return defaultResult;
  }
}

// ── Section D: Rate Limit API (Anthropic OAuth) ──────────────────────────────

function getCredentials() {
  try {
    if (existsSync(CRED_PATH)) {
      const parsed = JSON.parse(readFileSync(CRED_PATH, "utf-8"));
      const creds = parsed.claudeAiOauth || parsed;
      if (creds.accessToken) {
        return { accessToken: creds.accessToken, expiresAt: creds.expiresAt, refreshToken: creds.refreshToken };
      }
    }
  } catch { /* */ }

  if (process.platform === "darwin") {
    try {
      const raw = execFileSync("security", [
        "find-generic-password", "-s", "Claude Code-credentials", "-w",
      ], { timeout: 3000, encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }).trim();
      if (raw) {
        const parsed = JSON.parse(raw);
        const creds = parsed.claudeAiOauth || parsed;
        if (creds.accessToken) {
          return { accessToken: creds.accessToken, expiresAt: creds.expiresAt, refreshToken: creds.refreshToken };
        }
      }
    } catch { /* Keychain entry doesn't exist or parse failed */ }
  }

  return null;
}

function refreshAccessToken(refreshToken) {
  return new Promise((resolve) => {
    const body = new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: refreshToken,
      client_id: OAUTH_CLIENT_ID,
    }).toString();
    const req = https.request({
      hostname: "platform.claude.com",
      path: "/v1/oauth/token",
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded", "Content-Length": Buffer.byteLength(body) },
      timeout: API_TIMEOUT_MS,
    }, (res) => {
      let data = "";
      res.on("data", (ch) => { data += ch; });
      res.on("end", () => {
        if (res.statusCode === 200) {
          try {
            const p = JSON.parse(data);
            if (p.access_token) {
              resolve({ accessToken: p.access_token, refreshToken: p.refresh_token || refreshToken, expiresAt: p.expires_in ? Date.now() + p.expires_in * 1000 : p.expires_at });
              return;
            }
          } catch { /* */ }
        }
        resolve(null);
      });
    });
    req.on("error", () => resolve(null));
    req.on("timeout", () => { req.destroy(); resolve(null); });
    req.end(body);
  });
}

function fetchUsage(accessToken) {
  return new Promise((resolve) => {
    const req = https.request({
      hostname: "api.anthropic.com",
      path: "/api/oauth/usage",
      method: "GET",
      headers: { Authorization: `Bearer ${accessToken}`, "anthropic-beta": "oauth-2025-04-20", "Content-Type": "application/json" },
      timeout: API_TIMEOUT_MS,
    }, (res) => {
      let data = "";
      res.on("data", (ch) => { data += ch; });
      res.on("end", () => {
        if (res.statusCode === 200) {
          try { resolve(JSON.parse(data)); } catch { resolve(null); }
        } else resolve(null);
      });
    });
    req.on("error", () => resolve(null));
    req.on("timeout", () => { req.destroy(); resolve(null); });
    req.end();
  });
}

function writeBackCredentials(creds) {
  try {
    if (!existsSync(CRED_PATH)) return;
    const parsed = JSON.parse(readFileSync(CRED_PATH, "utf-8"));
    const target = parsed.claudeAiOauth || parsed;
    target.accessToken = creds.accessToken;
    if (creds.expiresAt != null) target.expiresAt = creds.expiresAt;
    if (creds.refreshToken) target.refreshToken = creds.refreshToken;
    // Atomic write: temp file + rename to prevent concurrent session clobber
    const tmp = CRED_PATH + ".tmp." + process.pid;
    writeFileSync(tmp, JSON.stringify(parsed, null, 2), { mode: 0o600 });
    renameSync(tmp, CRED_PATH);
  } catch { /* */ }
}

function readUsageCache() {
  try {
    if (!existsSync(USAGE_CACHE_PATH)) return null;
    const cache = JSON.parse(readFileSync(USAGE_CACHE_PATH, "utf-8"));
    if (cache?.data) {
      if (cache.data.fiveHourResets) cache.data.fiveHourResets = new Date(cache.data.fiveHourResets);
      if (cache.data.sevenDayResets) cache.data.sevenDayResets = new Date(cache.data.sevenDayResets);
    }
    return cache;
  } catch {
    return null;
  }
}

function writeUsageCache(data, error = false) {
  try {
    if (!existsSync(CACHE_DIR)) mkdirSync(CACHE_DIR, { recursive: true });
    // Atomic write to prevent torn JSON from concurrent sessions
    const tmp = USAGE_CACHE_PATH + ".tmp." + process.pid;
    writeFileSync(tmp, JSON.stringify({ timestamp: Date.now(), data, error }));
    renameSync(tmp, USAGE_CACHE_PATH);
  } catch { /* */ }
}

function isCacheValid(cache) {
  const ttl = cache.error ? CACHE_TTL_FAILURE_MS : CACHE_TTL_MS;
  return Date.now() - cache.timestamp < ttl;
}

// v9.19.0: Parse CC-provided rate_limits from stdin (v2.1.80+, SUPPORTS_RATE_LIMIT_STATUSLINE)
// Used as fallback when OAuth API is unavailable (enterprise, API-billing, expired creds)
function parseInputRateLimits(inputRateLimits) {
  if (!inputRateLimits) return null;
  const clamp = (v) => (v == null || !isFinite(v)) ? 0 : Math.max(0, Math.min(100, v));
  return {
    fiveHour: clamp(inputRateLimits.five_hour?.utilization),
    fiveHourResets: null,
    sevenDay: clamp(inputRateLimits.seven_day?.utilization),
    sevenDayResets: null,
  };
}

async function getUsage(inputRateLimits) {
  const cache = readUsageCache();
  if (cache && isCacheValid(cache)) {
    // v9.19.0: On error cache, still try CC-provided rate limits before returning null
    if (cache.data) return cache.data;
    return parseInputRateLimits(inputRateLimits);
  }

  let creds = getCredentials();
  if (!creds) {
    writeUsageCache(null, true);
    return parseInputRateLimits(inputRateLimits);
  }

  if (creds.expiresAt && creds.expiresAt <= Date.now()) {
    if (creds.refreshToken) {
      const refreshed = await refreshAccessToken(creds.refreshToken);
      if (refreshed) {
        creds = { ...creds, ...refreshed };
        writeBackCredentials(creds);
      } else {
        writeUsageCache(null, true);
        return parseInputRateLimits(inputRateLimits);
      }
    } else {
      writeUsageCache(null, true);
      return parseInputRateLimits(inputRateLimits);
    }
  }

  const resp = await fetchUsage(creds.accessToken);
  if (!resp) {
    writeUsageCache(null, true);
    return parseInputRateLimits(inputRateLimits);
  }

  const clamp = (v) => (v == null || !isFinite(v)) ? 0 : Math.max(0, Math.min(100, v));
  const parseDate = (s) => { try { const d = new Date(s); return isNaN(d.getTime()) ? null : d; } catch { return null; } };

  const data = {
    fiveHour: clamp(resp.five_hour?.utilization),
    fiveHourResets: parseDate(resp.five_hour?.resets_at),
    sevenDay: clamp(resp.seven_day?.utilization),
    sevenDayResets: parseDate(resp.seven_day?.resets_at),
  };
  writeUsageCache(data);
  return data;
}

// ── Section E: Version Check (npm registry) ──────────────────────────────────

function readVersionCache() {
  try {
    if (!existsSync(VERSION_CACHE_PATH)) return null;
    const cache = JSON.parse(readFileSync(VERSION_CACHE_PATH, "utf-8"));
    if (Date.now() - cache.timestamp < VERSION_CACHE_TTL_MS) return cache.data;
    return null;
  } catch {
    return null;
  }
}

function writeVersionCache(data) {
  try {
    if (!existsSync(CACHE_DIR)) mkdirSync(CACHE_DIR, { recursive: true });
    writeFileSync(VERSION_CACHE_PATH, JSON.stringify({ timestamp: Date.now(), data }));
  } catch { /* */ }
}

function fetchLatestVersion() {
  return new Promise((resolve) => {
    const req = https.request({
      hostname: "registry.npmjs.org",
      path: "/@anthropic-ai/claude-code/latest",
      method: "GET",
      headers: { Accept: "application/json" },
      timeout: 3000,
    }, (res) => {
      let data = "";
      res.on("data", (ch) => { data += ch; });
      res.on("end", () => {
        if (res.statusCode === 200) {
          try { resolve(JSON.parse(data).version || null); } catch { resolve(null); }
        } else resolve(null);
      });
    });
    req.on("error", () => resolve(null));
    req.on("timeout", () => { req.destroy(); resolve(null); });
    req.end();
  });
}

async function getLatestVersion() {
  const cached = readVersionCache();
  if (cached) return cached;
  const latest = await fetchLatestVersion();
  if (latest) writeVersionCache(latest);
  return latest;
}

// ── Section F: Transcript Parser ─────────────────────────────────────────────

function readTailLines(filePath, fileSize, maxBytes) {
  const start = Math.max(0, fileSize - maxBytes);
  const len = fileSize - start;
  const fd = openSync(filePath, "r");
  const buf = Buffer.alloc(len);
  try { readSync(fd, buf, 0, len, start); } finally { closeSync(fd); }
  const lines = buf.toString("utf8").split("\n");
  if (start > 0 && lines.length > 0) lines.shift();
  return lines;
}

async function parseTranscript(transcriptPath) {
  const result = {
    sessionStart: null, agents: [], todos: [],
    tools: { active: null, counts: {} },  // v9.10.2: Tool activity tracking
  };
  if (!transcriptPath || !existsSync(transcriptPath)) return result;

  const agentMap = new Map();
  const bgMap = new Map();
  let latestTodos = [];

  function processLine(line) {
    if (!line.trim()) return;
    let entry;
    try { entry = JSON.parse(line); } catch { return; }
    const ts = entry.timestamp ? new Date(entry.timestamp) : new Date();
    if (!result.sessionStart && entry.timestamp) result.sessionStart = ts;

    const content = entry.message?.content;
    if (!content || !Array.isArray(content)) return;

    for (const block of content) {
      if (block.type === "tool_use" && block.id && block.name) {
        if (block.name === "Task" || block.name === "proxy_Task") {
          const input = block.input;
          if (agentMap.size >= MAX_AGENT_MAP) {
            let oldest = null, oldestT = Infinity;
            for (const [id, a] of agentMap) {
              if (a.status === "completed" && a.startTime.getTime() < oldestT) {
                oldestT = a.startTime.getTime();
                oldest = id;
              }
            }
            if (oldest) agentMap.delete(oldest);
          }
          agentMap.set(block.id, {
            id: block.id,
            type: input?.subagent_type ?? "unknown",
            model: input?.model,
            description: input?.description ?? "",
            status: "running",
            startTime: ts,
          });
        }
        if (block.name === "TaskCreate" || block.name === "TodoWrite") {
          const input = block.input;
          if (input?.todos && Array.isArray(input.todos)) {
            latestTodos = input.todos.map((t) => ({ content: t.content, status: t.status }));
          }
        }
        // v9.10.2: Track tool activity (Read, Write, Edit, Bash, Grep, Glob)
        const TRACKED_TOOLS = ["Read", "Write", "Edit", "Bash", "Grep", "Glob", "WebSearch", "WebFetch"];
        if (TRACKED_TOOLS.includes(block.name)) {
          const inp = block.input || {};
          const target = inp.file_path?.split("/").pop() || inp.command?.substring(0, 30) || inp.pattern || inp.query || "";
          result.tools.active = { name: block.name, target: target.substring(0, 25), id: block.id };
          result.tools.counts[block.name] = (result.tools.counts[block.name] || 0) + 1;
        }
      }

      if (block.type === "tool_result" && block.tool_use_id) {
        // v9.10.2: Clear active tool when result arrives
        if (result.tools.active && result.tools.active.id === block.tool_use_id) {
          result.tools.active = null;
        }
        const agent = agentMap.get(block.tool_use_id);
        if (agent) {
          const text = typeof block.content === "string" ? block.content : (Array.isArray(block.content) ? block.content.map(b => b.text || "").join("") : "");
          if (text.includes("Async agent launched")) {
            const m = text.match(/agentId:\s*([a-zA-Z0-9]+)/);
            if (m) bgMap.set(m[1], block.tool_use_id);
          } else {
            agent.status = "completed";
            agent.endTime = ts;
          }
        }
        if (block.content) {
          const text = typeof block.content === "string" ? block.content : (Array.isArray(block.content) ? block.content.map(b => b.text || "").join("") : "");
          const tidM = text.match(/<task_id>([^<]+)<\/task_id>/);
          const stM = text.match(/<status>([^<]+)<\/status>/);
          if (tidM && stM && stM[1] === "completed") {
            const origId = bgMap.get(tidM[1]);
            if (origId) {
              const bg = agentMap.get(origId);
              if (bg && bg.status === "running") { bg.status = "completed"; bg.endTime = ts; }
            }
          }
        }
      }
    }
  }

  try {
    const stat = statSync(transcriptPath);
    if (stat.size > MAX_TAIL_BYTES) {
      const fd = openSync(transcriptPath, "r");
      const firstBuf = Buffer.alloc(Math.min(4096, stat.size));
      try { readSync(fd, firstBuf, 0, firstBuf.length, 0); } finally { closeSync(fd); }
      const firstLine = firstBuf.toString("utf8").split("\n")[0];
      if (firstLine.trim()) {
        try {
          const e = JSON.parse(firstLine);
          if (e.timestamp) result.sessionStart = new Date(e.timestamp);
        } catch { /* */ }
      }
      for (const line of readTailLines(transcriptPath, stat.size, MAX_TAIL_BYTES)) processLine(line);
    } else {
      const stream = createReadStream(transcriptPath);
      const rl = createInterface({ input: stream, crlfDelay: Infinity });
      for await (const line of rl) processLine(line);
    }
  } catch { /* partial results */ }

  const now = Date.now();
  for (const a of agentMap.values()) {
    if (a.status === "running" && now - a.startTime.getTime() > STALE_AGENT_MS) {
      a.status = "completed";
    }
  }

  const running = [...agentMap.values()].filter((a) => a.status === "running");
  const completed = [...agentMap.values()].filter((a) => a.status === "completed");
  result.agents = [...running, ...completed.slice(-(10 - running.length))].slice(0, 10);
  result.todos = latestTodos;
  return result;
}

// ── Section G: Rendering Helpers ─────────────────────────────────────────────

function formatDuration(ms) {
  if (ms < 0) ms = 0;
  const totalSec = Math.floor(ms / 1000);
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  if (h > 0) return `${h}h${m.toString().padStart(2, "0")}m`;
  if (m > 0) return `${m}m${s.toString().padStart(2, "0")}s`;
  return `${s}s`;
}

function formatTokens(n) {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
  return `${n}`;
}

function colorForPercent(pct, warnAt = 70, critAt = 85) {
  if (pct >= critAt) return C.red;
  if (pct >= warnAt) return C.yellow;
  return C.green;
}

function contextBar(pct) {
  const filled = Math.min(10, Math.max(0, Math.round(pct / 10)));
  const empty = 10 - filled;
  const color = colorForPercent(pct);
  return `${color}${"▰".repeat(filled)}${"▱".repeat(empty)} ${pct}%${C.reset}`;
}

function formatResetTime(resetDate) {
  if (!resetDate) return "";
  const d = resetDate instanceof Date ? resetDate : new Date(resetDate);
  if (isNaN(d.getTime())) return "";
  const ms = d.getTime() - Date.now();
  if (ms <= 0) return "";
  const totalMin = Math.floor(ms / 60_000);
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  const short = h > 0 ? `~${h}h` : `${m}m`;
  return `${C.slate600}(${short})${C.reset}`;
}

function stripAnsi(str) {
  return str.replace(/\x1b\[[0-9;]*m/g, "");
}

function padAnsi(str, width) {
  const visible = stripAnsi(str).length;
  const padding = Math.max(0, width - visible);
  return str + " ".repeat(padding);
}

function cacheHitRate(stdinData) {
  const cu = stdinData?.context_window?.current_usage;
  if (!cu) return null;
  const cacheRead = cu.cache_read_input_tokens ?? 0;
  const total = (cu.input_tokens ?? 0) + (cu.cache_creation_input_tokens ?? 0) + cacheRead;
  if (total === 0) return null;
  return Math.round((cacheRead / total) * 100);
}

// v9.19.0: RTK gain stats — cached for 120s to avoid repeated subprocess calls
const RTK_GAIN_CACHE_TTL_MS = 120_000;
let rtkGainCache = { data: null, ts: 0 };

function getRtkGain() {
  const now = Date.now();
  if (rtkGainCache.data !== undefined && (now - rtkGainCache.ts) < RTK_GAIN_CACHE_TTL_MS) {
    return rtkGainCache.data;
  }
  try {
    const raw = execFileSync("rtk", ["gain", "--json"], {
      timeout: 2000, encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    if (raw) {
      const parsed = JSON.parse(raw);
      const summary = parsed.summary || parsed;
      rtkGainCache = {
        data: {
          totalSaved: summary.total_saved ?? 0,
          totalCommands: summary.total_commands ?? 0,
          avgSavingsPct: summary.avg_savings_pct ?? 0,
        },
        ts: now,
      };
      return rtkGainCache.data;
    }
    // Empty output — cache null to avoid repeated 2s subprocess calls
    rtkGainCache = { data: null, ts: now };
    return null;
  } catch { /* rtk not installed or gain failed */ }
  rtkGainCache = { data: null, ts: now };
  return null;
}

function getContextPercent(stdin) {
  const pct = stdin.context_window?.used_percentage;
  if (typeof pct === "number" && !Number.isNaN(pct)) {
    return Math.min(100, Math.max(0, Math.round(pct)));
  }
  const size = stdin.context_window?.context_window_size;
  if (!size || size <= 0) return 0;
  const usage = stdin.context_window?.current_usage;
  const total = (usage?.input_tokens ?? 0) + (usage?.cache_creation_input_tokens ?? 0) + (usage?.cache_read_input_tokens ?? 0);
  return Math.min(100, Math.round((total / size) * 100));
}

function getModelId(stdin) {
  const id = stdin.model?.id ?? stdin.model?.display_name ?? "unknown";
  const m = id.match(/(?:claude-)?(opus|sonnet|haiku)-(\d+)-(\d+)/);
  if (m) {
    const name = m[1].charAt(0).toUpperCase() + m[1].slice(1);
    return `${name} ${m[2]}.${m[3]}`;
  }
  return id;
}

// ── Section H: Octopus Workflow Functions ─────────────────────────────────────

function readSession() {
  try {
    if (!existsSync(SESSION_FILE)) return null;
    const stat = statSync(SESSION_FILE);
    if (Date.now() - stat.mtimeMs > 30 * 60 * 1000) return null;
    return JSON.parse(readFileSync(SESSION_FILE, "utf8"));
  } catch {
    return null;
  }
}

// Read progress file for active agent name (v9.6.0)
let _progressCache = { data: null, ts: 0 };
function readProgress() {
  try {
    if (Date.now() - _progressCache.ts < 2000) return _progressCache.data;
    const sid = process.env.CLAUDE_SESSION_ID || "";
    if (!sid) { _progressCache = { data: null, ts: Date.now() }; return null; }
    const pf = join(HOME, ".claude-octopus", `progress-${sid}.json`);
    if (!existsSync(pf)) { _progressCache = { data: null, ts: Date.now() }; return null; }
    const data = JSON.parse(readFileSync(pf, "utf8"));
    _progressCache = { data, ts: Date.now() };
    return data;
  } catch {
    _progressCache = { data: null, ts: Date.now() };
    return null;
  }
}

// Get name of currently running agent from progress data (v9.6.0)
function activeAgentName(progress) {
  if (!progress || !progress.agents) return "";
  for (const [name, info] of Object.entries(progress.agents)) {
    if (info && info.status === "running") return name;
  }
  return "";
}

// Read project state from .octo/STATE.md for current task display (v9.6.0)
function readProjectState() {
  try {
    const stateFile = join(process.cwd(), ".octo", "STATE.md");
    if (!existsSync(stateFile)) return "";
    const content = readFileSync(stateFile, "utf8");
    const match = content.match(/current_position:\s*(.+)/i) || content.match(/## Current.*\n+(.+)/i);
    if (match && match[1]) return match[1].trim().slice(0, 40);
    return "";
  } catch {
    return "";
  }
}

function providerIndicators() {
  const indicators = [];
  if (process.env.OPENAI_API_KEY || existsSync(join(HOME, ".codex", "auth.json"))) {
    indicators.push(`${C.red}\u{1F534}${C.reset}`);
  }
  if (process.env.GEMINI_API_KEY || existsSync(join(HOME, ".gemini", "oauth_creds.json"))) {
    indicators.push(`${C.yellow}\u{1F7E1}${C.reset}`);
  }
  indicators.push(`${C.blue}\u{1F535}${C.reset}`);
  return indicators.join("");
}

function agentInfo(session) {
  if (!session) return "";
  const tasks = session.phase_tasks;
  if (!tasks || !tasks.total) return "";
  return `${C.dim}${tasks.completed}/${tasks.total}${C.reset}`;
}

function qualityGate(session) {
  if (!session || !session.quality_gates) return "";
  const gates = session.quality_gates;
  if (gates.passed) return `${C.green}\u2713${C.reset}`;
  if (gates.failed) return `${C.red}\u2717${C.reset}`;
  return "";
}

// v9.19.0: Cost projection from session metrics
function costProjection(session, inputCost) {
  try {
    const completed = session?.completed_phases || 0;
    const total = session?.total_phases || 4;
    const remaining = total - completed;
    const spent = inputCost?.total_cost_usd ?? 0;
    if (spent <= 0 || completed < 2) {
      // Need 2+ data points to project
      if (spent > 0) return `${C.green}$${spent.toFixed(2)}${C.reset}`;
      return "";
    }
    const avg = spent / completed;
    const projected = spent + avg * remaining;
    const costColor = projected >= 5 ? C.red : projected >= 1 ? C.yellow : C.green;
    let seg = `${costColor}$${spent.toFixed(2)}\u2192~$${projected.toFixed(2)}${C.reset}`;
    const ceiling = process.env.OCTO_BUDGET_CEILING;
    if (ceiling && projected > parseFloat(ceiling)) {
      seg += ` ${C.red}\u26A0${C.reset}`;
    }
    return seg;
  } catch {
    return "";
  }
}

function writeContextBridge(input) {
  try {
    const pct = Math.round(input?.context_window?.used_percentage || 0);
    const sid = input?.session_id || process.env.CLAUDE_SESSION_ID || "unknown";
    const bf = `/tmp/octopus-ctx-${sid}.json`;
    writeFileSync(bf, JSON.stringify({
      session_id: sid,
      used_pct: pct, remaining_pct: 100 - pct, ts: Math.floor(Date.now() / 1000),
    }) + "\n");
  } catch { /* */ }
}

// ── Section I: Main Render ───────────────────────────────────────────────────

function render(input, session, usage, transcript, latestVersion, config) {
  const pipe = `${C.slate800}\u2502`;
  const version = input?.version ?? null;
  const cost = input?.cost;

  // Smart mode: auto-inject Version column when update is available
  if (config.smart && version && latestVersion && version !== latestVersion) {
    if (!config.columns.includes("Version")) config.columns.push("Version");
  }

  const show = (id) => config.columns.includes(id);
  const contextPct = getContextPercent(input);
  const modelId = getModelId(input);

  // v9.6.0: Read progress for active agent display
  const progress = readProgress();
  const runningAgent = activeAgentName(progress);

  // v9.7.0: Effort level from stdin (CC v2.1.33+)
  const effort = input?.effort_level ?? null;
  const effortSymbol = effort ? { high: "\u25CF", medium: "\u25D0", low: "\u25CB" }[effort] || "" : "";

  // Column factory — maps column IDs to their rendered {label, value}
  const lbl = (id) => `${C.slate800bold}${id}:${C.reset}`;
  const columnFactory = {
    "Octo": () => {
      let val = `${C.cyan}\u{1F419}${C.reset}`;
      if (OCTO_VERSION) val += ` ${C.slate600}v${OCTO_VERSION}${C.reset}`;
      if (effortSymbol) val += ` ${C.slate600}${effortSymbol}${C.reset}`;
      if (config.preset) val += ` ${C.dim}[${config.preset.substring(0, 3)}]${C.reset}`;
      return { label: lbl("Octo"), value: val };
    },
    "Model": () => ({ label: lbl("Model"), value: `${C.slate600}\u25CF ${modelId}${C.reset}` }),
    "5h Usage": () => {
      if (!usage) return { label: lbl("5h Usage"), value: `${C.slate600}N/A${C.reset}` };
      const color = colorForPercent(usage.fiveHour, 60, 80);
      const reset = formatResetTime(usage.fiveHourResets);
      return { label: lbl("5h Usage"), value: `${color}${Math.round(usage.fiveHour)}%${C.reset}${reset ? ` ${reset}` : ""}` };
    },
    "7d Usage": () => {
      if (!usage) return { label: lbl("7d Usage"), value: `${C.slate600}N/A${C.reset}` };
      const color = colorForPercent(usage.sevenDay, 60, 80);
      const reset = formatResetTime(usage.sevenDayResets);
      return { label: lbl("7d Usage"), value: `${color}${Math.round(usage.sevenDay)}%${C.reset}${reset ? ` ${reset}` : ""}` };
    },
    "Context": () => {
      let warnPrefix = "";
      if (contextPct >= 90) warnPrefix = `\u{1F480} `;
      else if (contextPct >= 80) warnPrefix = `\u26A0\uFE0F `;
      return { label: lbl("Context"), value: `${warnPrefix}${contextBar(contextPct)}` };
    },
    "Cost": () => {
      const usd = cost?.total_cost_usd ?? 0;
      const added = cost?.total_lines_added ?? 0;
      const removed = cost?.total_lines_removed ?? 0;
      const costColor = usd >= 1 ? C.red : usd >= 0.25 ? C.yellow : C.green;
      let val = `${costColor}$${usd.toFixed(2)}${C.reset}`;
      if (added || removed) val += ` ${C.green}+${added}${C.reset}/${C.red}-${removed}${C.reset}`;
      return { label: lbl("Cost"), value: val };
    },
    "Cache": () => {
      const pct = cacheHitRate(input);
      if (pct !== null) {
        const color = pct >= 50 ? C.green : pct >= 20 ? C.yellow : C.slate600;
        return { label: lbl("Cache"), value: `${color}${pct}%${C.reset} ${C.slate600}hit${C.reset}` };
      }
      return { label: lbl("Cache"), value: `${C.slate600}N/A${C.reset}` };
    },
    "Session": () => {
      const durationMs = cost?.total_duration_ms ?? 0;
      return { label: lbl("Session"), value: `${C.slate600}${durationMs > 0 ? formatDuration(durationMs) : "N/A"}${C.reset}` };
    },
    "Changes": () => {
      const added = cost?.total_lines_added ?? 0;
      const removed = cost?.total_lines_removed ?? 0;
      const val = (added || removed)
        ? `${C.green}+${added}${C.reset}${C.slate600}/${C.reset}${C.red}-${removed}${C.reset}`
        : `${C.slate600}+0/-0${C.reset}`;
      return { label: lbl("Changes"), value: val };
    },
    "Tokens": () => {
      const cu = input?.context_window?.current_usage;
      const total = (cu?.input_tokens ?? 0) + (cu?.cache_creation_input_tokens ?? 0) + (cu?.cache_read_input_tokens ?? 0);
      return { label: lbl("Tokens"), value: `${C.slate600}${formatTokens(total)}${C.reset}` };
    },
    "Output Tokens": () => {
      const outTokens = input?.context_window?.total_output_tokens ?? 0;
      return { label: lbl("Out Tokens"), value: `${C.slate600}${formatTokens(outTokens)}${C.reset}` };
    },
    "API Time": () => {
      const apiMs = cost?.total_api_duration_ms ?? 0;
      return { label: lbl("API Time"), value: `${C.slate600}${apiMs > 0 ? formatDuration(apiMs) : "N/A"}${C.reset}` };
    },
    "Version": () => {
      const displayVersion = version || latestVersion;
      if (!displayVersion) return { label: lbl("Version"), value: `${C.slate600}N/A${C.reset}` };
      const dot = (version && latestVersion && version !== latestVersion)
        ? `${C.yellow}\u25CF${C.reset}` : `${C.green}\u25CF${C.reset}`;
      return { label: lbl("Version"), value: `${dot} ${C.slate600}v${displayVersion}${C.reset}` };
    },
    "5h Reset": () => {
      const val = usage?.fiveHourResets ? formatResetTime(usage.fiveHourResets) : "";
      return { label: lbl("5h Reset"), value: val || `${C.slate600}N/A${C.reset}` };
    },
    "7d Reset": () => {
      const val = usage?.sevenDayResets ? formatResetTime(usage.sevenDayResets) : "";
      return { label: lbl("7d Reset"), value: val || `${C.slate600}N/A${C.reset}` };
    },
    "RTK": () => {
      const gain = getRtkGain();
      if (!gain) return { label: lbl("RTK"), value: `${C.slate600}N/A${C.reset}` };
      const saved = formatTokens(gain.totalSaved);
      const pct = gain.avgSavingsPct;
      const color = pct >= 50 ? C.green : pct >= 20 ? C.yellow : C.slate600;
      return { label: lbl("RTK"), value: `${color}${saved}${C.reset} ${C.slate600}(${Math.round(pct)}%)${C.reset}` };
    },
    "Saved": () => {
      // v9.20.0: Read compression analytics for current session
      const analyticsPath = join(HOME, ".claude-octopus", "analytics", "compression.jsonl");
      try {
        if (!existsSync(analyticsPath)) return { label: lbl("Saved"), value: `${C.slate600}0${C.reset}` };
        const lines = readFileSync(analyticsPath, "utf-8").trim().split("\n").filter(Boolean);
        const sessionId = process.env.CLAUDE_SESSION_ID || "";
        let totalSaved = 0, events = 0;
        for (const line of lines) {
          try {
            const e = JSON.parse(line);
            if (sessionId && e.session !== sessionId) continue;
            totalSaved += e.saved || 0;
            events++;
          } catch { /* skip malformed */ }
        }
        if (events === 0) return { label: lbl("Saved"), value: `${C.slate600}0${C.reset}` };
        const formatted = totalSaved >= 1000 ? `${(totalSaved / 1000).toFixed(1)}k` : `${totalSaved}`;
        const color = totalSaved >= 5000 ? C.green : totalSaved >= 1000 ? C.yellow : C.slate600;
        return { label: lbl("Saved"), value: `${color}~${formatted}${C.reset} ${C.slate600}(${events})${C.reset}` };
      } catch {
        return { label: lbl("Saved"), value: `${C.slate600}0${C.reset}` };
      }
    },
  };

  // Build columns in config order (respects smart mode ordering)
  const columns = [];
  for (const id of config.columns) {
    const factory = columnFactory[id];
    if (factory) columns.push(factory());
  }

  const layout = config.layout || "vertical";
  const blankLine = `\n${C.reset}\u200B`;

  // Octopus workflow state
  const isActive = session && session.current_phase && session.current_phase !== "complete";

  let output;

  if (layout === "horizontal") {
    const hParts = [];
    if (isActive) {
      const phase = session.current_phase;
      const emoji = PHASE_EMOJI[phase] || "\u{1F419}";
      hParts.push(`${C.cyan}[\u{1F419}]${C.reset} ${emoji} ${phase}`);
    }
    for (const col of columns) {
      hParts.push(`${col.label} ${col.value}`);
    }
    output = C.reset + hParts.join(` ${pipe} `) + C.reset;
  } else {
    const colWidths = columns.map((col) => {
      const labelLen = stripAnsi(col.label).length;
      const valueLen = stripAnsi(col.value).length;
      return Math.max(labelLen, valueLen);
    });
    const labelRow = C.reset + columns.map((col, i) => padAnsi(col.label, colWidths[i])).join(` ${pipe} `) + C.reset;
    const valueRow = C.reset + columns.map((col, i) => padAnsi(col.value, colWidths[i])).join(` ${pipe} `) + C.reset;
    output = labelRow + "\n" + valueRow;
  }

  // Octopus workflow row (only during active workflows)
  if (isActive) {
    const phase = session.current_phase;
    const emoji = PHASE_EMOJI[phase] || "\u{1F419}";
    const completed = session.completed_phases || 0;
    const total = session.total_phases || 4;
    const providers = providerIndicators();
    const qg = qualityGate(session);
    const agents = agentInfo(session);

    const octoParts = [];
    octoParts.push(`${C.cyan}[\u{1F419} Octopus]${C.reset}`);
    octoParts.push(`${emoji} ${phase} ${C.dim}${completed}/${total}${C.reset}`);
    octoParts.push(providers);
    if (qg) octoParts.push(`QG: ${qg}`);
    const costSeg = costProjection(session, cost);
    if (costSeg) octoParts.push(`\u{1F4B0} ${costSeg}`);
    if (agents) {
      const agentSeg = runningAgent ? `Agents: ${agents} (${runningAgent})` : `Agents: ${agents}`;
      octoParts.push(agentSeg);
    }

    output += blankLine + "\n" + C.reset + octoParts.join(` ${pipe} `);
  } else {
    // v9.6.0: Show project task when no workflow active
    const projectTask = readProjectState();
    if (projectTask) {
      output += blankLine + "\n" + C.reset + `${C.cyan}[\u{1F419}]${C.reset} ${C.bold}"${projectTask}"${C.reset}`;
    }
  }

  // Agent/todo info row (from transcript)
  const line3 = [];
  const running = transcript.agents.filter((a) => a.status === "running");

  if (running.length > 0) {
    line3.push(`${C.slate800bold}Agents:${C.reset} ${C.cyan}${running.length}${C.reset}`);
  }

  const agentName = input?.agent?.name;
  if (agentName) {
    line3.push(`${C.slate800bold}Agent:${C.reset} ${C.magenta}${agentName}${C.reset}`);
  }

  // v9.10.2: Enhanced todo progress — show active task text, not just count
  if (transcript.todos.length > 0) {
    const done = transcript.todos.filter((t) => t.status === "completed").length;
    const total = transcript.todos.length;
    const todoColor = done === total ? C.green : C.yellow;
    const activeTodo = transcript.todos.find((t) => t.status !== "completed");
    const todoText = activeTodo ? activeTodo.content.substring(0, 35) : "All done";
    line3.push(`${todoColor}\u25B8${C.reset} ${C.slate600}${todoText}${C.reset} ${todoColor}(${done}/${total})${C.reset}`);
  }

  // v9.10.2: Tool activity tracking — show active + completed counts
  const toolCounts = transcript.tools?.counts || {};
  const activeTool = transcript.tools?.active;
  const toolParts = [];
  if (activeTool) {
    toolParts.push(`${C.yellow}\u25D0${C.reset} ${C.white}${activeTool.name}${C.reset}${activeTool.target ? `: ${C.slate600}${activeTool.target}${C.reset}` : ""}`);
  }
  for (const [name, count] of Object.entries(toolCounts)) {
    if (count > 0 && (!activeTool || activeTool.name !== name)) {
      toolParts.push(`${C.green}\u2713${C.reset} ${C.dim}${name} \u00D7${count}${C.reset}`);
    }
  }
  if (toolParts.length > 0) {
    line3.push(toolParts.join(` ${C.slate800}\u2502${C.reset} `));
  }

  if (line3.length > 0) {
    output += blankLine + "\n" + C.reset + line3.join(` ${pipe} `);
  }

  // Agent detail tree
  if (running.length > 0) {
    const agentLines = [];
    const showCount = Math.min(running.length, 5);
    for (let i = 0; i < showCount; i++) {
      const a = running[i];
      const isLast = i === showCount - 1;
      const prefix = isLast ? "\u2514\u2500" : "\u251C\u2500";
      const elapsed = formatDuration(Date.now() - a.startTime.getTime());
      const type = (a.type || "agent").substring(0, 14);
      const desc = (a.description || "").substring(0, 45);
      const modelLabel = a.model === "opus" ? `${C.magenta}Opus${C.reset}`
        : a.model === "haiku" ? `${C.green}Haiku${C.reset}`
        : `${C.cyan}Sonnet${C.reset}`;
      agentLines.push(`${C.reset}${C.slate800}${prefix}${C.reset} ${C.white}${type}${C.reset} ${modelLabel} ${C.slate600}${elapsed.padStart(5)}${C.reset}   ${C.slate600}${desc}${C.reset}`);
    }
    output += "\n" + agentLines.join("\n");
  }

  return (output + blankLine + "\n").replace(/ /g, "\u00A0");
}

// ── Section J: Main ──────────────────────────────────────────────────────────

async function main() {
  const input = await readStdin();
  if (!input) {
    process.exit(0);
  }

  const session = readSession();
  writeContextBridge(input);

  const [usage, transcript, latestVersion] = await Promise.all([
    getUsage(input.rate_limits),
    parseTranscript(input.transcript_path),
    getLatestVersion(),
  ]);

  const config = readConfig(input, usage);
  process.stdout.write(render(input, session, usage, transcript, latestVersion, config) + "\n");
}

main().catch(() => process.exit(0));
