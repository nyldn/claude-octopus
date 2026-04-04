---
command: optimize
description: Token optimization — detect, install RTK, configure hooks, show savings
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

# Token Optimization (/octo:optimize)

**Your first output line MUST be:** `🐙 Octopus Token Optimizer`

Interactive token optimization: detect RTK, offer to install it, configure hooks, show compression savings.

## EXECUTION CONTRACT (Mandatory)

### STEP 1: Detect Current State

Use a SINGLE Bash call to check everything:

```bash
echo "RTK_INSTALLED=$(command -v rtk >/dev/null 2>&1 && echo true || echo false)"
echo "RTK_VERSION=$(rtk --version 2>&1 | head -1 || echo none)"
echo "RTK_HOOK=$(grep -q 'rtk' "${HOME}/.claude/settings.json" 2>/dev/null && echo true || echo false)"
echo "RTK_GAIN=$(rtk gain --json 2>/dev/null | head -1 || echo none)"
echo "COMPRESS_ANALYTICS=$(wc -l < "${HOME}/.claude-octopus/analytics/compression.jsonl" 2>/dev/null || echo 0)"
echo "OCTO_COMPRESS=$(command -v octo-compress >/dev/null 2>&1 && echo true || echo false)"
SESSION="${CLAUDE_SESSION_ID:-unknown}"
BRIDGE="/tmp/octopus-ctx-${SESSION}.json"
echo "CTX_BRIDGE=$(cat "$BRIDGE" 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("used_pct","unknown"))' 2>/dev/null || echo unknown)"
```

### STEP 2: Display Compact Report

```
🐙 Token Optimizer
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RTK:           [Installed vX.Y.Z ✓ / Not installed ✗]
RTK Hook:      [Active ✓ / Not configured ✗]
RTK Savings:   [N tokens (~XX%) / No data yet]
Compressor:    [Active (N events) / Not available]
Context:       [XX% used / Unknown]
```

### STEP 3: Interactive Actions (AskUserQuestion)

Based on the detection results, ask the RIGHT question:

**If RTK is NOT installed:**

```javascript
AskUserQuestion({
  questions: [{
    question: "RTK saves 60-90% on bash output tokens. Install it now?",
    header: "Install RTK",
    multiSelect: false,
    options: [
      {label: "Install via brew", description: "brew install rtk (macOS, recommended)"},
      {label: "Install via cargo", description: "cargo install --git https://github.com/rtk-ai/rtk"},
      {label: "Skip for now", description: "Continue without RTK"}
    ]
  }]
})
```

If user chooses an install option, run the install command, then proceed to hook setup.

**If RTK is installed but hook NOT configured:**

```javascript
AskUserQuestion({
  questions: [{
    question: "RTK is installed but the Claude Code hook isn't active. Configure it?",
    header: "RTK Hook",
    multiSelect: false,
    options: [
      {label: "Run rtk init -g", description: "Auto-installs Claude Code bash hook for automatic compression"},
      {label: "Skip", description: "I'll configure it manually later"}
    ]
  }]
})
```

If user chooses to configure, run `rtk init -g`.

**If RTK is fully configured (installed + hook active):**

```javascript
AskUserQuestion({
  questions: [{
    question: "RTK is fully configured. What would you like to do?",
    header: "Optimize",
    multiSelect: false,
    options: [
      {label: "Show detailed gain stats", description: "Full breakdown by command type"},
      {label: "Show compression analytics", description: "Octopus output-compressor savings"},
      {label: "Token tips", description: "General token optimization tips"},
      {label: "Done", description: "Everything looks good"}
    ]
  }]
})
```

### STEP 4: Execute User's Choice

- **Install via brew**: `brew install rtk` then check version, then offer hook setup
- **Install via cargo**: `cargo install --git https://github.com/rtk-ai/rtk` then check version, then offer hook setup
- **Run rtk init -g**: Execute it, verify hook is in settings.json
- **Show gain stats**: Run `rtk gain` and format output
- **Show compression analytics**: Read `~/.claude-octopus/analytics/compression.jsonl`, summarize per-type
- **Token tips**: Show the tips block below

### Token Tips (when requested or always after install)

```
Token Optimization Tips
━━━━━━━━━━━━━━━━━━━━━━━
- Use Read/Grep/Glob tools instead of cat/grep/find in bash
- Pipe verbose commands: npm install 2>&1 | octo-compress
- Prefer --oneline, --short, --quiet flags on git commands
- For test output: --reporter=dot or | tail -50
- Use offset/limit when reading large files
- Above 70% context: consider /clear or /octo:resume in new session
```

## Validation Gates

- RTK detection attempted
- Interactive choice offered (not just a wall of text)
- Install executed if user consents
- Hook configured if user consents
- Compression analytics shown if available

## Note

This command overlaps with `/octo:doctor` (which reports RTK status) and `/octo:setup` (which configures providers). The difference: `/octo:optimize` is ACTION-oriented — it installs and configures, not just reports. `/octo:doctor` and `/octo:setup` should link here when RTK issues are found.
