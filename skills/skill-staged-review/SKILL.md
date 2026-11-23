---
name: skill-staged-review
disable-model-invocation: true
aliases:
  - staged-review
  - two-stage-review
description: "Use when a PR or feature needs both specification and code-quality review"
trigger: |
  Use when completing a major feature, preparing a PR, or when user says
  "staged review", "full review", "review against spec", or "two-stage review".
  Do NOT use for quick code checks — use skill-code-review instead.
execution_mode: enforced
validation_gates:
  - stage1_complete
  - stage2_complete
codex_short_description: "Check specification compliance, then review code quality"
---

# Two-Stage Review Pipeline

Separates **spec compliance** (did you build the right thing?) from **code quality**
(did you build it right?). Stage 1 must pass before Stage 2 runs.

---

## Stage 1: Spec Compliance

Validates the implementation against the intent contract.

### Step 1: Load Intent Contract

```bash
PLAN_STORAGE="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/plan-storage.sh"
OCTO_PLAN_DIR="$("$PLAN_STORAGE" current "$PWD" 2>/dev/null || true)"
INTENT_FILE="${OCTO_PLAN_DIR:+${OCTO_PLAN_DIR}/session-intent.md}"
if [[ -f "$INTENT_FILE" ]]; then
  echo "Intent contract found: $INTENT_FILE"
  cat "$INTENT_FILE"
else
  echo "WARNING: No current resolved intent contract found for this workspace"
  echo "Skipping Stage 1 — proceeding to Stage 2 (code quality) only."
fi
```

**If no intent contract exists:** Warn the user and skip to Stage 2. Do NOT fabricate
success criteria — the contract must exist from a prior workflow.

### Step 2: Validate Success Criteria

For each success criterion in the intent contract:

1. **Read the criterion** from the `## Success Criteria` section
2. **Find evidence** in the codebase that the criterion is met
3. **Mark status:**
   - `[PASS]` — Evidence confirms criterion is met
   - `[FAIL]` — Evidence shows criterion is NOT met
   - `[PARTIAL]` — Partially met, gaps identified

Present results:

```markdown
## Stage 1: Spec Compliance

### Success Criteria Check

#### Good Enough Criteria
- [PASS] Criterion 1: <how it was met>
- [FAIL] Criterion 2: <why not met, what's missing>

#### Exceptional Criteria
- [PARTIAL] Criterion 1: <what's done, what's remaining>
```

### Step 3: Validate Boundaries

For each boundary in the intent contract:

1. **Read the boundary** from the `## Boundaries` section
2. **Check for violations** in the implementation
3. **Mark status:**
   - `[RESPECTED]` — No violations found
   - `[VIOLATED]` — Implementation crosses the boundary

```markdown
### Boundary Check
- [RESPECTED] Boundary 1: <confirmation>
- [VIOLATED] Boundary 2: <what violated it>
```

### Step 4: Stage 1 Gate

| Result | Action |
|--------|--------|
| All criteria PASS + all boundaries RESPECTED | Proceed to Stage 2 |
| Any criterion FAIL | Report failures. Ask user: fix now or proceed anyway? |
| Any boundary VIOLATED | Report violations. Ask user: fix now or proceed anyway? |

**If user chooses to fix:** Stop review, list specific fixes needed.
**If user chooses to proceed:** Note the overrides and continue to Stage 2.

---

## Stage 2: Code Quality

Runs stub detection and full code quality review.

### Step 1: Admit the staged snapshot and check for stubs

Capture one immutable staged tree. The admission block below checks its
changed source files for stubs, placeholders and short files, then returns
the complete staged diff for the quality review. Deleted files remain in
the diff and have no staged file to scan.

### Step 2: Multi-LLM Quality Review (RECOMMENDED)

**After admitting and scanning the staged snapshot, dispatch its diff for parallel quality review.** A Claude-only review pipeline misses what external models catch — Codex excels at logic errors and correctness, while Antigravity provides an independent security and edge-case analysis. Using both produces higher-confidence findings.

**Admit the staged snapshot before checking provider availability:**

```bash
# Admit the complete staged text before any review. Do not substitute another
# range when staged input is empty or cannot be read.
DIFF_CONTENT=$(python3 -I - <<'PY_STAGED_DIFF'
import os
import re
import subprocess
import sys

# write-tree refuses unresolved index entries and freezes the admitted index.
staged = subprocess.check_output(['git', 'write-tree']).decode().strip()
head = subprocess.run(['git', 'rev-parse', '--verify', '--quiet', 'HEAD^{tree}'],
                      capture_output=True, text=True)
if head.returncode == 0:
    base = head.stdout.strip()
else:
    # Only a confirmed unborn branch may use an empty baseline. Other HEAD
    # discovery errors must stop rather than silently changing the review range.
    branch = subprocess.check_output(['git', 'symbolic-ref', '--quiet', 'HEAD']).decode().strip()
    if subprocess.run(['git', 'show-ref', '--verify', '--quiet', branch]).returncode != 1:
        sys.exit('Review incomplete: cannot resolve the staged review baseline.')
    base = subprocess.check_output(['git', 'hash-object', '-w', '-t', 'tree', '--stdin'],
                                   input=b'').decode().strip()
command = ['git', 'diff', '--no-ext-diff', '--no-textconv',
           '--no-renames', '--no-relative', '--ignore-submodules=none', '--no-color']
numstat = subprocess.check_output(command + ['--numstat', base, staged, '--'])
if any(line.split(b'\t', 2)[:2] == [b'-', b'-'] for line in numstat.splitlines()):
    sys.exit('Review incomplete: staged binary content needs separate complete review.')
raw = subprocess.check_output(command + ['--raw', '--no-abbrev', '-z', base, staged, '--'])
blobs = set()
sources = []
source_suffixes = (b'.ts', b'.tsx', b'.js', b'.jsx', b'.py', b'.go', b'.rs', b'.sh')
fields = raw.split(b'\0')
for header, path in zip(fields[::2], fields[1::2]):
    old_mode, new_mode, old_oid, new_oid, _ = header.split()
    if old_mode == b':160000' or new_mode == b'160000':
        sys.exit('Review incomplete: staged submodules need separate complete source review.')
    blobs.update(oid for oid in (old_oid, new_oid) if oid.strip(b'0'))
    if new_mode in (b'100644', b'100755') and path.endswith(source_suffixes):
        sources.append((path, new_oid))
# Forced-text attributes can hide NUL bytes outside the patch context. Inspect
# both affected revisions in bounded chunks, including deleted file content.
for oid in sorted(blobs):
    with subprocess.Popen(['git', 'cat-file', 'blob', oid.decode('ascii')],
                          stdout=subprocess.PIPE) as blob:
        while chunk := blob.stdout.read(65536):
            if b'\0' in chunk:
                blob.kill()
                sys.exit('Review incomplete: a changed blob contains NUL bytes and needs separate complete review.')
        if blob.wait() != 0:
            sys.exit('Review incomplete: could not read a changed blob.')
diff = subprocess.check_output(command + ['--binary', base, staged, '--'])
if re.search(rb'(?m)^GIT binary patch$', diff) or b'\0' in diff:
    sys.exit('Review incomplete: staged nontext content needs separate complete review.')
if re.search(rb'\[\[OCTOPUS_TRUSTED_JSON_CONTRACT_(?:BEGIN|END):[0-9a-fA-F]{32}\]\]', diff):
    sys.exit('Review incomplete: transport markers need separate lossless review.')
if not diff:
    sys.exit('Review incomplete: no staged changes. Select the intended review range explicitly.')
if len(diff) > 60000:
    sys.exit('Review incomplete: staged input exceeds the 60000-byte quick-review limit. Arrange complete file-based review.')
# Scan the postimage blobs from the admitted tree. Never reopen worktree paths.
checks = (
    (re.compile(rb'TODO|FIXME|PLACEHOLDER|XXX'), 'TODO/FIXME markers'),
    (re.compile(rb'(function.*\{\s*\}|=>\s*\{\s*\})'), 'empty functions'),
    (re.compile(rb'return (null|undefined);'), 'null/undefined returns'),
    (re.compile(rb'const.*(mock|test|dummy|fake).*='), 'mock/test data references'),
)
non_substantive = re.compile(rb'^\s*(//|/\*|\*|#|import|export|$)')
issues = 0
for path, oid in sources:
    counts = [0] * len(checks)
    substantive = 0
    with subprocess.Popen(['git', 'cat-file', 'blob', oid.decode('ascii')],
                          stdout=subprocess.PIPE) as blob:
        for line in blob.stdout:
            for index, (pattern, _) in enumerate(checks):
                if pattern.search(line):
                    counts[index] += 1
            if not non_substantive.match(line):
                substantive += 1
        if blob.wait() != 0:
            sys.exit('Review incomplete: could not scan a staged source blob.')
    label = ascii(os.fsdecode(path))
    for count, (_, description) in zip(counts, checks):
        if count:
            print(f'WARNING: {label} has {count} {description}', file=sys.stderr)
            issues += 1
    if substantive < 5:
        print(f'WARNING: {label} has only {substantive} substantive lines', file=sys.stderr)
        issues += 1
print(f'Stub detection complete: {len(sources)} source files scanned, {issues} issues found',
      file=sys.stderr)
print(f'Review snapshot: base tree {base}, staged tree {staged}', file=sys.stderr)
sys.stdout.buffer.write(diff)
PY_STAGED_DIFF
) || exit 1
```

If this admission step fails, stop before provider dispatch or a clean-review
claim. Binary and submodule changes require a separate complete content review;
their Git notices and object IDs do not establish source coverage. Keep the
entire admitted text in the prompt, including its final lines. Review covers
the printed immutable staged snapshot; later staging requires a fresh review.

**If external providers are available — dispatch focused reviews through Octopus routing:**
```bash
providers=()
command -v codex >/dev/null 2>&1 && providers+=(codex)
command -v agy >/dev/null 2>&1 && providers+=(agy)

for provider in "${providers[@]}"; do
  safe_provider=$(printf '%s' "$provider" | tr -c '[:alnum:]_-' '_')
  "${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/orchestrate.sh" spawn "$provider" \
    "Review this code diff for LOGIC, CORRECTNESS, and SECURITY issues. Focus on:
1. Logic bugs and off-by-one errors
2. Unhandled error paths
3. Race conditions or concurrency issues
4. Incorrect type handling or implicit coercions
5. Security issues at trust boundaries

Report ONLY high-confidence issues. Do NOT flag style preferences.

DIFF:
${DIFF_CONTENT}" > "/tmp/octopus-review-${safe_provider}.md" 2>/dev/null &
done
```

**Wait for external reviews to complete, then synthesize all findings from Claude plus available external providers into a unified quality assessment.** If external providers are unavailable, fall back to the Claude-only review below.

**Claude (you) performs the full quality review regardless:**

1. **Architecture alignment** — Does the code follow project patterns?
2. **Error handling** — Are errors caught and handled appropriately?
3. **Security** — Any OWASP Top 10 issues?
4. **Performance** — Any obvious bottlenecks or N+1 queries?
5. **Readability** — Clear naming, reasonable complexity?
6. **Test coverage** — Are new behaviors tested?

**Synthesize external findings:** If external providers returned results, merge their findings with yours. Where providers disagree on severity, note the divergence. Where multiple providers flag the same issue, mark it as high-confidence.

### Step 3: Present Stage 2 Results

```markdown
## Stage 2: Code Quality

### Stub Detection
- Files scanned: N
- Issues found: N
- [Details of each issue]

### Quality Review
- Architecture: [PASS/WARN/FAIL]
- Error Handling: [PASS/WARN/FAIL]
- Security: [PASS/WARN/FAIL]
- Performance: [PASS/WARN/FAIL]
- Readability: [PASS/WARN/FAIL]
- Test Coverage: [PASS/WARN/FAIL]

### Blocking Issues
[List any issues that must be fixed before merge]

### Recommendations
[Non-blocking suggestions for improvement]
```

---

## Combined Report

After both stages complete, present the unified report:

```markdown
## Staged Review — Complete

### Stage 1: Spec Compliance
- Success Criteria: N/N passed
- Boundaries: N/N respected
- Verdict: [PASS/FAIL]

### Stage 2: Code Quality
- Stub Detection: N issues
- Quality Score: [HIGH/MEDIUM/LOW]
- Blocking Issues: N
- Verdict: [PASS/FAIL]

### Overall Verdict: [PASS/FAIL]

[If FAIL: list specific items that must be addressed]
[If PASS: ready for merge/ship]
```

---

## When to Use Each Review Type

| Review Type | When | What It Checks |
|-------------|------|----------------|
| **skill-code-review** | Quick PR review | Code quality only |
| **skill-staged-review** | Major feature completion | Spec compliance + code quality |
| **skill-verification-gate** | Before any completion claim | Evidence of passing |

---

## Error Handling

| Error | Resolution |
|-------|------------|
| No intent contract | Skip Stage 1, warn user, run Stage 2 only |
| No changed files | Report nothing to review |
| Git not available | Use file listing instead of git diff |
| Stage 1 failures | Ask user: fix or override |
| Stage 2 blocking issues | Must fix before merge |

---

## The Bottom Line

```
Staged Review = Spec Compliance (Stage 1) + Code Quality (Stage 2)
Stage 1 gates Stage 2. Both must pass for overall PASS.
```

**Build the right thing, then build it right.**

---

## Post Results to PR (v8.44.0)

After the combined report is generated, check for an open PR and post findings.

```bash
# Detect open PR on current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
PR_NUM=""

if [[ -n "$CURRENT_BRANCH" && "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "master" ]]; then
    if command -v gh &>/dev/null; then
        PR_NUM=$(gh pr list --head "$CURRENT_BRANCH" --json number --jq '.[0].number' 2>/dev/null || echo "")
    fi
fi

if [[ -n "$PR_NUM" ]]; then
    # Post combined report through the outbound credential gate.
    REPO_SLUG=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
    COMMENT_BODY="## Staged Review — Claude Octopus

${COMBINED_REPORT}

---
*Staged review by Claude Octopus (/octo:staged-review)*"
    if ! "${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/safe-gh-comment.sh" \
            --repo "$REPO_SLUG" pr-comment "$PR_NUM" - <<< "$COMMENT_BODY"; then
        echo "GitHub write state is unknown; check for the staged review comment before retrying:" >&2
        gh pr view "$PR_NUM" --repo "$REPO_SLUG" --comments || true
        return 1 2>/dev/null || exit 1
    fi

    echo "Staged review posted to PR #${PR_NUM}"
fi
```

**Behavior:**
- Auto-posts when running inside `/octo:deliver` or `/octo:embrace` workflows
- Asks user first when invoked standalone via `/octo:staged-review`

## Execution Contract (MANDATORY - CANNOT SKIP)

This generated Claude Code skill preserves an enforced workflow contract from the source skill.

**PROHIBITED:**
- Do not summarize, simulate, or skip the referenced workflow command when this skill requires execution.
- Do not claim provider output or validation artifacts exist without checking the actual files or command output.
- Do not continue silently when a required provider, command, or host capability is unavailable; report the unavailable dependency and use a supported fallback.
