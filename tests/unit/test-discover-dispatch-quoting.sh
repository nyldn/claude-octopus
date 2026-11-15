#!/usr/bin/env bash
# Execute the documented child command with complete shell-quoted arguments.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$PROJECT_ROOT" "${1:-}" <<'PY'
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
references = [Path(sys.argv[2])] if sys.argv[2] else [
    root / 'skills/flow-discover/references/dispatch.md',
]
generated = root / 'codex-skills/flow-discover/references/dispatch.md'
if not sys.argv[2] and generated.exists():
    references.append(generated)

with tempfile.TemporaryDirectory(prefix='discover-quoting-') as temporary:
    fixture = Path(temporary) / "plugin's directory"
    (fixture / 'scripts').mkdir(parents=True)
    executable = fixture / 'scripts/orchestrate.sh'
    executable.write_text(
        '#!/usr/bin/env python3\nimport json, os, sys\n'
        'with open(os.environ["DISPATCH_CAPTURE"], "w") as output:\n'
        '    json.dump(sys.argv[1:], output)\n'
    )
    executable.chmod(0o755)
    capture = Path(temporary) / 'argv.json'
    marker = Path(temporary) / 'executed'
    environment = dict(os.environ, OCTO_RESEARCH_ROOT=str(fixture),
                       DISPATCH_CAPTURE=str(capture), DISPATCH_SENTINEL=str(marker))
    payloads = [
        '$(touch "$DISPATCH_SENTINEL")', '`touch "$DISPATCH_SENTINEL"`',
        "provider's perspective", "'", '', 'first line\nsecond line',
        'text; touch "$DISPATCH_SENTINEL"', 'spaces and tabs\tremain',
        '"$HOME" \\ literal', 'Unicode: café 🐙',
    ]
    controls = 0
    for reference in references:
        command, = [line for line in reference.read_text().splitlines()
                    if line.startswith('"$OCTO_RESEARCH_ROOT/scripts/orchestrate.sh" probe-single ')]
        for field in ('perspective_prompt', 'original_prompt'):
            for payload in payloads:
                values = dict(agent_type='codex', task_id='run-WP-1',
                              perspective_prompt='perspective', original_prompt='original',
                              run_id='probe-run-nonce')
                values[field] = payload
                rendered = command
                for name, value in values.items():
                    rendered = rendered.replace('<' + name + '>', shlex.quote(value))
                result = subprocess.run(['bash', '-c', rendered], env=environment,
                                        capture_output=True, text=True, timeout=5)
                assert not marker.exists(), f'{reference}: shell executed {field} content'
                assert result.returncode == 0, (reference, field, result.stderr)
                expected = ['probe-single', values['agent_type'], values['perspective_prompt'],
                            values['task_id'], values['original_prompt'], '--research-run',
                            values['run_id']]
                assert json.loads(capture.read_text()) == expected, (reference, field, payload)
                controls += 1
    print(f'{controls} production dispatch-template quoting controls passed')
PY
