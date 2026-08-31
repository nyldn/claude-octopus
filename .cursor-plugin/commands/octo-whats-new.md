---
description: "Review and enable Claude Octopus features added since you installed"
disable-model-invocation: true
allowed-tools: Bash, Read
---

# What's New (/octo:whats-new)

**Your first output line MUST be:** `🐙 Octopus What's New`

Show the settings added since the user's install point that still need a policy
choice, ask each as its own question, and record the answers so they are never
asked twice.

## Why this command exists

Features added after a user installs are invisible to them. The SessionStart
advisory asks for these choices automatically on the first session after an
upgrade, but that prompt is capped and suppressed in non-interactive sessions,
so this command is how the user reaches the same outstanding questions
deliberately.

Only features declaring `decision: required` in the manifest appear here. A
feature that ships with a sensible default and no real fork in behaviour is not
a question and must not be raised as one.

## EXECUTION CONTRACT (Mandatory)

### Step 1 — Load the outstanding questions

```bash
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}"
source "$OCTO_ROOT/scripts/lib/features.sh"

octo_features_available || {
    echo "Feature disclosure unavailable (jq missing, or manifest/ledger unreadable)."
    exit 0
}

# Tab-separated. Q<TAB>id<TAB>question, then C<TAB>id<TAB>value<TAB>label<TAB>description.
octo_features_prompt_manifest

# Features blocked on a missing prerequisite, listed but not askable.
for id in $(octo_features_offerable_ids); do
    prereq="$(octo_features_prereq "$id")"
    octo_features_prereq_ok "$prereq" || printf 'BLOCKED\t%s\t%s\n' "$id" "$prereq"
done
```

If nothing is returned, say `Nothing new to decide since your last upgrade.` and
stop. Do not pad the output or invent questions.

### Step 2 — Ask

Call `AskUserQuestion` with one question per `Q` line, using that feature's
question text and its own `C` choices verbatim. Do not invent options, do not
reword a policy choice into a yes/no, and keep each choice description's cost
note, because that is usually what the answer turns on.

`AskUserQuestion` takes at most 4 questions per call and 4 options per question.
If there are more than 4 outstanding features, ask the first four, record them,
then ask the rest in a second call.

`BLOCKED` features are shown with their missing prerequisite (for example
`requires the Codex CLI`) and are NOT asked. Show them rather than hiding them,
so the user learns the prerequisite exists.

WAIT for the answers. Apply nothing the user did not pick.

### Step 3 — Record every answer

```bash
octo_features_record "<id>" "<chosen value>" "<current plugin version>"
```

Record all of them, including any that picks the feature's default. Recording is
what stops the question being asked again; an unrecorded answer means the user is
asked the same thing after the next upgrade.

Read the current plugin version from `.claude-plugin/plugin.json` (`.version`).
Never hardcode it.

A recorded choice takes effect immediately for this repository. To pin one for
every shell, tell the user to export the feature's key with the chosen value:

```bash
echo 'export <KEY>=<value>' >> ~/.zshrc   # or ~/.bashrc
```

### Step 4 — Confirm

Print what is now set, one line per feature, plus anything still blocked on a
missing prerequisite. End on the substantive state, no closer.

## Notes

- Never write to `state.json` with anything other than `octo_features_record`
  and `octo_features_seed_watermark`. Hand-rolled `jq` edits here have raced the
  SessionStart hook's own write in the past.
- Do not re-ask a feature the ledger already records a choice for. The offer
  list already excludes them; do not work around it. This command shows only
  outstanding choices.
- This command never changes model routing, permissions, or quality gates by
  itself. It records consent; the runtime reads consent.
