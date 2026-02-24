---
name: skill-claw
aliases:
  - claw
  - openclaw-admin
  - sysadmin
description: "OpenClaw instance administration — manage hosts across macOS, Ubuntu/Debian, Docker, OCI, and Proxmox"
trigger: |
  AUTOMATICALLY ACTIVATE when user asks about:
  - "manage openclaw" or "openclaw status" or "openclaw health"
  - "update openclaw" or "upgrade openclaw" or "openclaw doctor"
  - "setup openclaw" or "install openclaw" or "deploy openclaw"
  - "openclaw gateway" or "openclaw channels" or "openclaw security"
  - "manage my server" or "sysadmin" or "server health"
  - "proxmox" or "lxc" or "oracle cloud" or "oci instance"
  - "harden my server" or "secure my host" or "firewall setup"
  - "openclaw on docker" or "openclaw compose"
  - "openclaw backup" or "openclaw restore" or "openclaw migrate"

  DO NOT activate for:
  - OpenClaw extension development (use plugin-dev skills)
  - Cloud architecture design from scratch (use /octo:develop with cloud-architect)
  - CI/CD pipeline design (use /octo:develop with deployment-engineer)
  - Application debugging unrelated to infrastructure (use /octo:debug)
  - Kubernetes orchestration (use devops-troubleshooter persona)
execution_mode: enforced
pre_execution_contract:
  - platform_detected
  - visual_indicators_displayed
validation_gates:
  - diagnostic_commands_executed
  - outcome_verified
---

# OpenClaw Instance Administration

## The Iron Law

```
DETECT PLATFORM FIRST. DIAGNOSE BEFORE CHANGING. VERIFY AFTER EVERY ACTION.
```

Never assume the OS or hosting environment. Never make changes without checking current state. Never claim success without verification.

---

## When to Use

**Use this skill for:**
- Installing, updating, or migrating OpenClaw instances
- Gateway lifecycle management (start, stop, restart, health checks)
- Host-level administration (packages, services, firewall, users, disks)
- Security hardening and audits
- Monitoring setup and troubleshooting
- Backup and disaster recovery
- Platform-specific configuration (macOS, Ubuntu/Debian, Docker, OCI, Proxmox)
- Channel configuration (WhatsApp, Telegram, Discord, Slack, Signal)

**Do NOT use for:**
- Writing OpenClaw extensions or plugins (use plugin-dev skills)
- Designing cloud architecture from scratch (use cloud-architect persona)
- Application-level code debugging (use `/octo:debug`)

---

## The Process

### Phase 1: Detect Platform

**You MUST detect the platform before running any administrative commands.**

```bash
# Detect OS
uname -s  # Darwin = macOS, Linux = Ubuntu/Debian/Proxmox host

# If Linux, detect distro
cat /etc/os-release 2>/dev/null | head -5

# Check if inside Docker
[ -f /.dockerenv ] && echo "Docker container" || echo "Not Docker"

# Check if on Proxmox host
command -v pveversion &>/dev/null && pveversion 2>/dev/null

# Check if inside Proxmox LXC
[ -f /proc/1/environ ] && grep -q container=lxc /proc/1/environ 2>/dev/null && echo "Proxmox LXC"

# Check for OCI metadata
curl -s -m 2 http://169.254.169.254/opc/v2/instance/ -H "Authorization: Bearer Oracle" 2>/dev/null | head -5
```

**Set the platform context** before proceeding:
- **macOS**: Homebrew, launchd, Application Firewall, APFS
- **Ubuntu/Debian**: apt, systemd, ufw, ext4/ZFS
- **Docker**: docker compose, container logs, volume management
- **OCI**: ARM architecture, VCN security, Tailscale, systemd
- **Proxmox**: qm/pct, vzdump, ZFS, LXC bind mounts

---

### Phase 2: Assess Current State

**Run diagnostics appropriate to the platform:**

#### OpenClaw Diagnostics (All Platforms)

```bash
# Check OpenClaw installation
command -v openclaw &>/dev/null && openclaw --version

# Gateway status
openclaw status --all

# Health check
openclaw health

# Doctor (auto-detect and report issues)
openclaw doctor

# Security audit
openclaw security audit
```

#### macOS Host Diagnostics

```bash
# Service status
launchctl list | grep openclaw

# System resources
vm_stat | head -10
df -h /

# Homebrew health
brew doctor 2>&1 | head -20

# Firewall status
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
```

#### Ubuntu/Debian Host Diagnostics

```bash
# Service status
systemctl --user status openclaw-gateway 2>/dev/null || systemctl status openclaw-gateway

# System resources
free -h
df -h /

# Failed services
systemctl --failed

# Firewall status
ufw status verbose

# Pending updates
apt list --upgradable 2>/dev/null | head -20
```

#### Docker Diagnostics

```bash
# Container status
docker compose ps

# Container health
docker inspect --format='{{.State.Health.Status}}' openclaw-gateway 2>/dev/null

# Resource usage
docker stats --no-stream

# Disk usage
docker system df
```

#### Proxmox Diagnostics

```bash
# Proxmox version
pveversion -v

# VM/LXC list
qm list 2>/dev/null
pct list 2>/dev/null

# Storage status
pvesm status

# ZFS health
zpool status 2>/dev/null

# Cluster status
pvecm status 2>/dev/null
```

---

### Phase 3: Execute the Requested Action

Route to the appropriate workflow based on user intent:

#### Installation Workflows

| Platform | Method |
|----------|--------|
| macOS | `curl -fsSL https://openclaw.ai/install.sh \| bash && openclaw onboard --install-daemon` |
| Ubuntu/Debian | `curl -fsSL https://openclaw.ai/install.sh \| bash && openclaw onboard --install-daemon` |
| Docker | `git clone https://github.com/openclaw/openclaw.git && cd openclaw && ./docker-setup.sh` |
| OCI ARM | Install Node.js 22 + build-essential, then curl installer, enable systemd lingering, configure Tailscale |
| Proxmox LXC | Create Ubuntu/Debian LXC, install Node.js 22, curl installer, configure bind mounts for persistence |

#### Service Lifecycle

| Action | macOS | Linux | Docker |
|--------|-------|-------|--------|
| Start | `launchctl start gui/$UID/com.openclaw.gateway` | `systemctl --user start openclaw-gateway` | `docker compose up -d` |
| Stop | `launchctl stop gui/$UID/com.openclaw.gateway` | `systemctl --user stop openclaw-gateway` | `docker compose down` |
| Restart | `openclaw gateway restart` | `openclaw gateway restart` | `docker compose restart` |
| Status | `launchctl list \| grep openclaw` | `systemctl --user status openclaw-gateway` | `docker compose ps` |
| Logs | `openclaw logs --follow` | `journalctl --user -u openclaw-gateway -f` | `docker compose logs -f` |

#### Update Workflow

1. **Backup** config, credentials, and workspace:
   ```bash
   cp -r ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak
   cp -r ~/.openclaw/credentials/ ~/.openclaw/credentials.bak/
   ```
2. **Update** using the appropriate method:
   ```bash
   # Installer (recommended)
   curl -fsSL https://openclaw.ai/install.sh | bash

   # npm
   npm i -g openclaw@latest

   # Docker
   docker compose pull && docker compose up -d
   ```
3. **Verify** the update:
   ```bash
   openclaw --version
   openclaw doctor
   openclaw health
   ```

#### Security Hardening Checklist

1. Gateway binds to loopback only (`127.0.0.1` / `::1`)
2. Token auth enabled — tokens treated as admin credentials
3. Tailscale or VPN for remote access — never expose port 18789
4. Filesystem restrictions: `tools.exec.applyPatch.workspaceOnly: true`, `tools.fs.workspaceOnly: true`
5. Docker sandboxing enabled for agent tool execution
6. DM pairing policy enforced for unknown senders
7. `openclaw security audit --deep --fix` passes clean
8. Credential permissions: `chmod 700 ~/.openclaw/credentials/`
9. Firewall: only required ports open (SSH, Tailscale UDP 41641)
10. Use Anthropic Opus 4.6 as agent model (best prompt injection resistance)

---

### Phase 4: Verify Outcome

**After every action, verify it took effect:**

```bash
# Check gateway is running
openclaw status

# Check health
openclaw health

# Run doctor to catch issues
openclaw doctor

# If security changes were made
openclaw security audit
```

**Report** the before/after state and any remaining issues.

---

## Key File Paths

| Path | Purpose |
|------|---------|
| `~/.openclaw/openclaw.json` | Main configuration (JSON5) |
| `~/.openclaw/credentials/` | API keys and auth tokens |
| `~/.openclaw/workspace/` | Agent workspace data |
| `~/.openclaw/sandboxes/` | Sandbox isolation directories |
| `~/Library/LaunchAgents/com.openclaw.gateway.plist` | macOS launchd service |
| `~/.config/systemd/user/openclaw-gateway.service` | Linux systemd user service |

---

## OpenClaw CLI Quick Reference

```
openclaw status [--all|--deep]         # Health overview
openclaw health                        # Gateway health check
openclaw doctor [--fix]                # Diagnostics + auto-fix
openclaw logs [--follow]               # Gateway logs
openclaw security audit [--deep] [--fix]  # Security scan

openclaw gateway start|stop|restart    # Service lifecycle
openclaw gateway install|uninstall     # Daemon management
openclaw configure                     # Interactive config wizard
openclaw update [--channel ...]        # Self-update

openclaw channels list|status|add|remove  # Messaging channels
openclaw models list|status [--probe]     # AI model config
openclaw agents list|add|delete           # Agent management
openclaw sessions list|history            # Session management
openclaw skills list|info|check           # Skills
openclaw plugins list|install|doctor      # Plugins
openclaw cron status|list|add|edit|rm     # Scheduled jobs
```

---

## Integration with Other Skills

| Scenario | Route |
|----------|-------|
| Infrastructure architecture needed | Hand off to cloud-architect persona |
| Application-level bug found | Hand off to `/octo:debug` |
| Security vulnerability in code | Hand off to `/octo:security` |
| Need CI/CD pipeline for deployment | Hand off to deployment-engineer persona |
| OpenClaw extension development | Hand off to plugin-dev skills |

---

## Red Flags — Don't Do This

| Action | Why It's Wrong |
|--------|----------------|
| Assume the OS without checking | macOS and Linux commands differ significantly |
| Expose port 18789 to the internet | Gateway should only bind to loopback; use Tailscale |
| Run `openclaw security audit --fix` without `--deep` first | Understand the findings before auto-remediating |
| Skip backup before updating | Updates can break config; always back up first |
| Use `docker compose down -v` without warning | Destroys volumes and all data |
| Grant `manage all-resources` in OCI IAM | Violates least-privilege; use scoped policies |
| Run privileged LXC containers on Proxmox | Unprivileged LXC is safer; only privilege if absolutely needed |
