---
description: "\"[advanced] Show cost breakdown by provider and workflow for the current session\""
allowed-tools: Bash, Read, Glob, Grep
---

# Cost Dashboard (/octo:costs)

**Your first output line MUST be:** `🐙 Octopus Cost Dashboard`

Display a cost breakdown by provider and workflow for the current session (and cumulative history).

## EXECUTION CONTRACT (Mandatory)

When the user invokes `/octo:costs`, you MUST follow these steps in order.

### STEP 1: Locate Usage Data

Search for session usage data in these locations (check all, use whichever exist):

```
~/.claude-octopus/usage/           # Per-session usage logs
~/.claude-octopus/routing.log      # Routing decisions with timestamps
~/.claude-octopus/sessions/        # Session state files
.claude-octopus/                   # Project-local usage data
```

Use the Bash tool to list and read files:

```bash
ls -la ~/.claude-octopus/usage/ 2>/dev/null || echo "No usage directory"
ls -la ~/.claude-octopus/routing.log 2>/dev/null || echo "No routing log"
ls -la ~/.claude-octopus/sessions/ 2>/dev/null || echo "No sessions directory"
ls -la .claude-octopus/ 2>/dev/null || echo "No project-local usage data"
```

### STEP 2: Parse Provider Usage

For each provider found in the usage data, extract:
- **Tokens in** (input/prompt tokens)
- **Tokens out** (output/completion tokens)
- **Query count** (number of invocations)
- **Estimated cost** (calculated from the Cost Reference table below)

### STEP 3: Display Per-Provider Breakdown

Format as a clean ASCII table:

```
Provider Cost Breakdown
============================================================
Provider           Tokens In   Tokens Out   Queries   Est Cost
------------------------------------------------------------
Claude Opus 4.6      45,200       12,800         3     $0.55
Claude Sonnet 4.6   128,000       34,500        12     $0.24
Codex CLI                 -            -         8     $0.64
Gemini CLI                -            -         4     $0.08
Perplexity                -            -         2     $0.06
------------------------------------------------------------
TOTAL                                           29     $1.57
============================================================
```

For providers where only query counts are available (Codex, Gemini, Antigravity, Perplexity), use the midpoint or included-access estimate from the reference table. Show $0.00 for free providers or unused providers.

### STEP 4: Display Per-Workflow Breakdown

Group costs by workflow/command that triggered them:

```
Workflow Cost Breakdown
============================================================
Workflow             Providers Used         Queries   Est Cost
------------------------------------------------------------
/octo:discover       Claude, Codex, Gemini, agy   8     $0.42
/octo:develop        Claude, Codex                 6     $0.35
/octo:review         Claude, Codex, Gemini, agy    9     $0.58
/octo:debate         Claude, Codex, Gemini, agy    6     $0.22
------------------------------------------------------------
TOTAL                                             29     $1.57
============================================================
```

### STEP 5: Display Session vs Cumulative View

Show both the current session totals and cumulative totals (if historical data exists):

```
Session Summary
============================================================
Current Session:   $1.57  (29 queries, started 2h 15m ago)
Cumulative (7d):   $8.42  (156 queries across 12 sessions)
Cumulative (30d): $34.18  (612 queries across 47 sessions)
============================================================
```

If cumulative data is not available, show only the current session.

### STEP 6: Handle No Data

If no usage data exists at all, display:

```
No usage data found.

Claude Octopus tracks provider usage in:
  ~/.claude-octopus/usage/     (per-session logs)
  ~/.claude-octopus/routing.log (routing decisions)

Usage data is recorded automatically when you run workflows like:
  /octo:discover   - Multi-AI research
  /octo:develop    - Multi-AI implementation
  /octo:review     - Multi-AI code review
  /octo:debate     - Multi-AI deliberation
  /octo:embrace    - Full 4-phase lifecycle

Run any multi-AI workflow to start tracking costs.
```

## Cost Reference

These are the current per-provider cost estimates used for calculations:

| Provider | Input | Output | Per-Query Estimate |
|----------|-------|--------|--------------------|
| Claude Opus 4.6 | $5/MTok | $25/MTok | varies by tokens |
| Claude Sonnet 4.6 | $0.80/MTok | $4/MTok | varies by tokens |
| Codex CLI | - | - | ~$0.01-0.15/query |
| Gemini CLI | - | - | ~$0.01-0.03/query |
| Antigravity CLI (`agy`) | - | - | Included with user's Antigravity access/subscription |
| Perplexity | - | - | ~$0.01-0.05/query |

**Notes:**
- Claude Sonnet 4.6 usage is included with Claude Code subscription (no extra cost for most users)
- Claude Opus 4.6 usage is billed at the rates above when using `claude-opus` agent type
- Codex, Gemini, Perplexity, and Antigravity usage are charged to the user's own provider credentials, subscriptions, or local auth
- Fast Opus 4.6 mode ($30/$150 MTok) is 6x standard pricing — flagged separately if detected

## Examples

```
/octo:costs                    # Show current session costs
/octo:costs                    # After running several workflows
```

## Validation Gates

- Usage data locations checked (all four paths)
- Per-provider breakdown displayed with token counts and estimated costs
- Per-workflow breakdown displayed with provider attribution
- Session and cumulative views shown when data is available
- Helpful guidance shown when no data exists
- All costs formatted to 2 decimal places with $ prefix

## Prohibited Actions

- Fabricating usage data that does not exist in the filesystem
- Showing only one view (must attempt both provider and workflow breakdowns)
- Omitting $0.00 entries for available but unused providers
- Rounding costs to whole dollars (always show cents)
