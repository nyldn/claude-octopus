---
command: history
description: Query past workflow results — filter by workflow type, date, or provider
allowed-tools: Bash, Read, Grep
---

# Workflow History (/octo:history)

Query structured records of past Claude Octopus workflow runs.

## EXECUTION CONTRACT (Mandatory)

When the user invokes `/octo:history`, follow these steps in order.

### STEP 1: Locate Run Store

Check for the run store file:

```bash
RUN_STORE="${HOME}/.claude-octopus/runs/run-log.jsonl"
if [[ -f "$RUN_STORE" ]]; then
    TOTAL=$(wc -l < "$RUN_STORE" | tr -d ' ')
    echo "Run store: $TOTAL entries"
else
    echo "No run store found at $RUN_STORE"
    echo ""
    echo "The run store records results from multi-AI workflows:"
    echo "  /octo:discover  - Multi-AI research"
    echo "  /octo:develop   - Multi-AI implementation"
    echo "  /octo:review    - Multi-AI code review"
    echo "  /octo:debate    - Multi-AI deliberation"
    echo "  /octo:embrace   - Full 4-phase lifecycle"
    echo ""
    echo "Run any multi-AI workflow to start recording history."
fi
```

If no run store exists, show the guidance above and stop.

### STEP 2: Parse Arguments

Accept optional arguments for filtering:

| Argument | Effect | Example |
|----------|--------|---------|
| (none) | Show last 10 runs | `/octo:history` |
| `N` (number) | Show last N runs | `/octo:history 20` |
| workflow name | Filter by workflow | `/octo:history discover` |
| date (YYYY-MM-DD) | Filter by date | `/octo:history 2026-03-21` |
| `stats` | Show summary statistics | `/octo:history stats` |
| `experiments` | Show experiment logs | `/octo:history experiments` |

Multiple arguments can be combined: `/octo:history discover 2026-03-21`

### STEP 3: Display Results

For each matching run, display as a table row:

```
Workflow History (last N runs)
═══════════════════════════════════════════════════════════════════
Date         Workflow     Providers           Findings  Status   Duration
─────────────────────────────────────────────────────────────────
2026-03-21   discover     codex,gemini,claude       12  success     45s
2026-03-21   review       codex,gemini,claude        8  success     62s
2026-03-20   develop      codex,claude               3  success    120s
2026-03-20   debate       codex,gemini,claude        —  success     95s
═══════════════════════════════════════════════════════════════════
```

Use the Bash tool to read the JSONL file and format:

```bash
RUN_STORE="${HOME}/.claude-octopus/runs/run-log.jsonl"
# Last 10 runs (default)
tail -10 "$RUN_STORE" | while IFS= read -r line; do
    echo "$line"
done
```

If jq is available, use it for cleaner formatting. If not, use grep + sed.

### STEP 4: Show Experiment Logs (if requested)

When `experiments` argument is passed, check for experiment iteration logs:

```bash
EXPERIMENTS_DIR="${HOME}/.claude-octopus/runs/experiments"
if [[ -d "$EXPERIMENTS_DIR" ]]; then
    ls -la "$EXPERIMENTS_DIR"/*.jsonl 2>/dev/null
else
    echo "No experiment logs found."
fi
```

Display experiment iterations with metric values and status (kept/reverted/error).

### STEP 5: Show Stats (if requested)

When `stats` argument is passed, compute and display:

```
Run Store Statistics
═══════════════════════════════════════════
Total runs:       156
Success rate:     142/156 (91%)
Date range:       2026-03-01 to 2026-03-21
Workflows used:   discover, develop, review, debate, embrace
Most frequent:    discover (48 runs)
═══════════════════════════════════════════
```

## Cost

History uses only local file reads. No external provider costs.
