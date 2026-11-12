#!/usr/bin/env python3
"""Save a private, read-only review snapshot and scan its selected file bytes."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def git(repo, *args, optional=False):
    result = subprocess.run(["git", "-C", str(repo), *args], capture_output=True)
    if result.returncode:
        if optional:
            return None
        raise RuntimeError("Git review input could not be read: " +
                           result.stderr.decode("utf-8", "replace").strip())
    return result.stdout


def commit(repo, ref, optional=False):
    value = git(repo, "rev-parse", "--verify", "--end-of-options", ref + "^{commit}", optional=optional)
    return value.decode().strip() if value is not None else None


def object_map(repo, head, staged):
    records = git(repo, "ls-files", "--stage", "-z") if staged else git(repo, "ls-tree", "-r", "-z", head)
    entries = {}
    for record in records.split(b"\0"):
        if not record:
            continue
        metadata, path = record.split(b"\t", 1)
        mode, middle, last = metadata.split()
        if staged:
            if last != b"0":
                raise RuntimeError("Resolve unmerged index entries before reviewing.")
            oid = middle
        else:
            oid = last
        entries[os.fsdecode(path)] = (mode, oid)
    return entries


def scan(data):
    if b"\0" in data:
        return {"scan_status": "binary"}
    lines = data.decode("utf-8", "replace").splitlines()
    return {
        "scan_status": "scanned",
        "todo_count": sum(bool(re.search(r"TODO|FIXME|PLACEHOLDER|XXX", line)) for line in lines),
        "empty_function_count": sum(bool(re.search(r"function.*\{\s*\}|=>\s*\{\s*\}", line)) for line in lines),
        "null_return_count": sum(bool(re.search(r"return (null|undefined);", line)) for line in lines),
        "substantive_lines": sum(not re.match(r"^\s*(//|/\*|\*|#|import|export|$)", line) for line in lines),
        "mock_reference_count": sum(bool(re.search(r"const.*(mock|test|dummy|fake).*=", line)) for line in lines),
    }


def worktree_bytes(repo, path):
    candidate = repo / path
    if candidate.is_symlink():
        return None, "non-regular"
    if not candidate.exists():
        return None, "deleted"
    if os.path.commonpath([str(repo), str(candidate.resolve())]) != str(repo):
        raise RuntimeError("Review source resolves outside the worktree.")
    if not candidate.is_file():
        return None, "non-regular"
    return candidate.read_bytes(), None


def render_files(repo, paths):
    chunks = []
    for path in paths:
        data, skipped = worktree_bytes(repo, path)
        if skipped or b"\0" in data:
            data = ("Not reviewed as text: " + (skipped or "binary") + "\n").encode()
        chunks.append(("File: " + json.dumps(path) + "\nBytes: " + str(len(data)) + "\n").encode() + data + b"\n")
    return b"".join(chunks)


def snapshot(repo, base=None, requested_head="HEAD", requested_scope="auto", requested_paths=()):
    repo = Path(os.fsdecode(git(repo, "rev-parse", "--show-toplevel").removesuffix(b"\n"))).resolve()
    current_head = commit(repo, "HEAD", optional=True)
    flags = ["--no-ext-diff", "--no-textconv", "--no-color", "--no-renames"]
    pathspecs, literal_paths = [], []
    for value in requested_paths:
        candidate = Path(os.path.abspath(repo / value))
        if os.path.commonpath([str(repo), str(candidate)]) != str(repo):
            raise RuntimeError("Requested review path is outside the repository.")
        relative = os.path.relpath(candidate, repo)
        literal_paths.append(relative)
        pathspecs.append(":(literal)" + relative)
    staged = git(repo, "diff", *flags, "--cached", "--name-only", "-z", "--", *pathspecs)
    working = git(repo, "diff", *flags, "--name-only", "-z", "--", *pathspecs)
    file_input = False
    if requested_scope == "files" or (requested_scope == "working" and current_head is None):
        scope, head, args, file_input = requested_scope, current_head, [], True
    elif base is not None:
        base = commit(repo, base)
        head = commit(repo, requested_head)
        scope, args = "committed", [base, head]
    elif requested_scope == "staged" or (requested_scope == "auto" and staged):
        scope, head = "staged", current_head
        args = ["--cached"] + ([head] if head else [])
    elif requested_scope == "working" or (requested_scope == "auto" and working):
        scope, head = "working", current_head
        args = [head] if head else []
    elif current_head:
        scope, head = "committed", current_head
        parent = commit(repo, head + "^", optional=True)
        args = [parent, head] if parent else None
    elif requested_scope == "commit":
        raise RuntimeError("No commit is available for the requested review.")
    else:
        scope, head, args = "empty", None, []

    if file_input:
        records = git(repo, "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", *pathspecs)
        paths = {os.fsdecode(path) for path in records.split(b"\0") if path}
        for path in literal_paths:
            # An explicitly named file may be untracked or ignored. A directory
            # uses Git's inventory so ignored dependency trees stay excluded.
            if (repo / path).is_file() or (repo / path).is_symlink():
                paths.add(path)
            elif not (repo / path).is_dir():
                raise RuntimeError("Requested review path does not exist.")
        paths = sorted(paths)
        patch_args = path_args = None
        patch = render_files(repo, paths)
    else:
        if args is None:
            patch_args = ["show", "--format=", *flags, head, "--", *pathspecs]
            path_args = ["diff-tree", "--root", "--no-commit-id", "--no-renames", "--name-only", "-r", "-z", head, "--", *pathspecs]
        else:
            patch_args = ["diff", *flags, *args, "--", *pathspecs]
            path_args = ["diff", *flags, "--name-only", "-z", *args, "--", *pathspecs]
        patch = git(repo, *patch_args)
        tracked_paths = git(repo, *path_args)
        untracked_args = ["ls-files", "--others", "--exclude-standard", "-z", "--", *pathspecs]
        untracked_paths = git(repo, *untracked_args) if requested_scope == "working" else b""
        extra_paths = [os.fsdecode(path) for path in untracked_paths.split(b"\0") if path]
        if extra_paths:
            patch += b"\nUntracked files:\n" + render_files(repo, extra_paths)
        paths = list(dict.fromkeys(os.fsdecode(path) for path in
                                   (tracked_paths + untracked_paths).split(b"\0") if path))
    entries = object_map(repo, head, scope == "staged") if scope in ("staged", "committed") else {}
    files = []
    for path in paths:
        row = {"path": path}
        if Path(path).suffix.lower() not in {".ts", ".tsx", ".js", ".jsx", ".py", ".go", ".rs", ".sh"}:
            row["scan_status"] = "non-source"
        elif scope in ("staged", "committed"):
            entry = entries.get(path)
            if entry is None:
                row["scan_status"] = "deleted"
            elif entry[0] not in (b"100644", b"100755"):
                row["scan_status"] = "non-regular"
            else:
                row.update(scan(git(repo, "cat-file", "blob", entry[1].decode())))
        else:
            data, skipped = worktree_bytes(repo, path)
            row.update({"scan_status": skipped} if skipped else scan(data))
        files.append(row)
    if file_input:
        unchanged = render_files(repo, paths) == patch
    else:
        final_patch = git(repo, *patch_args)
        if extra_paths:
            final_patch += b"\nUntracked files:\n" + render_files(repo, extra_paths)
        unchanged = (final_patch == patch and git(repo, *path_args) == tracked_paths and
                     (requested_scope != "working" or git(repo, *untracked_args) == untracked_paths))
    if not unchanged or commit(repo, "HEAD", optional=True) != current_head:
        raise RuntimeError("Review input changed while it was being captured; take a fresh snapshot.")

    directory = Path(tempfile.mkdtemp(prefix="octopus-review-"))
    try:
        patch_file = directory / "input.txt"
        report_file = directory / "stub-report.json"
        manifest = directory / "manifest.json"
        patch_file.write_bytes(patch)
        report_file.write_text(json.dumps(files, indent=2) + "\n")
        manifest.write_text(json.dumps({"repo": str(repo), "scope": scope, "head": head,
                                       "base": base, "input_file": str(patch_file),
                                       "stub_report": str(report_file), "file_count": len(paths)}, indent=2) + "\n")
        for file in (patch_file, report_file, manifest):
            file.chmod(0o600)
        return manifest
    except BaseException:
        shutil.rmtree(directory)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".")
    parser.add_argument("--base", help="Explicit committed review base; otherwise prefer staged, working, then last commit")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--scope", choices=("auto", "staged", "working", "commit", "files"), default="auto")
    parser.add_argument("--path", action="append", default=[])
    args = parser.parse_args()
    if args.head != "HEAD" and args.base is None:
        parser.error("--head requires --base")
    if args.scope == "files" and not args.path:
        parser.error("--scope=files requires at least one --path")
    if args.base is not None and args.scope not in ("auto", "commit"):
        parser.error("--base requires a committed review scope")
    try:
        print(snapshot(args.repo, args.base, args.head, args.scope, args.path))
    except (OSError, RuntimeError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
