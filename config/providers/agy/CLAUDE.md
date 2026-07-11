# Antigravity CLI Provider

Antigravity CLI (`agy`) is a first-class external CLI provider.

## Detection

```bash
command -v agy
```

## Dispatch

Callers deliver prompts through stdin (the provider-uniform contract);
`agy-exec.sh` caches the stdin prompt and passes it to Antigravity print mode
as `--print`'s argument. `--print` is a value-consuming string flag — agy does
NOT read a prompt from stdin, and a bare `agy --print --sandbox` invocation
makes the literal string `--sandbox` the prompt:

```bash
agy --sandbox --print-timeout "${OCTOPUS_AGY_PRINT_TIMEOUT:-5m0s}" --print "$PROMPT"
```

Prompts larger than 100KB (Linux caps one argv string at 128KB) stay in the
cached temp file; agy is pointed at it with `--add-dir` and a read-this-file
`--print` instruction.

When `OCTOPUS_AGY_MODEL` is set to a non-empty value other than `default`,
Octopus adds the model override before the prompt:

```bash
agy --sandbox --print-timeout "${OCTOPUS_AGY_PRINT_TIMEOUT:-5m0s}" --model "$OCTOPUS_AGY_MODEL" --print "$PROMPT"
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
`--model "$model"`. Callers pipe prompt content via stdin with
`printf '%s' ... | "${cmd_array[@]}"` in `scripts/lib/agent-sync.sh`;
`agy-exec.sh` converts that into the `--print` argument.
Antigravity also uses `agy --print-timeout`; Octopus enforces its own
orchestration timeout as a fallback around the provider command.

## Serving gemini seats through agy

`OCTOPUS_GEMINI_VIA_AGY=1` (also `on`/`true`/`yes`) makes `scripts/lib/dispatch.sh`
return `agy-exec.sh` for the `gemini|gemini-fast|gemini-image` agent types, so
existing workflows, phase routing, and role routing that seat gemini keep
working on Antigravity subscriptions. Google sunset Gemini Code Assist
free-tier OAuth for gemini-cli (`IneligibleTierError`); this option is the
migration path that does not require re-routing every gemini seat by hand.
Model pins follow `OCTOPUS_AGY_MODEL` (labels from `agy models`), not gemini
model ids, and provider health checks for gemini seats probe agy instead.

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

- `agy` is not treated as a Gemini CLI wrapper.
- Gemini-specific flags such as `-o text`, `--approval-mode yolo`, and the
  Gemini fallback helper are not used for Antigravity.
- `agy --print-timeout` is the primary timeout for Antigravity print mode.
- This provider was added in response to #423.
