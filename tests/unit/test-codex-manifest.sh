#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Codex plugin manifest"

test_case "Codex default prompts stay within the host limit of three"
if jq -e '.interface.defaultPrompt | (type == "array" and length <= 3)' \
    "$PROJECT_ROOT/.codex-plugin/plugin.json" >/dev/null; then
    test_pass
else
    test_fail "Codex supports at most three interface.defaultPrompt entries"
fi

test_case "Codex listing copy, explicit starter routes and complete skill blurbs are valid"
if python3 - "$PROJECT_ROOT" <<'PY_META'
import json, re, sys
from pathlib import Path
root = Path(sys.argv[1])
interface = json.loads((root / '.codex-plugin/plugin.json').read_text())['interface']
assert 0 < len(interface['shortDescription']) <= 30
assert 0 < len(interface['longDescription']) <= 4000
assert 'provider accounts' in interface['longDescription']
assert 'charges' in interface['longDescription']
assert not re.search(r'\b\d+ (providers|personas|commands|skills)\b', interface['longDescription'])
names = set()
for skill in (root / 'skills').rglob('SKILL.md'):
    match = re.search(r'^name:\s*["\']?([^\n"\']+)', skill.read_text(), re.M)
    if match:
        names.add(match[1])
for prompt in interface['defaultPrompt']:
    assert len(prompt) <= 128
    references = re.findall(r'\$([a-z][a-z0-9-]+)', prompt)
    assert references and all(name in names for name in references), prompt
for metadata in (root / 'skills').rglob('agents/openai.yaml'):
    text = metadata.read_text()
    description = json.loads(re.search(r'^  short_description: (.*)$', text, re.M)[1])
    assert 25 <= len(description) <= 64, metadata
    assert not description.endswith(('...', '…')), metadata
    assert '/octo:' not in description, metadata
    assert 'allow_implicit_invocation: false' in text, metadata
print('Listing limits, registered starter routes and all skill blurbs checked')
PY_META
then test_pass; else test_fail "Codex listing or skill presentation metadata is invalid"; fi

test_summary
