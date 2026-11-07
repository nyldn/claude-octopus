#!/usr/bin/env python3
"""JSON and path checks used only by the careful and freeze hooks."""

import json
import os
from pathlib import Path
import re
import shlex
import sys


def decision(kind, reason):
    """Emit one permission decision in the host hook JSON format."""
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": kind,
        "permissionDecisionReason": reason}}, separators=(",", ":")))


def codex_host():
    """Detect a Codex hook from host markers or the loaded plugin cache path."""
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
    """Require a string that can be passed to filesystem operations."""
    if not isinstance(value, str) or "\0" in value:
        raise ValueError("expected a string without NUL bytes")
    return value


def payload():
    """Read one hook input object from standard input."""
    data = json.load(sys.stdin)
    if not isinstance(data, dict):
        raise ValueError("expected a hook JSON object")
    return data


def tool_input(data):
    """Return tool arguments after requiring an object-shaped input."""
    value = data.get("tool_input", {})
    if not isinstance(value, dict):
        raise ValueError("expected a tool_input object")
    return value


def patch_paths(command):
    """Parse literal patch paths without executing heredocs or shell wrappers."""
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
    """Resolve a path relative to cwd, rejecting invalid or inaccessible paths."""
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
    """Deny writes and patch operations whose resolved paths leave the boundary."""
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


def unsafe_recursive_delete(command, cwd=None):
    """Check each recursive forced rm target without executing shell input."""
    safe_names = {"node_modules", "dist", ".next", "__pycache__", "build", "coverage", ".turbo"}
    shell_names = {"bash", "sh", "zsh", "eval", "dash", "ksh", "mksh", "lksh", "ash", "fish", "csh", "tcsh"}
    command_readers = shell_names | {"source", ".", "xargs", "parallel"}
    literal_text = command.replace("\\\n", "").replace("'", "").replace('"', "").replace("\\", "")
    mentions_rm = bool(re.search(r"\brm\b", literal_text))
    # Quoted command substitutions still execute. Do not exempt their contents.
    if mentions_rm and ("$(" in command or "`" in command):
        return True
    # POSIX shlex removes quotes and escapes from literal operator arguments.
    # Reject ambiguous input before those arguments can become segment breaks.
    if mentions_rm:
        quote, escaped = None, False
        for char in command:
            if escaped:
                if char in ";&|()\n":
                    return True
                escaped = False
            elif char == "\\" and quote != "'":
                escaped = True
            elif quote:
                if char == quote:
                    quote = None
                elif char in ";&|()\n":
                    return True
            elif char in "'\"":
                quote = char
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()\n")
        lexer.whitespace = " \t\r"
        lexer.whitespace_split = True
        # shlex treats a midword # as a comment, unlike the shell. Keeping #
        # literal may over-warn on comments but cannot hide a later rm.
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError:
        return mentions_rm
    working_directory = Path(cwd or os.getcwd())
    if not working_directory.is_absolute():
        raise ValueError("hook cwd must be absolute")
    working_directory = working_directory.resolve()
    segments, current = [], []
    for token in tokens:
        if token and all(c in ";&|()\n" for c in token):
            segments.append(current)
            current = []
        else:
            current.append(token)
    segments.append(current)
    for args in segments:
        wrapper = bool(args and Path(args[0]).name in ("sudo", "command", "env", "exec", "busybox", "rtk"))
        if wrapper:
            rm_index = next((i for i, value in enumerate(args) if Path(value).name == "rm"), None)
            if rm_index is not None:
                args = args[rm_index:]
        while args and (re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*=.*", args[0])
                        or args[0] in ("sudo", "command", "env", "exec")):
            args = args[1:]
        if not args:
            continue
        executable = args[0] if args[0] == "." else Path(args[0]).name
        if executable in ("cd", "pushd", "popd"):
            working_directory = None
        if executable in command_readers:
            # These commands execute stdin or files, not just visible arguments.
            if mentions_rm or any(unsafe_recursive_delete(a, cwd) for a in args[1:]):
                return True
        if executable != "rm":
            # Only known data-only forms can ignore literal rm text. Unknown
            # shell grammar and execution wrappers must not obtain an exemption.
            if executable not in ("echo", "printf", "grep", "rg"):
                if any(re.search(r"\brm\b", arg) for arg in args):
                    return True
                if mentions_rm:
                    if any(char in args[0] for char in ("$", "`")):
                        return True
                    if any(Path(arg).name in command_readers for arg in args[1:]):
                        return True
            continue
        recursive = force = False
        targets, options = [], True
        for arg in args[1:]:
            if options and arg == "--":
                options = False
            elif options and arg.startswith("--"):
                if arg == "--recursive": recursive = True
                elif arg == "--force": force = True
                elif arg not in ("--verbose", "--dir", "--interactive", "--preserve-root"):
                    return True
            elif options and arg.startswith("-"):
                recursive |= "r" in arg or "R" in arg
                force |= "f" in arg
            else:
                targets.append(arg)
        if not (recursive and force):
            # Dynamic shell options may contain recursive/force flags.
            if any(c in a for a in args[1:] for c in ("$", "`")):
                return True
            continue
        if working_directory is None:
            return True
        for target in targets:
            if any(c in target for c in ("$", "`", "*", "?", "[", "~", "{", "}")):
                return True
            path = Path(target)
            resolved = (path if path.is_absolute() else working_directory / path).resolve()
            # Only artifacts below this working directory qualify. Ancestor
            # names and similarly named directories outside it grant no exemption.
            try:
                relative = resolved.relative_to(working_directory)
            except ValueError:
                return True
            if not any(part in safe_names for part in relative.parts):
                return True
    return False


def main():
    """Dispatch a hook operation and reject malformed safety inputs."""
    mode = ""
    try:
        mode = sys.argv[1]
        if mode == "careful-decision":
            reason = sys.argv[2]
            if codex_host():
                decision("deny", reason + " Codex cannot ask for approval from a hook. "
                         "Ask the user to review the command and authorize deactivating "
                         "/octo:careful for this session before retrying. "
                         "The hook environment also supports OCTO_CAREFUL_MODE=off.")
            else:
                decision("ask", reason + " Confirm you want to proceed.")
        elif mode == "careful-rm":
            data = payload()
            command = string(tool_input(data).get("command", data.get("command", "")))
            print("unsafe" if unsafe_recursive_delete(command, data.get("cwd")) else "safe")
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
        if mode in ("field", "careful-rm"):
            return 1
        decision("deny", f"Safety check could not validate this operation: {error}. "
                 "Correct the hook input or patch before retrying.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
