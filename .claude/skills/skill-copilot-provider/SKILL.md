---
name: skill-copilot-provider
version: 2.0.0
aliases: [copilot-provider, github-copilot, copilot]
description: GitHub Copilot CLI as optional zero-cost provider via copilot -p programmatic mode
trigger: |
  AUTOMATICALLY ACTIVATE when user says:
  "copilot provider" or "add copilot" or "github copilot" or "use copilot"
  DO NOT activate for general copilot IDE usage or copilot chat in editor.
paths:
  - "**/.github/copilot*"
  - "**/.copilot*"
---

# GitHub Copilot Provider Skill

## Overview

GitHub Copilot CLI (GA since Feb 2026) serves as an optional provider in the Claude Octopus
multi-LLM ecosystem. Integration uses the official `copilot -p` programmatic mode, not
reverse-engineered API endpoints.

**Core principle:** Copilot supplements existing providers for research and exploration at
zero additional cost (uses existing GitHub Copilot subscription). Each prompt counts as one
premium request against your subscription quota.

**Agent types:** `copilot` (general), `copilot-research` (research-focused)

---

## Detection

```bash
# Check copilot CLI is available
if ! command -v copilot &>/dev/null; then
  # Copilot CLI not installed — silently skip
  return 0
fi
```

**Graceful degradation:** When Copilot CLI is unavailable or unauthenticated, silently skip.
Other providers continue to operate normally.

---

## Authentication

Copilot CLI checks credentials in this precedence order:

1. `COPILOT_GITHUB_TOKEN` env var (highest priority — fine-grained PAT with "Copilot Requests" permission)
2. `GH_TOKEN` env var
3. `GITHUB_TOKEN` env var
4. OAuth token from system keychain (via `copilot login`)
5. GitHub CLI (`gh`) authentication fallback

### Setup

**Option 1: Interactive login (recommended for local dev)**
```bash
copilot login
```

**Option 2: Fine-grained PAT (recommended for CI/automation)**
1. Create a fine-grained PAT at https://github.com/settings/personal-access-tokens/new
2. Enable the "Copilot Requests" permission
3. Set the env var:
```bash
export COPILOT_GITHUB_TOKEN="github_pat_..."
```

**Option 3: Reuse existing `gh` auth**
If `gh auth login` is already configured, Copilot CLI will use it automatically.

**Note:** Classic PATs (`ghp_*`) are NOT supported. Use fine-grained PATs (`github_pat_*`).

---

## Available Roles

| Role | Agent Type | Use Case |
|------|-----------|----------|
| **General** | `copilot` | Broad research, code explanation, exploration |
| **Research** | `copilot-research` | Research-focused exploration and analysis |

### Dispatch

```bash
# Programmatic mode (non-interactive)
copilot -p "<prompt>" --no-ask-user
```

---

## Provider Indicators

When Copilot is active in a multi-provider workflow:

```
Providers:
🔴 Codex CLI - Implementation
🟡 Gemini CLI - Security review
🟢 Copilot CLI - Research perspective
🔵 Claude - Synthesis
```

Indicator legend:
- 🔴 = Codex CLI
- 🟡 = Gemini CLI
- 🟢 = Copilot CLI
- 🟣 = Perplexity
- 🔵 = Claude

---

## Doctor Integration

The `/octo:doctor` providers check reports Copilot availability and auth method:

```
Providers:
  ✓ Copilot CLI installed (auth: keychain)
```

When unauthenticated: `⚠ Copilot CLI installed but not authenticated`
When missing: `ℹ Copilot CLI not installed (optional)`

---

## Integration Notes

1. **Zero additional cost** — Uses existing GitHub Copilot subscription (Pro, Pro+, Business, Enterprise)
2. **Premium request quota** — Each `copilot -p` prompt = 1 premium request from your monthly allowance
3. **Graceful degradation** — When unavailable, silently skip with no errors or warnings
4. **No provider cascade** — If unavailable, the role is reassigned to another provider
5. **Model selection** — Copilot CLI selects the model internally (default: Claude Sonnet 4.5, configurable via `/model`)
6. **Multi-model access** — Copilot subscription includes access to Claude, GPT, and Gemini models

---

## Example Workflows

### Research with Copilot

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 Discover Phase: Researching WebSocket authentication patterns

Providers:
🔴 Codex CLI - Technical implementation analysis
🟡 Gemini CLI - Ecosystem research
🟢 Copilot CLI - Research perspective
🔵 Claude - Strategic synthesis
```

### Copilot Unavailable (Graceful Degradation)

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 Discover Phase: Researching WebSocket authentication patterns

Providers:
🔴 Codex CLI - Technical implementation analysis
🟡 Gemini CLI - Ecosystem research
🔵 Claude - Strategic synthesis
```

When Copilot is not detected, it is silently omitted from the provider list.
