# Plugin Update Safety

Claude Octopus separates update detection from update execution. This avoids a
startup hook blocking a session, triggering authentication, or modifying the
same cached plugin tree that the host is currently executing.

## What happens automatically

`hooks/plugin-update-advisory.sh` runs at Claude Code `SessionStart` and reads
only local files:

- the plugin manifest loaded by the current session;
- Claude Code's installed-plugin registry;
- the locally refreshed `nyldn-plugins` catalog;
- cached Octopus version directories; and
- the marketplace auto-update preference.

It never invokes `claude`, `codex`, `git`, a Node package manager, or a network
client. It writes only a cooldown record under `~/.claude-octopus` so unchanged
advice is shown at most once every 30 days. A changed version or preference
fingerprint can be reported immediately.

`orchestrate.sh doctor updates` exposes the same local state on demand.

## What requires explicit consent

`orchestrate.sh update-plugin` delegates mutation to the active host:

- Claude Code refreshes `nyldn-plugins`, then updates
  `octo@nyldn-plugins`.
- Codex upgrades `nyldn-plugins`, then refreshes
  `claude-octopus@nyldn-plugins`, but only when the command is run outside an
  active Codex session.
- Factory and standalone installs receive host-specific/manual guidance instead
  of an assumed command.

The updater never enables auto-update by editing host state. In Claude Code,
the user opts in through `/plugin` → **Marketplaces** → **nyldn-plugins** →
**Enable auto-update**.

## Why reload is still required

Claude Code may download an update in the background, but the current process
continues using the plugin version it loaded at session start. Run
`/reload-plugins` or restart Claude Code after an update; restart Codex after a
Codex plugin update.

Do not replace the installed plugin from a terminal owned by the Codex session
that is using it. Codex can remove the old versioned cache directory while the
session still has hooks and skills bound to that path. `update-plugin` detects
this condition and exits before either Codex update command runs. Exit Codex,
run the printed commands from a separate terminal, and then start Codex again.

On the next session, Octopus compares the stable
`~/.claude-octopus/plugin` entrypoint with the version supplied by the host and
repairs it when they differ. The check uses physical paths, so an older cache
that still exists cannot keep commands pinned to stale scripts.

An installation older than this advisory cannot discover the new code by
itself. It needs one manual marketplace/plugin update. From then on, the local
advisory detects disabled auto-update and stale loaded sessions without adding
network or authentication risk to hooks.

## Prior art and host contracts

The design follows the host lifecycle instead of building a competing
self-updater:

- [Claude Code plugin auto-updates](https://code.claude.com/docs/en/discover-plugins#configure-auto-updates)
  are host-managed and opt-in for third-party marketplaces.
- [Claude Code marketplace management](https://code.claude.com/docs/en/plugin-marketplaces)
  provides the supported refresh and update commands.
- [claude-mem's version check](https://github.com/thedotmack/claude-mem/blob/4702c337d85aa12e8ab7f845264a78885676261f/plugin/scripts/version-check.js)
  demonstrates cooldown-limited update awareness, while Octopus keeps its hook
  strictly local.
- [Oh My Zsh update settings](https://github.com/ohmyzsh/ohmyzsh/wiki/Settings#update-settings)
  demonstrate the useful separation between notification cadence and an
  explicit update policy.
