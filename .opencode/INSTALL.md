# Installing Claude Octopus for OpenCode

Enable Claude Octopus skills in OpenCode via native skill discovery.

## Prerequisites

- Git
- OpenCode CLI installed

## Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/nyldn/claude-octopus.git ~/.opencode/claude-octopus
   ```

2. **Create the skills symlink:**
   ```bash
   mkdir -p ~/.agents/skills
   ln -s ~/.opencode/claude-octopus/skills ~/.agents/skills/claude-octopus
   ```

   **Windows (PowerShell):**
   ```powershell
   New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.agents\skills"
   cmd /c mklink /J "$env:USERPROFILE\.agents\skills\claude-octopus" "$env:USERPROFILE\.opencode\claude-octopus\skills"
   ```

3. **Restart OpenCode** to discover the skills.

## Verify

```bash
ls -la ~/.agents/skills/claude-octopus
```

You should see a symlink pointing to the skills directory.

## Updating

```bash
cd ~/.opencode/claude-octopus && git pull
```

Skills update instantly through the symlink.

## Uninstalling

```bash
rm ~/.agents/skills/claude-octopus
rm -rf ~/.opencode/claude-octopus
```
