#!/bin/bash
# Claude Octopus Sysadmin Safety Gate Hook
# PostToolUse hook for openclaw-admin persona
# Blocks destructive system commands without explicit confirmation patterns
# Returns JSON decision: {"decision": "continue|block", "reason": "..."}
set -euo pipefail

# Read tool output from stdin
INPUT=$(cat 2>/dev/null || echo '{}')

# Get tool name from hook input
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

# Only gate Bash commands
if [[ "$TOOL_NAME" != "Bash" ]]; then
    echo '{"decision": "continue"}'
    exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

# If no command, continue
if [[ -z "$COMMAND" ]]; then
    echo '{"decision": "continue"}'
    exit 0
fi

# Block destructive system commands
# 1. rm -rf on system paths
if echo "$COMMAND" | grep -qE 'rm\s+-[a-zA-Z]*r[a-zA-Z]*f.*(/(etc|var|usr|boot|sys|proc|home)|~|\$HOME)'; then
    echo '{"decision": "block", "reason": "Sysadmin safety gate: destructive rm -rf on system path blocked"}'
    exit 0
fi

# 2. Exposing OpenClaw gateway port to public internet
if echo "$COMMAND" | grep -qE '(ufw\s+allow|iptables.*ACCEPT|--publish|security-list.*18789).*18789'; then
    echo '{"decision": "block", "reason": "Sysadmin safety gate: exposing OpenClaw gateway port 18789 to public internet is unsafe — use Tailscale or VPN instead"}'
    exit 0
fi

# 3. docker compose down -v (destroys volumes)
if echo "$COMMAND" | grep -qE 'docker\s+compose\s+down\s+-v'; then
    echo '{"decision": "block", "reason": "Sysadmin safety gate: docker compose down -v destroys all volumes and data — remove -v flag or backup first"}'
    exit 0
fi

# 4. Disabling firewall entirely
if echo "$COMMAND" | grep -qE '(ufw\s+disable|pfctl\s+-d|systemctl\s+stop\s+(ufw|firewalld|nftables))'; then
    echo '{"decision": "block", "reason": "Sysadmin safety gate: disabling firewall entirely is unsafe — modify rules instead"}'
    exit 0
fi

# 5. Dropping all iptables rules
if echo "$COMMAND" | grep -qE 'iptables\s+-F'; then
    echo '{"decision": "block", "reason": "Sysadmin safety gate: flushing all iptables rules removes firewall protection"}'
    exit 0
fi

# 6. Running unverified install scripts as root
if echo "$COMMAND" | grep -qE 'curl.*\|\s*sudo\s+(ba)?sh'; then
    echo '{"decision": "block", "reason": "Sysadmin safety gate: piping curl to sudo sh is dangerous — download and inspect the script first"}'
    exit 0
fi

# 7. Destroying Proxmox VMs/containers without confirmation keyword
if echo "$COMMAND" | grep -qE '(qm|pct)\s+destroy'; then
    echo '{"decision": "block", "reason": "Sysadmin safety gate: VM/container destruction requires explicit user confirmation"}'
    exit 0
fi

# All checks passed
echo '{"decision": "continue"}'
exit 0
