---
description: "GitHub-aware work monitor - triages issues, PRs, and CI failures"
---

# Sentinel (/octo:sentinel)

## MANDATORY COMPLIANCE — DO NOT SKIP

**When the user invokes `/octo:sentinel`, you MUST execute the structured triage workflow below. You are PROHIBITED from:**
- Manually checking GitHub status without running the sentinel pipeline
- Skipping the triage scan and just reading `gh` output directly
- Deciding there's "nothing to triage" without actually running the checks
- Substituting a quick `gh pr list` for the full sentinel workflow

**The user chose `/octo:sentinel` for structured, prioritized triage — not a raw `gh` dump.**

---

**Your first output line MUST be:** `🐙 Octopus Sentinel`

GitHub-aware work monitor that triages issues, PRs, and CI failures. Sentinel observes and recommends workflows but never auto-executes them.

## Usage

```bash
/octo:sentinel              # One-time triage scan
/octo:sentinel --watch       # Continuous monitoring
/octo:sentinel --canary      # Post-deploy canary monitoring
/octo:sentinel --canary URL  # Monitor specific URL after deploy
```

## What Sentinel Monitors

| Source | Filter | Recommended Action |
|--------|--------|--------------------|
| Issues | `octopus` label | Classified via task type → workflow recommendation |
| PRs | Review requested | `/octo:ink` for code review |
| CI Runs | Failed status | `/octo:debug` for investigation |
| Deployments | Post-deploy health | Canary alerts → `/octo:debug` |

## Canary Mode (Post-Deploy Monitoring — Auto-Triggered)

**Auto-trigger:** Canary runs automatically when:
- The `/octo:deliver` phase completes successfully (post-validation health check)
- Sentinel `--watch` mode detects a new deployment via `gh api` (deployment event)
- The user runs `git push` to a branch with an active Vercel/Netlify/Railway deployment

No manual `--canary` flag needed — sentinel detects deployments and starts monitoring.

When invoked explicitly with `--canary`, or auto-triggered, sentinel switches to **post-deploy health monitoring**:

1. **Detect deployment** — reads the latest Vercel/GitHub deployment or uses the URL argument
2. **Baseline capture** — screenshots + console output + performance timing from pre-deploy (or first run)
3. **Health checks** (runs every 60s for 5 minutes, then every 5 minutes):
   - Page loads without errors (HTTP 200, no uncaught exceptions)
   - Console error detection (new errors not in baseline)
   - Core Web Vitals regression (LCP, CLS, FID compared to baseline)
   - Key UI elements render (checks for empty/broken layouts)
4. **Alert on anomalies** — if any check fails, sentinel reports:
   ```
   🐙 Sentinel Canary Alert
   ⚠ [anomaly type]: [description]
   Baseline: [expected]  |  Current: [observed]
   Recommendation: /octo:debug "[anomaly description]"
   ```
5. **Results** — written to `.octo/sentinel/canary-<timestamp>.md`

**Implementation:** Canary uses the Bash tool with `curl` for HTTP checks, and optionally the browser MCP (Playwright or Chrome DevTools) for screenshot comparison and console monitoring if available. Falls back to `curl`-only health checks when no browser tool is configured.

```bash
# Canary health check sequence
DEPLOY_URL="${1:-$(gh api repos/:owner/:repo/deployments --jq '.[0].payload.web_url // .[0].environment' 2>/dev/null)}"

# HTTP health
STATUS=$(curl -sf -o /dev/null -w '%{http_code}' "$DEPLOY_URL" 2>/dev/null)
LOAD_TIME=$(curl -sf -o /dev/null -w '%{time_total}' "$DEPLOY_URL" 2>/dev/null)

# Compare against baseline
BASELINE_FILE=".octo/sentinel/canary-baseline.json"
if [[ -f "$BASELINE_FILE" ]]; then
  BASELINE_TIME=$(jq -r '.load_time' "$BASELINE_FILE")
  # Flag if >50% slower than baseline
  if (( $(echo "$LOAD_TIME > $BASELINE_TIME * 1.5" | bc -l 2>/dev/null) )); then
    echo "REGRESSION: Load time ${LOAD_TIME}s vs baseline ${BASELINE_TIME}s"
  fi
fi
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OCTOPUS_SENTINEL_ENABLED` | `false` | Must be `true` to activate |
| `OCTOPUS_SENTINEL_INTERVAL` | `600` | Poll interval for --watch mode (seconds) |
| `OCTOPUS_CANARY_DURATION` | `300` | How long canary monitors (seconds, default 5 min) |
| `OCTOPUS_CANARY_INTERVAL` | `60` | Check interval during canary (seconds) |

## Safety

Sentinel is **triage-only**. It:
- Reads GitHub state (issues, PRs, CI runs)
- Monitors deploy health (canary mode)
- Classifies and recommends workflows
- Writes findings to `.octo/sentinel/triage-log.md`
- **Never** auto-executes any workflow

## Requirements

- GitHub CLI (`gh`) must be installed and authenticated
- Repository must be a GitHub repository

## EXECUTION CONTRACT (Mandatory)

When the user invokes `/octo:sentinel`, you MUST:

### 1. Check Prerequisites
- Verify `OCTOPUS_SENTINEL_ENABLED=true` is set
- Verify `gh` CLI is available

### 2. Execute Sentinel
```bash
OCTOPUS_SENTINEL_ENABLED=true bash scripts/orchestrate.sh sentinel $ARGUMENTS
```

### 3. Fire Reaction Engine (v8.45.0)
After triage, run the reaction engine to auto-respond to detected events:
```bash
# Check all active agents and fire reactions
REACTIONS="${HOME}/.claude-octopus/plugin/scripts/reactions.sh"
if [[ -x "$REACTIONS" ]]; then
  "$REACTIONS" check-all
fi
```

This automatically forwards CI failure logs to agents, forwards review comments, and escalates stuck agents — without requiring any new user commands.

### 4. Present Results
- Show triaged items with recommended workflows
- Show any reactions that fired (CI log forwarding, escalations)
- Display path to triage log
- If --watch mode, explain how to stop (Ctrl+C)
