---
name: skill-cost-projections
effort: low
aliases:
  - cost-projections
  - cost-forecast
  - budget-projection
description: "Project remaining workflow cost from per-phase averages — warns on budget ceiling overruns"
trigger: |
  AUTOMATICALLY ACTIVATE when user asks about workflow costs:
  - "cost projection", "estimate remaining cost"
  - "budget forecast", "how much will this cost"
  - "project cost", "cost estimate", "spending forecast"
  - "what's the cost so far", "am I over budget"

  DO NOT activate for:
  - General pricing questions about API models
  - One-time cost lookups unrelated to a running workflow
  - Provider availability or configuration questions
paths:
  - "**/.claude-octopus/**"
  - "**/analytics/**"
---

# Cost Projections Skill

## Overview

Projects remaining workflow cost based on per-phase averages from completed work. Displays cost data in the HUD/statusline and warns when projected totals exceed a configured budget ceiling.

**Minimum data requirement:** Needs **2+ completed steps** before projecting. With fewer than 2 data points, the average is unreliable — display actual spend only and skip projection.

---

## Step 1: Collect Completed Phase Costs

Read cost data from `~/.claude-octopus/metrics/` or from metrics-tracker.sh output. Each completed phase/step should have an associated cost entry.

```bash
# Read metrics from the session metrics directory
METRICS_DIR="$HOME/.claude-octopus/metrics"
SESSION_METRICS="$METRICS_DIR/session-$(date +%Y%m%d).jsonl"

# Each line contains: {"phase": "discover", "cost": 0.42, "tokens_in": 12000, "tokens_out": 3400, "timestamp": "..."}
# Sum costs from completed steps
completed_costs=$(jq -s '[.[].cost]' "$SESSION_METRICS")
completed_count=$(jq -s 'length' "$SESSION_METRICS")
total_spent=$(jq -s '[.[].cost] | add' "$SESSION_METRICS")
```

**Data sources (in priority order):**
1. `~/.claude-octopus/metrics/session-*.jsonl` — structured per-phase cost entries
2. `metrics-tracker.sh` output — fallback for legacy sessions
3. HUD accumulated cost counters — last resort

If fewer than 2 completed steps are available, display only actual spend:
```
💰 Spent: $0.42 (1 step complete — need 2+ for projection)
```

---

## Step 2: Compute Average Cost Per Step

Calculate the mean cost across all completed steps.

```bash
avg_cost=$(echo "$total_spent / $completed_count" | bc -l)
```

**Formula:**
```
avg_cost = total_cost / completed_steps
```

**Example:** If 3 steps cost $0.30, $0.50, $0.40 → avg = $1.20 / 3 = $0.40/step

---

## Step 3: Project Remaining Cost

Multiply the average cost per step by the number of remaining steps.

```bash
remaining_steps=$((total_steps - completed_count))
projected_remaining=$(echo "$avg_cost * $remaining_steps" | bc -l)
projected_total=$(echo "$total_spent + $projected_remaining" | bc -l)
```

**Formula:**
```
projected_remaining = avg_cost × remaining_steps
projected_total     = total_spent + projected_remaining
```

**Step counts by workflow type:**
| Workflow | Total Steps | Example Phases |
|----------|-------------|----------------|
| embrace  | 4           | Discover, Define, Develop, Deliver |
| research | 3-7         | Per-agent probe count |
| review   | 3           | Fleet, Verifier, Synthesis |
| debate   | 3           | Opening, Rebuttal, Synthesis |

---

## Step 4: Display in HUD

Format the cost projection for the HUD/statusline display.

**Standard display:**
```
💰 Spent: $2.40 | Est. remaining: $3.60 | Total: ~$6.00
```

**Format rules:**
- All dollar amounts to 2 decimal places
- Projected total prefixed with `~` to indicate estimate
- Use `💰` prefix for the cost line
- Show in a single compact line for statusline integration

**When insufficient data (< 2 steps):**
```
💰 Spent: $0.42 (need 2+ steps for projection)
```

**Integration:** This display line is emitted by the octopus-hud hook and rendered in the statusline alongside phase progress and provider status.

---

## Step 5: Budget Ceiling Warning

If the `OCTO_BUDGET_CEILING` environment variable is set, compare the projected total against it and warn on overrun.

```bash
if [[ -n "${OCTO_BUDGET_CEILING:-}" ]]; then
  ceiling="$OCTO_BUDGET_CEILING"
  if (( $(echo "$projected_total > $ceiling" | bc -l) )); then
    overage=$(echo "$projected_total - $ceiling" | bc -l)
    echo "⚠️ Budget ceiling: \$$ceiling — projected to exceed by \$$overage"
  fi
fi
```

**Display when over budget:**
```
💰 Spent: $2.40 | Est. remaining: $3.60 | Total: ~$6.00
⚠️ Budget ceiling: $5.00 — projected to exceed by $1.00
```

**Display when within budget:**
```
💰 Spent: $2.40 | Est. remaining: $3.60 | Total: ~$6.00
✅ Within budget ceiling: $10.00
```

**Note:** `OCTO_BUDGET_CEILING` is optional. When unset, no ceiling check is performed.

---

## Step 6: Profile Suggestion

If the projected total is high relative to the task, suggest switching to the budget profile to reduce costs.

```bash
# Suggest budget profile when projected total exceeds $5.00 (configurable)
COST_THRESHOLD="${OCTO_COST_THRESHOLD:-5.00}"
if (( $(echo "$projected_total > $COST_THRESHOLD" | bc -l) )); then
  echo "💡 Tip: Switch to OCTO_PROFILE=budget to reduce costs"
fi
```

**Display:**
```
💰 Spent: $2.40 | Est. remaining: $3.60 | Total: ~$6.00
💡 Tip: Switch to OCTO_PROFILE=budget to reduce costs
```

The budget profile (`OCTO_PROFILE=budget`) routes to cheaper models and reduces agent count to minimize spend.

---

## Complete Display Examples

**Normal — within budget, moderate cost:**
```
💰 Spent: $2.40 | Est. remaining: $3.60 | Total: ~$6.00
```

**Over budget ceiling:**
```
💰 Spent: $2.40 | Est. remaining: $3.60 | Total: ~$6.00
⚠️ Budget ceiling: $5.00 — projected to exceed by $1.00
💡 Tip: Switch to OCTO_PROFILE=budget to reduce costs
```

**Early in workflow (insufficient data):**
```
💰 Spent: $0.42 (need 2+ steps for projection)
```

**Low cost — no warnings:**
```
💰 Spent: $0.80 | Est. remaining: $0.80 | Total: ~$1.60
```

---

## Integration

### With octopus-hud hook
The cost projection line is rendered as part of the HUD statusline output, updated after each phase completes.

### With metrics-tracker.sh
Reads per-phase cost data written by the metrics tracker. Each completed phase logs cost, token counts, and provider details.

### With OCTO_PROFILE
When `OCTO_PROFILE=budget` is active, the projection accounts for reduced per-step costs from cheaper model routing.

---

## Error Handling

**No metrics directory:**
```
💰 Cost projection unavailable — no metrics data found
```

**Corrupted metrics data:**
Skip malformed entries and project from valid data only. If no valid entries remain, show unavailable message.

**Zero remaining steps:**
When all steps are complete, show final total only:
```
💰 Final cost: $4.80 (4 steps)
```
