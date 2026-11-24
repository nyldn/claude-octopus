#!/usr/bin/env python3
"""Turn a council seat's machine-readable CLI output back into its answer text
and append the seat's token usage and cost to a JSONL ledger.

Usage: seat-usage.py KIND OUTPUT_FILE LEDGER LABEL MODEL INPUT_PRICE OUTPUT_PRICE

KIND is "claude" (`claude --print --output-format json`) or "codex"
(`codex exec --json`). OUTPUT_FILE is rewritten in place with the answer text,
or left untouched when it does not parse, so a seat never loses its answer to
accounting. LABEL is "phase|persona". Prices are USD per million tokens and
price codex usage; claude reports its own total_cost_usd.

Input tokens exclude cache reads and writes. Reasoning tokens are part of
output tokens.
"""
import json
import os
import sys
import time

# OpenAI bills cached input at a tenth of the input tariff for the GPT-5 family.
CODEX_CACHED_INPUT_RATIO = float(os.environ.get("OCTOPUS_CODEX_CACHED_INPUT_RATIO", "0.1"))


def num(value):
    return value if isinstance(value, int) and value >= 0 else 0


def parse_claude(raw):
    doc = json.loads(raw)
    if not isinstance(doc, dict) or doc.get("type") != "result":
        raise ValueError("not a claude result object")
    text = doc.get("result")
    is_error = doc.get("is_error") is True
    if not isinstance(text, str) or (is_error and not text):
        if not is_error:
            raise ValueError("claude result has no text")
        errors = doc.get("errors")
        text = "\n".join(error for error in errors if isinstance(error, str)) if isinstance(errors, list) else ""
        if not text:
            subtype = doc.get("subtype")
            text = "Claude returned an error without a message"
            if isinstance(subtype, str) and subtype:
                text += f" ({subtype})"
            text += "."
    usage = doc.get("usage") if isinstance(doc.get("usage"), dict) else {}
    models = doc.get("modelUsage") if isinstance(doc.get("modelUsage"), dict) else {}
    if models:
        # modelUsage covers every model the session used (including subagents);
        # top-level usage can omit them.
        rows = [m for m in models.values() if isinstance(m, dict)]
        tokens = {
            "input_tokens": sum(num(m.get("inputTokens")) for m in rows),
            "cache_read_tokens": sum(num(m.get("cacheReadInputTokens")) for m in rows),
            "cache_write_tokens": sum(num(m.get("cacheCreationInputTokens")) for m in rows),
            "output_tokens": sum(num(m.get("outputTokens")) for m in rows),
        }
    else:
        tokens = {
            "input_tokens": num(usage.get("input_tokens")),
            "cache_read_tokens": num(usage.get("cache_read_input_tokens")),
            "cache_write_tokens": num(usage.get("cache_creation_input_tokens")),
            "output_tokens": num(usage.get("output_tokens")),
        }
    cost = doc.get("total_cost_usd")
    tokens["cost_usd"] = round(float(cost), 6) if isinstance(cost, (int, float)) else None
    tokens["cost_source"] = "claude-cli" if tokens["cost_usd"] is not None else None
    tokens["reported_model"] = ",".join(sorted(models)) or None
    return text, tokens


def parse_codex(raw, input_price, output_price):
    messages, errors = [], []
    failed_detail = None
    tokens = {"input_tokens": 0, "cache_read_tokens": 0, "cache_write_tokens": 0,
              "output_tokens": 0, "reasoning_tokens": 0}
    turns = 0
    for line in raw.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            event = json.loads(line)
        except ValueError:
            continue
        kind = event.get("type")
        if kind == "item.completed":
            item = event.get("item") or {}
            if item.get("type") == "agent_message" and isinstance(item.get("text"), str):
                messages.append(item["text"])
        elif kind == "turn.completed":
            failed_detail = None
            usage = event.get("usage") or {}
            turns += 1
            cached = num(usage.get("cached_input_tokens"))
            # Codex input_tokens includes the cached part.
            tokens["input_tokens"] += max(num(usage.get("input_tokens")) - cached, 0)
            tokens["cache_read_tokens"] += cached
            tokens["cache_write_tokens"] += num(usage.get("cache_write_input_tokens"))
            tokens["output_tokens"] += num(usage.get("output_tokens"))
            tokens["reasoning_tokens"] += num(usage.get("reasoning_output_tokens"))
        elif kind in ("error", "turn.failed"):
            detail = event.get("message") or (event.get("error") or {}).get("message")
            if isinstance(detail, str):
                errors.append(detail)
            if kind == "turn.failed":
                failed_detail = detail if isinstance(detail, str) else ""
    if not messages and not errors and not turns and failed_detail is None:
        raise ValueError("no codex events")
    if failed_detail is not None:
        text = failed_detail or "\n".join(errors) or "Codex turn failed without an error message."
    else:
        text = messages[-1] if messages else "\n".join(errors)
    if turns and input_price is not None and output_price is not None:
        # Reasoning tokens are billed as output and already counted in output_tokens.
        cost = (tokens["input_tokens"] * input_price
                + tokens["cache_read_tokens"] * input_price * CODEX_CACHED_INPUT_RATIO
                + tokens["cache_write_tokens"] * input_price
                + tokens["output_tokens"] * output_price) / 1_000_000
        tokens["cost_usd"] = round(cost, 6)
        tokens["cost_source"] = "estimated-list-price"
    else:
        tokens["cost_usd"] = None
        tokens["cost_source"] = None
    if not turns:
        tokens = {k: None for k in tokens}
    return text, tokens


def price(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def main(argv):
    if len(argv) != 8:
        print(__doc__, file=sys.stderr)
        return 2
    kind, output_file, ledger, label, model, input_price, output_price = argv[1:]
    try:
        with open(output_file, encoding="utf-8", errors="replace") as handle:
            raw = handle.read()
    except OSError:
        return 0
    try:
        if kind == "claude":
            text, tokens = parse_claude(raw)
        elif kind == "codex":
            text, tokens = parse_codex(raw, price(input_price), price(output_price))
        else:
            return 2
    except (ValueError, TypeError, AttributeError):
        return 1
    tmp = output_file + ".usage-tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        handle.write(text if text.endswith("\n") or not text else text + "\n")
    os.replace(tmp, output_file)
    phase, _, persona = label.partition("|")
    record = {"phase": phase or None, "persona": persona or None, "provider": kind,
              "model": model or None, "recorded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    record.update(tokens)
    if ledger:
        os.makedirs(os.path.dirname(ledger) or ".", exist_ok=True)
        # One short line per write; O_APPEND keeps parallel seats' lines whole.
        with open(ledger, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
