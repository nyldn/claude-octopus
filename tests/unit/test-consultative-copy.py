#!/usr/bin/env python3
"""Filesystem-level contracts for the default descriptor-based advisory copy."""

import importlib.util
import errno
import os
from pathlib import Path
import stat
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('consultative_copy', ROOT / 'scripts/helpers/consultative-copy.py')
copy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(copy)


@unittest.skipUnless(copy.supported(), 'descriptor copying is unsupported on this platform')
class CopyContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.source = self.base / 'source'
        self.destination = self.base / 'destination'
        self.outside = self.base / 'outside'
        for directory in (self.source, self.destination, self.outside):
            directory.mkdir()
        self.git('init', '-q')

    def git(self, *args, root=None):
        # Fixture writes use the same clean Git environment as enumeration.
        with copy.Directory(str(root or self.source)) as directory:
            return copy.git(directory, *args)

    def file(self, relative, content=b'safe bytes', tracked=True):
        target = self.source / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        if tracked:
            self.git('add', '--', relative)
        return target

    def link(self, relative, target):
        (self.source / relative).parent.mkdir(parents=True, exist_ok=True)
        (self.source / relative).symlink_to(target)
        self.git('add', '--', relative)

    def run_copy(self, scope=''):
        with copy.Directory(str(self.source)) as source, copy.Directory(str(self.destination)) as destination:
            copy.copy_tree(source, destination, scope)

    def mutate_before_leaf(self, action):
        original = copy.copy_leaf
        def changed(*args):
            action()
            return original(*args)
        return mock.patch.object(copy, 'copy_leaf', side_effect=changed)

    def test_working_tree_bytes_modes_ignored_deleted_and_unusual_names(self):
        target = self.file('deep/file with\nnewline')
        target.write_bytes(b'modified bytes')
        target.chmod(0o755)
        self.file('empty', b'')
        self.file('deleted/leaf').unlink()
        (self.source / 'deleted').rmdir()
        self.file('.gitignore', b'ignored\n')
        self.file('ignored', tracked=False)
        self.file('untracked', tracked=False)
        self.run_copy()
        self.assertEqual((self.destination / 'deep/file with\nnewline').read_bytes(), b'modified bytes')
        self.assertEqual(stat.S_IMODE((self.destination / 'deep/file with\nnewline').stat().st_mode), 0o755)
        self.assertEqual((self.destination / 'empty').read_bytes(), b'')
        self.assertTrue((self.destination / 'untracked').is_file())
        self.assertFalse((self.destination / 'ignored').exists())
        self.assertFalse((self.destination / '.git').exists())

    def test_safe_and_dangling_symlinks_are_preserved(self):
        self.file('deep/value')
        self.link('deep/safe', 'value')
        self.link('deep/dangling', '../missing/value')
        self.run_copy()
        self.assertEqual((self.destination / 'deep/safe').read_bytes(), b'safe bytes')
        self.assertEqual(os.readlink(self.destination / 'deep/dangling'), '../missing/value')

    def test_deleted_index_descendant_under_regular_file_is_skipped(self):
        self.file('a/b').unlink()
        (self.source / 'a').rmdir()
        self.file('a', b'replacement bytes', tracked=False)
        self.run_copy()
        self.assertEqual((self.destination / 'a').read_bytes(), b'replacement bytes')

    def test_tracked_regular_replaced_by_plain_directory_copies_untracked_contents(self):
        self.file('a\twith\nname').unlink()
        self.file('a\twith\nname/value', b'replacement directory bytes', tracked=False)
        self.file('.gitignore', b'a*with*name/ignored\n')
        self.file('a\twith\nname/ignored', b'ignored bytes', tracked=False)
        with mock.patch.object(copy.subprocess, 'run', wraps=subprocess.run) as commands:
            self.run_copy()
        self.assertEqual(commands.call_count, 2)
        self.assertEqual((self.destination / 'a\twith\nname/value').read_bytes(),
                         b'replacement directory bytes')
        self.assertFalse((self.destination / 'a\twith\nname/ignored').exists())

    def test_deleted_index_descendant_under_unsafe_ancestor_is_fatal(self):
        self.file('a/b').unlink()
        (self.source / 'a').rmdir()
        self.file('contained/value')
        for kind in ('symlink', 'fifo'):
            with self.subTest(kind=kind):
                if kind == 'symlink':
                    (self.source / 'a').symlink_to('contained')
                else:
                    os.mkfifo(self.source / 'a')
                try:
                    with copy.Directory(str(self.source)) as source:
                        with self.assertRaises(copy.UnsafeCopy):
                            copy.Directory.child(source.fd, 'a')
                    with self.assertRaises(copy.UnsafeCopy):
                        self.run_copy()
                finally:
                    (self.source / 'a').unlink()

    def test_directory_type_change_after_stat_is_not_a_deleted_index_entry(self):
        self.file('safe/value')
        original_open = os.open
        for kind in ('file', 'symlink', 'missing'):
            with self.subTest(kind=kind):
                swapped = False
                def racing_open(path, *args, **kwargs):
                    nonlocal swapped
                    if path == 'safe' and kwargs.get('dir_fd') is not None and not swapped:
                        swapped = True
                        (self.source / 'safe').rename(self.base / 'original')
                        if kind == 'file':
                            (self.source / 'safe').write_bytes(b'replacement')
                        elif kind == 'symlink':
                            (self.source / 'safe').symlink_to(self.outside)
                    return original_open(path, *args, **kwargs)
                try:
                    with mock.patch.object(copy.os, 'open', side_effect=racing_open):
                        with self.assertRaises(copy.UnsafeCopy):
                            self.run_copy()
                    self.assertTrue(swapped)
                finally:
                    if (self.source / 'safe').exists() or (self.source / 'safe').is_symlink():
                        (self.source / 'safe').unlink()
                    (self.base / 'original').rename(self.source / 'safe')

    def test_file_wrapper_failures_and_success_close_each_raw_descriptor_once(self):
        target = self.file('value')
        original_fdopen, original_close = os.fdopen, os.close
        for stage in ('input', 'output', 'success'):
            with self.subTest(stage=stage):
                captured, closed, ownership = [], [], []
                def wrapping(fd, mode, *args, **kwargs):
                    captured.append(fd)
                    ownership.append(kwargs.get('closefd', True))
                    if (stage == 'input' and mode == 'rb') or (stage == 'output' and mode == 'wb'):
                        raise OSError(errno.EMFILE, 'inert file-wrapper factory failure')
                    return original_fdopen(fd, mode, *args, **kwargs)
                def closing(fd):
                    closed.append(fd)
                    return original_close(fd)
                with copy.Directory(str(self.source)) as source, copy.Directory(str(self.destination)) as destination:
                    try:
                        with mock.patch.object(copy.os, 'fdopen', side_effect=wrapping), \
                                mock.patch.object(copy.os, 'close', side_effect=closing):
                            if stage == 'success':
                                copy.copy_regular(source.fd, destination.fd, 'value', target.stat())
                            else:
                                with self.assertRaises(OSError):
                                    copy.copy_regular(source.fd, destination.fd, 'value', target.stat())
                        self.assertEqual(ownership, [False] * len(captured))
                        for fd in captured:
                            self.assertEqual(closed.count(fd), 1)
                            with self.assertRaises(OSError):
                                os.fstat(fd)
                    finally:
                        # Mutant controls must not leak descriptors into later cases.
                        for fd in captured:
                            try:
                                os.fstat(fd)
                            except OSError:
                                continue
                            original_close(fd)
                if stage == 'success':
                    self.assertEqual((self.destination / 'value').read_bytes(), b'safe bytes')
                if (self.destination / 'value').exists():
                    (self.destination / 'value').unlink()

    def test_absolute_escaping_and_resolved_escaping_links_fail(self):
        (self.outside / 'secret').write_bytes(b'outside bytes')
        for target in (str(self.outside / 'secret'), '../outside/secret', '../../outside/secret'):
            with self.subTest(target=target):
                self.link('link', target)
                with self.assertRaises((copy.UnsafeCopy, OSError)):
                    self.run_copy()
                (self.source / 'link').unlink()

    def test_selected_subtree_is_literal_and_confines_links(self):
        self.file('a[1]/value')
        self.file('a1/value', b'wrong scope')
        self.link('a[1]/link', 'value')
        self.run_copy('a[1]')
        self.assertTrue((self.destination / 'a[1]/value').exists())
        self.assertFalse((self.destination / 'a1').exists())
        (self.source / 'a[1]/link').unlink()
        self.link('a[1]/link', '../a1/value')
        with self.assertRaises(copy.UnsafeCopy):
            with copy.Directory(str(self.source)) as root:
                copy.confined_link(root, 'a[1]/link', '../a1/value', 'a[1]')

    def test_generated_untracked_state_is_excluded_but_tracked_state_is_retained(self):
        self.file('octopus-copy-lists.123.456.abcdef/tracked')
        self.file('octopus-consultative.abcdef/private', tracked=False)
        self.file('deep/octopus-copy-lists.123.456.abcdef/private', tracked=False)
        self.file('octopus-copy-lists.123.456.ab.cde/ordinary', tracked=False)
        self.file('octopus-consultative.ab.cde/private', tracked=False)
        self.run_copy()
        self.assertTrue((self.destination / 'octopus-copy-lists.123.456.abcdef/tracked').exists())
        self.assertFalse((self.destination / 'octopus-consultative.abcdef').exists())
        self.assertFalse((self.destination / 'deep').exists())
        self.assertTrue((self.destination / 'octopus-copy-lists.123.456.ab.cde/ordinary').exists())
        self.assertFalse((self.destination / 'octopus-consultative.ab.cde').exists())

    def test_nested_git_trees_honor_their_own_ignore_rules(self):
        for replaces_index_file in (False, True):
            with self.subTest(replaces_index_file=replaces_index_file):
                name = 'replaced' if replaces_index_file else 'child'
                if replaces_index_file:
                    self.file(name).unlink()
                child = self.source / name
                child.mkdir()
                self.git('init', '-q', root=child)
                (child / '.gitignore').write_text('ignored\n')
                (child / 'value').write_bytes(b'child working tree')
                (child / 'ignored').write_bytes(b'nested secret')
                self.git('add', '.gitignore', 'value', root=child)
                self.run_copy()
                self.assertEqual((self.destination / name / 'value').read_bytes(), b'child working tree')
                self.assertFalse((self.destination / name / '.git').exists())
                self.assertFalse((self.destination / name / 'ignored').exists())
                shutil.rmtree(self.destination / name)

    def test_broken_nested_git_marker_fails_without_full_copy(self):
        self.file('child/value', tracked=False)
        oid = subprocess.check_output(['git', '-C', str(self.source), 'hash-object', '-w', '--stdin'], input=b'fixture').decode().strip()
        self.git('update-index', '--add', '--cacheinfo', '160000', oid, 'child')
        for marker in (None, 'gitdir: missing\n'):
            with self.subTest(marker=marker):
                if marker is not None:
                    (self.source / 'child/.git').write_text(marker)
                with self.assertRaises(copy.UnsafeCopy) as error:
                    self.run_copy()
                if marker is None:
                    self.assertIn('nested Git metadata is missing', str(error.exception))
                self.assertFalse((self.destination / 'child/value').exists())

    def test_ambient_git_state_and_trace_sinks_do_not_cross_enumeration(self):
        self.file('value')
        trace = self.outside / 'trace'
        env = {'GIT_DIR': str(self.outside), 'GIT_WORK_TREE': str(self.outside),
               'GIT_TRACE': str(trace), 'GIT_CONFIG_COUNT': '1',
               'GIT_CONFIG_KEY_0': 'core.worktree', 'GIT_CONFIG_VALUE_0': str(self.outside)}
        with mock.patch.dict(os.environ, env):
            self.run_copy()
        self.assertFalse(trace.exists())
        self.assertEqual((self.destination / 'value').read_bytes(), b'safe bytes')

    def test_root_replacement_after_enumeration_fails(self):
        self.file('value')
        def replace():
            self.source.rename(self.base / 'original')
            self.outside.rename(self.source)
        with self.mutate_before_leaf(replace), self.assertRaises(copy.UnsafeCopy):
            self.run_copy()
        self.assertFalse((self.destination / 'value').exists())

    def test_root_replacement_during_git_enumeration_fails(self):
        self.file('value')
        original = subprocess.run
        changed = False
        def replace(*args, **kwargs):
            nonlocal changed
            if not changed:
                changed = True
                self.source.rename(self.base / 'original')
                self.outside.rename(self.source)
            return original(*args, **kwargs)
        with mock.patch.object(copy.subprocess, 'run', side_effect=replace), self.assertRaises(copy.UnsafeCopy):
            self.run_copy()
        self.assertFalse((self.destination / 'value').exists())

    def test_nested_root_replacement_before_discovery_fails(self):
        child = self.source / 'child'
        child.mkdir()
        self.git('init', '-q', root=child)
        (child / 'value').write_bytes(b'safe')
        self.git('add', 'value', root=child)
        original = copy.git
        def replace(root, *arguments):
            if root.path == str(child):
                child.rename(self.base / 'original')
                self.outside.rename(child)
            return original(root, *arguments)
        with mock.patch.object(copy, 'git', side_effect=replace), self.assertRaises(copy.UnsafeCopy):
            self.run_copy()

    def test_resolved_symlink_chain_cannot_escape(self):
        self.link('a', 'b')
        self.link('b', str(self.outside))
        with self.assertRaises(copy.UnsafeCopy):
            self.run_copy()

    def test_regular_destination_replacement_after_copy_fails(self):
        self.file('value')
        secret = self.outside / 'secret'
        secret.write_bytes(b'outside bytes')
        original = copy.copy_regular
        for replacement in ('symlink', 'regular', 'same-inode', 'mode'):
            with self.subTest(replacement=replacement):
                fired = []
                def replace(*args):
                    result = original(*args)
                    output = self.destination / 'value'
                    if replacement == 'same-inode':
                        output.write_bytes(b'replacement bytes')
                    elif replacement == 'mode':
                        output.chmod(0o700)
                    else:
                        output.rename(self.base / ('original-' + replacement))
                    if replacement == 'symlink':
                        output.symlink_to(secret)
                    elif replacement == 'regular':
                        output.write_bytes(b'replacement bytes')
                    fired.append(True)
                    return result
                with mock.patch.object(copy, 'copy_regular', side_effect=replace), self.assertRaises(copy.UnsafeCopy):
                    self.run_copy()
                self.assertEqual(fired, [True])
                self.assertEqual(secret.read_bytes(), b'outside bytes')
            shutil.rmtree(self.destination)
            self.destination.mkdir()

    def test_created_symlink_replacement_with_confined_target_fails(self):
        self.file('safe')
        self.file('alternate')
        self.link('link', 'safe')
        original = copy.copy_leaf
        fired = []
        def replace(*args):
            result = original(*args)
            if args[2] == 'link':
                (self.destination / 'link').rename(self.base / 'original-link')
                (self.destination / 'link').symlink_to('alternate')
                fired.append(True)
            return result
        with mock.patch.object(copy, 'copy_leaf', side_effect=replace), self.assertRaises(copy.UnsafeCopy):
            self.run_copy()
        self.assertEqual(fired, [True])

    def test_nested_destinations_are_rechecked_after_outer_copy(self):
        child = self.source / 'child'
        child.mkdir()
        self.git('init', '-q', root=child)
        (child / 'value').write_bytes(b'nested bytes')
        self.git('add', 'value', root=child)
        self.file('trigger')
        secret = self.outside / 'value'
        secret.write_bytes(b'outside bytes')
        original = copy.copy_regular
        for replacement in ('leaf', 'ancestor'):
            with self.subTest(replacement=replacement):
                fired = []
                def replace(*args):
                    result = original(*args)
                    if args[2] == 'trigger':
                        nested = self.destination / 'child'
                        if replacement == 'leaf':
                            (nested / 'value').unlink()
                            (nested / 'value').symlink_to(secret)
                        else:
                            nested.rename(self.base / 'original-child')
                            nested.symlink_to(self.outside, target_is_directory=True)
                        fired.append(True)
                    return result
                with mock.patch.object(copy, 'copy_regular', side_effect=replace), self.assertRaises((copy.UnsafeCopy, OSError)):
                    self.run_copy()
                self.assertEqual(fired, [True])
                self.assertEqual(secret.read_bytes(), b'outside bytes')
            shutil.rmtree(self.destination)
            self.destination.mkdir()

    def test_empty_nested_destination_is_rechecked_after_outer_copy(self):
        child = self.source / 'child'
        child.mkdir()
        self.git('init', '-q', root=child)
        self.file('trigger')
        original = copy.copy_regular
        fired = []
        def replace(*args):
            result = original(*args)
            (self.destination / 'child').rename(self.base / 'original-child')
            (self.destination / 'child').symlink_to(self.outside, target_is_directory=True)
            fired.append(True)
            return result
        with mock.patch.object(copy, 'copy_regular', side_effect=replace), self.assertRaises((copy.UnsafeCopy, OSError)):
            self.run_copy()
        self.assertEqual(fired, [True])

    def test_destination_inside_source_is_rejected_by_default_entrypoint(self):
        child = self.source / 'output'
        child.mkdir()
        script = 'source "$1/scripts/lib/agent-sync.sh"; _octopus_copy_git_tracked_tree "$2" "$3"'
        result = subprocess.run(['bash', '-c', script, 'test', str(ROOT), str(self.source), str(child)],
                                text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(child.iterdir()), [])

    def test_direct_source_root_symlink_is_rejected(self):
        self.file('value')
        alias = self.base / 'source-link'
        alias.symlink_to(self.source)
        script = 'source "$1/scripts/lib/agent-sync.sh"; _octopus_copy_git_tracked_tree "$2" "$3"'
        result = subprocess.run(['bash', '-c', script, 'test', str(ROOT), str(alias), str(self.destination)],
                                text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.destination.iterdir()), [])

    def test_real_ancestor_replacement_after_validation_fails(self):
        self.file('safe/deep/value')
        def replace():
            (self.source / 'safe/deep').rename(self.base / 'original')
            self.outside.rename(self.source / 'safe/deep')
        with self.mutate_before_leaf(replace), self.assertRaises(copy.UnsafeCopy):
            self.run_copy()

    def test_ancestor_symlink_replacement_after_validation_fails(self):
        self.file('safe/value')
        def replace():
            (self.source / 'safe').rename(self.base / 'original')
            (self.source / 'safe').symlink_to(self.outside)
        with self.mutate_before_leaf(replace), self.assertRaises((copy.UnsafeCopy, OSError)):
            self.run_copy()

    def test_source_directory_swap_between_stat_and_open_fails(self):
        self.file('safe/deep/value')
        original_open = os.open
        swapped = False
        def racing_open(path, *args, **kwargs):
            nonlocal swapped
            if path == 'deep' and kwargs.get('dir_fd') is not None and not swapped:
                swapped = True
                (self.source / 'safe/deep').rename(self.base / 'original')
                self.outside.rename(self.source / 'safe/deep')
            return original_open(path, *args, **kwargs)
        with mock.patch.object(copy.os, 'open', side_effect=racing_open), self.assertRaises(copy.UnsafeCopy):
            self.run_copy()
        self.assertTrue(swapped)

    def test_source_leaf_replacement_with_link_or_real_file_fails(self):
        for kind in ('symlink', 'file'):
            with self.subTest(kind=kind):
                target = self.file('value')
                (self.outside / 'secret').write_bytes(b'outside bytes')
                def replace():
                    target.rename(self.base / ('original-' + kind))
                    if kind == 'symlink':
                        target.symlink_to(self.outside / 'secret')
                    else:
                        (self.outside / 'secret').rename(target)
                with self.mutate_before_leaf(replace), self.assertRaises(copy.UnsafeCopy):
                    self.run_copy()
                target.unlink()
        self.assertFalse((self.destination / 'value').exists())

    def test_an_entered_source_directory_cannot_redirect_reads_after_swap(self):
        self.file('safe/value')
        (self.outside / 'value').write_bytes(b'outside secret')
        original = copy.copy_regular
        def replace(*args):
            (self.source / 'safe').rename(self.base / 'original')
            (self.source / 'safe').symlink_to(self.outside)
            return original(*args)
        with mock.patch.object(copy, 'copy_regular', side_effect=replace):
            self.run_copy()
        self.assertEqual((self.destination / 'safe/value').read_bytes(), b'safe bytes')

    def test_destination_ancestor_redirection_never_writes_outside(self):
        self.file('safe/value')
        original = copy.copy_regular
        def replace(*args):
            (self.destination / 'safe').rename(self.base / 'old-output')
            (self.destination / 'safe').symlink_to(self.outside)
            return original(*args)
        with mock.patch.object(copy, 'copy_regular', side_effect=replace), self.assertRaises((copy.UnsafeCopy, OSError)):
            self.run_copy()
        self.assertFalse((self.outside / 'value').exists())

    def test_destination_leaf_symlink_is_never_followed(self):
        self.file('value')
        outside = self.outside / 'secret'
        outside.write_bytes(b'unchanged')
        (self.destination / 'value').symlink_to(outside)
        with self.assertRaises(OSError):
            self.run_copy()
        self.assertEqual(outside.read_bytes(), b'unchanged')

    def test_destination_root_replacement_fails(self):
        self.file('value')
        def replace():
            self.destination.rename(self.base / 'old-output')
            self.outside.rename(self.destination)
        with self.mutate_before_leaf(replace), self.assertRaises(copy.UnsafeCopy):
            self.run_copy()
        self.assertFalse((self.destination / 'value').exists())

    def test_regular_to_fifo_swap_before_open_does_not_wait_for_a_writer(self):
        target = self.file('value')
        original_open = os.open
        swapped = False
        def racing_open(path, flags, *args, **kwargs):
            nonlocal swapped
            if path == 'value' and flags & os.O_NONBLOCK and not swapped:
                swapped = True
                target.unlink()
                os.mkfifo(target)
            return original_open(path, flags, *args, **kwargs)
        with mock.patch.object(copy.os, 'open', side_effect=racing_open), self.assertRaises(copy.UnsafeCopy):
            self.run_copy()
        self.assertTrue(swapped)

    def test_special_files_are_rejected_without_blocking(self):
        fifo = self.source / 'pipe'
        os.mkfifo(fifo)
        with self.assertRaises(copy.UnsafeCopy):
            with copy.Directory(str(self.source)) as source, copy.Directory(str(self.destination)) as destination:
                copy.copy_leaf(source, destination, 'pipe', fifo.lstat(), [], '')

    def test_growing_source_is_bounded_and_rejected(self):
        target = self.file('value', b'initial')
        original_fdopen = os.fdopen
        def grow(fd, mode, *args, **kwargs):
            if mode == 'wb':
                with target.open('ab') as output:
                    output.write(b'growth' * 100000)
            return original_fdopen(fd, mode, *args, **kwargs)
        with mock.patch.object(copy.os, 'fdopen', side_effect=grow), self.assertRaises(copy.UnsafeCopy):
            self.run_copy()
        self.assertLessEqual((self.destination / 'value').stat().st_size, 7)

    def test_failure_does_not_leak_directory_descriptors(self):
        self.file('safe/value')
        if not Path('/proc/self/fd').is_dir():
            self.skipTest('descriptor count evidence needs procfs')
        before = len(os.listdir('/proc/self/fd'))
        for unused in range(20):
            with copy.Directory(str(self.source)) as source:
                with self.assertRaises(FileNotFoundError):
                    with source.descend(['safe', 'missing']):
                        pass
        self.assertEqual(len(os.listdir('/proc/self/fd')), before)

    def test_many_files_use_two_git_processes_per_repository(self):
        for i in range(300):
            self.file('deep/file-' + str(i), bytes([i % 256]), tracked=False)
        original = subprocess.run
        with mock.patch.object(copy.subprocess, 'run', wraps=original) as runner:
            self.run_copy()
        self.assertEqual(runner.call_count, 2)
        self.assertEqual(len(list((self.destination / 'deep').iterdir())), 300)

    def test_default_shell_entrypoint_copies_without_portable_leaf_processes(self):
        self.file('safe/value')
        script = ('source "$1/scripts/lib/agent-sync.sh"; '
                  '_octopus_copy_leaf_safely() { echo unexpected-leaf-process >&2; return 91; }; '
                  '_octopus_prepare_consultative_workspace "$2"')
        result = subprocess.run(['bash', '-c', script, 'test', str(ROOT), str(self.source)],
                                text=True, capture_output=True, check=True)
        workspace = Path(result.stdout.strip())
        self.addCleanup(shutil.rmtree, workspace.parent)
        self.assertEqual((workspace / 'safe/value').read_bytes(), b'safe bytes')
        self.assertEqual(result.stderr, '')

    def test_default_helper_ignores_repository_pythonpath(self):
        self.file('value')
        marker = self.outside / 'executed'
        (self.source / 'sitecustomize.py').write_text('from pathlib import Path\nPath(' + repr(str(marker)) + ').touch()\n')
        script = 'source "$1/scripts/lib/agent-sync.sh"; _octopus_prepare_consultative_workspace "$2"'
        env = dict(os.environ, PYTHONPATH=str(self.source))
        result = subprocess.run(['bash', '-c', script, 'test', str(ROOT), str(self.source)],
                                env=env, text=True, capture_output=True, check=True)
        self.addCleanup(shutil.rmtree, Path(result.stdout.strip()).parent)
        self.assertFalse(marker.exists())

    def test_rejected_default_copy_removes_workspace_before_dispatch(self):
        self.link('escape', str(self.outside))
        temporary = self.base / 'allocations'
        temporary.mkdir()
        script = 'source "$1/scripts/lib/agent-sync.sh"; _octopus_prepare_consultative_workspace "$2"'
        result = subprocess.run(['bash', '-c', script, 'test', str(ROOT), str(self.source)],
                                env=dict(os.environ, TMPDIR=str(temporary)), text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertEqual(list(temporary.iterdir()), [])


    def test_directory_to_file_race_at_open_fails(self):
        self.file('safe/deep/value')
        original_open = os.open
        swapped = False
        def racing_open(path, *args, **kwargs):
            nonlocal swapped
            if path == 'deep' and kwargs.get('dir_fd') is not None and not swapped:
                swapped = True
                directory = self.source / 'safe/deep'
                directory.rename(self.base / 'original')
                directory.write_bytes(b'replaced after validation')
            return original_open(path, *args, **kwargs)
        with mock.patch.object(copy.os, 'open', side_effect=racing_open), self.assertRaises(copy.UnsafeCopy):
            self.run_copy()
        self.assertTrue(swapped)


if __name__ == '__main__':
    unittest.main()
