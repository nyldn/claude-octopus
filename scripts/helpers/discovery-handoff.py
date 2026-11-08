#!/usr/bin/env python3
"""Commit completed discovery research and give Define a verified private snapshot."""
from contextlib import contextmanager
import base64
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile


def project_root():
    """Use the same physical project override as state-manager.sh."""
    return Path(os.environ.get('OCTOPUS_STATE_PROJECT_ROOT') or os.getcwd()).resolve()


def locate(workspace, legacy_hint=None):
    """Keep a physical project's handoff location stable across remote changes.

    Adopt a single legacy record in place, preserving its existing lock and any
    recovery journal. The canonical index is keyed only by the physical path.
    """
    workspace = Path(workspace).resolve()
    identity = hashlib.sha256(os.fsencode(str(project_root()))).hexdigest()
    stable = workspace / 'handoffs' / identity / 'discovery-handoff.json'
    with locked(stable) as (stable_record, _):
        index = stable.parent / 'location.json'
        hint = None if legacy_hint is None else Path(legacy_hint).parent.resolve() / 'discovery-handoff.json'
        if index.exists():
            saved = load(index)
            location = Path(saved['location']).parent.resolve() / Path(saved['location']).name
            allowed = location == stable or (location.parent.parent == workspace / 'projects'
                                               and location.name == 'discovery-handoff.json')
            if not allowed:
                raise ValueError('handoff index points outside this workspace')
            if hint is not None and hint != location and os.path.lexists(hint):
                raise ValueError('another legacy handoff exists for the current namespace; automatic selection stopped')
            return str(location)
        candidates = []
        for candidate in (workspace / 'projects').glob('*/discovery-handoff.json'):
            try:
                if candidate.parent.is_symlink():
                    raise ValueError('legacy handoff directory is a symlink')
                # Atomic legacy records can be filtered before acquiring a lock;
                # unrelated project directories must remain untouched.
                load(candidate)
                with locked(candidate) as (legacy, _):
                    load(legacy)
                candidates.append(candidate)
            except (OSError, ValueError, KeyError, TypeError, AttributeError):
                if candidate == hint:
                    raise ValueError('current legacy handoff is unreadable or belongs to another project')
                continue
        if len(candidates) > 1:
            raise ValueError('multiple legacy handoffs match this project; automatic adoption stopped')
        location = candidates[0] if candidates else stable_record
        save(index, {'version': 1, 'project': str(project_root()), 'location': str(location)})
        return str(location)


def research_bytes(value, run_id):
    """Read regular nonempty research without following any child symlinks."""
    project = project_root()
    home = Path(os.environ['HOME'])
    candidate = Path(value)
    filename = 'probe-synthesis-' + run_id + '.md'
    if candidate in (home / '.claude-octopus/results' / filename,
                     home.resolve() / '.claude-octopus/results' / filename):
        anchor = home.resolve()
        relative = Path('.claude-octopus/results') / filename
    elif (candidate.parts[-3:] == ('.octo', 'phases', 'phase-1-summary.md')
          and candidate.parent.parent.parent.resolve() == project):
        anchor = project
        relative = Path('.octo/phases/phase-1-summary.md')
    else:
        raise ValueError('research path is outside the supported discovery locations')
    descriptor = os.open(anchor, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in relative.parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                            dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        child = os.open(relative.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                        dir_fd=descriptor)
        with os.fdopen(child, 'rb') as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                raise ValueError('research is not a readable regular file')
            contents = stream.read()
    finally:
        os.close(descriptor)
    if not contents:
        raise ValueError('research is empty')
    return anchor / relative, contents


@contextmanager
def locked(state_file):
    """Serialize handoff operations without racing unrelated lifecycle writers."""
    directory = Path(state_file).parent
    directory.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(directory / 'discovery-handoff.lock',
                         os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield directory / 'discovery-handoff.json', descriptor
    finally:
        os.close(descriptor)


def load(path):
    """Read the private sidecar without following a replacement link."""
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'r') as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError('handoff state is not a regular file')
        state = json.load(stream)
    if state.get('version') != 1 or state.get('project') != str(project_root()):
        raise ValueError('handoff state belongs to another project or schema')
    return state


def save(path, state):
    """Publish a complete private record with an atomic same-directory rename."""
    descriptor, temporary = tempfile.mkstemp(prefix='.discovery-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w') as stream:
            json.dump(state, stream)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def current(path, run_id):
    """Require the caller's run under the lock and recover unfinished writes."""
    state = recover(path, load(path))
    if state['run_id'] != run_id or run_id is None:
        raise ValueError('another discovery superseded this run')
    return state


@contextmanager
def project_parent(relative):
    """Open a fixed project file's parent without following directory links."""
    descriptor = os.open(project_root(), os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in Path(relative).parts[:-1]:
            try:
                os.mkdir(part, 0o755, dir_fd=descriptor)
            except FileExistsError:
                pass
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                            dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        yield descriptor, Path(relative).name
    finally:
        os.close(descriptor)


def backup_project(relative):
    """Preserve exact pre-transaction project bytes and permissions for recovery."""
    with project_parent(relative) as (directory, name):
        try:
            descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                                 dir_fd=directory)
        except FileNotFoundError:
            return None
        with os.fdopen(descriptor, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode):
                raise ValueError('project lifecycle file is not regular')
            return {'bytes': base64.b64encode(stream.read()).decode('ascii'),
                    'mode': stat.S_IMODE(info.st_mode)}


def restore_project(relative, backup):
    """Restore a journaled file atomically without writing through project links."""
    with project_parent(relative) as (directory, name):
        if backup is None:
            try:
                os.unlink(name, dir_fd=directory)
            except FileNotFoundError:
                pass
            return
        temporary = '.discovery-rollback-' + os.urandom(16).hex()
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=directory)
        try:
            with os.fdopen(descriptor, 'wb') as stream:
                stream.write(base64.b64decode(backup['bytes'], validate=True))
                stream.flush()
                os.fsync(stream.fileno())
                os.fchmod(stream.fileno(), backup['mode'])
            os.replace(temporary, name, src_dir_fd=directory, dst_dir_fd=directory)
        finally:
            try:
                os.unlink(temporary, dir_fd=directory)
            except FileNotFoundError:
                pass


def recover(path, state):
    """Roll back an interrupted project transaction before any next operation."""
    journal = state.get('transaction')
    if journal is not None:
        # Restore the incomplete state first; leave the journal if any restore fails.
        for relative in ('.octo/STATE.md', '.octo/phases/phase-1-summary.md'):
            restore_project(relative, journal[relative])
        state.pop('transaction')
        state.update(status='failed', artifact=None)
        save(path, state)
    return state


def begin(state_file, run_id):
    """Invalidate old research before preparation; recover prior unfinished writes."""
    if run_id is not None and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', run_id):
        raise ValueError('invalid discovery run identity')
    with locked(state_file) as (path, lock_fd):
        if path.exists():
            try:
                previous = load(path)
            except (ValueError, KeyError, TypeError, AttributeError):
                # Explicit start/discard can replace corrupt metadata, never files.
                previous = None
            if previous is not None:
                recover(path, previous)
        save(path, {'version': 1, 'project': str(project_root()), 'run_id': run_id,
                    'status': 'discarded' if run_id is None else 'running', 'artifact': None})


def project_prepare(state_file, run_id):
    """Initialize opted-in project state only while this discovery is current."""
    with locked(state_file) as (path, lock_fd):
        state = current(path, run_id)
        try:
            # Validate .octo before invoking the existing lifecycle API.
            backup_project('.octo/STATE.md')
            script = Path(__file__).absolute().parents[1] / 'octo-state.sh'
            if not (project_root() / '.octo/STATE.md').exists():
                subprocess.run([str(script), 'init_project'], cwd=project_root(), check=True, pass_fds=(lock_fd,))
            subprocess.run([str(script), 'update_state', '--phase', '1', '--position',
                            'Discovery', '--status', 'in_progress'], cwd=project_root(), check=True, pass_fds=(lock_fd,))
            state['project_prepared'] = True
            save(path, state)
        except Exception:
            state.update(status='failed', artifact=None)
            save(path, state)
            raise


def publish(state_file, run_id, value):
    """Present and commit research plus optional project writes as a transaction."""
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', run_id):
        raise ValueError('invalid discovery run identity')
    with locked(state_file) as (path, lock_fd):
        state = current(path, run_id)
        try:
            artifact, contents = research_bytes(value, run_id)
            with tempfile.TemporaryDirectory(prefix='.discovery-complete-', dir=path.parent) as temporary:
                verified = Path(temporary) / 'research.md'
                verified.write_bytes(contents)
                verified.chmod(0o400)
                print('Discovery findings:', flush=True)
                subprocess.run(['cat', str(verified)], check=True, pass_fds=(lock_fd,))
                if os.environ.get('OCTOPUS_PROJECT_PERSISTENCE') == 'true':
                    if not state.get('project_prepared'):
                        raise ValueError('opt-in project state was not prepared for this run')
                    state['transaction'] = {relative: backup_project(relative) for relative in
                        ('.octo/STATE.md', '.octo/phases/phase-1-summary.md')}
                    state.update(status='committing', artifact=None)
                    save(path, state)
                    script = Path(__file__).absolute().parent / 'discovery-project-complete.sh'
                    subprocess.run(['bash', str(script), str(verified)], cwd=project_root(), check=True, pass_fds=(lock_fd,))
                completed = dict(state)
                completed.pop('transaction', None)
                completed.update(status='complete', artifact={'path': str(artifact),
                                 'sha256': hashlib.sha256(contents).hexdigest()})
                save(path, completed)
        except Exception:
            # Asynchronous termination leaves the journal for the next holder.
            # Children inherit the lock, so recovery waits until writers exit.
            # For ordinary errors restore project files before exposing failure.
            if state.get('transaction') is not None:
                try:
                    recover(path, state)
                except Exception as restore_error:
                    print('Discovery rollback incomplete; journal retained: ' + str(restore_error), file=sys.stderr)
            else:
                try:
                    state.update(status='failed', artifact=None)
                    save(path, state)
                except Exception as state_error:
                    print('Discovery failure state could not be recorded: ' + str(state_error), file=sys.stderr)
            raise


def snapshot(state_file, directory):
    """Copy exactly the validated bytes into a caller-owned private directory."""
    if not os.path.lexists(Path(state_file).parent / 'discovery-handoff.json'):
        return ''
    with locked(state_file) as (path, lock_fd):
        state = recover(path, load(path))
        record = state.get('artifact')
        if state.get('status') == 'discarded':
            return ''
        if state.get('status') != 'complete' or record is None:
            raise ValueError('discovery is incomplete; resume it or explicitly discard its binding')
        run_id = state['run_id']
        if not isinstance(run_id, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', run_id):
            raise ValueError('invalid discovery run identity')
        _, contents = research_bytes(record['path'], run_id)
        if hashlib.sha256(contents).hexdigest() != record['sha256']:
            raise ValueError('research changed after discovery completed')
        descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            info = os.fstat(descriptor)
            if info.st_uid != os.geteuid() or info.st_mode & 0o077:
                raise ValueError('snapshot directory is not private to this user')
            child = os.open('research.md', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                            0o400, dir_fd=descriptor)
            with os.fdopen(child, 'wb') as stream:
                stream.write(contents)
                stream.flush()
                os.fsync(stream.fileno())
        finally:
            os.close(descriptor)
    return str(Path(directory).resolve() / 'research.md')


def main():
    """Expose lifecycle, recovery and snapshot commands to the shipped skills."""
    try:
        args = sys.argv[1:]
        if len(args) in (2, 3) and args[0] == 'locate':
            print(locate(args[1], args[2] if len(args) == 3 else None))
        elif len(args) == 3 and args[0] == 'begin':
            begin(args[1], args[2])
        elif len(args) == 3 and args[0] == 'prepare':
            project_prepare(args[1], args[2])
        elif len(args) == 4 and args[0] == 'publish':
            publish(args[1], args[2], args[3])
        elif len(args) == 3 and args[0] == 'snapshot':
            print(snapshot(args[1], args[2]))
        elif len(args) == 2 and args[0] == 'discard':
            begin(args[1], None)
        else:
            raise ValueError('expected locate WORKSPACE [LEGACY_STATE], begin/prepare STATE RUN, publish STATE RUN FILE, snapshot STATE DIRECTORY, or discard STATE')
    except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.CalledProcessError) as error:
        print('Discovery handoff rejected: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
