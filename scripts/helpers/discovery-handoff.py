#!/usr/bin/env python3
"""Commit completed discovery research and give Define a verified private snapshot."""
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile


def project_root():
    """Use the same physical project override as state-manager.sh."""
    return Path(os.environ.get('OCTOPUS_STATE_PROJECT_ROOT') or os.getcwd()).resolve()


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
        yield directory / 'discovery-handoff.json'
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


def begin(state_file, run_id):
    """Invalidate old research and establish the latest discovery under lock."""
    if run_id is not None and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', run_id):
        raise ValueError('invalid discovery run identity')
    with locked(state_file) as path:
        save(path, {'version': 1, 'project': str(project_root()),
                    'run_id': run_id, 'artifact': None})


def publish(state_file, run_id, value):
    """Commit completed research only while this run is still current."""
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', run_id):
        raise ValueError('invalid discovery run identity')
    with locked(state_file) as path:
        state = load(path)
        if state['run_id'] != run_id or run_id is None:
            raise ValueError('another discovery superseded this run')
        artifact, contents = research_bytes(value, run_id)
        state['artifact'] = {'path': str(artifact),
                             'sha256': hashlib.sha256(contents).hexdigest()}
        save(path, state)


def snapshot(state_file, directory):
    """Copy exactly the validated bytes into a caller-owned private directory."""
    if not os.path.lexists(Path(state_file).parent / 'discovery-handoff.json'):
        return ''
    with locked(state_file) as path:
        state = load(path)
        record = state.get('artifact')
        if record is None:
            return ''
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
        if len(args) == 3 and args[0] == 'begin':
            begin(args[1], args[2])
        elif len(args) == 4 and args[0] == 'publish':
            publish(args[1], args[2], args[3])
        elif len(args) == 3 and args[0] == 'snapshot':
            print(snapshot(args[1], args[2]))
        elif len(args) == 2 and args[0] == 'discard':
            begin(args[1], None)
        else:
            raise ValueError('expected begin STATE RUN, publish STATE RUN FILE, snapshot STATE DIRECTORY, or discard STATE')
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        print('Discovery handoff rejected: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
