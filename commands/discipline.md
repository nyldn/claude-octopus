---
command: discipline
description: Toggle discipline mode — auto-invoke verification, brainstorming-before-coding, and review checks
---

# Discipline Mode

Toggle automatic skill invocation for development discipline.

## Usage

```
/octo:discipline on     — enable auto-invoke discipline checks
/octo:discipline off    — disable (back to manual invoke only)
/octo:discipline status — show current state
```

## What Discipline Mode Does

When **on**, you MUST follow these rules automatically — no user prompt needed:

### Development Gates

**1. Brainstorm gate** — Before writing ANY code or making changes, check:
- Has the approach been discussed/planned? If not, invoke `skill-thought-partner` or `skill-writing-plans`
- This applies even for "simple" changes

**2. Verification gate** — Before saying "done", "fixed", "passing", or committing, invoke `skill-verification-gate`:
- Run the actual verification command, read output, only claim success with evidence

**3. Review gate** — After completing any non-trivial code change, automatically:
- Spec compliance check + code quality review via subagent

**4. Response gate** — When receiving code review feedback, invoke `skill-review-response`:
- Verify feedback against actual code before implementing

**5. Investigation gate** — When encountering ANY bug, error, or test failure, invoke `skill-debug`:
- Root cause investigation before proposing fixes

### Knowledge Work Gates

**6. Context gate** — At the start of any task, detect dev vs knowledge work. If research, writing, design, or strategy — switch to KM mode. Use `skill-context-detection`.

**7. Decision gate** — When comparing options or evaluating trade-offs, present a structured comparison with criteria and scores — not just prose pros/cons. Use `skill-decision-support`.

**8. Intent gate** — Before any creative or writing task (README, docs, copy, design), lock in the goal and audience first. Validate output against locked goals. Use `skill-intent-contract`.

## How It Works

When the user runs `/octo:discipline on`, persist the setting:

```bash
mkdir -p ~/.claude-octopus/config
echo "OCTOPUS_DISCIPLINE=on" > ~/.claude-octopus/config/discipline.conf
```

The SessionStart hook reads this file and injects the discipline directive into the session context. The directive is ~30 lines (not 200+) — lightweight enough to not bloat context.

When off:
```bash
echo "OCTOPUS_DISCIPLINE=off" > ~/.claude-octopus/config/discipline.conf
```

## What Discipline Mode Does NOT Do

- Does not add new commands or skills — uses existing ones
- Does not slow down quick tasks — `/octo:quick` bypasses discipline checks
- Does not force multi-provider workflows — discipline is about rigor, not providers
- Does not fire on every single turn — only at the 5 gates above

## Execution Contract

When the user invokes `/octo:discipline`:

1. Parse the argument: `on`, `off`, or `status`
2. For `on`: write config file, confirm with banner
3. For `off`: write config file, confirm
4. For `status`: read config file, display current state
5. No args: show status

```bash
DISCIPLINE_CONF="${HOME}/.claude-octopus/config/discipline.conf"
mkdir -p "$(dirname "$DISCIPLINE_CONF")"

case "${1:-status}" in
    on)
        echo "OCTOPUS_DISCIPLINE=on" > "$DISCIPLINE_CONF"
        echo "🐙 Discipline mode: ON"
        echo "  Development gates:"
        echo "  ✓ 1. Brainstorm — plan before coding"
        echo "  ✓ 2. Verification — evidence before claims"
        echo "  ✓ 3. Review — check after implementing"
        echo "  ✓ 4. Response — verify before agreeing"
        echo "  ✓ 5. Investigation — root cause before fixing"
        echo "  Knowledge work gates:"
        echo "  ✓ 6. Context — detect dev vs knowledge work"
        echo "  ✓ 7. Decision — structured comparisons, not prose"
        echo "  ✓ 8. Intent — lock goals before creative work"
        ;;
    off)
        echo "OCTOPUS_DISCIPLINE=off" > "$DISCIPLINE_CONF"
        echo "🐙 Discipline mode: OFF — manual skill invocation only"
        ;;
    status|"")
        if [[ -f "$DISCIPLINE_CONF" ]] && grep -q "OCTOPUS_DISCIPLINE=on" "$DISCIPLINE_CONF" 2>/dev/null; then
            echo "🐙 Discipline mode: ON"
        else
            echo "🐙 Discipline mode: OFF"
        fi
        ;;
esac
```
