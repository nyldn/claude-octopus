#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/helpers/test-framework.sh"
test_suite "Command safety regressions"
test_case "deletion targets and stable guard sessions"
if python3 - "$ROOT" <<'CHECKS'
from pathlib import Path
import json, os, re, subprocess, sys, tempfile, uuid
root = Path(sys.argv[1])
sid = 'audit-' + uuid.uuid4().hex
base_env = dict(os.environ)
for key in ['CLAUDE_CODE_SESSION_ID', 'CLAUDE_SESSION_ID', 'CLAUDE_CODE_SESSION', 'CODEX_SESSION_ID', 'CODEX_TASK_ID', 'CODEX_PLUGIN_ROOT', 'CLAUDE_PLUGIN_ROOT', 'CODEX_SANDBOX', 'CODEX_HOME', 'OCTOPUS_HOST', 'PLUGIN_ROOT', 'OCTO_CAREFUL_MODE', 'OCTO_FREEZE_MODE']:
    base_env.pop(key, None)
def hook(name, data, env):
    """Run a real hook with isolated identity and return its permission decision."""
    result = subprocess.run(['bash', str(root/'hooks'/name)], input=json.dumps(data), env=env, text=True, capture_output=True, check=True)
    return json.loads(result.stdout)['hookSpecificOutput']['permissionDecision'] if result.stdout else 'allow'
state = Path('/tmp/octopus-careful-' + sid + '.txt')
try:
    state.write_text('active')
    env = dict(base_env, OCTOPUS_HOST='claude', CLAUDE_CODE_SESSION_ID=sid)
    for cmd, expected in [
        ('rm -rf /tmp/important node_modules', 'ask'),
        ('rm -rf node_modules && rm -rf /tmp/important', 'ask'),
        ('rm -fr /tmp/important', 'ask'),
        ('rm -R -f /tmp/important', 'ask'),
        ('/bin/rm --force --recursive /tmp/important', 'ask'),
        ('rm -rf node_modules dist', 'allow'),
        ("rm -rf ';' /tmp/important", 'ask'),
        ("rm -rf node_modules ';' /tmp/important", 'ask'),
        (r'rm -rf node_modules \; /tmp/important', 'ask'),
        ('rm -rf "|" /tmp/important', 'ask'),
        ('rm -rf node_modules/{dist,../src}', 'ask'),
        ('rm -rf node_modules/{1..3}', 'ask'),
        ("printf '%s' 'rm -rf /tmp/important' | bash", 'ask'),
        ("echo 'rm -rf /tmp/important' | /bin/sh", 'ask'),
        ("printf '%s' 'rm -rf /tmp/important' | env zsh", 'ask'),
        ("printf '%s' 'r''m -rf /tmp/important' | bash", 'ask'),
        ("printf '%s' 'rm -rf /tmp/important' | dash", 'ask'),
        ("printf '%s' 'rm -rf /tmp/important' | ksh", 'ask'),
        ("printf '%s' 'rm -rf /tmp/important' | env fish", 'ask'),
        ("printf '%s' 'rm -rf /tmp/important' | timeout 5 tcsh", 'ask'),
        ("printf '%s' 'rm -rf /tmp/important' | grep dash", 'allow'),
        ("printf '%s' 'rm -rf /tmp/important' | grep bash", 'allow'),
        ("printf '%s' 'rm -rf /tmp/important' | source /dev/stdin", 'ask'),
        ("printf '%s' 'rm -rf /tmp/important' | . /dev/stdin", 'ask'),
        ("printf '%s' 'rm -rf /tmp/important' | xargs", 'ask'),
        ("printf '%s' 'rm -rf /tmp/important' | timeout 5 parallel", 'ask'),
        ("printf '%s' 'rm -rf /tmp/important' | \"$SHELL\"", 'ask'),
        ("printf '%s' 'rm -rf /tmp/important' | timeout 5 \"$SHELL\"", 'ask'),
        ("printf '%s' 'rm -rf /tmp/important' | sudo -u somebody \"$SHELL\"", 'ask'),
        ("rg 'rm -rf' README.md | sed -n '$p'", 'allow'),
        ("env sed -n '$p' README.md | grep 'rm -rf'", 'allow'),
        ("env \"$SHELL\" -c 'rm -rf /tmp/important' rm", 'ask'),
        ("sudo -u somebody \"$SHELL\" -c 'rm -rf /tmp/important' rm", 'ask'),
        ('env FOO=bar rm -rf node_modules', 'allow'),
        ('sudo -u somebody rm -rf node_modules', 'allow'),
        ('timeout --kill-after 1s 5 rm -rf node_modules', 'allow'),
        ('command -v rm', 'allow'),
        ('rtk proxy echo rm', 'allow'),
        ('CMD=rm; time "$CMD" -rf /tmp/important', 'ask'),
        ('CMD=rm; time -p "$CMD" -rf /tmp/important', 'ask'),
        ('CMD=rm; /usr/bin/time -p "$CMD" -rf /tmp/important', 'ask'),
        ('time /bin/r[m] -rf /tmp/important', 'ask'),
        ('time -p env /bin/r[m] -rf /tmp/important', 'ask'),
        ('! /bin/r[m] -rf /tmp/important', 'ask'),
        ('time -p ! /bin/r[m] -rf /tmp/important', 'ask'),
        ('time -p rm -rf node_modules', 'allow'),
        ('time -p printf ok', 'allow'),
        ('time -p VALUE="$HOME" sed -n \'$p\' README.md', 'allow'),
        ('[[ -f README.md ]]', 'allow'),
        ('time -p [[ -f README.md ]]', 'allow'),
        ('/tmp/[[ -f README.md ]]', 'ask'),
        ('/bin/r[m] -rf /tmp/important', 'ask'),
        ('env /bin/r[m] -rf /tmp/important', 'ask'),
        ('timeout 5 /bin/r? -rf /tmp/important', 'ask'),
        ('/bin/*m -rf /tmp/important', 'ask'),
        ('/bin/{r,fo}m -rf /tmp/important', 'ask'),
        ('sudo -A /bin/r[m] -rf /tmp/important', 'ask'),
        ("'/tmp/literal[command]' argument", 'allow'),
        ('"/tmp/literal?command" argument', 'allow'),
        (r'/tmp/literal\[command\] argument', 'allow'),
        ("/tmp/literal'[command]' argument", 'allow'),
        ("'/tmp/literal*command' argument", 'allow'),
        ("'/tmp/literal{command}' argument", 'allow'),
        ('[ -f README.md ]', 'allow'),
        ('/usr/bin/[ -f README.md ]', 'allow'),
        ('/tmp/plain/[ -f README.md ]', 'allow'),
        ('/tmp/[x]/[ -f README.md ]', 'ask'),
        ('rg pattern *.md', 'allow'),
        (r'''c=$(printf '\162\155'); "$c" -rf /tmp/important''', 'ask'),
        (r'''c=$(printf '\162\155'); timeout 5 "$c" -rf /tmp/important''', 'ask'),
        (r'''c=$(printf '\162\155'); sudo -u "$USER" "$c" -rf /tmp/important''', 'ask'),
        (r'''printf '\162\155 -rf /tmp/important' | bash''', 'ask'),
        (r'''printf '\162\155 -rf /tmp/important' | xargs''', 'ask'),
        (r'''result=$(printf ok); printf '%s' "$result"''', 'allow'),
        (r'''VALUE="$HOME" sed -n '$p' README.md''', 'allow'),
        ('sudo -u somebody rm -rf /tmp/important', 'ask'),
        ('if true; then rm -rf /tmp/important; fi', 'ask'),
        ('for x in once; do rm -rf /tmp/important; done', 'ask'),
        ('timeout 5 rm -rf /tmp/important', 'ask'),
        ('rtk proxy rm -rf /tmp/important', 'ask'),
        ('rtk proxy rm -rf node_modules', 'allow'),
        ('echo ignored#; rm -rf /tmp/important', 'ask'),
        ('echo "$(rm -rf /tmp/important)"', 'ask'),
        ('echo `rm -rf /tmp/important`', 'ask'),
        ("trap 'rm -rf /tmp/important' EXIT", 'ask'),
        ('cd /tmp && rm -rf node_modules', 'ask'),
        ('xargs rm -fr /tmp/important', 'ask'),
        ('rm -rf node_modules/../../important', 'ask'),
        ('rm -rf "$TARGET"', 'ask'),
        ("echo 'rm -rf /tmp/important'", 'allow'),
    ]:
        assert hook('careful-check.sh', {'tool_name':'Bash','tool_input':{'command':cmd}}, env)==expected, cmd
    assert hook('careful-check.sh', {'tool_name':'Bash','cwd':42,'tool_input':{'command':'rm -rf node_modules'}}, env)=='deny'
    assert hook('careful-check.sh', {'tool_name':'Bash','cwd':'relative','tool_input':{'command':'rm -rf node_modules'}}, env)=='deny'
    with tempfile.TemporaryDirectory() as temporary:
        checkout = Path(temporary)/'build'/'app'; checkout.mkdir(parents=True)
        for target, expected in [('.', 'ask'), ('src', 'ask'), ('node_modules', 'allow'), ('dist/assets', 'allow'), ('../node_modules', 'ask')]:
            assert hook('careful-check.sh', {'tool_name':'Bash','cwd':str(checkout),'tool_input':{'command':'rm -rf '+target}}, env)==expected, target
        link = Path(temporary)/'node_modules'; outside = Path(temporary)/'private'; outside.mkdir(); link.symlink_to(outside)
        assert hook('careful-check.sh', {'tool_name':'Bash','tool_input':{'command':'rm -rf '+str(link)}}, env)=='ask'
finally:
    state.unlink(missing_ok=True)
with tempfile.TemporaryDirectory() as temporary:
    helper = root/'scripts/helpers/guard-state.sh'
    for existing in [False, True]:
        for failure in ['directory', 'replace']:
            careful = Path('/tmp/octopus-careful-'+sid+'.txt')
            freeze = Path('/tmp/octopus-freeze-'+sid+'.txt')
            prior = b'prior careful state\n'
            env = dict(base_env, OCTOPUS_HOST='claude', CLAUDE_CODE_SESSION_ID=sid)
            if existing:
                careful.write_bytes(prior)
            if failure == 'directory':
                freeze.mkdir()
            else:
                shim_dir = Path(temporary)/'rename-failure'; shim_dir.mkdir(exist_ok=True)
                shim = shim_dir/'python3'
                shim.write_text('#!'+sys.executable+'\nimport os,sys\noriginal=os.replace\n'
                    'def replace(source, destination):\n'
                    '    """Inject only the selected freeze publication failure."""\n'
                    '    if str(destination)==os.environ["FAIL_FREEZE_DEST"]: raise PermissionError("injected rename failure")\n'
                    '    return original(source,destination)\n'
                    'os.replace=replace\nsys.argv=sys.argv[1:]\n'
                    'exec(compile(sys.stdin.read(),"guard-replace-fixture","exec"))\n')
                shim.chmod(0o700)
                env.update(PATH=str(shim_dir)+os.pathsep+env['PATH'], FAIL_FREEZE_DEST=str(freeze))
            try:
                result = subprocess.run(['bash',str(helper),'guard-on',temporary],env=env,capture_output=True,text=True)
                assert result.returncode != 0, (existing, failure, 'guard unexpectedly succeeded')
                assert careful.read_bytes()==prior if existing else not careful.exists(), (existing, failure, 'careful state changed on failure')
                assert freeze.is_dir() if failure == 'directory' else not freeze.exists()
            finally:
                careful.unlink(missing_ok=True)
                if freeze.is_dir(): freeze.rmdir()
                else: freeze.unlink(missing_ok=True)
    for action, kind in [('careful-on', 'careful'), ('freeze-on', 'freeze')]:
        directory = Path('/tmp/octopus-'+kind+'-'+sid+'.txt')
        directory.mkdir()
        marker = directory/'preserved'; marker.write_text('existing state directory')
        env = dict(base_env, OCTOPUS_HOST='claude', CLAUDE_CODE_SESSION_ID=sid)
        try:
            args = ['bash', str(helper), action] + ([temporary] if kind == 'freeze' else [])
            result = subprocess.run(args, env=env, capture_output=True, text=True)
            assert result.returncode != 0, (action, 'directory destination reported success')
            assert list(directory.iterdir()) == [marker], 'temporary state was moved into the directory'
            assert marker.read_text() == 'existing state directory'
        finally:
            for owned in directory.iterdir():
                owned.unlink()
            directory.rmdir()
    for host, key in [('claude','CLAUDE_CODE_SESSION_ID'),('claude','CLAUDE_CODE_SESSION'),('codex','CODEX_SESSION_ID'),('codex','CODEX_TASK_ID')]:
        env = dict(base_env, OCTOPUS_HOST=host, **{key:sid, ('CLAUDE_PLUGIN_ROOT' if host=='claude' else 'CODEX_PLUGIN_ROOT'):str(root)})
        freeze = Path('/tmp/octopus-freeze-'+sid+'.txt')
        careful = Path('/tmp/octopus-careful-'+sid+'.txt')
        try:
            subprocess.run(['bash',str(helper),'guard-on',temporary],env=env,check=True,capture_output=True)
            assert hook('careful-check.sh',{'tool_name':'Bash','tool_input':{'command':"rg 'rm -rf' README.md | sed -n '$p'"}},env)=='allow'
            assert freeze.read_text().strip()==str(Path(temporary).resolve())
            assert hook('freeze-check.sh',{'tool_name':'Write','cwd':temporary,'tool_input':{'file_path':'/tmp/outside-command-audit'}},env)=='deny'
            assert hook('careful-check.sh',{'tool_name':'Bash','tool_input':{'command':'rm -rf /tmp/important'}},env)==('deny' if host=='codex' else 'ask')
            subprocess.run(['bash',str(helper),'freeze-off'],env=env,check=True,capture_output=True)
            assert not freeze.exists() and careful.exists()
            subprocess.run(['bash',str(helper),'careful-off'],env=env,check=True,capture_output=True)
            for document in ['commands/careful.md','.cursor-plugin/commands/octo-careful.md']:
                blocks = re.findall(r'```bash\n(.*?)\n```', (root/document).read_text(), re.S)
                assert len(blocks) == 2, document
                subprocess.run(['bash','-c',blocks[0]],env=env,check=True,capture_output=True)
                assert careful.exists(), (host, document, 'activation')
                subprocess.run(['bash','-c',blocks[1]],env=env,check=True,capture_output=True)
                assert not careful.exists(), (host, document, 'deactivation')
        finally:
            freeze.unlink(missing_ok=True); careful.unlink(missing_ok=True)
    result=subprocess.run(['bash',str(helper),'freeze-on',temporary],env=dict(base_env,OCTOPUS_HOST='claude'),capture_output=True,text=True)
    assert result.returncode==2 and 'no stable host session ID' in result.stderr
CHECKS
then test_pass; else test_fail "command safety regression"; fi
test_summary
