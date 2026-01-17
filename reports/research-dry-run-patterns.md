# Research Report: Dry-Run Patterns & Implementation Strategy

**Date:** January 17, 2026
**Subject:** Analysis of `test --dry-run` patterns, failure modes, and migration strategy for `claude-octopus`.

## 1. Executive Summary
The current "dry-run" implementation in `claude-octopus` uses a **Flag & Guard (Early Return)** pattern. While this successfully avoids costs and verifies high-level routing, it is the root cause of the "hangs" and "Exit Code 1" failures observed in integration tests. Because dry-run functions return early without producing expected artifacts (files, variables), downstream logic crashes or enters infinite loops.

**Recommendation:** Migrate from **Early Return** to **Service Virtualization (Mocking)**. Dry-run functions should not just "skip" work but "simulate" work by generating dummy artifacts.

## 2. Pattern Analysis

### A. The Current Pattern: Flag & Guard (Early Return)
**Mechanism:**
```bash
function spawn_agent() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Would spawn agent..."
        return 0  # <--- The Problem
    fi
    # ... Real logic ...
}
```
*   **Pros:** Easy to implement, zero cost, validates CLI routing.
*   **Cons:** **Leaky Abstractions.** The caller (`probe`, `orchestrate`) often assumes `spawn_agent` produced a result file or variable. When it returns `0` but produces nothing, the caller fails (e.g., trying to read a non-existent file) or hangs (looping forever waiting for a status change).
*   **Status:** Used currently. Causes failures in `test-probe-workflow.sh` and `test-dry-run-all.sh`.

### B. Industry Pattern: Service Virtualization (Mocking)
**Mechanism:**
```bash
function spawn_agent() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Mocking agent response..."
        cp "tests/fixtures/mock-response.json" "$OUTPUT_FILE" # <--- The Fix
        return 0
    fi
    # ... Real logic ...
}
```
*   **Pros:** executing the *entire* control flow. Downstream functions (parsers, synthesizers) run against mock data, validating the full pipeline, not just the start.
*   **Cons:** Requires maintaining mock fixtures.
*   **Relevance:** Standard in robust CLI tools (e.g., `aws-cli` stubbing, standard unit testing mocks).

### C. Industry Pattern: Plan & Apply (Terraform Style)
**Mechanism:**
1.  **Plan:** Generate a Directed Acyclic Graph (DAG) of actions.
2.  **Preview:** Show the DAG to the user (`terraform plan`).
3.  **Apply:** Execute the DAG.
*   **Pros:** Ultimate transparency and safety.
*   **Cons:** High architectural complexity. Requires separating "logic determination" from "execution."
*   **Relevance:** Ideal long-term goal for an Agent Orchestrator but likely too complex for an immediate fix.

## 3. Failure Analysis (Local Context)
Based on `reports/dry-run-analysis.md` and codebase search:

| Component | Failure Mode | Cause |
| :--- | :--- | :--- |
| **Probe Phase** | `Exit Code 1`, `WARN: No results` | `spawn_agent` returns early; `synthesize_results` runs but finds no input files to process. |
| **Ralph Loop** | **Hang / Timeout** | The optimization loop waits for an "improvement score." In dry-run, no score is generated, so the loop condition never breaks. |
| **Integration Tests** | False Positives | Some tests pass simply because they check for "no error output" rather than "correct workflow execution." |

## 4. Implementation Plan (Migration)

To fix the specific issues in `claude-octopus`, we should adopt the **Service Virtualization** pattern.

### Phase 1: Mocking the Agent Interface
Modify `spawn_agent` (or equivalent lower-level function) to produce dummy outputs when `DRY_RUN=true`.
*   **Input:** Prompt text.
*   **Output:** Write a generic Markdown/JSON response to the expected output path.
*   **Benefit:** Allows `synthesize_results` and other downstream processors to run without crashing.

### Phase 2: Mocking the Optimization Loop
Update the `ralph` / `optimize` logic to decrement a loop counter or return a "perfect score" mock during dry-runs.
*   **Fix:** Prevents infinite loops by simulating a successful optimization criteria being met immediately.

### Phase 3: Validation
Update `tests/smoke/test-dry-run-all.sh` to verify not just "exit code 0" but also the presence of mock artifacts in the final output.

## 5. Conclusion
The "What has been done before?" analysis shows that `claude-octopus` is currently in the naive "Early Return" stage. To achieve stability and useful testing, it must advance to the "Service Virtualization" stage, where dry-runs simulate data flow, not just control flow.
