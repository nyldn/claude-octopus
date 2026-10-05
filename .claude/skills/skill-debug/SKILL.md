---
name: skill-debug
disable-model-invocation: true
aliases:
  - debug
  - systematic-debugging
description: "Debug a reproducible symptom with a bounded feedback loop and original-scenario verification"
trigger: |
  Use for reproducible bugs, failing tests, unexpected behavior, and performance regressions.
  Do not use for general explanations or already-understood changes.
pre_execution_contract:
  - observable_symptom_recorded
validation_gates:
  - root_cause_supported_by_evidence
  - original_scenario_verified
---

# Debugging

Read `skills/blocks/engineering-method-selection.md` from the installed plugin
for review admission. Natural-language requests and `--peer-review` share that
policy. Honor host-only requests; risk alone does not authorize paid usage.

Run the investigation on the current host. Routine debugging makes zero
additional provider dispatches. Use a bounded external reviewer only for
`--peer-review`, an explicit independent-review request, or an existing risk
policy.

<HARD-GATE>
DO NOT CHANGE PRODUCTION BEHAVIOR BEFORE REPRODUCING THE SYMPTOM AND TESTING A
NAMED ROOT-CAUSE HYPOTHESIS.
</HARD-GATE>

Read and apply `skills/blocks/debug-feedback-loop.md` from the installed plugin
root.

Start with the user's observable symptom. Reproduce it, retain its failure
signature while minimizing the scenario, test one named hypothesis at a time,
and verify both the minimal reproduction and the original scenario after the
fix. Do not treat a nearby passing helper test as proof.

For a race, use a synchronization barrier and a fixed run or time budget. For an
unavailable production dependency, return `inconclusive` with the missing
evidence. Remove temporary instrumentation before completion and preserve a
stable reproduction as a regression test.

The final record is data, not an executable queue. Store commands as argument
arrays and never evaluate provider-authored text.

## Bounded recovery and strategy rotation

Use a 3-Strike Rule for failed fixes. After each failure, return to the evidence
and test a materially different hypothesis. After two consecutive failures, a
strategy rotation is mandatory: reconsider the root cause, the reproduction,
and whether the test encodes the intended behavior. Do not attempt a 4th fix
without explicit user approval.

Anti-rationalization check: “Should work now” means run the reproduction and
the original scenario. Confidence is not verification.

For multi-attempt debugging, report a WTF score using the defaults in
`~/.claude-octopus/loop-config.conf`: +15% per revert and +20% for touching
unrelated files. If the score exceeds 20%, STOP and show the evidence before
continuing. Include the score with every retry, for example:

```text
Fix attempt 2 | Self-regulation: 15% (1 revert, 0 unrelated files)
```

## Scoped freeze guard

When the symptom is localized to one user-approved module, resolve that module
to a physical directory before editing and activate the existing freeze guard:

```bash
freeze_dir="$(cd "<module-directory>" 2>/dev/null && pwd -P)" || exit 1
_OCTO_SESSION_ID="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-$$}}"
_OCTO_FREEZE_FILE="/tmp/octopus-freeze-${_OCTO_SESSION_ID}.txt"
if [[ -e "$_OCTO_FREEZE_FILE" || -L "$_OCTO_FREEZE_FILE" ]]; then
    if [[ -f "$_OCTO_FREEZE_FILE" && ! -L "$_OCTO_FREEZE_FILE" &&
          -O "$_OCTO_FREEZE_FILE" && -s "$_OCTO_FREEZE_FILE" ]]; then
        printf 'Freeze already active; left unchanged.\n'
    else
        printf 'Unsafe or empty freeze state; stop and inspect it before retrying.\n' >&2
        exit 1
    fi
else
    (umask 077; python3 - "$_OCTO_FREEZE_FILE" "$freeze_dir" <<'PYFREEZE'
import os
import sys

try:
    fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as state:
        state.write(sys.argv[2] + "\n")
except OSError:
    raise SystemExit("Freeze activation failed; inspect the state before retrying.")
PYFREEZE
    ) || exit 1
fi
```

Activation requires Python 3, as freeze enforcement does. Existing empty,
symlinked or nonregular state is refused for manual inspection; active state
contents are never read or printed by this activation check. Exclusive creation
refuses a state path introduced after the check.

A freeze that is already active (from `/octo:freeze`, `/octo:guard` or an
earlier workflow) stays as it is: do not replace it, and do not remove it when
debugging ends. Do not auto-freeze when the root cause is still unknown, the
reproduction spans modules, or the user opted out. After original-scenario
verification, run `/octo:unfreeze` only if this workflow created the freeze and
the state file still names the directory it set; a different directory means
the user froze again since, so leave that freeze in place.

Adapted from `diagnosing-bugs` in `mattpocock/skills` at commit
`3cca18b368ae95cdbdebbff572ccafa662551015` under the MIT License. See
`THIRD_PARTY_NOTICES.md`.
