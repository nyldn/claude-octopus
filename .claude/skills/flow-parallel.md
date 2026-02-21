---
name: flow-parallel
aliases:
  - parallel
  - team
  - teams
  - team-of-teams
description: Team of Teams — decompose compound tasks across independent claude instances
execution_mode: enforced
validation_gates:
  - wbs_generated
  - instructions_written
  - processes_launched
  - all_work_packages_complete
---

# STOP - SKILL ALREADY LOADED

**DO NOT call Skill() again. DO NOT load any more skills. Execute directly.**

---

## EXECUTION CONTRACT (MANDATORY - CANNOT SKIP)

This skill uses **ENFORCED execution mode**. You MUST follow this exact 7-step sequence.

**Architectural Principle:** Task tool subagents do NOT load plugins. Independent `claude -p` processes DO. This skill spawns independent `claude -p` processes so each work package gets the full Octopus plugin, its own Double Diamond, agents, and quality gates.

---

### STEP 1: Clarifying Questions (MANDATORY)

**Ask via AskUserQuestion BEFORE any other action.**

You MUST gather these inputs from the user:

```
AskUserQuestion with these questions:

1. **Compound task**: What compound task should be decomposed?
   - Use inline args if provided (e.g., /octo:parallel "build auth system")
   - If no args: ask "What compound task should I decompose into parallel work packages?"

2. **Work package count**: How many work packages?
   - Options: "3 (Recommended)", "4", "5", "Custom (up to 10)"
   - Default: 3-5 is optimal

3. **Dependencies**: Are the work packages independent?
   - "Fully independent - no dependencies between packages (Recommended)"
   - "Some dependencies - packages may need to share interfaces"
   - "Sequential dependencies - packages must complete in order"
```

If user provided a description inline with the command (e.g., `/octo:parallel build a full auth system with OAuth, RBAC, and audit logging`), use that as the task description but STILL ask remaining questions (count, dependencies).

If user says "skip" for any question, use defaults: 3 work packages, fully independent.

**DO NOT PROCEED TO STEP 2 until questions answered.**

---

### STEP 2: Display Visual Indicators (MANDATORY - BLOCKING)

**Display this banner BEFORE any decomposition:**

```
CLAUDE OCTOPUS ACTIVATED - Team of Teams Mode
Parallel Phase: Decomposing compound task into N independent work packages

Architecture:
  Main (this session) - Orchestrator: decompose, launch, monitor, aggregate
  WP-1..WP-N (claude -p) - Independent workers with full plugin capabilities

Each worker:
  - Runs as independent claude -p process
  - Loads full Octopus plugin
  - Has own context, tools, and quality gates
  - Produces output.md + exit-code

Estimated Time: 5-15 minutes (depending on task complexity)
```

**DO NOT PROCEED TO STEP 3 until banner displayed.**

---

### STEP 3: Read Prior State (MANDATORY - State Management)

**Before decomposing, read any prior context:**

```bash
# Initialize state if needed
if [[ -d ".octo" ]]; then
  echo "Found existing .octo/ state directory"
else
  echo "No prior .octo/ state found - starting fresh"
fi

# Check for prior discover/spec context
if [[ -f ".octo/STATE.md" ]]; then
  echo "Prior state found:"
  cat .octo/STATE.md
fi

if [[ -f ".octo/PROJECT.md" ]]; then
  echo "Prior project context found:"
  cat .octo/PROJECT.md
fi
```

Use any prior context (discover findings, spec definitions, project state) to inform the WBS decomposition.

**DO NOT PROCEED TO STEP 4 until state read.**

---

### STEP 4: Decompose into WBS (MANDATORY)

Claude analyzes the compound task and produces a Work Breakdown Structure.

**Decomposition rules:**
- Break into 3-5 independent work packages (WP-1 through WP-N, max 10)
- Each WP gets: name, scope description, expected output files, dependencies
- Validate: non-overlapping scopes, collectively exhaustive
- Each WP must be self-contained enough for an independent claude -p process

**Create the coordination directory and WBS:**

```bash
# Create parallel coordination directory
mkdir -p .octo/parallel

# Write wbs.json
cat > .octo/parallel/wbs.json << 'WBSEOF'
{
  "task": "<compound task description>",
  "created": "<ISO timestamp>",
  "work_packages": [
    {
      "id": "WP-1",
      "name": "<work package name>",
      "scope": "<what this WP covers>",
      "expected_outputs": ["<list of files this WP should produce>"],
      "dependencies": [],
      "status": "pending"
    }
  ]
}
WBSEOF
```

**You MUST write actual WBS content** based on your analysis of the compound task. The JSON above is a template — populate it with real decomposition.

**Validation gate: `wbs_generated`** — Verify `.octo/parallel/wbs.json` exists and contains valid JSON:

```bash
# Validate WBS was created
if [[ -f ".octo/parallel/wbs.json" ]]; then
  python3 -c "import json; json.load(open('.octo/parallel/wbs.json')); print('WBS validation: PASSED')" 2>/dev/null || echo "WBS validation: FAILED - invalid JSON"
else
  echo "WBS validation: FAILED - file not found"
fi
```

**DO NOT PROCEED TO STEP 5 until WBS validated.**

---

### STEP 5: Generate Instruction Files (MANDATORY)

For each work package in the WBS, create an instructions file and a launch script.

**For each WP-N, create:**

#### `instructions.md`

```bash
mkdir -p ".octo/parallel/WP-N"

cat > ".octo/parallel/WP-N/instructions.md" << 'INSTREOF'
# Work Package WP-N: <name>

## Task
<Clear description of what this work package must accomplish>

## Scope Boundaries
- IN SCOPE: <what this WP covers>
- OUT OF SCOPE: <what other WPs handle — explicit boundaries>

## Expected Output
- Files to create/modify: <explicit file paths — MANDATORY>
- Location: <where outputs go in the project>

## Integration Contract
- This WP produces: <what downstream consumers can expect>
- This WP consumes: <what it needs from the project, NOT from other WPs>

## Quality Expectations
- Code must compile/parse without errors
- Follow existing project conventions
- Include basic error handling
INSTREOF
```

**CRITICAL:** Every instructions.md MUST contain explicit file paths. Vague descriptions like "create the auth module" are PROHIBITED — specify exact paths like `src/auth/oauth.ts`.

#### `launch.sh`

```bash
cat > ".octo/parallel/WP-N/launch.sh" << 'LAUNCHEOF'
#!/bin/bash
cd "<absolute-project-root-path>"
unset CLAUDECODE
cat "$(dirname "$0")/instructions.md" | claude -p --dangerously-skip-permissions > "$(dirname "$0")/output.md" 2>"$(dirname "$0")/agent.log"
echo $? > "$(dirname "$0")/exit-code"
touch "$(dirname "$0")/.done"
LAUNCHEOF

chmod +x ".octo/parallel/WP-N/launch.sh"
```

**You MUST replace `<absolute-project-root-path>`** with the actual project root (use `pwd` to determine it).

**Validation gate: `instructions_written`** — Verify all instruction files exist:

```bash
# Count WPs from wbs.json
wp_count=$(python3 -c "import json; print(len(json.load(open('.octo/parallel/wbs.json'))['work_packages']))")

# Verify each WP has instructions.md and launch.sh
missing=0
for i in $(seq 1 "$wp_count"); do
  if [[ ! -f ".octo/parallel/WP-$i/instructions.md" ]]; then
    echo "MISSING: .octo/parallel/WP-$i/instructions.md"
    missing=$((missing + 1))
  fi
  if [[ ! -f ".octo/parallel/WP-$i/launch.sh" ]]; then
    echo "MISSING: .octo/parallel/WP-$i/launch.sh"
    missing=$((missing + 1))
  fi
done

if [[ "$missing" -eq 0 ]]; then
  echo "Instruction files validation: PASSED ($wp_count work packages)"
else
  echo "Instruction files validation: FAILED ($missing files missing)"
fi
```

**DO NOT PROCEED TO STEP 6 until all instruction files validated.**

---

### STEP 6: Launch & Monitor (MANDATORY)

Launch each work package as a background process with a 12-second stagger between spawns.

**Launch sequence:**

```bash
PROJECT_ROOT="$(pwd)"
WP_COUNT=$(python3 -c "import json; print(len(json.load(open('.octo/parallel/wbs.json'))['work_packages']))")

echo "Launching $WP_COUNT work packages with 12-second stagger..."

for i in $(seq 1 "$WP_COUNT"); do
  echo "Launching WP-$i at $(date '+%H:%M:%S')..."
  bash ".octo/parallel/WP-$i/launch.sh" &
  WP_PID=$!
  echo "$WP_PID" > ".octo/parallel/WP-$i/pid"
  echo "  WP-$i launched (PID: $WP_PID)"

  # 12-second stagger between launches (skip after last)
  if [[ "$i" -lt "$WP_COUNT" ]]; then
    echo "  Waiting 12 seconds before next launch..."
    sleep 12
  fi
done

echo "All $WP_COUNT work packages launched."
```

**Monitor loop — poll for completion:**

```bash
TIMEOUT=600  # 10 minutes per WP
START_TIME=$(date +%s)
COMPLETED=0

echo "Monitoring work packages (timeout: ${TIMEOUT}s per WP)..."

while [[ "$COMPLETED" -lt "$WP_COUNT" ]]; do
  COMPLETED=0
  for i in $(seq 1 "$WP_COUNT"); do
    if [[ -f ".octo/parallel/WP-$i/.done" ]]; then
      COMPLETED=$((COMPLETED + 1))
    fi
  done

  ELAPSED=$(( $(date +%s) - START_TIME ))
  echo "Progress: $COMPLETED/$WP_COUNT complete (${ELAPSED}s elapsed)"

  if [[ "$ELAPSED" -gt "$((TIMEOUT * WP_COUNT))" ]]; then
    echo "TIMEOUT: Not all work packages completed within $(( TIMEOUT * WP_COUNT ))s"
    break
  fi

  if [[ "$COMPLETED" -lt "$WP_COUNT" ]]; then
    sleep 15
  fi
done

echo "Monitoring complete: $COMPLETED/$WP_COUNT work packages finished."
```

**Validation gate: `processes_launched`** — Verify PID files exist for all WPs.

**IMPORTANT:** The launch and monitor commands above should be run via the Bash tool. You may need to combine them or run the monitor as a separate polling step. The monitor loop will block until all WPs complete or timeout.

**DO NOT PROCEED TO STEP 7 until monitoring complete.**

---

### STEP 7: Aggregate & Present (MANDATORY)

After all work packages complete (or timeout), aggregate results.

**Read all outputs and exit codes:**

```bash
echo "=== WORK PACKAGE RESULTS ==="
echo ""

FAILED=0
SUCCEEDED=0

for i in $(seq 1 "$WP_COUNT"); do
  WP_DIR=".octo/parallel/WP-$i"

  if [[ -f "$WP_DIR/exit-code" ]]; then
    EXIT_CODE=$(cat "$WP_DIR/exit-code")
  else
    EXIT_CODE="N/A (not completed)"
  fi

  if [[ "$EXIT_CODE" == "0" ]]; then
    STATUS="SUCCESS"
    SUCCEEDED=$((SUCCEEDED + 1))
  else
    STATUS="FAILED (exit code: $EXIT_CODE)"
    FAILED=$((FAILED + 1))
  fi

  echo "WP-$i: $STATUS"

  if [[ -f "$WP_DIR/output.md" ]]; then
    OUTPUT_SIZE=$(wc -c < "$WP_DIR/output.md" | tr -d ' ')
    echo "  Output: $OUTPUT_SIZE bytes"
  else
    echo "  Output: MISSING"
  fi

  echo ""
done

echo "=== SUMMARY ==="
echo "Total: $WP_COUNT | Succeeded: $SUCCEEDED | Failed: $FAILED"
```

**Then read each output.md** using the Read tool and present an integrated summary to the user:

1. Read all `output.md` files from completed WPs
2. Flag any failed WPs (non-zero exit code) with their `agent.log` content
3. Present a unified summary of what was accomplished
4. List any files created or modified across all WPs
5. Note any integration points that need manual attention

**Present results in this format:**

```
=== TEAM OF TEAMS - RESULTS ===

Compound Task: <original task>
Work Packages: N total | N succeeded | N failed

WP-1: <name> - [SUCCESS/FAILED]
  <summary of what was accomplished>

WP-2: <name> - [SUCCESS/FAILED]
  <summary of what was accomplished>

...

Integration Notes:
- <any cross-WP concerns>
- <files that may need reconciliation>

Failed Work Packages (if any):
- WP-X: <error summary from agent.log>

Coordination Files: .octo/parallel/
```

**Validation gate: `all_work_packages_complete`** — All WPs have `.done` files and exit codes checked.

---

## Coordination Protocol Directory Structure

Created and managed by this skill:

```
.octo/parallel/
  wbs.json              # Work Breakdown Structure
  WP-1/
    instructions.md     # Task instructions for this WP
    launch.sh           # Launch script (runs claude -p)
    output.md           # Agent output (created by claude -p)
    agent.log           # Agent stderr log (created by launch.sh)
    exit-code           # Process exit code (created by launch.sh)
    pid                 # Process ID (created by orchestrator)
    .done               # Completion marker (created by launch.sh)
  WP-2/
    ...
  WP-N/
    ...
```

---

## Prohibitions (MANDATORY - CANNOT VIOLATE)

- CANNOT use Task tool subagents as substitute (they don't load plugins)
- CANNOT skip WBS decomposition (Step 4)
- CANNOT launch without instruction files (Step 5 must precede Step 6)
- CANNOT skip 12-second stagger between launches
- CANNOT declare success without checking exit codes
- CANNOT proceed to next step without completing current step
- CANNOT write vague instructions — explicit file paths are MANDATORY
- CANNOT launch more than 10 work packages
- CANNOT skip the monitoring loop

---

## Error Handling

**If a work package fails (non-zero exit code):**
1. Read its `agent.log` for error details
2. Present the error to the user
3. Offer to retry the failed WP individually
4. Do NOT re-run succeeded WPs

**If monitoring times out:**
1. Report which WPs completed and which did not
2. Check if timed-out WPs are still running (check PID)
3. Offer to wait longer or kill remaining processes

**If `claude` command is not available:**
1. Check with `command -v claude`
2. Report to user and STOP — cannot proceed without claude CLI

---

## Example Usage

### Example: Authentication System

```
User: /octo:parallel build a full authentication system with OAuth, RBAC, and audit logging

Decomposition:
  WP-1: OAuth Integration
    - OAuth provider setup (Google, GitHub)
    - Token management and refresh
    - Callback handlers
    Files: src/auth/oauth.ts, src/auth/providers/

  WP-2: RBAC Implementation
    - Role and permission models
    - Authorization middleware
    - Role assignment API
    Files: src/auth/rbac.ts, src/middleware/authorize.ts

  WP-3: Audit Logging
    - Audit event model
    - Logging middleware
    - Audit query API
    Files: src/audit/logger.ts, src/audit/events.ts

Each WP runs as independent claude -p with full Octopus plugin.
Results aggregated after all complete.
```
