#!/usr/bin/env python3
"""One text-only Claude Messages request using an explicit API key."""
import argparse
import json
import math
import os
import sys
import urllib.error
import urllib.request

ENDPOINT = "https://api.anthropic.com/v1/messages"
MODELS = {"claude-sonnet-5-5", "claude-opus-5-5"}
EFFORTS = {"auto", "low", "medium", "high", "xhigh", "max"}
MAX_RESPONSE_BYTES = 16 * 1024 * 1024


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def urlopen(request, timeout):
    return urllib.request.build_opener(NoRedirect()).open(request, timeout=timeout)


def thinking_config(model, effort, thinking):
    if model not in MODELS:
        raise ValueError("anthropic-api supports claude-sonnet-5-5 and claude-opus-5-5; use the CLI seat for other models")
    if effort not in EFFORTS:
        raise ValueError("effort must be auto, low, medium, high, xhigh, or max")
    if thinking not in {"auto", "adaptive", "between_tools"}:
        raise ValueError("thinking must be auto, adaptive, or between_tools")
    if thinking == "auto":
        thinking = "between_tools" if model == "claude-sonnet-5-5" and effort in {"low", "medium", "high"} else "adaptive"
    if thinking == "between_tools" and (model != "claude-sonnet-5-5" or effort not in {"low", "medium", "high"}):
        raise ValueError("between_tools requires Sonnet 5.5 at low, medium, or high effort")
    return {"type": thinking}


def execute(prompt, *, model="claude-sonnet-5-5", effort="high", thinking="auto"):
    config = thinking_config(model, effort, thinking)
    key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not key.strip():
        raise ValueError("ANTHROPIC_API_KEY is required; CLI and OAuth credentials are not used")
    if not prompt.strip():
        raise ValueError("a nonempty prompt is required on stdin")
    try:
        timeout = float(os.environ.get("OCTOPUS_ANTHROPIC_API_TIMEOUT", "120"))
        max_tokens = int(os.environ.get("OCTOPUS_ANTHROPIC_API_MAX_TOKENS", "8192"))
    except ValueError:
        raise ValueError("timeout and max tokens must be numeric") from None
    if not math.isfinite(timeout) or not 0 < timeout <= 600:
        raise ValueError("timeout must be greater than zero and at most 600 seconds")
    if not 1 <= max_tokens <= 128000:
        raise ValueError("max tokens must be between 1 and 128000")
    payload = {"model": model, "max_tokens": max_tokens, "thinking": config,
               "messages": [{"role": "user", "content": prompt}]}
    if effort != "auto":
        payload["output_config"] = {"effort": effort}
    request = urllib.request.Request(ENDPOINT, data=json.dumps(payload).encode("utf-8"),
                                     headers={"x-api-key": key, "anthropic-version": "2023-06-01",
                                              "Content-Type": "application/json"}, method="POST")
    try:
        with urlopen(request, timeout=timeout) as response:
            raw = response.read(MAX_RESPONSE_BYTES + 1)
    except urllib.error.HTTPError as error:
        code = error.code
        error.close()
        raise RuntimeError(f"Anthropic Messages returned HTTP {code}") from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise RuntimeError("Anthropic Messages connection failed or timed out") from None
    if len(raw) > MAX_RESPONSE_BYTES:
        raise RuntimeError("Anthropic Messages response exceeded the size limit")
    try:
        result = json.loads(raw)
    except (ValueError, UnicodeDecodeError):
        raise RuntimeError("Anthropic Messages returned invalid JSON") from None
    if not isinstance(result, dict) or result.get("stop_reason") != "end_turn":
        raise RuntimeError("Anthropic Messages did not finish a text answer; refusal, truncation, and tool calls are not retried")
    content = result.get("content")
    if not isinstance(content, list) or any(not isinstance(block, dict) for block in content):
        raise RuntimeError("Anthropic Messages returned invalid content blocks")
    if any(block.get("type") == "tool_use" for block in content):
        raise RuntimeError("anthropic-api has no tool execution support")
    text = "".join(block["text"] for block in content if block.get("type") == "text" and isinstance(block.get("text"), str))
    if not text.strip():
        raise RuntimeError("Anthropic Messages returned no text answer")
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default="claude-sonnet-5-5")
    parser.add_argument("--effort", default="high")
    parser.add_argument("--thinking", default=os.environ.get("OCTOPUS_ANTHROPIC_API_THINKING", "auto"))
    args = parser.parse_args()
    try:
        output = execute(sys.stdin.read(), model=args.model, effort=args.effort, thinking=args.thinking)
    except (ValueError, RuntimeError) as error:
        print(f"anthropic-api: {error}", file=sys.stderr)
        return 1
    print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
