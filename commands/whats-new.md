---
command: whats-new
description: "Review and enable Claude Octopus features added since you installed"
allowed-tools: Bash, Read
---

# What's New (/octo:whats-new)

**Your first output line MUST be:** `🐙 Octopus What's New`

Show the features that landed after the user's install point, let them enable or
decline each one, and record the decision so they are never asked twice.

## Why this command exists

Features added after a user installs are invisible to them. The SessionStart
version advisory is one line and easy to miss, and a hook cannot run an
interactive picker. This command is the interactive half: the advisory points
here, and this is where consent is actually collected and written down.

## EXECUTION CONTRACT (Mandatory)

### Step 1 — Load the offer list

```bash
source "${CLAUDE_PLUGIN_ROOT:-.}/scripts/lib/features.sh" 2>/dev/null \
  || source ./scripts/lib/features.sh

octo_features_available || {
    echo "Feature disclosure unavailable (jq missing, or manifest/ledger unreadable)."
    exit 0
}

for id in $(octo_features_offerable_ids); do
    prereq="$(octo_features_prereq "$id")"
    if octo_features_prereq_ok "$prereq"; then state="offerable"; else state="blocked:$prereq"; fi
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$id" "$state" "$(octo_features_key "$id")" \
        "$(octo_features_title "$id")" "$(octo_features_description "$id")"
done
```

If the list is empty, say `Nothing new since your last upgrade.` and stop. Do not
pad the output or invent features.

### Step 2 — Present the list

Render one block per feature: title, what it does, the env var it sets, and the
cost implication when there is one. Features whose state is `blocked:<prereq>`
are shown with the reason (for example `requires the Codex CLI`) and are NOT
offered for enabling. Show them rather than hiding them, so the user learns the
prerequisite exists and can install it.

State the cost plainly for anything that spends money. `fable5-escalation` runs
at $10/$50 per MTok, twice Opus 5, and the user needs that number before
deciding, not after.

### Step 3 — Collect decisions

Use `AskUserQuestion` with one question per offerable feature, options
`Enable` / `Not now`. Multiple features may be presented in a single call (up to
the tool's 4-question limit; batch the remainder into a second call).

WAIT for the answers. Do not assume, and do not enable anything the user did not
explicitly choose.

### Step 4 — Record and apply

For each answer:

```bash
# Enable
octo_features_record "<id>" enabled "<current plugin version>"
# Not now
octo_features_record "<id>" declined "<current plugin version>"
```

`declined` is sticky: that feature will not be offered again. Tell the user this
so "Not now" is an informed choice, and tell them how to change their mind:
`/octo:model-config` for routing features, or exporting the env var directly.

For each enabled feature, the recorded consent is what the runtime reads, so
nothing further is required for it to take effect in this repository. If the user
wants it active in every shell, tell them to add the export to their profile:

```bash
echo 'export <KEY>=1' >> ~/.zshrc   # or ~/.bashrc
```

Read the current plugin version from `.claude-plugin/plugin.json` (`.version`).
Never hardcode it.

### Step 5 — Confirm

Print a short summary: what is now enabled, what was declined, and what remains
blocked on a missing prerequisite. End on the substantive state, no closer.

## Notes

- Never write to `state.json` with anything other than `octo_features_record`
  and `octo_features_seed_watermark`. Hand-rolled `jq` edits here have raced the
  SessionStart hook's own write in the past.
- Do not re-offer a feature the ledger already records a decision for. The
  offer list already excludes them; do not work around it.
- This command never changes model routing, permissions, or quality gates by
  itself. It records consent; the runtime reads consent.
