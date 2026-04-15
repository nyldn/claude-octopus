---
name: skill-opencli-desktop
version: 1.0.0
description: Desktop control via OpenCLI Browser Bridge: screenshots, tab and app management
trigger:
  - "take a screenshot"
  - "open Chrome tab"
  - "switch to app"
  - "control desktop"
  - "browser automation"
  - "screen capture"
---

# OpenCLI Desktop Control

Desktop application interaction via Browser Bridge for screenshots, tab management, and visual verification.

## Prerequisites

- `npm install -g @jackwener/opencli && opencli setup`
- Chrome Browser Bridge extension (from GitHub Releases)
- Chrome running with extension active
- macOS: Screen Recording permission for Chrome

## MCP Tool

```
opencli_desktop(app: "chrome", command: "screenshot")
opencli_desktop(app: "chrome", command: "list-tabs")
opencli_desktop(app: "chrome", command: "open-tab", args: ["https://example.com"])
opencli_desktop(app: "chrome", command: "switch-tab", args: ["3"])
opencli_desktop(app: "system", command: "active-window")
```

## Use Cases

1. **Visual Verification** — Screenshot after code changes to confirm UI
2. **Tab Management** — Open/close/switch Chrome tabs programmatically
3. **Content Capture** — Grab rendered content from JS-heavy SPAs
4. **Workflow Automation** — Chain desktop actions for testing

## Integration with Workflows

- Combine with `skill-visual-feedback` for UI review loops
- Combine with `skill-opencli-research` for live URL exploration
- Use in `flow-deliver` for visual regression checking

## Safety

- **NEVER close tabs, clear data, or terminate apps without asking user confirmation first**
- Always verify target app exists before interacting
- Verify Browser Bridge is connected before any desktop action

## Error Recovery

| Error | Fix |
|-------|-----|
| `Browser Bridge unavailable` | Install .crx from GitHub Releases |
| `Chrome not running` | Launch Chrome, wait for Bridge |
| `Permission denied` | macOS: Settings → Privacy → Screen Recording → Chrome |

## Security

- Local-only execution, no remote access
- Screenshots may contain sensitive data — handle carefully
- Runs within Chrome sandbox
