# Claude Code v2.1+ Update Research & Implementation Plan

**Date:** January 28, 2026
**Target Version:** Claude Code v2.1.20+
**Goal:** Enhance Claude Octopus with new upstream features for autonomous operation.

## 1. Executive Summary

Recent updates to Claude Code (v2.1.20 through v2.1.23) have introduced features specifically targeting reliability in non-interactive modes, file operation stability, and UI customization. These updates align perfectly with the "Octopus" vision of a multi-agent, autonomous engineering platform. This plan outlines how to leverage these features to create a more robust "autonomous mode" and improve the user experience.

## 2. Feature Analysis (v2.1.20 - v2.1.23)

### 2.1 Customizable Spinner Verbs (v2.1.23)
*   **Feature:** A new setting `spinnerVerbs` allows customization of the loading state text.
*   **Opportunity:** We can replace generic verbs (Thinking, Processing) with "Octopus-themed" verbs (Synthesizing, Orchestrating, Tentacles Reaching, Ink Spreading).
*   **Impact:** High delight, improved branding, and immediate visual feedback that the "Octopus" plugin is active.

### 2.2 File Tool Preference (v2.1.21)
*   **Feature:** Claude now has an explicit preference for using internal file operation tools (`WriteFile`, `ReplaceString`) over bash-based text manipulation (`sed`, `echo`).
*   **Opportunity:** We should explicitly bake this preference into our expert personas (`backend-architect`, `implementer`). Previous personas often relied on shell commands which could be brittle with escaping.
*   **Impact:** Higher success rate for complex code generation and refactoring tasks.

### 2.3 Non-Interactive Structured Output Fix (v2.1.22)
*   **Feature:** Fixed a bug where structured outputs (JSON/XML) were unreliable in non-interactive (`-p`) mode.
*   **Opportunity:** This is critical for the `orchestrate.sh` script and `skill-iterative-loop`. We can now reliably parse JSON status updates from background agents without fear of truncation or formatting errors.
*   **Impact:** "Deep Autonomy" where agents can communicate state reliably without user supervision.

### 2.4 Timeout & Progress Display (v2.1.23)
*   **Feature:** Bash commands now show timeout durations, and search progress is improved.
*   **Opportunity:** We can tune our long-running tasks (like `test-all` or `audit`) to set appropriate timeouts and rely on the UI to inform the user, reducing the need for "please wait" chatter.

## 3. Implementation Plan

### Phase 1: Thematic Immersion (Configuration)
**Goal:** Make Claude Octopus feel like a distinct platform.

1.  **Update `hooks/setup-hook.md`**:
    *   Add a step to configure `spinnerVerbs` in the global or project Claude config.
    *   *Proposed Verbs:* `["Orchestrating", "Synthesizing", "Analyzing", "Reasoning", "Connecting", "Weaving", "Reviewing"]`

### Phase 2: Robust Autonomy (Personas)
**Goal:** Reduce "brittle" shell-based file edits.

1.  **Update `agents/personas/*.md`**:
    *   Inject a standard "Tooling Directive" into the base prompt of all engineering personas.
    *   *Directive:* "PREFERRED TOOLS: Always use `WriteFile` and `ReplaceString` for file modifications. Do NOT use `sed`, `awk`, or `echo` for file editing unless strictly necessary. Reliability is paramount."

### Phase 3: Feedback Loops (Skills)
**Goal:** Enable self-correcting autonomous loops.

1.  **Update `skills/skill-iterative-loop.md`**:
    *   Enhance the "Progress Tracking" section to suggest using JSON output blocks for machine-readable status if running in `-p` mode.
    *   Leverage the v2.1.22 fix to allow the loop controller to parse these statuses reliably.

### Phase 4: "Deep Autonomy" Mode (New Skill)
**Goal:** A "fire and forget" mode for long tasks.

1.  **Create `skills/skill-autonomous-mode.md`**:
    *   **Trigger:** "work on this in the background", "autonomous mode", "take the wheel".
    *   **Behavior:**
        *   Sets `spinnerVerbs` to "Autonomous" set.
        *   Enables `skill-iterative-loop` by default.
        *   Sets a higher timeout for shell commands.
        *   Uses `WriteFile` exclusively.
        *   Suppresses non-essential output (Quiet Mode).

## 4. Immediate Next Steps

1.  Modify `hooks/setup-hook.md` to inject the new configuration.
2.  Update `agents/personas/backend-architect.md` as a pilot for the new tooling directives.
