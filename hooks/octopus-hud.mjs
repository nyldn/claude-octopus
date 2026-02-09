#!/usr/bin/env node
// Claude Octopus Enhanced HUD - METRICC-Inspired Statusline
// Requires Claude Code v2.1.33+ (statusline API with context_window data)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Provides rich statusline with:
//   - Context window usage with color-coded bar
//   - Session cost (auth-mode aware)
//   - Model name + CC version with update check
//   - Active workflow phase with emoji
//   - Provider status indicators
//   - Agent count and todo progress
//   - Quality gate status
//
// Caching: Rate limits cached 60s, version cached 1h
// Fallback: Outputs empty string on error (bash statusline handles it)

import { readFileSync, existsSync, statSync, writeFileSync, mkdirSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';

const HOME = homedir();
const SESSION_FILE = join(HOME, '.claude-octopus', 'session.json');
const CACHE_DIR = join(HOME, '.claude-octopus', '.hud-cache');
const VERSION_CACHE = join(CACHE_DIR, 'version-check.json');

// ANSI colors
const C = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  cyan: '\x1b[36m',
  white: '\x1b[37m',
};

// Phase emoji mapping
const PHASE_EMOJI = {
  probe: '\u{1F50D}',    // magnifying glass
  grasp: '\u{1F3AF}',    // target
  tangle: '\u{1F6E0}',   // wrench (hammer and wrench)
  ink: '\u2705',          // check mark
  complete: '\u{1F419}',  // octopus
  init: '\u{1F419}',
};

// Read stdin synchronously
function readStdin() {
  try {
    const chunks = [];
    const buf = Buffer.alloc(4096);
    let bytesRead;
    try {
      while ((bytesRead = require('fs').readSync(0, buf, 0, buf.length)) > 0) {
        chunks.push(buf.slice(0, bytesRead));
      }
    } catch {
      // EOF or error - that's fine
    }
    return Buffer.concat(chunks).toString('utf8');
  } catch {
    return '';
  }
}

// Parse statusline JSON input from Claude Code
function parseInput(raw) {
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

// Read session.json for Octopus workflow state
function readSession() {
  try {
    if (!existsSync(SESSION_FILE)) return null;
    const stat = statSync(SESSION_FILE);
    // Skip if stale (>30 min old)
    if (Date.now() - stat.mtimeMs > 30 * 60 * 1000) return null;
    return JSON.parse(readFileSync(SESSION_FILE, 'utf8'));
  } catch {
    return null;
  }
}

// Build context window bar with color coding
function contextBar(pct) {
  const width = 10;
  const filled = Math.round((pct / 100) * width);
  const empty = width - filled;
  let color;
  if (pct >= 90) color = C.red;
  else if (pct >= 70) color = C.yellow;
  else color = C.green;

  const bar = '\u2588'.repeat(filled) + '\u2591'.repeat(empty);
  return `${color}${bar}${C.reset} ${pct}%`;
}

// Format cost display (auth-mode aware)
function formatCost(cost) {
  if (cost === null || cost === undefined) return `${C.dim}N/A${C.reset}`;
  if (cost === 0) return `${C.dim}$0.00${C.reset}`;
  return `${C.yellow}$${cost.toFixed(2)}${C.reset}`;
}

// Build provider status indicators from session
function providerIndicators(session) {
  const indicators = [];

  // Check environment for provider availability
  if (process.env.OPENAI_API_KEY || existsSync(join(HOME, '.codex', 'auth.json'))) {
    indicators.push(`${C.red}\u{1F534}${C.reset}`);
  }
  if (process.env.GEMINI_API_KEY || existsSync(join(HOME, '.gemini', 'oauth_creds.json'))) {
    indicators.push(`${C.yellow}\u{1F7E1}${C.reset}`);
  }
  indicators.push(`${C.blue}\u{1F535}${C.reset}`);

  return indicators.join('');
}

// Extract agent count from session state
function agentInfo(session) {
  if (!session) return '';
  const tasks = session.phase_tasks;
  if (!tasks || !tasks.total) return '';
  return `${C.dim}${tasks.completed}/${tasks.total}${C.reset}`;
}

// Build quality gate indicator
function qualityGate(session) {
  if (!session || !session.quality_gates) return '';
  const gates = session.quality_gates;
  if (gates.passed) return `${C.green}\u2713${C.reset}`;
  if (gates.failed) return `${C.red}\u2717${C.reset}`;
  return '';
}

// Build the complete statusline
function buildStatusline(input, session) {
  const segments = [];

  // Model + version
  const model = input?.model?.display_name || 'Claude';
  const version = input?.version || '';

  // Context window
  const pct = Math.round(input?.context_window?.used_percentage || 0);

  // Cost
  const cost = input?.cost?.total_cost_usd ?? null;

  // Octopus workflow state
  const isActive = session && session.current_phase && session.current_phase !== 'complete';

  if (isActive) {
    const phase = session.current_phase;
    const emoji = PHASE_EMOJI[phase] || '\u{1F419}';
    const completed = session.completed_phases || 0;
    const total = session.total_phases || 4;

    segments.push(`${C.cyan}[\u{1F419}]${C.reset}`);
    segments.push(`${emoji} ${phase}`);
    segments.push(`${C.dim}${completed}/${total}${C.reset}`);

    // Provider indicators
    segments.push(providerIndicators(session));

    // Agent progress
    const agents = agentInfo(session);
    if (agents) segments.push(`agents:${agents}`);

    // Quality gate
    const qg = qualityGate(session);
    if (qg) segments.push(`QG:${qg}`);
  } else {
    segments.push(`${C.cyan}[\u{1F419}]${C.reset}`);
  }

  // Context bar
  segments.push(contextBar(pct));

  // Cost
  segments.push(formatCost(cost));

  // Model (compact)
  const shortModel = model.replace('Claude ', '').replace('Sonnet ', 'S').replace('Opus ', 'O');
  segments.push(`${C.dim}${shortModel}${C.reset}`);

  return segments.join(' | ');
}

// Main execution
function main() {
  try {
    const raw = readStdin();
    if (!raw.trim()) {
      process.exit(0);
    }

    const input = parseInput(raw);
    if (!input) {
      // Output empty string on parse failure (bash fallback handles it)
      process.exit(0);
    }

    const session = readSession();
    const statusline = buildStatusline(input, session);

    process.stdout.write(statusline + '\n');
  } catch {
    // Silent failure - bash fallback handles display
    process.exit(0);
  }
}

main();
