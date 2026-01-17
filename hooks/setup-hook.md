---
event: Setup
description: Auto-initialize Claude Octopus workspace and verify providers on --init
---

# Setup Hook (Claude Code v2.1.10)

This hook runs automatically when Claude Code is started with `--init`, `--init-only`, or `--maintenance` flags.

## What It Does

1. Creates session-aware workspace directories
2. Verifies provider availability (Codex/Gemini)
3. Validates Claude Code version compatibility
4. Initializes analytics tracking

## Trigger

Runs on Setup event (v2.1.10 feature):
- `claude --init`
- `claude --init-only`
- `claude --maintenance`

## Implementation

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh init --quiet
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh detect-providers
```

## Output

On successful setup:
```
Claude Octopus workspace initialized
Session: ${CLAUDE_SESSION_ID}
Results: ~/.claude-octopus/results/${CLAUDE_SESSION_ID}/
Plans: ~/.claude-octopus/plans/${CLAUDE_SESSION_ID}/
```

## Workspace Structure

```
~/.claude-octopus/
├── results/
│   └── ${SESSION_ID}/           # Session-specific results
│       ├── .session-id
│       ├── .created-at
│       ├── probe-synthesis-*.md
│       └── ...
├── plans/
│   └── ${SESSION_ID}/           # Session-specific plans
├── logs/
│   └── ${SESSION_ID}/           # Session-specific logs
└── analytics/
    └── agent-usage.csv
```

## Benefits

- Automatic workspace setup on first use
- Provider issues detected early
- Session isolation for cleaner organization
