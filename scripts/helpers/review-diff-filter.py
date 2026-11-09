#!/usr/bin/env python3
"""Remove complete Git diff blocks selected by repository-relative path globs."""

import codecs
import fnmatch
import re
import sys


def git_path(value):
    """Decode Git's C-quoted bytes, including octal UTF-8 and control characters."""
    if value.startswith(b'"') and value.endswith(b'"'):
        value = codecs.escape_decode(value[1:-1])[0]
    return value.decode("utf-8", "surrogateescape")


def block_path(block):
    """Prefer destination metadata; deleted files use their original path."""
    header = block.split(b"\n", 1)[0].removeprefix(b"diff --git ").rstrip(b"\r")
    middle = len(header) // 2
    # --no-prefix repeats the complete path, even for binary/mode-only changes.
    # Comparing byte halves preserves spaces and Git's C-quoted token boundary.
    original = destination = None
    for line in block.splitlines()[1:]:
        if line.startswith((b"@@", b"GIT binary patch", b"Binary files ")):
            break
        if line.startswith((b"rename to ", b"copy to ")):
            return git_path(line.split(b" to ", 1)[1])
        if line.startswith(b"--- "):
            original = line[4:].split(b"\t", 1)[0]
        if line.startswith(b"+++ "):
            destination = line[4:].split(b"\t", 1)[0]
    # Rename/copy destinations above take precedence: a standard header can
    # coincidentally have equal halves for a path containing " a/" or " b/".
    if header[middle:middle + 1] == b" " and header[:middle] == header[middle + 1:]:
        return git_path(header[:middle])
    value = original if destination == b"/dev/null" else destination
    if value:
        path = git_path(value)
        return path[2:] if path.startswith(("a/", "b/")) else None
    # Binary and mode-only changes have no +++ header. Unquoted Git paths
    # may contain spaces; identical old/new names disambiguate those headers.
    quoted = re.fullmatch(rb'("(?:\\.|[^"\\])*") (.+)', header)
    if quoted:
        left, right = (git_path(value) for value in quoted.groups())
        return right[2:] if left.startswith("a/") and right.startswith("b/") else None
    candidates = []
    for separator in re.finditer(rb' (?=b/|")', header):
        left, right = git_path(header[:separator.start()]), git_path(header[separator.end():])
        if left.startswith("a/") and right.startswith("b/"):
            if left[2:] == right[2:]:
                return right[2:]
            candidates.append(right[2:])
    return candidates[0] if len(candidates) == 1 else None


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: review-diff-filter.py SKIP_PATTERNS < DIFF")
    patterns = [line.strip().strip("`") for line in sys.argv[1].splitlines() if line.strip()]
    # Keep line endings and hunk bytes intact. Unknown formats remain reviewable.
    for block in re.split(rb"(?m)(?=^diff --git )", sys.stdin.buffer.read()):
        path = block_path(block) if block.startswith(b"diff --git ") else None
        if path is not None and any(
            fnmatch.fnmatchcase(path, pattern + "*" if pattern.endswith("/") else pattern)
            for pattern in patterns
        ):
            continue
        sys.stdout.buffer.write(block)


if __name__ == "__main__":
    main()
