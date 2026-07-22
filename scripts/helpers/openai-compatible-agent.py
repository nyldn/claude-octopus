#!/usr/bin/env python3
import argparse, json, os, re, subprocess, sys, time, urllib.parse, urllib.request, urllib.error
from pathlib import Path

PROVIDERS = {
    "generic": {"base_url": "", "api_key_env": "OPENAI_API_KEY", "model": "", "headers": {}},
    "openrouter": {
        "base_url": "https://openrouter.ai/api/v1",
        "api_key_env": "OPENROUTER_API_KEY",
        "model": "",
        "headers": {
            "HTTP-Referer": "https://github.com/nyldn/claude-octopus",
            "X-Title": "Claude Octopus",
        },
    },
    "atlascloud": {
        "base_url": "https://api.atlascloud.ai/v1",
        "api_key_env": "ATLASCLOUD_API_KEY",
        "model": "",
        "headers": {},
    },
}


def configure_utf8_stdio(*streams) -> None:
    targets = streams or (sys.stdout, sys.stderr)
    for stream in targets:
        reconfigure = getattr(stream, "reconfigure", None)
        if callable(reconfigure):
            try:
                reconfigure(encoding="utf-8", errors="replace")
            except (AttributeError, ValueError, OSError):
                pass


def normalize_cli_path(value: str) -> str:
    if os.name != "nt":
        return value
    match = re.match(r"^/(?:cygdrive/)?([A-Za-z])(?:/(.*))?$", value)
    if not match:
        return value
    drive = match.group(1).upper()
    tail = (match.group(2) or "").replace("/", "\\")
    return f"{drive}:\\{tail}"


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

READ_ONLY_TOOLS = [
    {"type":"function","function":{"name":"read_file","description":"Read a UTF-8 file under cwd.","parameters":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}}},
    {"type":"function","function":{"name":"list_files","description":"List files under a path within cwd.","parameters":{"type":"object","properties":{"path":{"type":"string"}}}}},
    {"type":"function","function":{"name":"git_status","description":"Return concise git status for cwd.","parameters":{"type":"object","properties":{}}}},
    {"type":"function","function":{"name":"git_diff","description":"Return staged and unstaged git diff for cwd.","parameters":{"type":"object","properties":{}}}},
]

WRITE_TOOLS = [
    {"type":"function","function":{"name":"write_file","description":"Write UTF-8 content to a file under cwd.","parameters":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}},
    {"type":"function","function":{"name":"run_command","description":"Run a shell command in cwd with a short timeout.","parameters":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}}},
]

TOOLS = READ_ONLY_TOOLS + WRITE_TOOLS


def tools_for_mode(mode: str) -> list:
    return READ_ONLY_TOOLS if mode == "readonly" else TOOLS

def resolve_path(cwd: Path, rel: str) -> Path:
    p = (cwd / rel).resolve(); c = cwd.resolve()
    if p != c and c not in p.parents:
        raise ValueError("path escapes cwd")
    return p

def tool_exec(cwd: Path, name: str, args: dict, tool_mode: str = "full") -> str:
    try:
        allowed = {item["function"]["name"] for item in tools_for_mode(tool_mode)}
        if name not in allowed:
            return f"ERROR: tool {name} is unavailable in {tool_mode} mode"
        if name == "read_file":
            return resolve_path(cwd, str(args.get("path", ""))).read_text(encoding="utf-8", errors="replace")[:20000]
        if name == "list_files":
            base = resolve_path(cwd, str(args.get("path", ".")))
            if base.is_file():
                return str(base.relative_to(cwd.resolve()))
            files = []
            for path in sorted(base.rglob("*")):
                if path.is_file() and ".git" not in path.parts:
                    files.append(str(path.relative_to(cwd.resolve())))
                    if len(files) >= 500:
                        files.append("... output limited to 500 files")
                        break
            return "\n".join(files)
        if name == "git_status":
            timeout = env_float("OPENAI_COMPAT_COMMAND_TIMEOUT", 20.0)
            r = subprocess.run(["git", "status", "--short"], cwd=str(cwd), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout, check=False)
            return (f"exit={r.returncode}\n" + r.stdout)[-20000:]
        if name == "write_file":
            p = resolve_path(cwd, str(args.get("path", ""))); p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(str(args.get("content", "")), encoding="utf-8")
            return f"wrote {p.relative_to(cwd.resolve())} ({p.stat().st_size} bytes)"
        if name == "run_command":
            cmd = str(args.get("command", ""))
            if len(cmd) > 600: return "ERROR: command too long"
            timeout = env_float("OPENAI_COMPAT_COMMAND_TIMEOUT", 20.0)
            r = subprocess.run(cmd, cwd=str(cwd), shell=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout, check=False)  # noqa: S602 - intentional shell-command tool
            return (f"exit={r.returncode}\n" + r.stdout)[-20000:]
        if name == "git_diff":
            timeout = env_float("OPENAI_COMPAT_COMMAND_TIMEOUT", 20.0)
            unstaged = subprocess.run(["git", "diff", "--", "."], cwd=str(cwd), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout, check=False)
            staged = subprocess.run(["git", "diff", "--cached", "--", "."], cwd=str(cwd), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout, check=False)
            combined = f"UNSTAGED exit={unstaged.returncode}\n{unstaged.stdout}\nSTAGED exit={staged.returncode}\n{staged.stdout}"
            return combined[-40000:]
        return f"ERROR: unknown tool {name}"
    except Exception as e:
        return f"ERROR: {type(e).__name__}: {e}"

def api_call(base_url, key, model, headers_extra, messages, max_tokens=1400, request_timeout=60.0, max_retries=3, reasoning_effort=None, reasoning_policy="best_effort", tools=None):
    active_tools = TOOLS if tools is None else tools
    payload = {"model": model, "messages": messages, "tools": active_tools, "tool_choice": "auto", "temperature": 0}
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
                and any(token in body_text.lower() for token in ("reasoning_effort", "reasoning effort", "reasoning"))
            ):
                print("chat_reasoning_fallback unsupported reasoning_effort; retrying without it", file=sys.stderr)
                return api_call(
                    base_url, key, model, headers_extra, messages,
                    max_tokens=max_tokens,
                    request_timeout=request_timeout,
                    max_retries=max_retries,
                    reasoning_effort=None,
                    reasoning_policy="strict",
                    tools=active_tools,
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


def is_unevaluated_tool_text(content: str) -> bool:
    text = content.strip()
    if not text:
        return False
    if re.search(r"<\s*(tool_call|function_call|function_calls)\b", text, re.IGNORECASE):
        return True
    # Intent-only transitions are intermediate agent messages, not verdicts.
    return bool(
        len(text) < 1200
        and re.search(
            r"(?:^|\n)\s*(?:i(?:'ll| will| need to)|let me)\s+(?:first\s+)?(?:inspect|read|check|run|look|review)\b",
            text,
            re.IGNORECASE,
        )
    )

def main() -> int:
    configure_utf8_stdio()
    ap = argparse.ArgumentParser()
    ap.add_argument("--provider", choices=sorted(PROVIDERS), default="generic")
    ap.add_argument("--base-url"); ap.add_argument("--api-key-env"); ap.add_argument("--model")
    ap.add_argument("--cwd", required=True); ap.add_argument("--max-turns", type=int, default=env_int("OPENAI_COMPAT_MAX_TURNS", 20, 1)); ap.add_argument("--prompt")
    ap.add_argument("--reasoning-effort", choices=["low", "medium", "high", "xhigh", "max"])
    ap.add_argument("--reasoning-policy", choices=["strict", "best_effort"], default="best_effort")
    ap.add_argument("--tool-mode", choices=["full", "readonly"], default="full")
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
    if not base_url:
        print("ERROR: missing OPENAI_COMPAT_BASE_URL or --base-url", file=sys.stderr); return 2
    key = os.environ.get(key_env)
    if not key:
        print(f"ERROR: missing {key_env}", file=sys.stderr); return 2
    max_tokens = env_int("OPENAI_COMPAT_MAX_TOKENS", 1400, 0)
    request_timeout = env_float("OPENAI_COMPAT_REQUEST_TIMEOUT", 60.0)
    max_retries = env_int("OPENAI_COMPAT_MAX_RETRIES", 3, 1)
    cwd = Path(normalize_cli_path(args.cwd)).resolve(); prompt = args.prompt if args.prompt is not None else sys.stdin.read()
    system_prompt = (
        "You are a read-only code-review agent. Use the provided structured tools to inspect the worktree. "
        "Never modify files. Do not stop after announcing what you will inspect and never print tool calls as text. "
        "Finish with a visible evidence-based verdict."
        if args.tool_mode == "readonly"
        else
        "You are a coding agent. Use tools when needed. For implementation tasks, edit files, call git_diff before final, and do not stop after only reading files. Final answer must be visible text. If a verification command fails because a local dependency or tool is missing, stop retrying that same command, call git_diff if not already done, and give a final answer that reports the blocker and the worktree changes."
    )
    active_tools = tools_for_mode(args.tool_mode)
    messages = [
        {"role":"system","content":system_prompt},
        {"role":"user","content":prompt},
    ]
    print(f"provider={args.provider} base_url={base_url} model={model} cwd={cwd}", file=sys.stderr)
    requested_reasoning = args.reasoning_effort or "none"
    print(f"chat_reasoning requested={requested_reasoning} policy={args.reasoning_policy}", file=sys.stderr)
    for turn in range(1, args.max_turns + 1):
        d = api_call(base_url, key, model, cfg.get("headers", {}), messages, max_tokens=max_tokens, request_timeout=request_timeout, max_retries=max_retries, reasoning_effort=args.reasoning_effort, reasoning_policy=args.reasoning_policy, tools=active_tools)
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
                out = tool_exec(cwd, fn, parse_args(raw), args.tool_mode)
                print(f"tool {fn} -> {len(out)} chars", file=sys.stderr)
                messages.append({"role":"tool", "tool_call_id": tc.get("id"), "name": fn, "content": out})
            continue
        if is_unevaluated_tool_text(content):
            print("unevaluated_tool_text detected; requesting structured continuation", file=sys.stderr)
            messages.append({"role":"assistant", "content":content})
            messages.append({"role":"user", "content":"Your previous response stopped at an unevaluated tool call or an intent-only transition. Use the provided structured tools now, then return a visible evidence-based verdict."})
            continue
        if content.strip():
            print(content); return 0
        messages.append({"role":"user","content":"Your previous assistant message was empty. Provide a visible final answer, or continue with tools if work remains."})
    print("ERROR: no visible final answer after max turns", file=sys.stderr); return 1

if __name__ == "__main__":
    raise SystemExit(main())
