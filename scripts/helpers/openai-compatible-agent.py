#!/usr/bin/env python3
import argparse, json, os, subprocess, sys, urllib.request, urllib.error
from pathlib import Path

PROVIDERS = {
    "generic": {"base_url": "", "api_key_env": "OPENAI_API_KEY", "model": "", "headers": {}},
}

TOOLS = [
    {"type":"function","function":{"name":"read_file","description":"Read a UTF-8 file under cwd.","parameters":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}}},
    {"type":"function","function":{"name":"write_file","description":"Write UTF-8 content to a file under cwd.","parameters":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}},
    {"type":"function","function":{"name":"run_command","description":"Run a shell command in cwd with a short timeout.","parameters":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}}},
    {"type":"function","function":{"name":"git_diff","description":"Return git diff for cwd.","parameters":{"type":"object","properties":{}}}},
]

def resolve_path(cwd: Path, rel: str) -> Path:
    p = (cwd / rel).resolve(); c = cwd.resolve()
    if p != c and c not in p.parents:
        raise ValueError("path escapes cwd")
    return p

def tool_exec(cwd: Path, name: str, args: dict) -> str:
    try:
        if name == "read_file":
            return resolve_path(cwd, str(args.get("path", ""))).read_text(encoding="utf-8", errors="replace")[:20000]
        if name == "write_file":
            p = resolve_path(cwd, str(args.get("path", ""))); p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(str(args.get("content", "")), encoding="utf-8")
            return f"wrote {p.relative_to(cwd.resolve())} ({p.stat().st_size} bytes)"
        if name == "run_command":
            cmd = str(args.get("command", ""))
            if len(cmd) > 600: return "ERROR: command too long"
            r = subprocess.run(cmd, cwd=str(cwd), shell=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
            return (f"exit={r.returncode}\n" + r.stdout)[-20000:]
        if name == "git_diff":
            r = subprocess.run("git diff -- .", cwd=str(cwd), shell=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
            return (f"exit={r.returncode}\n" + r.stdout)[-30000:]
        return f"ERROR: unknown tool {name}"
    except Exception as e:
        return f"ERROR: {type(e).__name__}: {e}"

def api_call(base_url, key, model, headers_extra, messages, max_tokens=1400):
    payload = {"model": model, "messages": messages, "tools": TOOLS, "tool_choice": "auto", "temperature": 0, "max_tokens": max_tokens}
    headers = {"Authorization": "Bearer " + key, "Content-Type": "application/json", **headers_extra}
    req = urllib.request.Request(base_url.rstrip("/") + "/chat/completions", data=json.dumps(payload).encode(), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")[:2000]
        raise RuntimeError(f"HTTP {e.code}: {body}")

def parse_args(raw: str) -> dict:
    try: return json.loads(raw or "{}")
    except Exception: return {"_raw": raw}

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--provider", choices=sorted(PROVIDERS), default="generic")
    ap.add_argument("--base-url"); ap.add_argument("--api-key-env"); ap.add_argument("--model")
    ap.add_argument("--cwd", required=True); ap.add_argument("--max-turns", type=int, default=int(os.environ.get("OPENAI_COMPAT_MAX_TURNS", "20"))); ap.add_argument("--prompt")
    args = ap.parse_args(); cfg = PROVIDERS[args.provider]
    base_url = args.base_url or os.environ.get("OPENAI_COMPAT_BASE_URL") or cfg["base_url"]
    key_env = args.api_key_env or os.environ.get("OPENAI_COMPAT_API_KEY_ENV") or cfg["api_key_env"]
    model = args.model or os.environ.get("OPENAI_COMPAT_MODEL") or cfg["model"]
    if not model:
        print("ERROR: missing OPENAI_COMPAT_MODEL or --model", file=sys.stderr); return 2
    if not base_url:
        print("ERROR: missing OPENAI_COMPAT_BASE_URL or --base-url", file=sys.stderr); return 2
    key = os.environ.get(key_env)
    if not key:
        print(f"ERROR: missing {key_env}", file=sys.stderr); return 2
    cwd = Path(args.cwd).resolve(); prompt = args.prompt if args.prompt is not None else sys.stdin.read()
    messages = [
        {"role":"system","content":"You are a coding agent. Use tools when needed. For implementation tasks, edit files, call git_diff before final, and do not stop after only reading files. Final answer must be visible text. If a verification command fails because a local dependency or tool is missing, stop retrying that same command, call git_diff if not already done, and give a final answer that reports the blocker and the worktree changes."},
        {"role":"user","content":prompt},
    ]
    print(f"provider={args.provider} base_url={base_url} model={model} cwd={cwd}", file=sys.stderr)
    for turn in range(1, args.max_turns + 1):
        d = api_call(base_url, key, model, cfg.get("headers", {}), messages)
        ch = d.get("choices", [{}])[0]; msg = ch.get("message", {})
        finish = ch.get("finish_reason")
        raw_content = msg.get("content")
        if isinstance(raw_content, str):
            content = raw_content
        elif raw_content is None:
            content = ""
        else:
            content = json.dumps(raw_content, ensure_ascii=False)
        calls = msg.get("tool_calls") or []
        print(f"turn={turn} finish={finish} content_len={len(content)} tool_calls={len(calls)}", file=sys.stderr)
        if calls:
            messages.append({"role":"assistant", "content": content, "tool_calls": calls})
            for tc in calls:
                fn = (tc.get("function") or {}).get("name", ""); raw = (tc.get("function") or {}).get("arguments", "{}")
                out = tool_exec(cwd, fn, parse_args(raw))
                print(f"tool {fn} -> {len(out)} chars", file=sys.stderr)
                messages.append({"role":"tool", "tool_call_id": tc.get("id"), "name": fn, "content": out})
            continue
        if content.strip():
            print(content); return 0
        messages.append({"role":"user","content":"Your previous assistant message was empty. Provide a visible final answer, or continue with tools if work remains."})
    print("ERROR: no visible final answer after max turns", file=sys.stderr); return 1

if __name__ == "__main__":
    raise SystemExit(main())
