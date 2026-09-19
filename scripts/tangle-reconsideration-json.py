#!/usr/bin/env python3
from __future__ import annotations
import json, os, re, sys

PATH_RE = re.compile(r'^[A-Za-z0-9_.@%+/-]+$')
ACTIONS = {'move_to_reads','remove_write','add_write'}
DECISIONS = {'accept','reject'}


def extract(raw: str):
    raw = raw.strip()
    if raw.startswith('```'):
        lines = raw.splitlines()
        if lines and lines[0].strip() in {'```','```json','```JSON'}:
            raw = '\n'.join(lines[1:-1] if lines[-1].strip() == '```' else lines[1:]).strip()
    try:
        obj = json.loads(raw)
        return obj if isinstance(obj, dict) else None
    except json.JSONDecodeError:
        pass
    dec = json.JSONDecoder(); found = []
    for i, ch in enumerate(raw):
        if ch != '{':
            continue
        try:
            obj, end = dec.raw_decode(raw[i:])
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict):
            found.append((i, i + end, obj))
    maximal = []
    for candidate in found:
        st, en, _ = candidate
        if any(ost <= st and en <= oen and (ost, oen) != (st, en) for ost, oen, _ in found):
            continue
        maximal.append(candidate)
    return maximal[0][2] if len(maximal) == 1 else None


def basic_valid(obj):
    if not isinstance(obj, dict) or set(obj) != {'schema_version','decisions','decomposition'}:
        return False
    if obj['schema_version'] != 1 or not isinstance(obj['decisions'], list) or not isinstance(obj['decomposition'], dict):
        return False
    seen = set()
    for item in obj['decisions']:
        if not isinstance(item, dict) or set(item) != {'action','path','decision','reason'}:
            return False
        action = item['action']; path = item['path']; decision = item['decision']; reason = item['reason']
        if action not in ACTIONS or decision not in DECISIONS:
            return False
        if not isinstance(path, str) or not PATH_RE.fullmatch(path) or any(c in path for c in '*?[]'):
            return False
        if not isinstance(reason, str) or not reason.strip():
            return False
        key = (action, path)
        if key in seen:
            return False
        seen.add(key)
    return True


def expected_from_legacy(text: str):
    out = []
    rx = re.compile(r'^\s*-\s*(MOVE_TO_READS|REMOVE_WRITE|ADD_WRITE):\s*([^\s—]+)(?:\s+—\s+.*)?$', re.I)
    names = {'MOVE_TO_READS':'move_to_reads','REMOVE_WRITE':'remove_write','ADD_WRITE':'add_write'}
    for line in text.splitlines():
        m = rx.match(line)
        if not m:
            continue
        path = m.group(2).strip()
        if PATH_RE.fullmatch(path) and not any(c in path for c in '*?[]'):
            out.append({'action': names[m.group(1).upper()], 'path': path})
    return out


def coverage_ok(obj, expected):
    actual = {(x['action'], x['path']) for x in obj['decisions']}
    exp = {(x['action'], x['path']) for x in expected}
    return len(actual) == len(obj['decisions']) and actual == exp


def canonical(obj):
    return json.dumps(obj, ensure_ascii=False, separators=(',', ':'))


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'validate'
    raw = sys.stdin.read()
    if mode == 'expected':
        sys.stdout.write(json.dumps(expected_from_legacy(raw), ensure_ascii=False, separators=(',', ':')) + '\n')
        return
    obj = extract(raw)
    if obj is None or not basic_valid(obj):
        raise SystemExit(1)
    if mode == 'validate-coverage':
        try:
            expected = json.loads(os.environ.get('TANGLE_RECONSIDERATION_EXPECTED_SCOPE_REVIEW_JSON', '[]'))
        except json.JSONDecodeError:
            raise SystemExit(1)
        if not isinstance(expected, list) or not all(isinstance(x, dict) and set(x) == {'action','path'} for x in expected):
            raise SystemExit(1)
        if not coverage_ok(obj, expected):
            raise SystemExit(1)
    if mode == 'decomposition':
        sys.stdout.write(canonical(obj['decomposition']) + '\n')
    elif mode == 'decisions':
        for item in obj['decisions']:
            reason = re.sub(r'\s+', ' ', item['reason'].strip())
            sys.stdout.write(f"- {item['decision'].upper()} {item['action'].upper()}: {item['path']} — {reason}\n")
    else:
        sys.stdout.write(canonical(obj) + '\n')


if __name__ == '__main__':
    main()
