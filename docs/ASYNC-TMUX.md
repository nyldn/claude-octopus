# Async Task Management & Tmux Visualization

Claude Octopus includes **async task management** and **tmux visualization** for better performance and transparency during multi-agent workflows.

## Async Mode

Enable async mode for improved progress tracking and parallel execution:

```bash
./scripts/orchestrate.sh probe "research auth patterns" --async
```

**Benefits:**
- Better progress tracking with elapsed time
- Optimized parallel execution
- Cleaner console output
- Lower memory overhead

**When to use:**
- Multi-agent workflows (probe, tangle)
- Long-running tasks
- Resource-constrained environments

## Tmux Visualization

Watch agents work in real-time with tmux panes:

```bash
./scripts/orchestrate.sh embrace "implement auth system" --tmux
```

**What you get:**
- Live agent output in separate tmux panes
- Auto-balancing layout as agents spawn/complete
- Visual progress without blocking
- Titled panes showing agent roles

**Example layout for `probe` phase:**
```
┌─────────────────────┬─────────────────────┐
│ 🔍 Problem Analysis │ 📚 Solution Research│
├─────────────────────┼─────────────────────┤
│ ⚠️  Edge Cases      │ 🔧 Feasibility      │
└─────────────────────┴─────────────────────┘
```

**Example layout for `tangle` phase:**
```
┌──────────────┬──────────────┬──────────────┐
│ ⚙️ Subtask 1 │ 🧠 Subtask 2 │ ⚙️ Subtask 3 │
├──────────────┼──────────────┼──────────────┤
│ ⚙️ Subtask 4 │ 🧠 Subtask 5 │ ⚙️ Subtask 6 │
└──────────────┴──────────────┴──────────────┘
```

**Requirements:**
- `tmux` installed (`brew install tmux` or `apt install tmux`)
- Automatically enables async mode
- Works in new session or existing tmux window

**Attaching to session:**
```bash
# If session created in background
tmux attach -t claude-octopus-<pid>
```

## Environment Variables

Control async/tmux globally:

```bash
# Enable async by default
export OCTOPUS_ASYNC_MODE=true

# Enable tmux by default
export OCTOPUS_TMUX_MODE=true

# Run workflow
./scripts/orchestrate.sh probe "research caching strategies"
```

## Disabling Features

```bash
# Disable async (use standard progress tracking)
./scripts/orchestrate.sh probe "..." --no-async

# Disable tmux (use terminal output)
./scripts/orchestrate.sh probe "..." --no-tmux
```

## Comparison: Standard vs Async vs Tmux

| Feature | Standard | Async | Tmux |
|---------|----------|-------|------|
| Progress tracking | Basic (N/M complete) | Detailed (with elapsed time) | Visual (live panes) |
| Output | Buffered to files | Buffered to files | Live streaming |
| Performance | Good | Better (optimized waiting) | Good (slight overhead) |
| User experience | Simple | Informative | Immersive |
| Requirements | None | None | tmux installed |
| Best for | Scripts, CI/CD | Interactive use | Development, debugging |

## Performance Tips

**For maximum performance:**
```bash
./scripts/orchestrate.sh embrace "task" --async -p 8
# Enables: async mode + 8 parallel agents
```

**For best transparency:**
```bash
./scripts/orchestrate.sh embrace "task" --tmux --verbose
# Enables: tmux visualization + detailed logging
```

**For CI/CD:**
```bash
./scripts/orchestrate.sh embrace "task" --ci
# Uses: standard mode (no tmux), non-interactive, JSON output
```

---

[← Back to README](../README.md)
