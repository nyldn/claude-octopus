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
      "wave": 1,
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

### STEP 4.5: Dependency Validation & Wave Assignment (MANDATORY)

If any work package has non-empty `dependencies`, validate the dependency graph and assign wave numbers.

**Skip this step** if all work packages have `"dependencies": []` — they all get wave 1 (backward compatible).

**Run dependency validation and wave assignment:**

```bash
python3 << 'DEPEOF'
import json, sys

with open('.octo/parallel/wbs.json') as f:
    wbs = json.load(f)

packages = wbs['work_packages']
ids = {wp['id'] for wp in packages}
deps = {wp['id']: wp.get('dependencies', []) for wp in packages}

# Check for missing references
errors = []
for wp_id, wp_deps in deps.items():
    for dep in wp_deps:
        if dep not in ids:
            errors.append(f"WP {wp_id} depends on unknown {dep}")

if errors:
    print("DEPENDENCY VALIDATION: FAILED")
    for e in errors:
        print(f"  ERROR: {e}")
    sys.exit(1)

# Cycle detection (DFS)
WHITE, GRAY, BLACK = 0, 1, 2
color = {wp_id: WHITE for wp_id in ids}

def has_cycle(node, path):
    color[node] = GRAY
    for dep in deps[node]:
        if color[dep] == GRAY:
            cycle = path[path.index(dep):] + [dep]
            return cycle
        if color[dep] == WHITE:
            result = has_cycle(dep, path + [dep])
            if result:
                return result
    color[node] = BLACK
    return None

for wp_id in ids:
    if color[wp_id] == WHITE:
        cycle = has_cycle(wp_id, [wp_id])
        if cycle:
            print(f"DEPENDENCY VALIDATION: FAILED - Cycle detected: {' -> '.join(cycle)}")
            sys.exit(1)

# Topological sort and wave assignment
waves = {}
assigned = set()

def get_wave(wp_id):
    if wp_id in waves:
        return waves[wp_id]
    if not deps[wp_id]:
        waves[wp_id] = 1
        return 1
    max_dep_wave = max(get_wave(d) for d in deps[wp_id])
    waves[wp_id] = max_dep_wave + 1
    return waves[wp_id]

for wp_id in ids:
    get_wave(wp_id)

# Update WBS with wave assignments
for wp in packages:
    wp['wave'] = waves[wp['id']]

with open('.octo/parallel/wbs.json', 'w') as f:
    json.dump(wbs, f, indent=2)

max_wave = max(waves.values())
print(f"DEPENDENCY VALIDATION: PASSED")
print(f"Waves assigned: {max_wave}")
for w in range(1, max_wave + 1):
    wave_wps = [wp_id for wp_id, wave in waves.items() if wave == w]
    print(f"  Wave {w}: {', '.join(wave_wps)}")
DEPEOF
```

**If validation fails:** Report the error to the user and STOP. Do not proceed with invalid dependencies.

**DO NOT PROCEED TO STEP 5 until dependencies validated (or step skipped for independent WPs).**

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

## Dependency Context
- This WP depends on: <list of dependency WP IDs, or "none">
- Outputs from completed dependencies will be provided below when available
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

### STEP 6: Launch & Monitor — Wave-Based Execution (MANDATORY)

Launch work packages in dependency waves. Wave 1 runs first; Wave 2 starts only after Wave 1 completes (with outputs injected); and so on.

**If all WPs are in Wave 1** (no dependencies), this behaves identically to the original launch — backward compatible.

**Wave-based launch sequence:**

```bash
PROJECT_ROOT="$(pwd)"
WBS_FILE=".octo/parallel/wbs.json"
MAX_WAVE=$(python3 -c "import json; wbs=json.load(open('$WBS_FILE')); print(max(wp.get('wave',1) for wp in wbs['work_packages']))")
TIMEOUT=600  # 10 minutes per wave

echo "Executing $MAX_WAVE wave(s)..."

for WAVE in $(seq 1 "$MAX_WAVE"); do
  echo ""
  echo "=== WAVE $WAVE ==="
  echo ""

  # Get WPs for this wave
  WAVE_WPS=$(python3 -c "
import json
wbs=json.load(open('$WBS_FILE'))
wps=[wp['id'] for wp in wbs['work_packages'] if wp.get('wave',1)==$WAVE]
print(' '.join(wps))
  ")

  # Inject outputs from completed dependency WPs into instructions
  for WP_ID in $WAVE_WPS; do
    WP_NUM="${WP_ID#WP-}"
    WP_DIR=".octo/parallel/$WP_ID"

    # Get dependencies for this WP
    DEPS=$(python3 -c "
import json
wbs=json.load(open('$WBS_FILE'))
wp=[w for w in wbs['work_packages'] if w['id']=='$WP_ID'][0]
print(' '.join(wp.get('dependencies',[])))
    ")

    if [[ -n "$DEPS" ]]; then
      echo "Injecting dependency outputs into $WP_ID..."
      echo "" >> "$WP_DIR/instructions.md"
      echo "## Outputs from Dependencies" >> "$WP_DIR/instructions.md"
      for DEP in $DEPS; do
        DEP_DIR=".octo/parallel/$DEP"
        if [[ -f "$DEP_DIR/output.md" ]]; then
          echo "" >> "$WP_DIR/instructions.md"
          echo "### From $DEP:" >> "$WP_DIR/instructions.md"
          head -c 4000 "$DEP_DIR/output.md" >> "$WP_DIR/instructions.md"
        fi
      done
    fi
  done

  # Launch WPs in this wave with 12s stagger
  WAVE_COUNT=0
  for WP_ID in $WAVE_WPS; do
    WP_NUM="${WP_ID#WP-}"
    echo "Launching $WP_ID at $(date '+%H:%M:%S')..."
    bash ".octo/parallel/$WP_ID/launch.sh" &
    WP_PID=$!
    echo "$WP_PID" > ".octo/parallel/$WP_ID/pid"
    echo "  $WP_ID launched (PID: $WP_PID)"
    WAVE_COUNT=$((WAVE_COUNT + 1))

    # 12-second stagger within wave (skip after last)
    REMAINING=$(echo "$WAVE_WPS" | wc -w | tr -d ' ')
    if [[ "$WAVE_COUNT" -lt "$REMAINING" ]]; then
      echo "  Waiting 12 seconds before next launch..."
      sleep 12
    fi
  done

  # Monitor this wave
  START_TIME=$(date +%s)
  COMPLETED=0
  WAVE_TOTAL=$(echo "$WAVE_WPS" | wc -w | tr -d ' ')

  echo "Monitoring Wave $WAVE ($WAVE_TOTAL WPs, timeout: ${TIMEOUT}s)..."

  while [[ "$COMPLETED" -lt "$WAVE_TOTAL" ]]; do
    COMPLETED=0
    for WP_ID in $WAVE_WPS; do
      if [[ -f ".octo/parallel/$WP_ID/.done" ]]; then
        COMPLETED=$((COMPLETED + 1))
      fi
    done

    ELAPSED=$(( $(date +%s) - START_TIME ))
    echo "Wave $WAVE progress: $COMPLETED/$WAVE_TOTAL complete (${ELAPSED}s elapsed)"

    if [[ "$ELAPSED" -gt "$TIMEOUT" ]]; then
      echo "TIMEOUT: Wave $WAVE did not complete within ${TIMEOUT}s"
      break
    fi

    if [[ "$COMPLETED" -lt "$WAVE_TOTAL" ]]; then
      sleep 15
    fi
  done

  echo "Wave $WAVE complete: $COMPLETED/$WAVE_TOTAL finished."
done

echo ""
echo "All waves executed."
```

**Validation gate: `processes_launched`** — Verify PID files exist for all WPs.

**IMPORTANT:** The launch and monitor commands above should be run via the Bash tool. You may need to combine them or run the monitor as a separate polling step. The monitor loop will block until each wave completes or times out.

**DO NOT PROCEED TO STEP 7 until all waves complete.**

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
- CANNOT launch a wave before its dependency wave completes
- CANNOT skip dependency validation when dependencies exist

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
