---
name: skill-opencli-desktop
version: 1.0.0
description: Desktop application control via OpenCLI Browser Bridge — screenshots, tab management, and app interaction. Use when: AUTOMATICALLY ACTIVATE when user needs desktop interaction:. "take a screenshot" or "open Chrome tab" or "switch to app". "control desktop" or "browser automation" or "screen capture"
---

# OpenCLI Desktop Control

## The Iron Law

```
VERIFY BROWSER BRIDGE IS RUNNING. CONFIRM APP TARGET. NEVER EXECUTE DESTRUCTIVE ACTIONS WITHOUT CONFIRMATION.
```

Never assume Browser Bridge is connected. Always verify the target application exists. Always confirm before destructive operations (closing tabs, clearing data).

---

## ⚠️ EXECUTION CONTRACT (MANDATORY)

Before executing ANY desktop action, you MUST complete these blocking steps:

### STEP 1: Verify Browser Bridge (BLOCKING)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/opencli-bridge.sh status
# Verify "browser_bridge": "connected" in output
```

**If Browser Bridge not connected → STOP.** Tell user to install Chrome extension and launch Chrome.

### STEP 2: Confirm Destructive Actions (BLOCKING)

For any action that closes, clears, or terminates:
- **ALWAYS ask user for explicit confirmation before executing**
- Show what will be affected
- Never auto-execute destructive operations

### STEP 3: Execute Action

Only proceed after Steps 1-2 pass.

---

## When to Use

**Use this skill for:**
- Taking screenshots of desktop applications
- Managing Chrome tabs (list, open, close, switch)
- Capturing rendered web page content (JavaScript-heavy SPA)
- Interacting with desktop applications through Browser Bridge
- Visual verification of UI changes

**Do NOT use for:**
- Simple URL fetching (use `skill-opencli-research` with `fetch`)
- Server-side web scraping (use `read_url_content`)
- File system operations (use standard file tools)
- Mobile device interaction (use Mobile MCP tools)

---

## Prerequisites

1. **OpenCLI installed**: `npm install -g @jackwener/opencli`
2. **Browser Bridge extension** installed in Chrome
3. **Chrome running** with Browser Bridge active
4. **OpenCLI daemon running**: `opencli daemon start`

### Setup Verification

```bash
# Full status check
${CLAUDE_PLUGIN_ROOT}/scripts/opencli-bridge.sh status

# Expected output includes:
# "browser_bridge": "connected"
```

---

## Available Desktop Actions

### Screenshot

Capture a screenshot of the current screen or a specific application.

```bash
# Via MCP tool
opencli_desktop(app: "chrome", action: "screenshot")

# Via bridge script
${CLAUDE_PLUGIN_ROOT}/scripts/opencli-bridge.sh desktop chrome screenshot
```

### Tab Management

```bash
# List open tabs
opencli_desktop(app: "chrome", action: "list-tabs")

# Open a new tab
opencli_desktop(app: "chrome", action: "open-tab", args: "https://example.com")

# Switch to a specific tab
opencli_desktop(app: "chrome", action: "switch-tab", args: "3")
```

### Application Interaction

```bash
# Get active window info
opencli_desktop(app: "system", action: "active-window")

# Focus an application
opencli_desktop(app: "vscode", action: "focus")
```

---

## Integration with Octopus Workflows

### Visual Feedback Loop

Combine screenshots with code review for visual verification:

```
1. Make code changes (flow-develop)
2. Take screenshot via OpenCLI (this skill)
3. Analyze visual changes (skill-visual-feedback)
4. Iterate if needed
```

### Research + Desktop

Combine research with desktop exploration for live demos:

```
1. Search for trending topics (skill-opencli-research)
2. Open relevant URLs in Chrome (this skill)
3. Capture and analyze rendered content
4. Include visuals in synthesis report
```

---

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| `Browser Bridge unavailable` | Extension not installed/active | Install .crx from GitHub Releases, enable in Chrome |
| `Chrome not running` | Browser closed | Launch Chrome, wait for Bridge connection |
| `App not found` | Invalid app target | Check app name spelling, ensure app is running |
| `Permission denied` | macOS screen recording permission | System Settings → Privacy → Screen Recording → Chrome |

---

## Security Considerations

- Desktop actions are **local only** — no remote execution
- Screenshots may contain sensitive information — handle with care
- Browser Bridge runs within Chrome's sandbox
- No network transmission of captured data unless explicitly requested
