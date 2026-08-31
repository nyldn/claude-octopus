---
description: "[advanced] Compatibility view of the deterministic Octopus usage report"
disable-model-invocation: true
allowed-tools: Bash
---

# Cost Dashboard (/octo:costs)

For table output, your first output line MUST be `🐙 Octopus Cost Dashboard`.
For JSON, emit only the helper output—no banner or commentary.

This v10 compatibility command shows the cost-focused view of `/octo:usage`.
It is scheduled for removal in v11.

## EXECUTION CONTRACT (Mandatory)

When the user invokes `/octo:costs`, run the helper once with the Bash tool:

```bash
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}"
helper="$OCTO_ROOT/scripts/helpers/usage-report.sh"
if [[ ! -x "$helper" ]]; then
  echo "ERROR: Claude Octopus usage report helper is unavailable. Run /octo:setup." >&2
  exit 1
fi
format="table"
case " $ARGUMENTS " in
  *" --format json "*|*" --format=json "*) format="json" ;;
esac
"$helper" --view costs --format "$format"
```

Choose the format before invoking the helper and invoke it exactly once. For
JSON, emit only the helper output. The helper owns pricing, session aggregation,
provider rows, and the workflow cost breakdown. Do not inspect usage files or
calculate rates inside the model response.
