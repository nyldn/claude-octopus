# Research: Test Task --dry-run Patterns

**Date:** January 17, 2026
**Subject:** Analysis of dry-run patterns in `claude-octopus` and industry comparison.

## 1. Context & Interpretation
The query "test task --dry-run" refers to the pattern of executing the `orchestrate.sh` CLI with a dummy prompt (e.g., "test task") and the `-n` / `--dry-run` flag. This is the primary mechanism used in `tests/smoke/test-dry-run-all.sh` and `tests/integration/test-value-proposition.sh` to validate system integrity without incurring LLM costs.

## 2. Current Implementation Analysis
The project uses a **Flag & Guard** pattern.

*   **Mechanism:** The `-n` flag sets a global `DRY_RUN=true` variable.
*   **Execution:** Critical functions (e.g., `spawn_agent`, `iterate_loop`) contain explicit checks:
    ```bash
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would execute: ..."
        return 0
    fi
    ```
*   **Scope:** Covers command routing, argument parsing, and high-level workflow orchestration (`probe`, `grasp`, `tangle`, `ink`, `embrace`).

## 3. What Worked (Successes)
*   **Speed & Cost:** Smoke tests run in seconds and cost $0, allowing `test-dry-run-all.sh` to be a viable pre-commit hook.
*   **User Transparency:** The dry-run output acts as an "Execution Plan" (e.g., "Would spawn 4 parallel research agents"), helping users understand complex multi-agent workflows before execution.
*   **Routing Validation:** Effectively proves that the complex `case` statements and flag parsing in `orchestrate.sh` are correct.

## 4. What Failed (Issues & Limitations)
*   **Logic Gaps (The "Early Return" Problem):** Because functions return immediately upon detecting dry-run, the code paths *downstream* (response parsing, file handling, state updates) are never exercised. This leads to bugs that only appear in production.
*   **Infinite Loops / Hangs:** As noted in `TESTING_STATUS.md` ("test-dry-run-all appears to hang"), loops that depend on agent output to terminate (e.g., the `ralph` iteration loop) can fail if the dry-run mock doesn't simulate the "completion promise" correctly.
*   **Test-Prod Parity:** The dry-run execution path is significantly different from the production path, reducing confidence that a passing dry-run means a working system.

## 5. Comparative Patterns & Recommendations

| Pattern | Description | vs. Current |
| :--- | :--- | :--- |
| **No-Op (Current)** | Log intent and return early. | **Current State.** Good for CLI args, bad for logic. |
| **Service Virtualization** | Execute full logic but mock external APIs. | **Recommended.** Instead of `return 0`, return a hardcoded JSON/Markdown string. |
| **Plan & Apply** | (Terraform style) Separate planning from execution phases. | **Ideal for Agents.** Generate the full prompt chain first, then execute. |

### Recommendation for `claude-octopus`
Refactor the dry-run logic from "Skip" to "Mock".
Instead of:
```bash
if [[ "$DRY_RUN" == "true" ]]; then return 0; fi
```
Use:
```bash
if [[ "$DRY_RUN" == "true" ]]; then
    echo "MOCKED RESPONSE"
    return 0
fi
```
This ensures downstream variables are populated, preventing hangs in loops that expect data.
