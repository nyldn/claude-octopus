#!/usr/bin/env python3
"""Bind full discovery research to its project and run before Define reuses it."""
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys


def research_file(value, run_id):
    """Accept one regular nonempty summary, rejecting links below trusted roots."""
    project = Path.cwd().resolve()
    home = Path(os.environ['HOME'])
    candidate = Path(value)
    # HOME is host-owned and may use a system alias such as /var on macOS.
    host_results = home / '.claude-octopus/results'
    if candidate in (host_results / ('probe-synthesis-' + run_id + '.md'),
                      home.resolve() / '.claude-octopus/results' / ('probe-synthesis-' + run_id + '.md')):
        anchor = home.resolve()
        relative = Path('.claude-octopus/results') / candidate.name
    elif (candidate.parts[-3:] == ('.octo', 'phases', 'phase-1-summary.md')
          and candidate.parent.parent.parent.resolve() == project):
        anchor = project
        relative = Path('.octo/phases/phase-1-summary.md')
    else:
        raise ValueError('research path is outside the supported discovery locations')
    path = anchor
    for part in relative.parts:
        path = path / part
        if stat.S_ISLNK(path.lstat().st_mode):
            raise ValueError('research path contains a symlink')
    if not stat.S_ISREG(path.stat().st_mode) or not os.access(path, os.R_OK):
        raise ValueError('research is not a readable regular file')
    contents = path.read_bytes()
    if not contents:
        raise ValueError('research is empty')
    return path, hashlib.sha256(contents).hexdigest()


def capture(value, run_id):
    """Capture the full artifact hash without storing research in previews."""
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', run_id):
        raise ValueError('invalid discovery run identity')
    path, digest = research_file(value, run_id)
    return {'project': str(Path.cwd().resolve()), 'run_id': run_id,
            'path': str(path), 'sha256': digest}


def select(state):
    """Restore only the current project's run; never infer it from .octo state."""
    context = state.get('context', {})
    saved = context.get('discovery_artifact')
    if not saved:
        return ''
    record = json.loads(saved)
    if (record['project'] != str(Path.cwd().resolve())
            or record['run_id'] != context.get('discovery_run')):
        raise ValueError('research does not belong to the current project and discovery')
    actual = capture(record['path'], record['run_id'])
    if actual != record:
        raise ValueError('research changed after discovery completed')
    return actual['path']


def main():
    """Expose capture and selection to the shipped workflow shell blocks."""
    try:
        if len(sys.argv) == 4 and sys.argv[1] == 'capture':
            print(json.dumps(capture(sys.argv[2], sys.argv[3])))
        elif sys.argv[1:] == ['select']:
            print(select(json.load(sys.stdin)))
        else:
            raise ValueError('expected capture FILE RUN_ID or select with state on stdin')
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        print('Discovery handoff rejected: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
