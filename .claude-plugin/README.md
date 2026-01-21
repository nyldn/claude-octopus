# Claude Octopus Plugin Configuration

## ⚠️ CRITICAL: Plugin Name

**The plugin name in `plugin.json` MUST remain `"octo"`**

```json
{
  "name": "octo"  // ⚠️ DO NOT CHANGE
}
```

### Why?

- Command prefix: `/octo:discover`, `/octo:debate`, etc.
- Changing this breaks all existing commands and user workflows
- Package name (`claude-octopus` in `package.json`) is different and correct

### More Information

- **Detailed explanation:** `PLUGIN_NAME_LOCK.md`
- **All safeguards:** `../SAFEGUARDS.md`
- **Validate:** Run `make test-plugin-name`

---

This directory contains the Claude Code plugin configuration for Claude Octopus.
