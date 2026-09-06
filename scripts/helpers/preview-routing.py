#!/usr/bin/env python3
"""Offline, side-effect-free previews of Octopus routing decisions."""

from __future__ import annotations

import argparse
import importlib.util
import json
import math
import os
import re
import signal
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

MAX_INPUT = 1024 * 1024
TIMEOUT = 5.0
OUTPUT_LIMIT = 1024 * 1024
SAFE_BINARY_NAMES = {
    "agy",
    "claude",
    "codex",
    "copilot",
    "cursor-agent",
    "grok",
    "kimi",
    "ollama",
    "opencode",
    "qwen",
    "vibe",
}
READINESS = {"available", "degraded", "missing", "unknown"}
BILLING = {"subscription", "api", "local", "mixed", "unknown"}
SAFE_ROUTE_KEYS = {"provider", "model", "reasoning", "reasoningPolicy"}
SAFE_VALUE = re.compile(r"^[A-Za-z0-9._:/+ ()-]{0,256}$")

ROOT = Path(__file__).resolve().parents[2]
SUPERVISOR_PATH = ROOT / "shared" / "process_supervisor.py"
SUPERVISOR_SPEC = importlib.util.spec_from_file_location(
    "octopus_preview_process_supervisor", SUPERVISOR_PATH
)
if SUPERVISOR_SPEC is None or SUPERVISOR_SPEC.loader is None:
    raise RuntimeError("shared process supervisor is unavailable")
SUPERVISOR = importlib.util.module_from_spec(SUPERVISOR_SPEC)
SUPERVISOR_SPEC.loader.exec_module(SUPERVISOR)


class ProtocolError(ValueError):
    pass


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ProtocolError("duplicate JSON key")
        result[key] = value
    return result


def _constant(_value):
    raise ProtocolError("non-finite JSON number")


def _float(value):
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ProtocolError("non-finite JSON number")
    return parsed


def read_request(path):
    if path == "-":
        raw = sys.stdin.buffer.read(MAX_INPUT + 1)
    else:
        with open(path, "rb") as handle:
            raw = handle.read(MAX_INPUT + 1)
    if len(raw) > MAX_INPUT:
        raise ProtocolError("input exceeds 1 MiB")
    try:
        text = raw.decode("utf-8", errors="strict")
        value = json.loads(
            text,
            object_pairs_hook=_pairs,
            parse_constant=_constant,
            parse_float=_float,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ProtocolError, ValueError, RecursionError) as exc:
        raise ProtocolError("input is not one UTF-8 JSON value") from exc
    if not isinstance(value, dict):
        raise ProtocolError("top-level JSON value must be an object")
    return value


def exact_keys(value, required, optional=()):
    allowed = set(required) | set(optional)
    unknown = set(value) - allowed
    missing = set(required) - set(value)
    if unknown:
        raise ProtocolError("unknown field: " + sorted(unknown)[0])
    if missing:
        raise ProtocolError("missing field: " + sorted(missing)[0])


def safe_string(value, field, allow_empty=True):
    if not isinstance(value, str) or (not allow_empty and not value):
        raise ProtocolError(field + " must be a string")
    if not SAFE_VALUE.fullmatch(value):
        raise ProtocolError(field + " contains unsupported characters")
    return value


def bounded_utf8_string(value, field, maximum):
    if not isinstance(value, str):
        raise ProtocolError(field + " must be a string")
    try:
        encoded = value.encode("utf-8", errors="strict")
    except UnicodeEncodeError as exc:
        raise ProtocolError(field + " must be valid UTF-8") from exc
    if "\0" in value:
        raise ProtocolError(field + " contains a NUL byte")
    if len(encoded) > maximum:
        raise ProtocolError(field + " exceeds its size limit")
    return value


def validate_observations(value):
    if not isinstance(value, list) or len(value) > 64:
        raise ProtocolError("observations must be an array with at most 64 entries")
    result = []
    for item in value:
        if not isinstance(item, dict):
            raise ProtocolError("observation must be an object")
        exact_keys(
            item,
            {"provider", "readiness", "billing_mode", "checked_at", "source"},
        )
        provider = safe_string(item["provider"], "observation.provider", False)
        readiness = item["readiness"]
        billing = item["billing_mode"]
        if not isinstance(readiness, str) or readiness not in READINESS:
            raise ProtocolError("observation.readiness is invalid")
        if not isinstance(billing, str) or billing not in BILLING:
            raise ProtocolError("observation.billing_mode is invalid")
        result.append(
            {
                "provider": provider,
                "readiness": readiness,
                "billing_mode": billing,
                "checked_at": safe_string(item["checked_at"], "observation.checked_at"),
                "source": safe_string(item["source"], "observation.source"),
            }
        )
    return result


def env_key(value):
    return re.sub(r"^_+|_+$", "", re.sub(r"[^A-Z0-9_]+", "_", value.upper().replace("-", "_")))


def allowed_environment_keys(phase, operation):
    phase_key = env_key(phase)
    operation_key = env_key(operation)
    keys = {"OCTOPUS_LEGACY_ROLES", "OCTOPUS_REVIEWER_FLIP"}
    if phase_key:
        keys.add("OCTOPUS_" + phase_key + "_AGENT")
    if operation_key:
        keys.add("OCTOPUS_" + operation_key + "_AGENT")
    if phase_key and operation_key:
        keys.add("OCTOPUS_" + phase_key + "_" + operation_key + "_AGENT")
    return keys


def validate_route(route, field):
    if isinstance(route, str):
        return safe_string(route, field, False)
    if not isinstance(route, dict):
        raise ProtocolError(field + " must be a string or route object")
    unknown = set(route) - SAFE_ROUTE_KEYS
    if unknown:
        raise ProtocolError(field + " has unsupported route field")
    if "provider" not in route:
        raise ProtocolError(field + " route requires provider")
    return {key: safe_string(value, field + "." + key) for key, value in route.items()}


def validate_config(value):
    if not isinstance(value, dict):
        raise ProtocolError("config must be an object")
    exact_keys(value, {"routing"})
    routing = value["routing"]
    if not isinstance(routing, dict):
        raise ProtocolError("config.routing must be an object")
    exact_keys(routing, {"roles", "phases"})
    result = {"routing": {"roles": {}, "phases": {}}}
    for group in ("roles", "phases"):
        routes = routing[group]
        if not isinstance(routes, dict) or len(routes) > 128:
            raise ProtocolError("config.routing." + group + " must be a bounded object")
        for key, route in routes.items():
            safe_string(key, "route key", False)
            result["routing"][group][key] = validate_route(route, "route")
    return result


def validate_request(request):
    if type(request.get("schema_version")) is not int or request["schema_version"] != 1:
        raise ProtocolError("schema_version must be 1")
    kind = request.get("kind")
    if kind == "policy":
        required = {
            "schema_version", "kind", "prompt", "role", "phase", "policy",
            "user_pin", "project_pin", "requires_independent", "author_model",
            "candidate_verifier", "observations",
        }
        exact_keys(request, required)
        for field in ("role", "phase", "user_pin", "project_pin", "author_model", "candidate_verifier"):
            safe_string(request[field], field)
        request["prompt"] = bounded_utf8_string(request["prompt"], "prompt", 262144)
        if not isinstance(request["policy"], str) or request["policy"] not in {"off", "eval"}:
            raise ProtocolError("policy must be off or eval")
        if not isinstance(request["requires_independent"], bool):
            raise ProtocolError("requires_independent must be boolean")
    elif kind == "workflow-provider":
        required = {
            "schema_version", "kind", "phase", "operation", "role",
            "default_provider", "config", "environment", "available_binaries",
            "observations",
        }
        exact_keys(request, required, {"effective_preferences"})
        for field in ("phase", "operation", "role", "default_provider"):
            safe_string(request[field], field)
        request["config"] = validate_config(request["config"])
        environment = request["environment"]
        if not isinstance(environment, dict):
            raise ProtocolError("environment must be an object")
        allowed = allowed_environment_keys(request["phase"], request["operation"])
        if set(environment) - allowed:
            raise ProtocolError("environment contains an unsupported key")
        for key, value in environment.items():
            safe_string(value, "environment." + key)
        binaries = request["available_binaries"]
        if not isinstance(binaries, list) or len(binaries) > len(SAFE_BINARY_NAMES):
            raise ProtocolError("available_binaries must be a bounded array")
        if any(not isinstance(item, str) or item not in SAFE_BINARY_NAMES for item in binaries):
            raise ProtocolError("available_binaries contains an unsupported name")
        preferences = request.get("effective_preferences", {})
        if not isinstance(preferences, dict) or set(preferences) - {"reviewer_flip"}:
            raise ProtocolError("effective_preferences is invalid")
        if (
            "reviewer_flip" in preferences
            and (
                not isinstance(preferences["reviewer_flip"], str)
                or preferences["reviewer_flip"] not in {"claude", "codex"}
            )
        ):
            raise ProtocolError("effective_preferences.reviewer_flip is invalid")
    else:
        raise ProtocolError("kind must be policy or workflow-provider")
    request["observations"] = validate_observations(request["observations"])
    return request


def access_for(provider, observations):
    for item in observations:
        if item["provider"] == provider:
            result = dict(item)
            result["evidence"] = "caller-supplied"
            return result
    return {
        "readiness": "unknown",
        "billing_mode": "unknown",
        "checked_at": "",
        "source": "none",
        "evidence": "not-checked",
    }


def sanitized_environment(home, bin_dir, config_path, supplied):
    result = {
        "HOME": str(home),
        "PATH": str(bin_dir) + os.pathsep + os.defpath,
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "OCTOPUS_PROVIDERS_CONFIG": str(config_path),
    }
    result.update(supplied)
    return result


def run_child(argv, cwd, env):
    try:
        returncode, output = SUPERVISOR.run_bounded_process(
            argv,
            cwd,
            TIMEOUT,
            shell=False,
            output_limit=OUTPUT_LIMIT,
            env=env,
            kill_grace=0.5,
            strict_output=True,
        )
    except SUPERVISOR.OutputLimitExceeded as exc:
        raise RuntimeError("resolver output exceeded 1 MiB") from exc
    except UnicodeDecodeError as exc:
        raise RuntimeError("resolver output was not UTF-8") from exc
    if returncode != 0:
        raise RuntimeError("resolver exited nonzero")
    try:
        result = json.loads(output, object_pairs_hook=_pairs, parse_constant=_constant)
    except (json.JSONDecodeError, ProtocolError) as exc:
        raise RuntimeError("resolver did not emit exactly one JSON value") from exc
    if not isinstance(result, dict):
        raise RuntimeError("resolver result must be an object")
    return result


def make_markers(bin_dir, names):
    for name in names:
        path = bin_dir / name
        path.write_text("#!/bin/sh\nexit 97\n", encoding="utf-8")
        path.chmod(stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)


def preview_policy(request, temp_root):
    config_path = temp_root / "providers.json"
    config_path.write_text('{"routing":{"roles":{},"phases":{}}}\n', encoding="utf-8")
    env = sanitized_environment(temp_root / "home", temp_root / "bin", config_path, {})
    script = (
        'set -euo pipefail; root="$1"; shift; '
        'source "$root/scripts/lib/execution-profile.sh"; '
        'class="$(octo_route_task_class "$1" "$2" "$3")"; shift 3; '
        'decision="$(octo_route_decision "$class" "$1" "$2" "$3" "$4" "$5" "$6")"; '
        'author_family="$(octo_model_family "$5")"; '
        'model="$(jq -r .model <<<"$decision")"; '
        'model_family="$(octo_model_family "$model")"; '
        'jq -cn --argjson decision "$decision" '
        '--arg author_family "$author_family" --arg model_family "$model_family" '
        "'{decision:$decision,author_family:$author_family,model_family:$model_family}'"
    )
    resolver = run_child(
        [
            "/bin/bash", "-c", script, "bash", str(ROOT), request["prompt"],
            request["role"], request["phase"], request["policy"],
            request["user_pin"], request["project_pin"],
            "true" if request["requires_independent"] else "false",
            request["author_model"], request["candidate_verifier"],
        ],
        ROOT,
        env,
    )
    decision = resolver["decision"]
    limitations = [
        "model-entitlement-not-checked",
        "fallback-not-executed",
        "production-dispatch-not-verified",
    ]
    independence_qualified = decision.get("coverage") != "independent" or (
        resolver.get("author_family") != "unknown"
        and resolver.get("model_family") != "unknown"
    )
    if not independence_qualified:
        limitations.append("independence-not-established-author-family-unknown")
    return {
        "schema_version": 1,
        "status": "complete",
        "preview_kind": "policy",
        "guarantee": "evaluation-policy-only",
        "decision": decision,
        "independence_qualified": independence_qualified,
        "access": access_for(decision.get("provider", "unknown"), request["observations"]),
        "dispatch_admissibility": "not_checked",
        "production_dispatch_verified": False,
        "limitations": limitations,
    }


def preview_workflow(request, temp_root):
    home = temp_root / "home"
    bin_dir = temp_root / "bin"
    config_path = temp_root / "providers.json"
    home.mkdir(mode=0o700, exist_ok=True)
    bin_dir.mkdir(mode=0o700, exist_ok=True)
    make_markers(bin_dir, request["available_binaries"])
    config_path.write_text(json.dumps(request["config"]), encoding="utf-8")
    supplied = dict(request["environment"])
    preferences = request.get("effective_preferences", {})
    preference_source = "not-supplied"
    if "reviewer_flip" in preferences and "OCTOPUS_REVIEWER_FLIP" not in supplied:
        supplied["OCTOPUS_REVIEWER_FLIP"] = preferences["reviewer_flip"]
        preference_source = "caller-supplied-effective-choice"
    elif "OCTOPUS_REVIEWER_FLIP" in supplied:
        preference_source = "request-environment-override"
    env = sanitized_environment(home, bin_dir, config_path, supplied)
    script = (
        'set -euo pipefail; export PLUGIN_DIR="$1"; shift; '
        'source "$PLUGIN_DIR/scripts/lib/features.sh"; '
        'source "$PLUGIN_DIR/scripts/lib/execution-profile.sh"; '
        'source "$PLUGIN_DIR/scripts/lib/agent-utils.sh"; '
        'provider="$(octopus_execution_profile_provider "$1" "$2" "$3" "$4")"; '
        'model="$(_octopus_profile_field "$1" "$3" model 2>/dev/null || true)"; '
        'jq -cn --arg provider "$provider" --arg model "$model" '
        "'{provider:$provider,configured_model:(if $model == \"\" then null else $model end)}'"
    )
    decision = run_child(
        [
            "/bin/bash", "-c", script, "bash", str(ROOT), request["phase"],
            request["operation"], request["role"], request["default_provider"],
        ],
        ROOT,
        env,
    )
    limitations = [
        "model-resolution-not-run",
        "authentication-not-checked",
        "model-entitlement-not-checked",
        "quota-not-checked",
        "fallback-not-executed",
        "dispatch-gates-not-run",
    ]
    if preference_source == "not-supplied" and request["role"] in {"reviewer", "code-reviewer"}:
        limitations.append("persisted-reviewer-choice-not-supplied")
    configured_model = decision.get("configured_model")
    if configured_model in {"gpt-6-astra", "claude-fable-5-1"}:
        limitations.extend(["explicit-only-policy-not-checked", "security-admission-not-checked"])
    provider = decision.get("provider", "unknown")
    return {
        "schema_version": 1,
        "status": "complete",
        "preview_kind": "workflow-provider",
        "guarantee": "provider-selection-before-dispatch-gates",
        "decision": {
            "provider": provider,
            "configured_model": configured_model,
            "effective_model": None,
            "reviewer_choice_source": preference_source,
        },
        "access": access_for(provider, request["observations"]),
        "dispatch_admissibility": "not_checked",
        "production_dispatch_verified": False,
        "limitations": limitations,
    }


def interrupted(_signum, _frame):
    raise KeyboardInterrupt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, interrupted)
    try:
        request = validate_request(read_request(args.input))
        with tempfile.TemporaryDirectory(prefix="octopus-routing-preview-") as directory:
            temp_root = Path(directory)
            (temp_root / "home").mkdir(mode=0o700, exist_ok=True)
            (temp_root / "bin").mkdir(mode=0o700, exist_ok=True)
            if request["kind"] == "policy":
                result = preview_policy(request, temp_root)
            else:
                result = preview_workflow(request, temp_root)
        json.dump(result, sys.stdout, separators=(",", ":"), allow_nan=False)
        sys.stdout.write("\n")
        return 0
    except ProtocolError as exc:
        print("preview-routing: invalid input: " + str(exc), file=sys.stderr)
        return 2
    except FileNotFoundError:
        print("preview-routing: required local dependency is unavailable", file=sys.stderr)
        return 3
    except subprocess.TimeoutExpired:
        print("preview-routing: resolver timed out", file=sys.stderr)
        return 5
    except KeyboardInterrupt:
        print("preview-routing: interrupted", file=sys.stderr)
        return 130
    except Exception as exc:
        print("preview-routing: resolver failed: " + type(exc).__name__, file=sys.stderr)
        return 4


if __name__ == "__main__":
    raise SystemExit(main())
