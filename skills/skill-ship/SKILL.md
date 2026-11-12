---
name: skill-ship
disable-model-invocation: true
user-invocable: true
description: "Package and finalize an initialized project after delivery is complete"
trigger: |
  EXPLICITLY USE when the user asks to ship, finalize, or deliver the project.
---

# Ship project

Run only after an explicit user request. Keep this skill manually invoked. It
archives project state, records the shipped status, and creates a Git tag only
after the delivered source has a reviewed commit. Use `flow-deliver` for phase
validation; this skill finalizes an initialized project.

## 1. Check project state

Require `.octo/STATE.md`. Read fields through the state script's API, and query
phase 4 through `get_phase_status`. Markdown in `STATE.md` uses fields such as
`**Status:**`; grepping for `status:` does not read the canonical state.

Use the installation that loaded this skill. In Claude Code, use
`CLAUDE_PLUGIN_ROOT`; in Codex, use `CODEX_PLUGIN_ROOT`. If neither is set,
use an explicitly verified `OCTO_ROOT` or validate the stable installed fallback.
Do not select an installation from the project directory.

```bash
ship_check_readiness() {
SHIP_OVERRIDE_ARGUMENT="${1:-}"
SHIP_DELIVERY_OVERRIDE=0
case "$SHIP_OVERRIDE_ARGUMENT" in ''|--user-approved-override) ;; *) return 1 ;; esac
if [[ ! -d .octo || ! -f .octo/STATE.md ]]; then
    echo "Cannot ship: no initialized .octo/STATE.md project."
    return 1
fi

OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${DROID_PLUGIN_ROOT:-${OCTO_ROOT:-${HOME}/.claude-octopus/plugin}}}}"
OCTO_ROOT="$(cd -- "$OCTO_ROOT" && pwd -P)" || return 1
for required in scripts/octo-state.sh scripts/orchestrate.sh scripts/helpers/workflow-result.sh; do
    [[ -x "$OCTO_ROOT/$required" ]] || { echo "Cannot ship: installation is incomplete." >&2; return 1; }
done
STATE_TOOL="$OCTO_ROOT/scripts/octo-state.sh"
STATE_OUTPUT=$("$STATE_TOOL" read_state) || return 1
STATUS=$(printf '%s\n' "$STATE_OUTPUT" | sed -n 's/^status=//p')
CURRENT_PHASE=$(printf '%s\n' "$STATE_OUTPUT" | sed -n 's/^current_phase=//p')
DELIVER_STATUS=$("$STATE_TOOL" get_phase_status 4) || return 1
printf 'Status: %s\nCurrent phase: %s\nDeliver phase: %s\n' \
    "$STATUS" "$CURRENT_PHASE" "$DELIVER_STATUS"
if [[ "$DELIVER_STATUS" != complete ]]; then
    if [[ "$SHIP_OVERRIDE_ARGUMENT" != --user-approved-override ]]; then
        echo "Cannot ship: Deliver phase lacks completion evidence. Ask the user whether to explicitly override this gate." >&2
        return 1
    fi
    SHIP_DELIVERY_OVERRIDE=1
    echo "Readiness override: user requested ship anyway; delivery completion is not established."
else
    echo "Delivery completion evidence: phase 4 is complete."
fi
}
ship_check_readiness || exit 1
```

Shipping requires explicit delivery completion evidence:
`get_phase_status 4` must return `complete`. A status of `complete`, phase 4
being current, or history entries by themselves do not prove delivery passed.
If delivery is `in_progress`, `blocked`, `unknown`, or anything other than
`complete`, stop until the user completes `flow-deliver`.

An inherited environment variable never authorizes an override. Only after the
user explicitly approves shipping this incomplete run, repeat the readiness
block with its final call changed to
`ship_check_readiness --user-approved-override || exit 1`. Pass that literal
argument for the approved run; do not derive it from an environment variable.
Record the approval and readiness result in the run handoff. Describe delivery
completion evidence as absent. This override does not waive the audit, review,
clean-commit or tag checks below.

## 2. Run the delivery audit

**EXECUTION CONTRACT (MANDATORY - CANNOT SKIP)**

Use the installation root established above for execution and result
validation. Run `orchestrate.sh ink` and require a fresh validated report with
launcher status `COMPLETE`. Do not substitute a single-provider review or an
older report. If critical issues remain, stop shipping until the user resolves
them and reruns `flow-deliver`.

```bash
# Restore the loaded root when this step starts in a fresh shell.
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${DROID_PLUGIN_ROOT:-${OCTO_ROOT:-${HOME}/.claude-octopus/plugin}}}}"
bash "$OCTO_ROOT/scripts/helpers/ensure-plugin-root.sh" || exit 1
RUN_MARKER=$(mktemp) || exit 1
RUN_STATUS=0
OCTOPUS_WORKFLOW_INVOCATION_ID="${RUN_MARKER##*/}" \
    "$OCTO_ROOT/scripts/orchestrate.sh" ink \
    "Security audit for delivery - comprehensive review of code changes for production readiness" || RUN_STATUS=$?
REPORT_STATUS=0
VALIDATION_FILE=$("$OCTO_ROOT/scripts/helpers/workflow-result.sh" ink \
    "$RUN_MARKER" "$RUN_STATUS") || REPORT_STATUS=$?
rm -f "$RUN_MARKER"
[[ "$REPORT_STATUS" == 0 ]] || exit "$REPORT_STATUS"
echo "AUDIT COMPLETE: $VALIDATION_FILE"
```

Read the validated report and summarize its result, quality score, critical
issues, and warnings. Stop if it reports critical issues.

## 3. Capture lessons

Ask the user what went well, what should improve, and what they learned. They
may answer "skip". Append supplied lessons to `.octo/LESSONS.md`; do not archive
or delete that file. Count headings with one numeric result, including zero:

```bash
LESSON_COUNT=$(grep -c '^## ' .octo/LESSONS.md 2>/dev/null || true)
LESSON_COUNT=${LESSON_COUNT:-0}
echo "Lessons captured: $LESSON_COUNT"
```

## 4. Record shipped status and archive project state

Use the validated installation's state writer to update the canonical status
and append the shipping history entry. Keep the current phase. Do not edit
`STATE.md` with `sed` or replace its history.

```bash
: "${STATE_TOOL:?Restore the verified state tool}"
: "${VALIDATION_FILE:?Restore the validated delivery report}"
mkdir -p .octo/archive || exit 1
ARCHIVE="$(mktemp -d ".octo/archive/$(date -u '+%Y%m%d-%H%M%S').XXXXXX")" || exit 1
ARCHIVE_TIMESTAMP="${ARCHIVE##*/}"
"$STATE_TOOL" write_state --status shipped \
    --history "Project shipped; archive: $ARCHIVE; audit: $VALIDATION_FILE" || exit 1
for name in STATE.md PROJECT.md ROADMAP.md ISSUES.md; do
    if [[ -f ".octo/$name" ]]; then
        cp -- ".octo/$name" "$ARCHIVE/" || exit 1
    fi
done
printf 'Archive: %s\n' "$ARCHIVE"
ls -la -- "$ARCHIVE" || exit 1
```

The archive is reserved exclusively, so a second run cannot overwrite it.
`LESSONS.md` stays outside the archive. Preserve the run values and validated
report in the task context and restore them when starting a new shell.

Now inspect `git status`, the full diff, the archive, and `STATE.md`. Preserve
all unrelated user changes. Commit only the intended delivered source and
eligible state after review and within the existing authorized file scope.
If that scope is missing, stop before staging or committing. Preserve ignored state locally rather than adding it forcibly. If
`.octo` state or archives are ignored, disclose that the Git checkpoint captures
the committed source and excludes that local state. Preserve the local archive
separately; do not advertise the tag as a complete state backup.

Record the reviewed source commit as `SHIP_REVIEWED_HEAD`. Resume at the
checkpoint step with that commit clean and unchanged, while retaining the
already checked delivery and audit evidence. Do not rerun the readiness gate
against the now-shipped status. If the evidence was lost, stop and recover the
recorded handoff; `shipped` alone does not prove delivery passed.

```bash
git status --short
git diff -- .octo
git diff --cached -- .octo
```

Once the reviewed delivered-state commit is clean and verified, create the
checkpoint. Tagging is allowed only as part of the user's explicit shipping
request. Check the command result and the tag object before reporting success.

```bash
: "${ARCHIVE:?Restore the recorded archive path}"
: "${ARCHIVE_TIMESTAMP:?Restore the recorded archive timestamp}"
: "${SHIP_REVIEWED_HEAD:?Restore the reviewed delivered-source commit}"
[[ "$ARCHIVE" == ".octo/archive/$ARCHIVE_TIMESTAMP" && -d "$ARCHIVE" && -f "$ARCHIVE/STATE.md" ]] || { echo "Archive is incomplete." >&2; exit 1; }
SHIP_CURRENT_HEAD="$(git rev-parse HEAD)" || exit 1
SHIP_WORKTREE_STATUS="$(git status --porcelain)" || exit 1
[[ "$SHIP_CURRENT_HEAD" == "$SHIP_REVIEWED_HEAD" && -z "$SHIP_WORKTREE_STATUS" ]] || {
    echo "Cannot tag: preserve or commit intended changes, then review the current commit." >&2; exit 1;
}
SHIP_LOCAL_STATE=0
for state_path in .octo/STATE.md "$ARCHIVE/STATE.md"; do
    if git check-ignore -q -- "$state_path"; then
        SHIP_LOCAL_STATE=1
    else
        IGNORE_STATUS=$?
        [[ "$IGNORE_STATUS" == 1 ]] || exit "$IGNORE_STATUS"
        git ls-files --error-unmatch -- "$state_path" >/dev/null 2>&1 || {
            echo "Cannot tag: non-ignored state is absent from the reviewed commit." >&2; exit 1;
        }
    fi
done
SHIP_CURRENT_STATE="$("$STATE_TOOL" read_state)" || exit 1
printf '%s\n' "$SHIP_CURRENT_STATE" | grep -qx 'status=shipped' || exit 1
if [[ "$SHIP_LOCAL_STATE" == 1 ]]; then
    echo "Checkpoint scope: committed source only; ignored state and archive remain local."
else
    SHIP_COMMITTED_STATE="$(git show HEAD:.octo/STATE.md)" || exit 1
    printf '%s\n' "$SHIP_COMMITTED_STATE" | grep -qx '\*\*Status:\*\* shipped' || exit 1
fi
CHECKPOINT_TAG="octo-checkpoint-shipped-${ARCHIVE_TIMESTAMP}"
git tag -a "$CHECKPOINT_TAG" "$SHIP_REVIEWED_HEAD" -m "Project shipped - $(date '+%Y-%m-%d %H:%M:%S')" || exit 1
SHIP_TAG_COMMIT="$(git rev-parse --verify "refs/tags/${CHECKPOINT_TAG}^{commit}")" || exit 1
[[ "$SHIP_TAG_COMMIT" == "$SHIP_REVIEWED_HEAD" ]] || {
    echo "Checkpoint tag verification failed: $CHECKPOINT_TAG" >&2; exit 1;
}
echo "Checkpoint created: $CHECKPOINT_TAG"
```

Count issue and lesson metrics once each:

```bash
ISSUES_RESOLVED=$(grep -c '^\- \[x\]' .octo/ISSUES.md 2>/dev/null || true)
ISSUES_RESOLVED=${ISSUES_RESOLVED:-0}
LESSON_COUNT=$(grep -c '^## ' .octo/LESSONS.md 2>/dev/null || true)
LESSON_COUNT=${LESSON_COUNT:-0}
printf 'Issues resolved: %s\nLessons captured: %s\n' "$ISSUES_RESOLVED" "$LESSON_COUNT"
```

## 5. Report

Report shipping only after the verified tag exists. Include delivery evidence
or clearly identify the user's "ship anyway" override, the audit result,
archive path, checkpoint coverage, metrics, and tag. If tag creation or verification fails, report
that the project state was updated but the checkpoint was not created. Never
claim checkpoint success on a failed tag command.

Claude Code entries are `/octo:skill-ship`, `/octo:embrace` and `/octo:deliver`.
Codex users invoke `$skill-ship` and `$flow-deliver`. To initialize a project
in Codex, use the verified installation's CLI entry
`"$OCTO_ROOT/scripts/orchestrate.sh" embrace "<description>"`.
