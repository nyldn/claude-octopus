#!/usr/bin/env python3
"""Validate explicitly selected OpenAI-compatible presets without reading keys."""

import json
import math
import os
from pathlib import Path
import re
from urllib.parse import urlsplit


def load_custom_provider(name):
    """Return a validated preset, or fail before any credential or HTTP use."""
    if not isinstance(name, str) or not re.fullmatch(r"[a-z][a-z0-9-]{0,62}", name):
        raise ValueError("custom provider name must be a lowercase identifier")
    config_path = Path(os.environ.get(
        "OCTOPUS_PROVIDERS_CONFIG",
        str(Path.home() / ".claude-octopus/config/providers.json"),
    ))
    with config_path.open(encoding="utf-8") as stream:
        config = json.load(stream)
    if not isinstance(config, dict) or not isinstance(config.get("custom_providers"), dict):
        raise ValueError("providers.json must contain a custom_providers object")
    preset = config["custom_providers"].get(name)
    if not isinstance(preset, dict):
        raise ValueError("selected custom provider is not configured")
    if preset.get("type") != "openai-compatible":
        raise ValueError("custom provider type must be openai-compatible")
    _validate_endpoint(preset.get("base_url"))
    key_env = preset.get("api_key_env")
    if not isinstance(key_env, str) or not re.fullmatch(r"[A-Z][A-Z0-9_]*_KEY", key_env):
        raise ValueError("custom provider api_key_env must be an uppercase name ending in _KEY")
    if key_env == "KEENABLE_API_KEY":
        raise ValueError("the search credential cannot authenticate a model provider")
    _validate_models(preset.get("allowed_models"), preset.get("default_model"))
    if preset.get("council", False) is not False:
        raise ValueError("custom provider council registration is not supported yet")
    _validate_pricing(preset.get("pricing"))
    return dict(preset)


def _validate_endpoint(url):
    if not isinstance(url, str) or any(ord(c) <= 32 or ord(c) == 127 for c in url):
        raise ValueError("custom provider base_url must be an HTTPS URL")
    parsed = urlsplit(url)
    # Loopback HTTP is useful for explicitly configured local proxies. Reject
    # URL userinfo, query and fragments so credentials cannot change the host.
    if (not parsed.hostname or parsed.username is not None or parsed.password is not None
            or parsed.query or parsed.fragment
            or parsed.scheme not in ("http", "https")
            or (parsed.scheme == "http" and parsed.hostname not in ("localhost", "127.0.0.1", "::1"))):
        raise ValueError("custom provider URL requires HTTPS or loopback HTTP without userinfo, query or fragment")
    # Accessing port also rejects malformed/out-of-range port specifications.
    parsed.port


def _validate_models(models, default_model):
    if not isinstance(models, list) or not models:
        raise ValueError("custom provider allowed_models must be a nonempty list")
    if any(not isinstance(model, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/@+-]*", model) for model in models):
        raise ValueError("custom provider models must be single model identifiers")
    if len(models) != len(set(models)) or default_model not in models:
        raise ValueError("custom provider default_model must belong to its unique allowed_models")


def _validate_pricing(pricing):
    if pricing is not None:
        if not isinstance(pricing, dict) or set(pricing) != {"input", "output"}:
            raise ValueError("custom provider pricing requires input and output USD per million tokens")
        if any(isinstance(value, bool) or not isinstance(value, (int, float))
               or (isinstance(value, float) and not math.isfinite(value))
               or value < 0 for value in pricing.values()):
            raise ValueError("custom provider prices must be finite nonnegative numbers")


def custom_provider_environment(key_env):
    """Retain one selected credential and the bundled helper's runtime knobs."""
    names = {
        "PATH", "HOME", "TERM", "TMPDIR", "LANG", "LC_ALL", "PYTHONIOENCODING",
        "OPENAI_COMPAT_MAX_TOKENS", "OPENAI_COMPAT_REQUEST_TIMEOUT",
        "OPENAI_COMPAT_MAX_RETRIES", "OPENAI_COMPAT_COMMAND_TIMEOUT",
        "OPENAI_COMPAT_COMMAND_KILL_GRACE", "OPENAI_COMPAT_MAX_TURNS",
        "OPENAI_COMPAT_UNSAFE_COMMANDS", key_env,
    }
    return {name: value for name, value in os.environ.items() if name in names}
