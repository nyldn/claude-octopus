---
description: "Execute tasks in loops with conditions, iterative improvements until goals are met"
---

# Loop - Iterative Execution Skill

**Your first output line MUST be:** `🐙 Octopus Loop Mode`

## Instructions

Read and follow the full skill instructions from:
`${HOME}/.claude-octopus/plugin/.claude/skills/skill-iterative-loop.md`

## Quick Usage

Just use natural language:
```
"Loop 5 times auditing, enhancing, testing"
"Keep trying until all tests pass"
"Iterate until performance improves"
```

Or use the explicit command:
```
/octo:loop "run tests and fix issues" --max 5
/octo:loop "optimize performance until < 100ms"
```

## Loop Execution Approach

1. **Define Goal**: Clear success criteria and exit conditions
2. **Set Max Iterations**: Safety limit to prevent infinite loops
3. **Execute**: Run the task/operation
4. **Evaluate**: Check if goal is met or progress made
5. **Loop or Complete**: Continue if needed, stop when done

## What You Get

- Systematic iteration with progress tracking
- Clear exit conditions (max iterations or goal met)
- Progress metrics after each iteration
- Stall detection (stops if no progress)
- Final summary of all iterations

## Use Cases

**Testing Loops:**
```
"Loop until all unit tests pass, max 3 attempts"
"Keep fixing failing tests until test suite is green"
```

**Optimization Iterations:**
```
"Loop 5 times optimizing query performance"
"Iterate until API response time is under 100ms"
```

**Progressive Enhancement:**
```
"Loop around 3 times enhancing error handling"
"Iterate improving code quality until score > 80"
```

**Retry Patterns:**
```
"Try up to 5 times to connect to the database"
"Loop until deployment succeeds, max 3 retries"
```

## Safety Features

- **Max iterations enforced**: Never infinite loops
- **Stall detection**: Stops if no progress after N iterations
- **Clear exit criteria**: Always know when to stop
- **Progress tracking**: See improvement each iteration

## Parameters

- **Task/Goal**: What to execute or achieve
- **Max iterations**: Safety limit (default: 5, max: 20)
- **Exit condition**: When to stop ("until tests pass", "until score > X")
- **Progress metric**: How to measure improvement

## Natural Language Examples

```
"Loop 5 times auditing, enhancing, testing the authentication module"
"Keep trying until the deployment succeeds, max 3 attempts"
"Iterate improving the algorithm until performance is under 50ms"
"Run the optimization loop 10 times and track progress"
"Loop around 3 times fixing linting errors until all clear"
```

## Metric Verification Mode

When you specify a `Metric:` command, the loop switches to mechanical metric verification. Each iteration makes ONE atomic change, commits it with an `experiment:` prefix, measures the metric, and automatically reverts if the metric worsens.

### Metric Mode Parameters

- **Metric:** `<shell command>` — must output a number (the value to optimize)
- **Direction:** `higher` or `lower` — whether bigger or smaller numbers are better
- **Guard:** `<shell command>` — must exit 0 for a change to be kept (run after metric)
- **Iterations:** `N` — max iterations (default: unbounded)

### Metric Mode Examples

```
/octo:loop Metric: npm test -- --coverage | grep 'All files' | awk '{print $10}' Direction: higher Guard: npm test Iterations: 20
```

```
/octo:loop Metric: time npm run build 2>&1 | grep real | awk '{print $2}' Direction: lower Iterations: 10
```

```
/octo:loop Metric: wc -l src/**/*.ts | tail -1 | awk '{print $1}' Direction: lower Guard: npm test Iterations: 15
```

### How It Works

1. Establishes baseline by running the metric command
2. Each iteration: one change → git commit → measure → keep or revert
3. Results logged to `.claude-octopus/experiments/<date>.jsonl`
4. Resumes from existing log if experiment was interrupted
5. Reports improvement summary when complete

See the full skill documentation for detailed execution contract and rules.

## Integration with Other Skills

- Combines well with `/octo:debug` for iterative bug fixing
- Works with `/octo:tdd` for red-green-refactor loops
- Useful with `/octo:review` for iterative quality improvements
- Pairs with `/octo:security` for iterative vulnerability remediation
