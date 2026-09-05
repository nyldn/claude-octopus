#!/usr/bin/env python3
"""JSON and path checks used only by the careful and freeze hooks."""

import json
import os
from pathlib import Path
import re
import sys


def decision(kind, reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": kind,
        "permissionDecisionReason": reason}}, separators=(",", ":")))


def codex_host():
    if (os.environ.get("OCTOPUS_HOST") == "codex"
            or os.environ.get("CODEX_SANDBOX")
            or os.environ.get("CODEX_PLUGIN_ROOT")):
        return True
    # Both hosts set CLAUDE_PLUGIN_ROOT. CODEX_HOME alone can be inherited.
    roots = [str(Path(__file__).resolve())]
    roots += [os.environ.get(key, "") for key in ("PLUGIN_ROOT", "CLAUDE_PLUGIN_ROOT")]
    custom_home = os.environ.get("CODEX_HOME", "").rstrip("/")
    return any("/.codex/plugins/cache/" in root
               or (custom_home and root.startswith(custom_home + "/plugins/cache/"))
               for root in roots)


def string(value):
    if not isinstance(value, str) or "\0" in value:
        raise ValueError("expected a string without NUL bytes")
    return value


def payload():
    data = json.load(sys.stdin)
    if not isinstance(data, dict):
        raise ValueError("expected a hook JSON object")
    return data


def tool_input(data):
    value = data.get("tool_input", {})
    if not isinstance(value, dict):
        raise ValueError("expected a tool_input object")
    return value


def patch_paths(command):
    text = string(command).strip()
    # Accept a literal patch or a single quoted heredoc, never execute a wrapper.
    if not text.startswith("*** Begin Patch\n"):
        wrapper = re.fullmatch(
            r"apply_patch[ \t]+<<[ \t]*(['\"])([A-Za-z_][A-Za-z_0-9]*)\1[ \t]*\n"
            r"(.*)\n\2", text, re.DOTALL)
        if not wrapper:
            raise ValueError("unrecognized apply_patch command")
        text = wrapper.group(3)
    lines = text.split("\n")
    if lines[0] != "*** Begin Patch" or lines[-1] != "*** End Patch":
        raise ValueError("incomplete patch envelope")
    paths = []
    i = 1
    while i < len(lines) - 1:
        header = re.fullmatch(r"\*\*\* (Add File|Update File|Delete File): (.+)", lines[i])
        if not header:
            raise ValueError("unknown patch operation or missing filename")
        operation, filename = header.groups()
        paths.append(filename)
        i += 1
        if operation == "Update File" and lines[i].startswith("*** Move to: "):
            paths.append(lines[i][len("*** Move to: "):])
            i += 1
        if operation == "Delete File":
            continue
        body_count = 0
        hunk_count = 0
        while i < len(lines) - 1:
            line = lines[i]
            if line.startswith("*** ") and line != "*** End of File":
                break
            if operation == "Add File":
                if not line.startswith("+"):
                    raise ValueError("invalid Add File body")
            elif line == "@@" or line.startswith("@@ "):
                if body_count and not hunk_count:
                    raise ValueError("empty update hunk")
                hunk_count = 0
                i += 1
                # A hunk marker must be followed by patch content.
                if i >= len(lines) - 1 or not lines[i].startswith((" ", "+", "-")):
                    raise ValueError("empty update hunk")
                continue
            elif line == "*** End of File":
                if not hunk_count:
                    raise ValueError("misplaced end-of-file marker")
                i += 1
                break
            elif not line.startswith((" ", "+", "-")):
                raise ValueError("invalid Update File body")
            body_count += 1
            hunk_count += 1
            i += 1
        if operation == "Update File" and not body_count:
            raise ValueError("missing Update File body")
    if not paths:
        raise ValueError("patch contains no file operations")
    return paths


def canonical_path(value, cwd):
    value = string(value)
    if not value.strip() or any(ord(char) < 32 for char in value):
        raise ValueError("empty path or control character in path")
    path = Path(value)
    path = path if path.is_absolute() else cwd / path
    # Newer Python versions suppress symlink-loop errors in non-strict resolve.
    # Permit missing files, but reject loops and inaccessible existing ancestors.
    for ancestor in (path, *path.parents):
        try:
            ancestor.stat()
        except FileNotFoundError:
            pass
    # resolve follows existing symlinks before processing '..', including when
    # the final file or some parent directories do not exist yet.
    return path.resolve()


def freeze(data, boundary):
    name = string(data.get("tool_name"))
    if name not in ("Edit", "Write", "apply_patch"):
        return
    cwd = Path(string(data.get("cwd", os.getcwd())))
    if not cwd.is_absolute():
        raise ValueError("hook cwd must be absolute")
    cwd = cwd.resolve()
    root = canonical_path(boundary, cwd)
    inputs = tool_input(data)
    paths = (patch_paths(inputs.get("command")) if name == "apply_patch"
             else [inputs.get("file_path")])
    for value in paths:
        path = canonical_path(value, cwd)
        if path != root and root not in path.parents:
            decision("deny", f"Edit blocked: {value} is outside freeze boundary ({root}). "
                     "Use /octo:unfreeze to remove the restriction.")
            return


def main():
    mode = sys.argv[1]
    try:
        if mode == "careful-decision":
            reason = sys.argv[2]
            if codex_host():
                decision("deny", reason + " Codex cannot ask for approval from a hook. "
                         "Ask the user to review the command and authorize deactivating "
                         "/octo:careful for this session before retrying. "
                         "The hook environment also supports OCTO_CAREFUL_MODE=off.")
            else:
                decision("ask", reason + " Confirm you want to proceed.")
        elif mode == "field":
            data = payload()
            field = sys.argv[2]
            value = (data.get("tool_name") if field == "tool_name" else
                     tool_input(data).get("command", data.get("command", "")))
            print(string(value), end="")
        elif mode == "freeze":
            freeze(payload(), sys.argv[2])
        else:
            raise ValueError("unknown safety helper mode")
    except (ValueError, TypeError, OSError, RuntimeError, IndexError) as error:
        if mode == "field":
            return 1
        decision("deny", f"Safety check could not validate this operation: {error}. "
                 "Correct the hook input or patch before retrying.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
