# Antigravity CLI Provider

Antigravity CLI (`agy`) is a first-class external CLI provider.

## Detection

```bash
command -v agy
```

## Dispatch

Prompts are delivered through stdin and executed with Antigravity print mode:

```bash
agy --print --sandbox --print-timeout "${OCTOPUS_AGY_PRINT_TIMEOUT:-5m0s}"
```

When `OCTOPUS_AGY_MODEL` is set to a non-empty value other than `default`,
Octopus adds the model override:

```bash
agy --print --sandbox --print-timeout "${OCTOPUS_AGY_PRINT_TIMEOUT:-5m0s}" --model "$OCTOPUS_AGY_MODEL"
```

Octopus dispatches through `scripts/helpers/agy-exec.sh`, which is the command
returned for `agy|agy-research|antigravity` by `scripts/lib/dispatch.sh`.
`agy-exec.sh` reads `OCTOPUS_AGY_MODEL` (default `Claude Sonnet 4.6 (Thinking)`)
and `OCTOPUS_AGY_PRINT_TIMEOUT` (default `5m0s`). Antigravity display model
names with spaces are passed as a single argv element.

Set `OCTOPUS_AGY_MODEL=default` to omit `--model` and use the Antigravity CLI
default. Set `OCTOPUS_AGY_PRINT_TIMEOUT` to override the print-mode wait time.

When `OCTOPUS_AGY_MODEL` is non-empty and not `default`, Octopus adds:

```bash
--model "$OCTOPUS_AGY_MODEL"
```

The helper builds the command as a Bash argv array, preserving spaces in
`--model "$model"`. Prompt content is piped to the provider via stdin with
`printf '%s' ... | "${cmd_array[@]}"` in `scripts/lib/agent-sync.sh`.
Antigravity also uses `agy --print-timeout`; Octopus enforces its own
orchestration timeout as a fallback around the provider command.

## Security Note

By default, Antigravity (`agy`) runs under a minimal `env -i` environment:
`HOME`, `PATH`, `TERM`, `TMPDIR`, W3C trace headers, and optional
`AGY_AUTH_TOKEN`, `AGY_CONFIG`, or `ANTIGRAVITY_API_KEY`.

Set `OCTOPUS_ALLOW_FULL_AGY_ENV=true` only if your local Antigravity auth flow
requires the desktop/session environment to be inherited. In that mode, `agy`
can see all exported environment variables in the shell that starts Octopus.

Avoid exporting secrets that are not needed by local CLI tools before running
`agy` workflows. If you are unsure what is currently exported, check with a
command such as:

```bash
env | grep -Ei 'secret|token|key'
```

Keep `OCTOPUS_AGY_PRINT_TIMEOUT` set high enough for isolated print-mode runs if
your selected model needs more time.

## Notes

- `agy` is not treated as a retired Google CLI wrapper.
- Google-CLI-specific flags such as `-o text`, `--approval-mode yolo`, and the
  retired Google fallback helper are not used for Antigravity.
- `agy --print-timeout` is the primary timeout for Antigravity print mode.
- This provider was added in response to #423.
