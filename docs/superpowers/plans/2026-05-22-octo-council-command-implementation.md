# Octo Council Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first production slice of `/octo:council`: command registration, skill docs, deterministic flag parsing, council recommendation dry-run, budget validation, artifact scaffolding, and tests.

**Architecture:** Add `scripts/lib/council.sh` as the command's shell library and keep `scripts/orchestrate.sh` limited to sourcing and routing. The first slice avoids provider fanout and implements deterministic preflight/dry-run behavior so later phases can add dispatch safely behind tested contracts.

**Tech Stack:** Bash, existing Claude Code plugin command manifests, `jq` for JSON validation, existing shell test framework.

---

## File Map

- Create: `scripts/lib/council.sh` - parser, defaults, budget validation, council recommendation, summary JSON, dry-run command handler.
- Create: `.claude/commands/council.md` - Claude Code slash command wrapper.
- Create: `skills/skill-council/SKILL.md` - reusable council workflow skill.
- Create: `tests/unit/test-council-command.sh` - unit coverage for parser, defaults, cost validation, JSON schema, fixture env.
- Create: `tests/smoke/test-council-command.sh` - command-level smoke coverage for help and dry-run.
- Modify: `scripts/orchestrate.sh` - source `council.sh` and route `council` command.
- Modify: `scripts/lib/usage-help.sh` - command-specific help entry.
- Modify: `.claude-plugin/plugin.json` - register command and skill.

## Task 1: Command Registration And Help

**Files:**
- Create: `.claude/commands/council.md`
- Create: `skills/skill-council/SKILL.md`
- Modify: `.claude-plugin/plugin.json`
- Modify: `scripts/orchestrate.sh`
- Modify: `scripts/lib/usage-help.sh`
- Test: `tests/unit/test-council-command.sh`

- [ ] **Step 1: Write the failing registration test**

Create `tests/unit/test-council-command.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Council Command"

test_council_command_files_are_registered() {
    test_case "Council command and skill are registered"

    local command_file="$PROJECT_ROOT/.claude/commands/council.md"
    local skill_file="$PROJECT_ROOT/skills/skill-council/SKILL.md"
    local plugin_file="$PROJECT_ROOT/.claude-plugin/plugin.json"

    [[ -f "$command_file" ]] || { test_fail "Missing $command_file"; return 1; }
    [[ -f "$skill_file" ]] || { test_fail "Missing $skill_file"; return 1; }

    if jq -e '.commands[] | select(. == "./.claude/commands/council.md")' "$plugin_file" >/dev/null &&
       jq -e '.skills[] | select(. == "./skills/skill-council")' "$plugin_file" >/dev/null; then
        test_pass
    else
        test_fail "plugin.json missing council command or skill"
        return 1
    fi
}

test_council_orchestrate_route_exists() {
    test_case "orchestrate.sh routes council command"

    if grep -q 'council)' "$PROJECT_ROOT/scripts/orchestrate.sh" &&
       grep -q 'council_run' "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "council route missing"
        return 1
    fi
}

test_council_command_files_are_registered
test_council_orchestrate_route_exists
test_summary
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
bash tests/unit/test-council-command.sh
```

Expected: fails because `council.md`, `skill-council`, and route do not exist yet.

- [ ] **Step 3: Add minimal command and skill registration**

Add `.claude/commands/council.md`:

```markdown
---
command: council
description: "Multi-LLM council for advice, decision support, implementation plans, and gated implementation"
skill: skill-council
---

# Council

Use `/octo:council <task>` when the user wants a structured council of multiple LLM personas to advise, critique, synthesize, and optionally hand off an approved implementation plan.

Run through `skill-council`. Do not skip provider/cost preflight, quorum checks, or implementation gates.
```

Add `skills/skill-council/SKILL.md`:

```markdown
---
name: skill-council
description: "Run a configurable multi-LLM council with personas, budget caps, synthesis, veto gates, and optional implementation handoff."
---

# Council

Use this skill for `/octo:council` and council-style requests.

Start with preflight: goal, domain, style, depth, members, budget, providers, personas, and implementation permission. Default to dry-run style explanation when the user has not approved implementation.

Preserve disagreement, summarize risks, and require explicit approval before any implementation handoff.
```

In `.claude-plugin/plugin.json`, add:

```json
"./skills/skill-council"
```

to `skills`, and:

```json
"./.claude/commands/council.md"
```

to `commands`.

In `scripts/orchestrate.sh`, add:

```bash
source "${SCRIPT_DIR}/lib/council.sh" 2>/dev/null || true
```

near the other `scripts/lib/*.sh` sources, and add the route:

```bash
council)
    council_run "$@"
    ;;
```

In `scripts/lib/usage-help.sh`, add a `usage_command` branch:

```bash
council)
    cat << EOF
${YELLOW}council${NC} - Multi-LLM council advice and gated implementation

${YELLOW}Usage:${NC} $(basename "$0") council [OPTIONS] <task>

${YELLOW}Options:${NC}
  --goal advice|decision|plan|implement|review
  --domain auto|architecture|product|security|business|research|docs
  --style balanced|adversarial|implementation|executive|red-team
  --depth quick|standard|deep
  --members auto|3|5|7
  --persona <name>[,<name>]
  --implement never|after-approval|plan-only
  --worktree auto|on|off
  --benchmark auto|on|off
  --providers auto|claude,codex,agy,opencode,openrouter
  --max-cost <usd>
  --dry-run
  --json
  --output-dir <path>
EOF
    ;;
```

- [ ] **Step 4: Run the test and verify GREEN**

Run:

```bash
bash tests/unit/test-council-command.sh
```

Expected: passes registration tests.

## Task 2: Parser, Defaults, And Dry-Run Artifact

**Files:**
- Create: `scripts/lib/council.sh`
- Modify: `tests/unit/test-council-command.sh`
- Test: `tests/unit/test-council-command.sh`

- [ ] **Step 1: Add failing parser/dry-run tests**

Append tests that source `scripts/lib/council.sh` and assert:

```bash
test_council_defaults_are_depth_aware() {
    test_case "Council defaults are depth aware"
    source "$PROJECT_ROOT/scripts/lib/council.sh"
    council_parse_args --depth standard --dry-run "Review auth"
    [[ "$COUNCIL_DEPTH" == "standard" ]] || { test_fail "depth not parsed"; return 1; }
    [[ "$COUNCIL_MEMBERS" == "auto" ]] || { test_fail "members default not auto"; return 1; }
    [[ "$COUNCIL_RESOLVED_MEMBERS" == "5" ]] || { test_fail "standard should resolve to 5 members"; return 1; }
    [[ "$COUNCIL_MAX_COST" == "2.00" ]] || { test_fail "standard default budget should be 2.00"; return 1; }
    test_pass
}

test_council_rejects_non_usd_budget() {
    test_case "Council rejects non-USD budget values"
    source "$PROJECT_ROOT/scripts/lib/council.sh"
    set +e
    council_parse_args --max-cost '$2.00' "Review auth" >/tmp/council-budget.out 2>&1
    local status=$?
    set -e
    [[ $status -eq 2 ]] || { test_fail "expected exit code 2, got $status"; return 1; }
    grep -q "USD decimal" /tmp/council-budget.out || { test_fail "missing usage hint"; return 1; }
    test_pass
}

test_council_dry_run_writes_summary_json() {
    test_case "Council dry-run writes summary JSON"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    source "$PROJECT_ROOT/scripts/lib/council.sh"
    council_run --dry-run --goal advice --depth quick --output-dir "$tmp_dir" "Should we use Redis?"
    local summary
    summary="$(find "$tmp_dir" -name summary.json -type f | head -1)"
    [[ -n "$summary" ]] || { test_fail "summary.json not written"; return 1; }
    jq -e '.command == "council" and .status == "dry-run" and .implementation.worktree == "auto"' "$summary" >/dev/null || {
        test_fail "summary JSON contract mismatch"
        return 1
    }
    test_pass
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
bash tests/unit/test-council-command.sh
```

Expected: fails because `scripts/lib/council.sh` does not exist.

- [ ] **Step 3: Implement minimal `scripts/lib/council.sh`**

Implement exported functions:

```bash
council_usage
council_parse_args
council_resolve_defaults
council_validate_budget
council_create_run_dir
council_write_summary_json
council_run
```

Keep first-slice behavior deterministic:

- no provider fanout
- no file edits
- `--dry-run` always writes `summary.json`
- non-USD `--max-cost` exits `2`
- `OCTOPUS_COUNCIL_FIXTURE` is accepted only for tests

- [ ] **Step 4: Run tests and verify GREEN**

Run:

```bash
bash tests/unit/test-council-command.sh
```

Expected: all unit tests pass.

## Task 3: Smoke Test And Syntax Coverage

**Files:**
- Create: `tests/smoke/test-council-command.sh`
- Test: `tests/smoke/test-council-command.sh`

- [ ] **Step 1: Write smoke tests**

Create `tests/smoke/test-council-command.sh` with checks for:

- `scripts/orchestrate.sh council --help` shows `--max-cost`
- `scripts/orchestrate.sh council --dry-run --output-dir "$tmp" "Should we use Redis?"` writes valid `summary.json`
- `OCTOPUS_COUNCIL_FIXTURE=critical-veto scripts/orchestrate.sh council --dry-run ...` records fixture mode in summary

- [ ] **Step 2: Run smoke test and verify RED/GREEN as needed**

Run:

```bash
bash tests/smoke/test-council-command.sh
```

Expected after implementation: pass.

## Task 4: Validation And Commit

**Files:**
- All changed files above.

- [ ] **Step 1: Run focused validation**

Run:

```bash
bash tests/unit/test-council-command.sh
bash tests/smoke/test-council-command.sh
bash tests/unit/test-command-frontmatter.sh
jq empty .claude-plugin/plugin.json
bash -n scripts/lib/council.sh scripts/orchestrate.sh scripts/lib/usage-help.sh
git diff --check
```

- [ ] **Step 2: Commit first implementation slice**

Run:

```bash
git add -f docs/superpowers/plans/2026-05-22-octo-council-command-implementation.md
git add .claude/commands/council.md skills/skill-council/SKILL.md scripts/lib/council.sh scripts/orchestrate.sh scripts/lib/usage-help.sh .claude-plugin/plugin.json tests/unit/test-council-command.sh tests/smoke/test-council-command.sh
git commit -m "feat: start octo council command"
```

## Follow-On Tasks

- Add benchmark snapshot ingestion and freshness decay.
- Add provider availability and provider diversity scoring.
- Add real Phase 1 fanout with read-only sandbox enforcement.
- Add Phase 2 critique, Phase 3 revision, Phase 4 synthesis.
- Add Phase 5 veto schema and Phase 6 implementation handoff.
- Add release/version/changelog once the command is fully implemented.
