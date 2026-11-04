#!/usr/bin/env python3
"""Select an advertised document skill without executing or installing it."""
import argparse
import json
from pathlib import Path
import re
import sys

FORMATS = ("pptx", "docx", "xlsx", "pdf")
SKILL_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}\Z")


def read_config(path, format_name):
    if not path.exists():
        return {}
    with path.open(encoding="utf-8") as handle:
        config = json.load(handle)
    if not isinstance(config, dict):
        raise ValueError("Renderer config must be a JSON object")
    entry = config.get(format_name, {})
    if not isinstance(entry, dict):
        raise ValueError("Renderer format entry must be an object")
    if entry and not isinstance(entry.get("skill"), str):
        raise ValueError("Configured renderer needs a skill name")
    return entry


def resolve_renderer(format_name, available, entry, renderer=None, template=None):
    """Explicit choices win; absent or ambiguous choices never silently change."""
    if renderer is not None:
        selected, selection = renderer, "request"
    elif entry:
        selected, selection = entry["skill"], "config"
    elif f"document-skills:{format_name}" in available:
        selected, selection = f"document-skills:{format_name}", "default"
    else:
        candidates = sorted({name for name in available
                             if name == format_name or name.endswith(":" + format_name)})
        if not candidates:
            raise ValueError(f"No advertised {format_name} renderer; enable a suitable skill")
        if len(candidates) != 1:
            raise ValueError("Multiple advertised renderers; choose one with --renderer")
        selected, selection = candidates[0], "discovered"
    if not SKILL_NAME.fullmatch(selected):
        raise ValueError("Renderer skill name is invalid")
    if selected not in available:
        raise ValueError("Selected renderer is not advertised; enable it or change the selection")
    if template is None and selection == "config":
        template = entry.get("template")
    if template is not None:
        if not isinstance(template, str) or not template.strip():
            raise ValueError("Template must be a nonempty file path")
        template_path = Path(template).expanduser().resolve()
        if not template_path.is_file():
            raise ValueError("Template must name an existing file")
        template = str(template_path)
    return {"skill": selected, "template": template, "format": format_name, "selection": selection}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--format", choices=FORMATS, required=True)
    parser.add_argument("--available-skill", action="append", default=[])
    parser.add_argument("--config", type=Path,
                        default=Path.home() / ".claude-octopus/document-renderers.json")
    parser.add_argument("--renderer")
    parser.add_argument("--template")
    args = parser.parse_args()
    try:
        entry = {} if args.renderer is not None else read_config(args.config.expanduser().resolve(), args.format)
        result = resolve_renderer(args.format, args.available_skill, entry, args.renderer, args.template)
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"Renderer selection failed: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
