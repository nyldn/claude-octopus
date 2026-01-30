# Plan: Claude Octopus v2.2 Migration (Leveraging Claude Code v2.1.20+)

## 1. Executive Summary
This plan outlines the technical steps to modernize the `claude-octopus` plugin to fully leverage the new features introduced in Claude Code versions v2.1.20 through v2.1.23. The goal is to enhance autonomy, improve stability, and simplify the architecture by replacing custom implementations with native Claude Code primitives.

**Key Drivers:**
*   **Autonomy:** Utilize Background Agents (v2.0.60) and native Task Management (v2.1.16) for self-directed workflows.
*   **Integration:** Adopt the MCP Registry (v2.1.23) and native Hooks (v2.1.0+) for tighter system integration.
*   **Simplification:** Replace custom agent orchestration with native Agent configurations and Skills.

## 2. Prerequisites
To execute this plan, the environment must meet the following requirements:
*   **Claude Code Version:** >= v2.1.23
*   **Environment Variables:**
    *   `CLAUDE_CODE_ENABLE_TASKS=1` (Enables native task system)
    *   `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` (Allows modular `CLAUDE.md` loading)

## 3. Core Migration Areas

### 3.1. Native Hooks Architecture
**Current State:** Custom shell scripts (`hooks/`) and markdown descriptions (`hooks/setup-hook.md`) triggered via manual orchestration.
**Target State:** Native Event Hooks defined in `.claude/hooks/` or agent frontmatter.

*   **Setup Hook:** Migrate `hooks/setup-hook.md` logic to a native `Setup` hook that responds to `--init`.
    *   *Action:* Create `.claude/hooks/setup.sh` (or define in `plugin.json` if supported) that runs `scripts/orchestrate.sh init`.
*   **Lifecycle Hooks:** Implement `SubagentStart` and `SubagentStop` hooks to track and manage the multi-agent lifecycle natively.
    *   *Action:* Add hook definitions to `agents/config.yaml` to be injected into generated agent configs.
*   **Quality Gates:** Convert `hooks/quality-gate.sh` to a `PreToolUse` hook that intercepts critical actions (like `git push`) and enforces checks.

### 3.2. Native Agent & Task Integration
**Current State:** Custom `agents/config.yaml` mapped to CLI commands; custom "Ralph Wiggum" loop for iteration.
**Target State:** Native Agent API usage with Background Agents and Task System.

*   **Background Agents:** Update `multi.md` and `parallel-agents` skill to explicitly use the `&` background operator or `context: background` setting.
    *   *Benefit:* Allows true parallel execution of "octopus tentacles" without blocking the user.
*   **Native Tasks:** Replace "Ralph Wiggum" iteration with the Native Task system.
    *   *Action:* Update `skill-task-management.md` to utilize the `TaskUpdate` tool.
    *   *Feature:* Use dependency tracking for complex, multi-stage workflows (e.g., "Develop" phase depends on "Design" phase tasks).
*   **Agent Configuration:** Update `agents/config.yaml` translation logic to output native `agent` settings (System Prompt, Tool Restrictions, Model) directly to the session.

### 3.3. MCP & Provider Integration
**Current State:** Custom "provider-routing" logic.
**Target State:** Native MCP Integration.

*   **Registry:** Use the new MCP Registry features to discover and configure external tools (e.g., for specialized research or coding tasks).
*   **Dynamic Updates:** Leverage dynamic tool updates (v2.1.0) to allow agents to "learn" new capabilities mid-session without restart.

## 4. Implementation Plan

### Phase 1: Foundation (Hooks & Setup)
1.  **Refactor `hooks/`:**
    *   Rename `hooks/setup-hook.md` to `.claude/hooks/Setup.md` (or equivalent supported format).
    *   Verify `--init` trigger works with native `Setup` event.
2.  **Modular Config:**
    *   Ensure `CLAUDE.md` and `plugin.json` are structured to be loaded via `--add-dir` if intended for external use.

### Phase 2: Autonomy (Agents & Tasks)
1.  **Update Agent Skills:**
    *   Modify `skill-parallel-agents.md` to use `&` for background execution.
    *   Add `agent` field to skill frontmatter to enforce specific personas (e.g., `agent: backend-architect`).
2.  **Implement Task System:**
    *   Refactor `skill-task-management.md` to instruct the model to use `TaskCreate`, `TaskUpdate` (with dependencies), and `TaskDelete` tools.
    *   Remove legacy "Ralph Wiggum" looping logic in favor of `status: failed` task updates which naturally prompt retry.

### Phase 3: Safety & Integration (MCP & Gates)
1.  **Security Hooks:**
    *   Implement `PreToolUse` hook for `bash` and `git` tools to enforce `quality-gate.sh` logic natively.
    *   Use `PermissionRequest` hooks to auto-grant known safe read-only operations while prompting for writes.
2.  **MCP Migration:**
    *   Review `provider-routing-validator.sh` and see if it can be replaced by querying the MCP Registry.

## 5. Success Metrics
*   **Autonomy:** Complex multi-step workflows (e.g., "Research and Plan") run to completion with < 1 user intervention.
*   **Performance:** Parallel agents reduce total wall-clock time for "Tangle" phase by 30%.
*   **Code Simplification:** Reduction of custom orchestration shell script lines by ~20%.
