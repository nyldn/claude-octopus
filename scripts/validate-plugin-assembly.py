#!/usr/bin/env python3
"""Validate Claude Octopus plugin assembly structure.

This is intentionally dependency-free. It validates the file contracts that keep
skills, commands, agents, and connector metadata wired in a predictable Claude
Code plugin shape.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


REQUIRED_PLUGIN_FIELDS = ("name", "version", "description")
KEBAB_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def rel(root: Path, path: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def extract_frontmatter(text: str) -> tuple[dict[str, str], str | None]:
    if not text.startswith("---\n") and not text.startswith("---\r\n"):
        return {}, "missing frontmatter"

    lines = text.splitlines()
    if not lines or lines[0] != "---":
        return {}, "missing frontmatter"

    end = None
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            end = i
            break

    if end is None:
        return {}, "missing closing frontmatter delimiter"

    meta: dict[str, str] = {}
    current_key: str | None = None
    for raw in lines[1:end]:
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue

        if re.match(r"^[A-Za-z0-9_-]+:", line):
            key, value = line.split(":", 1)
            key = key.strip()
            value = value.strip().strip("\"'")
            meta[key] = value
            current_key = key
            continue

        if current_key and line.startswith((" ", "\t")):
            # Accept basic YAML continuation lines without parsing full YAML.
            if meta[current_key] in ("|", ">"):
                meta[current_key] = line.strip()
            elif line.strip() and not meta[current_key]:
                meta[current_key] = line.strip().strip("\"'")

    return meta, None


def require_frontmatter(
    root: Path,
    file: Path,
    required: tuple[str, ...],
    errors: list[str],
    *,
    validate_name: bool = False,
) -> None:
    text = file.read_text(encoding="utf-8", errors="replace")
    meta, err = extract_frontmatter(text)
    if err:
        errors.append(f"{rel(root, file)}: {err}")
        return

    for field in required:
        if not meta.get(field):
            errors.append(f"{rel(root, file)}: missing required frontmatter field: {field}")

    if validate_name and meta.get("name") and not KEBAB_RE.match(meta["name"]):
        errors.append(f"{rel(root, file)}: name must be kebab-case: {meta['name']}")


def validate_json(root: Path, file: Path, errors: list[str]) -> dict | None:
    try:
        return json.loads(file.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        errors.append(f"{rel(root, file)}: invalid JSON: {exc.msg} at line {exc.lineno}")
        return None


def validate_plugin_manifest(root: Path, errors: list[str]) -> None:
    manifest = root / ".claude-plugin" / "plugin.json"
    if not manifest.is_file():
        errors.append(".claude-plugin/plugin.json: missing plugin manifest")
        return

    data = validate_json(root, manifest, errors)
    if not isinstance(data, dict):
        return

    for field in REQUIRED_PLUGIN_FIELDS:
        if not data.get(field):
            errors.append(f"{rel(root, manifest)}: missing required field: {field}")


def validate_json_files(root: Path, errors: list[str]) -> None:
    candidates = [
        root / ".claude-plugin" / "marketplace.json",
        root / ".claude-plugin" / "hooks.json",
        root / ".mcp.json",
        root / ".lsp.json",
        root / "settings.json",
    ]
    for file in candidates:
        if file.is_file():
            validate_json(root, file, errors)


def validate_skills(root: Path, errors: list[str]) -> int:
    checked = 0
    for file in sorted(root.glob("skills/*/SKILL.md")):
        require_frontmatter(root, file, ("name", "description"), errors, validate_name=True)
        checked += 1

    legacy = root / ".claude" / "skills"
    if legacy.is_dir():
        for file in sorted(legacy.glob("*.md")):
            require_frontmatter(root, file, ("name", "description"), errors, validate_name=True)
            checked += 1

    return checked


def validate_commands(root: Path, errors: list[str]) -> int:
    checked = 0
    for directory in (root / "commands", root / ".claude" / "commands"):
        if not directory.is_dir():
            continue
        for file in sorted(directory.glob("*.md")):
            require_frontmatter(root, file, ("description",), errors)
            checked += 1

    return checked


def validate_agents(root: Path, errors: list[str]) -> int:
    checked = 0
    patterns = [
        "agents/personas/*.md",
        "agents/droids/*.md",
        ".claude/agents/*.md",
    ]
    for pattern in patterns:
        for file in sorted(root.glob(pattern)):
            require_frontmatter(root, file, ("name", "description"), errors, validate_name=True)
            checked += 1
    return checked


def validate_agent_config_refs(root: Path, errors: list[str]) -> int:
    config = root / "agents" / "config.yaml"
    if not config.is_file():
        return 0

    checked = 0
    base = config.parent
    for line_no, line in enumerate(config.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
        match = re.search(r"^\s*file:\s*([A-Za-z0-9_./-]+\.md)\s*$", line)
        if not match:
            continue
        checked += 1
        target = base / match.group(1)
        if not target.is_file():
            errors.append(
                f"{rel(root, config)}:{line_no}: file reference does not exist: {match.group(1)}"
            )
    return checked


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="plugin root to validate")
    args = parser.parse_args(argv)

    root = Path(args.root).resolve()
    errors: list[str] = []
    counts = {
        "skills": 0,
        "commands": 0,
        "agents": 0,
        "agent_refs": 0,
    }

    validate_plugin_manifest(root, errors)
    validate_json_files(root, errors)
    counts["skills"] = validate_skills(root, errors)
    counts["commands"] = validate_commands(root, errors)
    counts["agents"] = validate_agents(root, errors)
    counts["agent_refs"] = validate_agent_config_refs(root, errors)

    if errors:
        print(f"FAIL — plugin assembly has {len(errors)} issue(s):", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print(
        "OK — plugin assembly: "
        f"{counts['skills']} skills, "
        f"{counts['commands']} commands, "
        f"{counts['agents']} agents, "
        f"{counts['agent_refs']} agent config reference(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
