#!/usr/bin/env python3
import argparse, json, os, re, subprocess, sys, time, urllib.parse, urllib.request, urllib.error
from pathlib import Path

PROVIDERS = {
    "generic": {"base_url": "", "api_key_env": "OPENAI_API_KEY", "model": "", "headers": {}},
    "atlascloud": {
        "base_url": "https://api.atlascloud.ai/v1",
        "api_key_env": "ATLASCLOUD_API_KEY",
        "model": "",
        "headers": {},
    },
}


def env_int(name: str, default: int, minimum: int = 0) -> int:
    raw = os.environ.get(name, "")
    if raw == "":
        return default
    try:
        value = int(raw)
    except ValueError:
        print(f"WARN: invalid {name}={raw!r}; using {default}", file=sys.stderr)
        return default
    return max(minimum, value)

def env_float(name: str, default: float, minimum: float = 0.1) -> float:
    raw = os.environ.get(name, "")
    if raw == "":
        return default
    try:
        value = float(raw)
    except ValueError:
        print(f"WARN: invalid {name}={raw!r}; using {default}", file=sys.stderr)
        return default
    return max(minimum, value)

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


# Guardrails for run_command.
#
# read_file/write_file are confined to cwd by resolve_path, but run_command
# runs an arbitrary string through a shell, so that confinement was decorative:
# the model could delete or exfiltrate anything the invoking user can reach.
# This is a guardrail against an unsupervised model doing something destructive,
# NOT a sandbox — a determined adversary can trivially encode around it. Real
# isolation needs a container or a restricted user.
#
# Set OPENAI_COMPAT_UNSAFE_COMMANDS=1 to disable (e.g. inside a throwaway
# container where the blast radius is already bounded).
_BLOCKED_COMMAND_PATTERNS = [
    # Destructive recursive deletes outside the working tree
    (r'\brm\s+(?:(?:(?:-[A-Za-z]+|--[A-Za-z-]+)\s+)*(?:-[A-Za-z]*[rR][A-Za-z]*|--recursive)'
     r'(?:\s+(?:-[A-Za-z]+|--[A-Za-z-]+))*)\s+(?:[^\s|;&]+\s+)*'
     r'(?:"(?:/[^"]*|\$(?:\{HOME\}|HOME)(?:/[^"]*)?)"(?:/[^\s|;&]*)?|'
     r"'(?:/[^']*|\$(?:\{HOME\}|HOME)(?:/[^']*)?)'(?:/[^\s|;&]*)?|"
     r'(?:/[^\s|;&]*|~(?:/[^\s|;&]*)?|\$(?:\{HOME\}|HOME)(?:/[^\s|;&]*)?))(?:\s|$)',
     "recursive delete targeting an absolute or home path"),
    # Privilege escalation
    (r'(^|[|;&]\s*)sudo\s', "sudo"),
    (r'(^|[|;&]\s*)(doas|su)\s', "privilege escalation"),
    # Download-and-execute
    (r'(curl|wget)\b[^|;&]*\|\s*(sudo\s+)?(ba|z|k)?sh', "piping a download into a shell"),
    # Reading credential stores
    (r'(/etc/(shadow|sudoers)|\.ssh/id_[a-z0-9]+|\.aws/credentials|\.netrc|\.git-credentials)',
     "reading a credential file"),
    # Disk / device level writes
    (r'\b(mkfs|dd)\b[^|;&]*\bof=/dev/', "raw device write"),
    # Whole-history rewrites and forced pushes to a remote
    (r'\bgit\s+push\b[^|;&]*(--force(?!-with-lease)|\s-f(\s|$))', "forced push"),
]


def command_is_blocked(cmd: str):
    """Return a human-readable reason when cmd matches a guardrail, else None."""
    if os.environ.get("OPENAI_COMPAT_UNSAFE_COMMANDS", "") == "1":
        return None
    import re as _re
    for pattern, reason in _BLOCKED_COMMAND_PATTERNS:
        if _re.search(pattern, cmd):
            return reason
    return None

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
            blocked = command_is_blocked(cmd)
            if blocked:
                print(f"tool run_command BLOCKED ({blocked}): {cmd[:200]}", file=sys.stderr)
                return (f"ERROR: refused — {blocked}. This agent may not run that. "
                        f"Work within the project directory, or ask the operator to run it.")
            timeout = env_float("OPENAI_COMPAT_COMMAND_TIMEOUT", 20.0)
            r = subprocess.run(cmd, cwd=str(cwd), shell=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout, check=False)  # noqa: S602 - intentional shell-command tool
            return (f"exit={r.returncode}\n" + r.stdout)[-20000:]
        if name == "git_diff":
            timeout = env_float("OPENAI_COMPAT_COMMAND_TIMEOUT", 20.0)
            r = subprocess.run(["git", "diff", "--", "."], cwd=str(cwd), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout, check=False)
            return (f"exit={r.returncode}\n" + r.stdout)[-30000:]
        return f"ERROR: unknown tool {name}"
    except Exception as e:
        return f"ERROR: {type(e).__name__}: {e}"


def normalize_reasoning_effort(value):
    if value in {"xhigh", "max"}:
        return "high"
    return value


def is_astra_model(model):
    return model == "gpt-6-astra"


def rejects_reasoning_effort(body_text):
    text = body_text.lower()
    field = r"(?<![A-Za-z0-9_-])reasoning(?:_effort| effort|-effort)(?![A-Za-z0-9_-])"
    kind = r"(?:field|parameter|argument|property)"
    rejection = r"(?:unsupported|not supported|unrecognized|unknown|unexpected|not allowed|not permitted)"
    patterns = (
        rf"{rejection}\s+{kind}\s*:?\s*[\"'`]?{field}",
        rf"{kind}\s+[\"'`]?{field}[\"'`]?\s+(?:is\s+)?{rejection}",
        rf"{field}[\"'`]?\s+(?:{kind}\s+)?(?:is\s+)?{rejection}",
    )
    return any(re.search(pattern, text) for pattern in patterns)


def api_call(base_url, key, model, headers_extra, messages, max_tokens=0, request_timeout=60.0, max_retries=3, reasoning_effort=None, reasoning_policy="best_effort", tool_policy="auto"):
    if is_astra_model(model) and tool_policy == "auto":
        raise ValueError("gpt-6-astra tools require the Responses API; this adapter uses Chat Completions")
    payload = {"model": model, "messages": messages}
    if not is_astra_model(model):
        payload["temperature"] = 0
    if tool_policy == "auto":
        payload["tools"] = TOOLS
        payload["tool_choice"] = "auto"
    if reasoning_effort:
        payload["reasoning_effort"] = reasoning_effort
    if max_tokens > 0:
        payload["max_tokens"] = max_tokens
    headers = {"Authorization": "Bearer " + key, "Content-Type": "application/json", **headers_extra}
    body = json.dumps(payload).encode()
    endpoint = base_url.rstrip("/") + "/chat/completions"
    scheme = urllib.parse.urlparse(endpoint).scheme
    if scheme not in {"http", "https"}:
        raise ValueError(f"unsupported OPENAI-compatible base URL scheme: {scheme or '<missing>'}")
    retry_statuses = {429, 502, 503, 504}
    last_error = None
    for attempt in range(1, max(1, max_retries) + 1):
        print(f"chat_start attempt={attempt}/{max(1, max_retries)} messages={len(messages)} bytes={len(body)} timeout={request_timeout} max_tokens={max_tokens if max_tokens > 0 else 'provider_default'}", file=sys.stderr)
        req = urllib.request.Request(endpoint, data=body, headers=headers, method="POST")
        started = time.time()
        try:
            with urllib.request.urlopen(req, timeout=request_timeout) as r:
                raw = r.read().decode()
                print(f"chat_done attempt={attempt}/{max(1, max_retries)} status=200 elapsed={time.time() - started:.2f}s bytes={len(raw)}", file=sys.stderr)
                return json.loads(raw)
        except urllib.error.HTTPError as e:
            body_text = e.read().decode(errors="replace")[:2000]
            if (
                reasoning_effort
                and reasoning_policy == "best_effort"
                and e.code in {400, 422}
                and rejects_reasoning_effort(body_text)
            ):
                print("chat_reasoning_fallback unsupported reasoning_effort; retrying without it", file=sys.stderr)
                return api_call(
                    base_url, key, model, headers_extra, messages,
                    max_tokens=max_tokens,
                    request_timeout=request_timeout,
                    max_retries=max_retries,
                    reasoning_effort=None,
                    reasoning_policy="strict",
                    tool_policy=tool_policy,
                )
            last_error = RuntimeError(f"HTTP {e.code}: {body_text}")
            print(f"chat_error attempt={attempt}/{max(1, max_retries)} status={e.code} elapsed={time.time() - started:.2f}s", file=sys.stderr)
            if e.code not in retry_statuses or attempt >= max(1, max_retries):
                raise last_error
        except Exception as e:
            last_error = e
            print(f"chat_error attempt={attempt}/{max(1, max_retries)} error={type(e).__name__}: {str(e)[:300]}", file=sys.stderr)
            if attempt >= max(1, max_retries):
                raise RuntimeError(f"request failed after {attempt} attempt(s): {e}") from e
        time.sleep(min(float(attempt), 5.0))
    raise RuntimeError(f"request failed after retries: {last_error}")

def parse_args(raw: str) -> dict:
    try: return json.loads(raw or "{}")
    except Exception: return {"_raw": raw}

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--provider", choices=sorted(PROVIDERS), default="generic")
    ap.add_argument("--base-url"); ap.add_argument("--api-key-env"); ap.add_argument("--model")
    ap.add_argument("--cwd", required=True)
    ap.add_argument("--prompt")
    ap.add_argument("--reasoning-effort", choices=["low", "medium", "high", "xhigh", "max"])
    ap.add_argument("--reasoning-policy", choices=["strict", "best_effort"], default="best_effort")
    ap.add_argument("--tool-policy", choices=["auto", "none"], default="auto")
    args = ap.parse_args(); cfg = PROVIDERS[args.provider]
    base_url = args.base_url or os.environ.get("OPENAI_COMPAT_BASE_URL") or cfg["base_url"]
    key_env = args.api_key_env or os.environ.get("OPENAI_COMPAT_API_KEY_ENV") or cfg["api_key_env"]
    if args.provider == "atlascloud":
        model = args.model or os.environ.get("ATLASCLOUD_MODEL") or os.environ.get("OCTOPUS_ATLASCLOUD_MODEL") or os.environ.get("OPENAI_COMPAT_MODEL") or cfg["model"]
    else:
        model = args.model or os.environ.get("OPENAI_COMPAT_MODEL") or cfg["model"]
    if not model:
        model_hint = "ATLASCLOUD_MODEL, OCTOPUS_ATLASCLOUD_MODEL, OPENAI_COMPAT_MODEL, or --model" if args.provider == "atlascloud" else "OPENAI_COMPAT_MODEL or --model"
        print(f"ERROR: missing {model_hint}", file=sys.stderr); return 2
    if is_astra_model(model) and args.tool_policy == "auto":
        print("ERROR: gpt-6-astra tools require the Responses API; use Codex CLI or --tool-policy none", file=sys.stderr)
        return 2
    if not base_url:
        print("ERROR: missing OPENAI_COMPAT_BASE_URL or --base-url", file=sys.stderr); return 2
    key = os.environ.get(key_env)
    if not key:
        print(f"ERROR: missing {key_env}", file=sys.stderr); return 2
    max_tokens = env_int("OPENAI_COMPAT_MAX_TOKENS", 0, 0)
    request_timeout = env_float("OPENAI_COMPAT_REQUEST_TIMEOUT", 60.0)
    max_retries = env_int("OPENAI_COMPAT_MAX_RETRIES", 3, 1)
    cwd = Path(args.cwd).resolve(); prompt = args.prompt if args.prompt is not None else sys.stdin.read()
    messages = [
        {"role":"system","content":"You are a coding agent. Use tools when needed. For implementation tasks, edit files, call git_diff before final, and do not stop after only reading files. Final answer must be visible text. If a verification command fails because a local dependency or tool is missing, stop retrying that same command, call git_diff if not already done, and give a final answer that reports the blocker and the worktree changes."},
        {"role":"user","content":prompt},
    ]
    print(f"provider={args.provider} base_url={base_url} model={model} cwd={cwd}", file=sys.stderr)
    requested_reasoning = args.reasoning_effort or "none"
    effective_reasoning = normalize_reasoning_effort(args.reasoning_effort)
    effective_label = effective_reasoning or "none"
    print(f"chat_reasoning requested={requested_reasoning} effective={effective_label} policy={args.reasoning_policy}", file=sys.stderr)
    turn = 0
    while True:
        turn += 1
        d = api_call(base_url, key, model, cfg.get("headers", {}), messages, max_tokens=max_tokens, request_timeout=request_timeout, max_retries=max_retries, reasoning_effort=effective_reasoning, reasoning_policy=args.reasoning_policy, tool_policy=args.tool_policy)
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
            if args.tool_policy == "none":
                print("ERROR: provider returned tool calls while tool policy is none", file=sys.stderr)
                return 1
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

if __name__ == "__main__":
    raise SystemExit(main())
