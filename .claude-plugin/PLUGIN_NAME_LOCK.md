# Plugin Name Lock

## CRITICAL: DO NOT CHANGE THE PLUGIN NAME

The plugin name in `plugin.json` **MUST remain "octo"**.
The plugin name in `marketplace.json` **MUST also be "octo"**.

### Why?

The `name` field in `plugin.json` controls **two things**:
1. **Command namespace** — `/octo:discover`, `/octo:embrace`, etc.
2. **Plugin identity in `/plugin` UI** — install, uninstall, update, enable/disable

These names **MUST match** so that `/plugin uninstall octo` works correctly when the plugin was installed as `octo@nyldn-plugins`.

```json
// plugin.json
{
  "name": "octo"  // → /octo:* commands + /plugin identity
}
```

```json
// marketplace.json plugins[].name
{
  "name": "octo"  // → install as octo@nyldn-plugins (matches plugin.json)
}
```

### What NOT to do

```json
// ❌ WRONG — breaks /plugin UI (name mismatch)
// plugin.json: "octo", marketplace.json: "claude-octopus"
// → /plugin uninstall tries "octo" but installed as "claude-octopus"

// ❌ WRONG — breaks command namespace
// plugin.json: "claude-octopus"
// → Commands become /claude-octopus:discover (too long!)
```

### Package vs Plugin Name

| File | Name | Purpose |
|------|------|---------|
| `package.json` | `"claude-octopus"` | npm/repository identity |
| `.claude-plugin/plugin.json` | `"octo"` | Command prefix + plugin identity |
| `.claude-plugin/marketplace.json` | `"octo"` | Install name (must match plugin.json) |

### Historical Context

**Commits that fixed this:**
- `d9e8354` - Reverted plugin name to 'octo' for correct command prefixes
- `57ce38c` - Removed namespace prefix from command frontmatter
- v9.0.0 - Aligned marketplace.json name to "octo" to fix /plugin uninstall

**Why it broke twice:**
1. Someone changed plugin.json thinking it should match the package name
2. marketplace.json was set to "claude-octopus" causing /plugin UI mismatch

### Tests

The `validate-release.sh` script checks that both names are "octo".

---

**Last verified:** 2026-03-14
**Status:** Plugin name is "octo" in BOTH plugin.json and marketplace.json — LOCKED
