#!/usr/bin/env python3
"""Internal portable feature storage used by existing Octopus workflows."""

import argparse
import datetime
import fcntl
import hashlib
import importlib.util
import json
import os
import re
import stat
import subprocess
import sys
import uuid

_spec = importlib.util.spec_from_file_location('artifact_safety', os.path.join(os.path.dirname(__file__), 'artifact-safety.py'))
safety = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(safety)
MAX_BYTES = 1048576
KINDS = ('spec', 'plan', 'tasks', 'research', 'decisions')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_input(path):
    parent, leaf = os.path.split(os.path.abspath(path))
    with Root(os.path.realpath(parent)) as root:
        return root.read(leaf)


def relative(path):
    parts = path.split('/')
    if not path or path.startswith('/') or any(p in ('', '.', '..', '.git') for p in parts):
        raise ValueError('invalid repository-relative path')
    if any(ord(c) < 32 or ord(c) == 127 for c in path):
        raise ValueError('invalid path characters')
    return parts


class Root:
    """Keep artifact operations on the approved directory descriptors."""

    def __init__(self, path):
        self.path = os.path.abspath(path)
        self.fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
        try:
            for part in self.path.split('/'):
                if part:
                    child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=self.fd)
                    os.close(self.fd)
                    self.fd = child
        except BaseException:
            os.close(self.fd)
            raise

    def __enter__(self):
        return self

    def __exit__(self, *args):
        os.close(self.fd)

    def directory(self, parts, create=False):
        fd = os.dup(self.fd)
        try:
            for part in parts:
                if create:
                    try:
                        os.mkdir(part, 0o755, dir_fd=fd)
                    except FileExistsError:
                        pass
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                os.close(fd)
                fd = child
            return fd
        except BaseException:
            os.close(fd)
            raise

    def read(self, path):
        parts = relative(path)
        parent = self.directory(parts[:-1])
        try:
            fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
            try:
                if not stat.S_ISREG(os.fstat(fd).st_mode):
                    raise ValueError('artifact is not a regular file')
                data = bytearray()
                while len(data) <= MAX_BYTES:
                    chunk = os.read(fd, min(65536, MAX_BYTES + 1 - len(data)))
                    if not chunk:
                        break
                    data.extend(chunk)
                if len(data) > MAX_BYTES:
                    raise ValueError('artifact exceeds size limit')
                return bytes(data)
            finally:
                os.close(fd)
        finally:
            os.close(parent)

    def write(self, path, data, exclusive=False):
        if not safety.certify(data.decode('utf-8')):
            raise ValueError('artifact safety scan withheld content')
        parts = relative(path)
        parent = self.directory(parts[:-1], create=True)
        temporary = '.octopus-stage-' + uuid.uuid4().hex
        try:
            if exclusive:
                fd = os.open(parts[-1], os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644, dir_fd=parent)
            else:
                try:
                    existing = os.stat(parts[-1], dir_fd=parent, follow_symlinks=False)
                    if not stat.S_ISREG(existing.st_mode):
                        raise ValueError('artifact target is not a regular file')
                except FileNotFoundError:
                    pass
                fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644, dir_fd=parent)
            try:
                with os.fdopen(fd, 'wb') as output:
                    output.write(data)
                    output.flush()
                    os.fsync(output.fileno())
                if not exclusive:
                    os.rename(temporary, parts[-1], src_dir_fd=parent, dst_dir_fd=parent)
                os.fsync(parent)
            finally:
                if not exclusive:
                    try:
                        os.unlink(temporary, dir_fd=parent)
                    except FileNotFoundError:
                        pass
        finally:
            os.close(parent)


def read_json(root, path, default=None):
    try:
        return json.loads(root.read(path).decode('utf-8'))
    except FileNotFoundError:
        return default


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')


def token(value, limit=120):
    return re.sub(r'[^A-Za-z0-9._-]', '-', value)[:limit] or 'unknown'


def manifest(root, feature):
    path = feature + '/feature.json' if feature else '.octopus-feature.json'
    current = read_json(root, path)
    if current is None:
        current = {'schema_version': 1, 'feature_id': str(uuid.uuid4()), 'feature': feature,
                   'phase': 'spec', 'artifacts': {}, 'authors': [], 'policy': None}
    if current.get('schema_version') != 1 or current.get('feature') != feature:
        raise ValueError('unsupported or mismatched feature manifest')
    uuid.UUID(current['feature_id'])
    return path, current


def git(root, *args):
    environment = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    result = subprocess.run(['git', '-c', 'core.fsmonitor=false', '-C', root, *args], env=environment, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, timeout=5, check=False)
    return result.stdout.decode('utf-8', errors='strict').strip() if result.returncode == 0 else None


def features(root):
    try:
        fd = root.directory(['specs'])
    except FileNotFoundError:
        return []
    try:
        names = os.listdir(fd)
        if len(names) > 4096:
            raise ValueError('too many feature directories')
        result = []
        for name in sorted(names):
            if re.fullmatch(r'[0-9]{3,9}-[a-z0-9][a-z0-9-]{0,79}', name):
                info = os.stat(name, dir_fd=fd, follow_symlinks=False)
                if stat.S_ISDIR(info.st_mode):
                    result.append('specs/' + name)
        return result
    finally:
        os.close(fd)


def selection(root, feature, reason, legacy=False, warnings=None):
    spec_path = feature + '/spec.md' if feature else 'spec.md'
    result = {'schema_version': 1, 'root': root.path, 'feature': feature,
              'spec_path': spec_path, 'legacy': legacy, 'reason': reason,
              'warnings': warnings or []}
    try:
        _, item = manifest(root, feature)
        result['feature_id'] = item['feature_id']
        result['phase'] = item['phase']
    except (OSError, ValueError, KeyError, TypeError):
        result['feature_id'] = None
    return result


def resolve(args):
    root_path = os.path.abspath(args.root)
    with Root(root_path) as root:
        if args.explicit:
            path = args.explicit
            if os.path.isabs(path):
                path = os.path.relpath(path, root.path)
            relative(path)
            if path.endswith('.md'):
                feature = os.path.dirname(path)
                if feature and args.create:
                    try:
                        os.close(root.directory(relative(feature), create=True))
                    except OSError:
                        pass
                result = selection(root, feature, 'explicit artifact path', legacy=not bool(feature))
                result['spec_path'] = path
                return result
            fd = root.directory(relative(path))
            os.close(fd)
            return selection(root, path, 'explicit feature')
        if args.layout == 'legacy':
            return selection(root, '', 'legacy layout configured', legacy=True)
        try:
            known = features(root)
        except (OSError, ValueError):
            if args.create:
                return selection(root, '', 'feature layout is unsafe or unavailable, using spec.md', legacy=True,
                                 warnings=['feature directory could not be read safely'])
            return {'schema_version': 1, 'feature': None, 'warning': 'existing feature layout could not be read safely'}
        branch = git(root.path, 'branch', '--show-current') or ''
        matched = [f for f in known if branch == f.split('/')[-1] or branch.endswith('/' + f.split('/')[-1])]
        if len(matched) == 1:
            return selection(root, matched[0], 'current branch feature')
        if len(known) == 1 and (not args.create or os.path.isdir(os.path.join(root.path, '.specify'))):
            return selection(root, known[0], 'existing feature layout')
        if not args.create:
            if len(known) > 1:
                return {'schema_version': 1, 'feature': None, 'ambiguous': True,
                        'candidates': known, 'reason': 'select an existing feature explicitly'}
            try:
                root.read('spec.md')
                return selection(root, '', 'existing root specification', legacy=True)
            except FileNotFoundError:
                return {'schema_version': 1, 'feature': None, 'reason': 'no portable feature found'}
        if git(root.path, 'rev-parse', '--show-toplevel') is None:
            return selection(root, '', 'outside Git, using spec.md', legacy=True)
        try:
            os.stat('specs', dir_fd=root.fd, follow_symlinks=False)
            has_specs = True
        except FileNotFoundError:
            has_specs = False
        if not has_specs:
            try:
                root.read('spec.md')
                return selection(root, '', 'existing root spec.md preserved; migration requires a user decision', legacy=True,
                                 warnings=['OCTOPUS_FEATURE_LAYOUT=legacy keeps root spec.md'])
            except FileNotFoundError:
                pass
        try:
            slug = re.sub(r'[^a-z0-9-]', '-', args.name.lower())[:80].strip('-') or 'feature'
            slug = re.sub('-+', '-', slug)
            ledger = root.directory(['specs', '.octopus-allocations'], create=True)
            try:
                entries = os.listdir(ledger)
                if len(entries) > 100000:
                    raise ValueError('allocation ledger limit reached')
                ordinals = [int(os.path.basename(f).split('-', 1)[0]) for f in known]
                ordinals += [int(n[:-5]) for n in entries if re.fullmatch(r'[0-9]{3,9}\.json', n)]
                ordinal = max(ordinals, default=0) + 1
                for _ in range(100):
                    if ordinal > 999999999:
                        raise ValueError('allocation ordinal limit reached')
                    feature_id = str(uuid.uuid4())
                    name = f'{ordinal:03d}-{slug}'
                    entry = json.dumps({'schema_version': 1, 'ordinal': ordinal, 'feature_id': feature_id,
                                        'feature': 'specs/' + name, 'allocated_at': stamp()}) + '\n'
                    try:
                        root.write(f'specs/.octopus-allocations/{ordinal:03d}.json', entry.encode(), exclusive=True)
                        break
                    except FileExistsError:
                        ordinal += 1
                else:
                    raise ValueError('allocation contention limit reached')
                specs_fd = root.directory(['specs'])
                try:
                    os.mkdir(name, 0o755, dir_fd=specs_fd)
                finally:
                    os.close(specs_fd)
                feature = 'specs/' + name
                path, item = manifest(root, feature)
                item['feature_id'] = feature_id
                item['ordinal'] = ordinal
                root.write(path, (json.dumps(item, indent=2) + '\n').encode())
                return selection(root, feature, 'allocated portable feature directory')
            finally:
                os.close(ledger)
        except (OSError, ValueError):
            return selection(root, '', 'feature allocation unavailable, using spec.md', legacy=True,
                             warnings=['feature directory could not be allocated safely'])


def publish(args):
    with Root(os.path.abspath(args.root)) as root:
        feature = args.feature.strip('/')
        if feature:
            relative(feature)
        if args.kind not in KINDS:
            raise ValueError('unsupported artifact kind')
        withheld = False
        try:
            text = read_input(args.input).decode('utf-8', errors='strict')
            text = safety.clean_text(text)
            if not safety.certify(text):
                raise ValueError('artifact scan withheld content')
            if args.kind == 'research':
                if not args.provider or not args.run_id or not args.distilled:
                    raise ValueError('research must be an attributed accepted synthesis')
                if not text.strip():
                    raise ValueError('accepted synthesis is empty')
                text = '# Research\n\nProvider: ' + token(args.provider) + '\nModel: ' + token(args.model or 'unknown') + '\nCollected: ' + stamp() + '\nRuntime run: ' + token(args.run_id) + '\n\n' + text
        except (OSError, UnicodeError, ValueError):
            withheld = True
            text = '# ' + args.kind.capitalize() + '\n\nContent retained in runtime state.\nArtifact: ' + args.kind + '\nRun: ' + token(args.run_id or 'unknown') + '\n'
        if not safety.certify(text):
            raise ValueError('artifact pointer failed safety validation')
        path = feature + '/' + args.kind + '.md' if feature else args.kind + '.md'
        if args.target:
            relative(args.target)
            if os.path.dirname(args.target) != feature:
                raise ValueError('explicit artifact target must remain in selected feature')
            path = args.target
        directory = root.directory(relative(feature) if feature else [], create=True)
        try:
            fcntl.flock(directory, fcntl.LOCK_EX)
            metadata_path, item = manifest(root, feature)
            item['artifacts'][args.kind] = {'path': path, 'digest': digest(text.encode()), 'withheld': withheld,
                                           'run_id': token(args.run_id or 'unknown'), 'updated_at': stamp()}
            if args.provider:
                author = {'provider': token(args.provider), 'model': token(args.model or 'unknown')}
                if author not in item['authors']:
                    item['authors'].append(author)
            if not args.preserve_phase:
                item['phase'] = {'spec': 'plan', 'plan': 'develop', 'tasks': 'develop'}.get(args.kind, item['phase'])
            metadata_bytes = (json.dumps(item, indent=2) + '\n').encode()
            if not safety.certify(metadata_bytes.decode('utf-8')):
                raise ValueError('artifact metadata failed safety validation')
            root.write(path, text.encode('utf-8'))
            root.write(metadata_path, metadata_bytes)
        finally:
            fcntl.flock(directory, fcntl.LOCK_UN)
            os.close(directory)
        return {'schema_version': 1, 'published': True, 'path': path, 'withheld': withheld,
                'feature_id': item['feature_id'], 'phase': item['phase']}


def resume(args):
    choice = resolve(args)
    if choice.get('ambiguous') or choice.get('feature') is None:
        return choice
    with Root(os.path.abspath(args.root)) as root:
        feature = choice['feature']
        _, item = manifest(root, feature)
        artifacts = {}
        warnings = []
        for kind in KINDS:
            default_path = feature + '/' + kind + '.md' if feature else kind + '.md'
            entry = item.get('artifacts', {}).get(kind, {})
            path = entry.get('path', default_path) if isinstance(entry, dict) else default_path
            try:
                relative(path)
                if os.path.dirname(path) != feature:
                    raise ValueError('artifact leaves its selected feature')
                content = root.read(path).decode('utf-8', errors='strict')
                if not safety.certify(content):
                    warnings.append(kind + ' was withheld from portable resume')
                    continue
                artifacts[kind] = {'path': path, 'digest': digest(content.encode()), 'text': content}
            except FileNotFoundError:
                pass
            except (OSError, UnicodeError, ValueError):
                warnings.append(kind + ' could not be read safely')
        return {'schema_version': 1, 'feature': feature, 'feature_id': item['feature_id'], 'phase': item['phase'],
                'artifacts': artifacts, 'authors': item['authors'], 'policy': item.get('policy'),
                'clarifications': item.get('clarifications'), 'task_history': item.get('task_history'),
                'task_completion': item.get('task_completion'), 'analysis': item.get('analysis'),
                'complexity': item.get('complexity'),
                'historical_completion': True, 'warnings': warnings,
                'reason': 'recovered repository artifacts; fresh verification is required for completion claims'}


def update(args):
    with Root(os.path.abspath(args.root)) as root:
        feature = args.feature.strip('/')
        directory = root.directory(relative(feature) if feature else [])
        try:
            fcntl.flock(directory, fcntl.LOCK_EX)
            path, item = manifest(root, feature)
            incoming = json.loads(read_input(args.input).decode('utf-8'))
            allowed = {'policy', 'phase', 'task_history', 'task_completion', 'clarifications', 'analysis', 'complexity'}
            if not isinstance(incoming, dict) or set(incoming) - allowed:
                raise ValueError('unsupported portable metadata')
            # Policy passages remain runtime-only. Portable policy references are
            # relative source paths and content digests.
            policy = incoming.get('policy')
            if policy is not None:
                if set(policy) - {'source', 'digest'}:
                    raise ValueError('policy snapshot cannot be stored in the manifest')
                if policy.get('source'):
                    relative(policy['source'])
            encoded = json.dumps(incoming)
            if re.search(r'(?:/Users/|/home/|[A-Za-z]:\\Users\\)', encoded):
                raise ValueError('machine-local paths cannot be stored in the manifest')
            if not safety.certify(encoded):
                raise ValueError('portable metadata was withheld by the safety scan')
            item.update(incoming)
            root.write(path, (json.dumps(item, indent=2) + '\n').encode())
            return {'schema_version': 1, 'updated': True, 'feature_id': item['feature_id']}
        finally:
            fcntl.flock(directory, fcntl.LOCK_UN)
            os.close(directory)


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest='command', required=True)
    for command in ('resolve', 'resume'):
        p = commands.add_parser(command)
        p.add_argument('--root', required=True)
        p.add_argument('--explicit', default='')
        p.add_argument('--name', default='feature')
        p.add_argument('--layout', choices=('auto', 'legacy'), default='auto')
        p.add_argument('--create', action='store_true')
    p = commands.add_parser('publish')
    p.add_argument('--root', required=True)
    p.add_argument('--feature', default='')
    p.add_argument('--kind', choices=KINDS, required=True)
    p.add_argument('--input', required=True)
    p.add_argument('--provider', default='')
    p.add_argument('--model', default='')
    p.add_argument('--run-id', default='')
    p.add_argument('--target', default='')
    p.add_argument('--distilled', action='store_true')
    p.add_argument('--preserve-phase', action='store_true')
    p = commands.add_parser('update')
    p.add_argument('--root', required=True)
    p.add_argument('--feature', default='')
    p.add_argument('--input', required=True)
    args = parser.parse_args()
    try:
        value = {'resolve': resolve, 'publish': publish, 'resume': resume, 'update': update}[args.command](args)
        print(json.dumps(value))
        return 0
    except (OSError, ValueError, UnicodeError, KeyError, TypeError, subprocess.TimeoutExpired):
        print(json.dumps({'schema_version': 1, 'published': False, 'warning': 'portable artifact operation unavailable; keep draft in runtime state'}))
        return 2


if __name__ == '__main__':
    sys.exit(main())
