#!/usr/bin/env python3
"""Copy eligible Git working-tree bytes through inode-checked directory FDs."""

import contextlib
import os
import re
import stat
import subprocess
import sys


class UnsafeCopy(ValueError):
    pass


def identity(info):
    return info.st_dev, info.st_ino


def parts(path):
    result = path.split('/')
    if not path or any(p in ('', '.', '..', '.git') for p in result):
        raise UnsafeCopy('invalid repository-relative entry')
    return result


def supported():
    return (hasattr(os, 'O_NOFOLLOW') and hasattr(os, 'O_DIRECTORY')
            and all(f in os.supports_dir_fd for f in
                    (os.open, os.stat, os.mkdir, os.readlink, os.symlink, os.utime))
            and all(f in os.supports_follow_symlinks for f in (os.stat, os.utime)))


class Directory:
    """An opened root plus checked, non-link descendants, following feature helpers."""

    flags = os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0) | getattr(os, 'O_NOFOLLOW', 0)

    def __init__(self, path, expected=None):
        self.path = os.path.abspath(path)
        self.fd = os.open('/', self.flags)
        try:
            for name in self.path.split('/')[1:]:
                if name:
                    child = self.child(self.fd, name)
                    os.close(self.fd)
                    self.fd = child
            self.identity = identity(os.fstat(self.fd))
            if expected is not None and self.identity != expected:
                raise UnsafeCopy('root identity changed before opening')
            self.check()
        except BaseException:
            os.close(self.fd)
            raise

    def __enter__(self):
        return self

    def __exit__(self, *unused):
        os.close(self.fd)

    def check(self):
        current = os.stat(self.path, follow_symlinks=False)
        if not stat.S_ISDIR(current.st_mode) or identity(current) != self.identity:
            raise UnsafeCopy('root identity changed')

    @classmethod
    def child(cls, parent, name, expected=None, create=False):
        if create:
            try:
                os.mkdir(name, 0o755, dir_fd=parent)
            except FileExistsError:
                pass
        before = os.stat(name, dir_fd=parent, follow_symlinks=False)
        if not stat.S_ISDIR(before.st_mode):
            raise UnsafeCopy('directory ancestor is not a real directory')
        child = os.open(name, cls.flags, dir_fd=parent)
        if identity(before) != identity(os.fstat(child)) or (expected is not None and identity(before) != expected):
            os.close(child)
            raise UnsafeCopy('directory identity changed before entry')
        return child

    @contextlib.contextmanager
    def descend(self, components, expected=None, create=False):
        current = os.dup(self.fd)
        captured = []
        try:
            for i, name in enumerate(components):
                child = self.child(current, name, None if expected is None else expected[i], create)
                os.close(current)
                current = child
                captured.append(identity(os.fstat(current)))
            yield current, captured
        finally:
            os.close(current)


def git(root, *arguments):
    """Run Git from the held directory, without inherited repository routing."""
    root.check()
    environment = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    previous = os.open('.', Directory.flags)
    try:
        os.fchdir(root.fd)
        result = subprocess.run(['git', '-c', 'core.fsmonitor=false', *arguments],
                                env=environment, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    finally:
        os.fchdir(previous)
        os.close(previous)
    root.check()
    if result.returncode:
        raise UnsafeCopy('Git enumeration or discovery failed')
    return result.stdout


def generated(path):
    pattern = r'(?:octopus-consultative|octopus-copy-lists)\.(?:[^/]{6}|[0-9]+\.[0-9]+\.[^/.]{6})'
    return any(re.fullmatch(pattern, name, re.DOTALL) for name in path.split('/'))


def confined_link(root, relative, target, scope=''):
    if not target or target.startswith('/'):
        raise UnsafeCopy('absolute or empty symlink target')
    scoped = relative[len(scope) + 1:] if scope else relative
    lexical = os.path.normpath(os.path.join(os.path.dirname(scoped), target))
    if lexical == '..' or lexical.startswith('../'):
        raise UnsafeCopy('symlink escapes selected tree')
    boundary = os.path.join(root.path, scope) if scope else root.path
    resolved = os.path.realpath(os.path.join(root.path, relative))
    if os.path.commonpath((boundary, resolved)) != boundary:
        raise UnsafeCopy('resolved symlink escapes selected tree')


def copy_leaf(source, destination, relative, info, ancestors, scope):
    components = parts(relative)
    output_target = None
    source.check()
    destination.check()
    with source.descend(components[:-1], ancestors) as (parent, unused):
        current = os.stat(components[-1], dir_fd=parent, follow_symlinks=False)
        if identity(current) != identity(info) or stat.S_IFMT(current.st_mode) != stat.S_IFMT(info.st_mode):
            raise UnsafeCopy('source leaf changed after validation')
        with destination.descend(components[:-1], create=True) as (output_parent, output_ancestors):
            if stat.S_ISLNK(current.st_mode):
                target = os.readlink(components[-1], dir_fd=parent)
                output_target = target
                confined_link(source, relative, target, scope)
                if identity(os.stat(components[-1], dir_fd=parent, follow_symlinks=False)) != identity(current):
                    raise UnsafeCopy('source symlink changed during read')
                os.symlink(target, components[-1], dir_fd=output_parent)
                created_identity = identity(os.stat(components[-1], dir_fd=output_parent, follow_symlinks=False))
                os.utime(components[-1], ns=(current.st_atime_ns, current.st_mtime_ns),
                         dir_fd=output_parent, follow_symlinks=False)
                output_info = os.stat(components[-1], dir_fd=output_parent, follow_symlinks=False)
                if identity(output_info) != created_identity:
                    raise UnsafeCopy('destination symlink changed during creation')
            elif stat.S_ISREG(current.st_mode):
                output_info = copy_regular(parent, output_parent, components[-1], current)
            else:
                raise UnsafeCopy('unsupported source leaf')
        # A replaced destination ancestor cannot make a successful copy vanish
        # or redirect a subsequent write, even when the old FD remains valid.
        with destination.descend(components[:-1], output_ancestors):
            pass
    source.check()
    destination.check()
    return output_info, output_ancestors, output_target


def copy_regular(parent, output_parent, name, expected):
    source_fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
    with os.fdopen(source_fd, 'rb', buffering=0) as input_file:
        before = os.fstat(input_file.fileno())
        if not stat.S_ISREG(before.st_mode) or identity(before) != identity(expected):
            raise UnsafeCopy('source leaf changed before open')
        output_fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                            0o600, dir_fd=output_parent)
        with os.fdopen(output_fd, 'wb') as output_file:
            remaining = before.st_size
            while remaining:
                chunk = input_file.read(min(remaining, 1024 * 1024))
                if not chunk:
                    raise UnsafeCopy('source bytes truncated during copy')
                output_file.write(chunk)
                remaining -= len(chunk)
            output_file.flush()
            after = os.fstat(input_file.fileno())
            if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns):
                raise UnsafeCopy('source bytes changed during copy')
            os.fchmod(output_file.fileno(), stat.S_IMODE(before.st_mode))
            os.utime(output_file.fileno(), ns=(before.st_atime_ns, before.st_mtime_ns))
            return os.fstat(output_file.fileno())


def copy_tree(source, destination, scope=''):
    pathspec = ['--', ':(literal,top)' + scope] if scope else []
    tracked = git(source, 'ls-files', '-z', '--cached', *pathspec).split(b'\0')
    untracked = git(source, 'ls-files', '-z', '--others', '--exclude-standard', *pathspec).split(b'\0')
    entries = dict.fromkeys(os.fsdecode(p).rstrip('/') for p in tracked if p)
    entries.update(dict.fromkeys(os.fsdecode(p).rstrip('/') for p in untracked if p and not generated(os.fsdecode(p))))
    leaves = []
    materialized = []
    for relative in entries:
        source.check()
        if scope and not relative.startswith(scope + '/') and relative != scope:
            raise UnsafeCopy('Git returned an entry outside the selected subtree')
        components = parts(relative)
        with contextlib.ExitStack() as stack:
            try:
                parent, ancestors = stack.enter_context(source.descend(components[:-1]))
            except FileNotFoundError:
                continue
            try:
                info = os.stat(components[-1], dir_fd=parent, follow_symlinks=False)
            except FileNotFoundError:
                continue  # Deleted index entries have no working-tree bytes.
            if stat.S_ISDIR(info.st_mode):
                materialized.extend(nested(source, destination, relative, info, ancestors))
            elif stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
                leaves.append((relative, info, ancestors))
            else:
                raise UnsafeCopy('unsupported source entry')
    for relative, info, ancestors in leaves:
        output_info, output_ancestors, output_target = copy_leaf(source, destination, relative, info, ancestors, scope)
        materialized.append((relative, stat.S_IFMT(info.st_mode), output_info, output_ancestors, output_target))
    source.check()
    destination.check()
    # Every produced leaf, including nested trees, must still be the inode we
    # wrote when the complete tree succeeds. Validate the final link graph too.
    for relative, kind, output_info, output_ancestors, output_target in materialized:
        components = parts(relative)
        with destination.descend(components[:-1], output_ancestors) as (parent, unused):
            current = os.stat(components[-1], dir_fd=parent, follow_symlinks=False)
            if stat.S_IFMT(current.st_mode) != kind or identity(current) != identity(output_info):
                raise UnsafeCopy('destination leaf changed after copy')
            if ((current.st_size, current.st_mode, current.st_mtime_ns, current.st_ctime_ns) !=
                    (output_info.st_size, output_info.st_mode, output_info.st_mtime_ns, output_info.st_ctime_ns)):
                raise UnsafeCopy('destination bytes or metadata changed after copy')
            if stat.S_ISLNK(kind):
                target = os.readlink(components[-1], dir_fd=parent)
                if target != output_target:
                    raise UnsafeCopy('destination symlink target changed after copy')
                confined_link(destination, relative, target, scope)
    source.check()
    destination.check()
    return materialized


def nested(source, destination, relative, info, ancestors):
    components = parts(relative)
    with source.descend(components, ancestors + [identity(info)]) as (fd, unused):
        try:
            os.stat('.git', dir_fd=fd, follow_symlinks=False)
        except FileNotFoundError as exc:
            raise UnsafeCopy('nested Git metadata is missing') from exc
        with destination.descend(components, create=True) as (output_fd, output_ancestors):
            expected_output = identity(os.fstat(output_fd))
        with Directory(os.path.join(source.path, relative), identity(info)) as child:
            top = os.fsdecode(git(child, 'rev-parse', '--show-toplevel')).rstrip('\n')
            if os.path.realpath(top) != child.path:
                raise UnsafeCopy('nested directory is not its own Git work tree')
            with Directory(os.path.join(destination.path, relative), expected_output) as output:
                materialized = copy_tree(child, output)
                output_info = os.fstat(output.fd)
    source.check()
    # Retain the nested root itself even if it has no eligible leaves.
    return [(relative, stat.S_IFMT(info.st_mode), output_info, output_ancestors[:-1], None)] + [
        (relative + '/' + path, kind, leaf_info, output_ancestors + ancestors, target)
        for path, kind, leaf_info, ancestors, target in materialized]


def main():
    if not supported():
        return 78  # The shell caller retains its portable, checked copier.
    if len(sys.argv) == 2 and sys.argv[1] == '--supported':
        return 0
    source_path, destination_path, scope, source_identity, destination_identity = sys.argv[1:]
    with Directory(source_path, tuple(map(int, source_identity.split(':')))) as source:
        with Directory(destination_path, tuple(map(int, destination_identity.split(':')))) as destination:
            if os.path.commonpath((source.path, destination.path)) == source.path:
                raise UnsafeCopy('destination is inside the source tree')
            if scope:
                with source.descend(parts(scope)):
                    pass
            copy_tree(source, destination, scope)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print('consultative copy failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
