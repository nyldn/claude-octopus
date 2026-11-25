---
name: skill-cost-projections
disable-model-invocation: true
effort: low
aliases:
  - cost-projections
  - cost-forecast
  - budget-projection
description: "Project remaining workflow cost from per-phase averages — warns on budget ceiling overruns"
trigger: |
  EXPLICITLY USE when user asks about workflow costs:
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
codex_short_description: "Estimate remaining workflow cost from recorded usage"
---

# Cost Projections Skill

## Overview

Projects remaining workflow cost based on per-phase averages from completed work. Displays cost data in the HUD/statusline and warns when projected totals exceed a configured budget ceiling.

**Minimum data requirement:** Needs **2+ completed steps** before projecting. With fewer than 2 data points, the average is unreliable — display actual spend only and skip projection.

---

## Step 1: Collect Completed Phase Costs

Set `total_steps` for the workflow in Step 3 and run the following blocks in
the same shell. Use the JSONL file only when its entries are known to describe
the current workflow. Each completed step should have one cost entry in USD.

```bash
# Read metrics from the session metrics directory
METRICS_DIR="$HOME/.claude-octopus/metrics"
SESSION_METRICS="$METRICS_DIR/session-$(date +%Y%m%d).jsonl"

# Parse each line separately so damaged rows do not discard valid costs.
if [[ ! -f "$SESSION_METRICS" || ! -r "$SESSION_METRICS" ]] ||
   ! summary=$(jq -nRer '
      reduce (inputs | fromjson? | objects | .cost | numbers | select(isfinite and . >= 0))
        as $cost ([0, 0]; [.[0] + 1, .[1] + $cost])
      | select(.[0] > 0 and (.[1] | isfinite)) | @tsv
    ' "$SESSION_METRICS"); then
    printf '%s\n' 'Cost projection unavailable: no usable metrics data found.'
    exit 0
fi
IFS=$'\t' read -r completed_count total_spent <<< "$summary"
if (( completed_count < 2 )); then
    LC_ALL=C printf 'Spent: %.2f USD (need 2+ steps for projection)\n' "$total_spent"
    exit 0
fi
```

If per-step data is unavailable, report any known spend separately. A
`metrics-tracker.sh` or HUD total can provide spend, but the total alone does
not establish the number of completed steps.

If fewer than 2 completed steps are available, display only actual spend:
```
💰 Spent: 0.42 USD (1 step complete — need 2+ for projection)
```

---

## Step 2: Compute Average Cost Per Step

Calculate the mean cost across all completed steps.

```bash
avg_cost=$(jq -nr --argjson spent "$total_spent" --argjson count "$completed_count" '$spent / $count')
```

**Formula:**
```
avg_cost = total_cost / completed_steps
```

**Example:** If 3 steps cost 0.30 USD, 0.50 USD, 0.40 USD → avg = 1.20 USD / 3 = 0.40 USD/step

---

## Step 3: Project Remaining Cost

Multiply the average cost per step by the number of remaining steps.

```bash
if ! projection=$(jq -ner --arg planned "${total_steps:-}" \
    --argjson count "$completed_count" --argjson average "$avg_cost" \
    --argjson spent "$total_spent" '
    ($planned | select(test("^[0-9]+$")) | tonumber) as $planned
    | ([$planned - $count, 0] | max) as $remaining
    | ($average * $remaining) as $estimate
    | [$remaining, $estimate, $spent + $estimate]
    | select(all(.[]; isfinite)) | @tsv
'); then
    LC_ALL=C printf 'Spent: %.2f USD (remaining cost unavailable)\n' "$total_spent"
    exit 0
fi
IFS=$'\t' read -r remaining_steps projected_remaining projected_total <<< "$projection"
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
💰 Spent: 2.40 USD | Est. remaining: 3.60 USD | Total: ~6.00 USD
```

**Format rules:**
- All dollar amounts to 2 decimal places
- Projected total prefixed with `~` to indicate estimate
- Use `💰` prefix for the cost line
- Show in a single compact line for statusline integration

**When insufficient data (< 2 steps):**
```
💰 Spent: 0.42 USD (need 2+ steps for projection)
```

**Integration:** This display line is emitted by the octopus-hud hook and rendered in the statusline alongside phase progress and provider status.

---

## Step 5: Budget Ceiling Warning

If the `OCTO_BUDGET_CEILING` environment variable is set, compare the projected total against it and warn on overrun.

```bash
if [[ -n "${OCTO_BUDGET_CEILING:-}" ]]; then
  ceiling="$OCTO_BUDGET_CEILING"
  if overage=$(jq -ner --argjson total "$projected_total" --arg limit "$ceiling" '
    ($limit | tonumber? | select(isfinite and . >= 0)) as $limit
    | $total - $limit | select(. > 0)
  '); then
    LC_ALL=C printf '⚠️ Budget ceiling: %s USD — projected to exceed by %.2f USD\n' "$ceiling" "$overage"
  fi
fi
```

**Display when over budget:**
```
💰 Spent: 2.40 USD | Est. remaining: 3.60 USD | Total: ~6.00 USD
⚠️ Budget ceiling: 5.00 USD — projected to exceed by 1.00 USD
```

**Display when within budget:**
```
💰 Spent: 2.40 USD | Est. remaining: 3.60 USD | Total: ~6.00 USD
✅ Within budget ceiling: 10.00 USD
```

**Note:** `OCTO_BUDGET_CEILING` is optional. When unset, no ceiling check is performed.

---

## Step 6: Profile Suggestion

If the projected total is high relative to the task, suggest switching to the budget profile to reduce costs.

```bash
# Suggest budget profile when projected total exceeds 5.00 USD (configurable)
COST_THRESHOLD="${OCTO_COST_THRESHOLD:-5.00}"
if jq -ne --argjson total "$projected_total" --arg limit "$COST_THRESHOLD" '
  $total > ($limit | tonumber? | select(isfinite and . >= 0))
' >/dev/null; then
  echo "💡 Tip: Switch to OCTO_PROFILE=budget to reduce costs"
fi
```

**Display:**
```
💰 Spent: 2.40 USD | Est. remaining: 3.60 USD | Total: ~6.00 USD
💡 Tip: Switch to OCTO_PROFILE=budget to reduce costs
```

The budget profile (`OCTO_PROFILE=budget`) routes to cheaper models and reduces agent count to minimize spend.

---

## Complete Display Examples

**Normal — within budget, moderate cost:**
```
💰 Spent: 2.40 USD | Est. remaining: 3.60 USD | Total: ~6.00 USD
```

**Over budget ceiling:**
```
💰 Spent: 2.40 USD | Est. remaining: 3.60 USD | Total: ~6.00 USD
⚠️ Budget ceiling: 5.00 USD — projected to exceed by 1.00 USD
💡 Tip: Switch to OCTO_PROFILE=budget to reduce costs
```

**Early in workflow (insufficient data):**
```
💰 Spent: 0.42 USD (need 2+ steps for projection)
```

**Low cost — no warnings:**
```
💰 Spent: 0.80 USD | Est. remaining: 0.80 USD | Total: ~1.60 USD
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
💰 Final cost: 4.80 USD (4 steps)
```
