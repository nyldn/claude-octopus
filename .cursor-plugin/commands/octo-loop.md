---
description: "[advanced] Execute tasks in loops with conditions, iterative improvements until goals are met"
disable-model-invocation: true
---

# Loop - Iterative Execution Skill

**Your first output line MUST be:** `🐙 Octopus Loop Mode`

## Instructions

Read and follow the full skill instructions from:
`${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/.claude/skills/skill-iterative-loop/SKILL.md`

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

`Metric: <command>` measures each candidate using a frozen numeric metric and
optional `Guard: <command>`. Without a guard, accept only a measured
improvement and report that no guard ran; do not claim safety validation. Set `Direction: higher` or `Direction: lower`.
Defaults are five iterations, 30 elapsed minutes, and 14 additional model
calls. `Iterations: N` accepts 1 through 20; `Minutes: N` and `Calls: N` accept
positive integers. Stop at the first exhausted budget or two stalled rounds.
Retries consume the same budgets, including after an interruption.

Work on isolated candidate copies. Preserve the user's dirty files, untracked
files, and staged index. Rejected experiments discard only owned candidates;
the workflow does not stage, commit, reset, or revert the user's repository.
Check for concurrent changes before publishing only the authorized files and
verify the delivered result. Missing isolation or deadline support stops the run.

```text
/octo:loop Metric: npm test -- --coverage Direction: higher Guard: npm test Iterations: 5 Minutes: 30 Calls: 14
```

The metric command must output one number. See the delegated skill for the
complete preservation, scoring, timeout, and resume contract.

## Integration with Other Skills

- Combines well with `/octo:debug` for iterative bug fixing
- Works with `/octo:tdd` for red-green-refactor loops
- Useful with `/octo:review` for iterative quality improvements
- Pairs with `/octo:security` for iterative vulnerability remediation
