#!/usr/bin/env python3
"""Read the installed command catalog without initializing a workflow."""

import argparse
import json
from pathlib import Path
import re
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("topic", nargs="*", help="command or topic; list shows all commands")
    parser.add_argument("--json", action="store_true", help="print the installed catalog as JSON")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        manifest = json.loads((root / ".claude-plugin/plugin.json").read_text())
        commands = []
        for relative in manifest["commands"]:
            try:
                path = (root / relative).resolve()
                path.relative_to(root)
                content = path.read_text().split("---", 2)
                if len(content) != 3 or content[0].strip():
                    raise ValueError("missing frontmatter")
                match = re.search(r"^description:\s*(.+)$", content[1], re.MULTILINE)
                description = match.group(1).strip().strip("\"'") if match else ""
            except (OSError, ValueError, TypeError) as exc:
                print(f"Skipping command {relative!r}: {exc}", file=sys.stderr)
                continue
            commands.append({"command": f"/octo:{path.stem}", "description": description})
        topic = " ".join(args.topic).strip().lower().removeprefix("/octo:")
        if topic and topic != "list":
            commands = [entry for entry in commands if topic in (entry["command"] + " " + entry["description"]).lower()]
        if args.json:
            print(json.dumps({"version": manifest["version"], "commands": commands}))
        else:
            print("Claude Octopus command guide")
            if not topic:
                print('Start with /octo:setup, then /octo:auto "describe your task".\n')
                primary = {"setup", "auto", "guide", "review", "debug", "security", "resume", "costs"}
                commands = [entry for entry in commands if entry["command"].split(":")[1] in primary]
            for entry in commands:
                print(f'{entry["command"]:24} {entry["description"]}')
            if not commands:
                print("No matching installed command. Run octopus guide list.")
            elif not topic:
                print("\nUse /octo:guide <topic> or octopus guide list for more commands.")
        return 0
    except (OSError, ValueError, KeyError, TypeError, IndexError) as exc:
        print(f"Cannot read installed command catalog: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
