# Command Code CLI provider

Octopus can dispatch `commandcode`, `commandcode-research`, and `commandcode-fast` through the native Command Code CLI.

## Install and authenticate

```bash
npm i -g command-code@latest
export COMMAND_CODE_API_KEY="..."
```

Interactive `cmd login` credentials are also accepted by the CLI health check. Octopus does not implement OAuth itself.

## Configure a model

```bash
export OCTOPUS_COMMANDCODE_MODEL=deepseek/deepseek-v4-pro
# or providers.json: {"providers":{"commandcode":{"default":"deepseek/deepseek-v4-pro"}}}
```

The adapter uses Command Code headless NDJSON mode, extracts the final result, disables onboarding and auto-update, and keeps Octopus as the worktree/orchestration owner. Read-only roles run in `plan` mode; implementer/developer roles receive `--yolo` only inside the Octopus-managed workspace.

Optional controls:

- `OCTOPUS_COMMANDCODE_BIN` — override the CLI executable.
- `OCTOPUS_COMMANDCODE_MAX_TURNS` — default `30`.
- `OCTOPUS_COMMANDCODE_ALLOWED_MODELS` — comma-separated model allowlist.
- `CMD_ZDR=1` — require Command Code zero-data-retention routing.
