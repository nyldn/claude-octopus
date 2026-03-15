---
command: claw
description: OpenClaw instance administration — manage hosts across macOS, Ubuntu/Debian, Docker, OCI, and Proxmox
---

# Claw - OpenClaw System Administration

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:claw <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "skill-claw", args: "<user's arguments>")
```

**✗ INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:claw", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `skill-claw` skill. Skills use the `Skill` tool, not `Task`.

---

**Auto-loads the `skill-claw` skill for OpenClaw instance administration.**

## Quick Usage

Just use natural language:
```
"Check if my OpenClaw instance is healthy"
"Update OpenClaw to the latest stable version"
"Set up OpenClaw on my Proxmox server"
"Harden my server security"
"Configure the Telegram channel"
"Set up Tailscale for remote access"
```

## What It Manages

- **Gateway lifecycle**: Start, stop, restart, health checks, daemon install
- **5 platforms**: macOS (launchd), Ubuntu/Debian (systemd), Docker (compose), OCI (ARM), Proxmox (LXC)
- **6 channels**: WhatsApp, Telegram, Discord, Slack, Signal, iMessage
- **Security**: Audit, hardening, firewall, Tailscale, credential management
- **Updates**: Backup, upgrade, rollback, version pinning
- **Monitoring**: Logs, health checks, resource usage, diagnostics

## Methodology

Every action follows:
1. **DETECT** platform — never assume the OS
2. **DIAGNOSE** first — non-destructive checks before changes
3. **EXECUTE** action — platform-specific commands
4. **VERIFY** outcome — confirm the change took effect

## Natural Language Examples

```
"Check my server health"
"Update openclaw to latest"
"Set up tailscale"
"Configure slack channel"
"Harden my server"
"Set up openclaw on docker"
```
