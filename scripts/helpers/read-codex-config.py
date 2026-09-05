#!/usr/bin/env python3
"""Print the credential environment variable for Codex's effective provider."""

import ast
import os
import re
import sys
from pathlib import Path


ENV_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
BARE_KEY = re.compile(r"^[A-Za-z0-9_-]+$")


class ConfigError(ValueError):
    pass


def _strip_comment(line: str) -> str:
    quote = None
    escaped = False
    result = []
    for char in line:
        if escaped:
            result.append(char)
            escaped = False
            continue
        if char == "\\" and quote == '"':
            result.append(char)
            escaped = True
            continue
        if char in ("'", '"'):
            if quote is None:
                quote = char
            elif quote == char:
                quote = None
            result.append(char)
            continue
        if char == "#" and quote is None:
            break
        result.append(char)
    if quote is not None:
        raise ConfigError("unterminated TOML string")
    return "".join(result).strip()


def _parse_string(value: str) -> str:
    value = value.strip()
    if len(value) < 2 or value[0] not in ("'", '"') or value[-1] != value[0]:
        raise ConfigError("relevant Codex values must be quoted strings")
    if value[0] == "'":
        return value[1:-1]  # TOML literal strings do not interpret backslashes.
    try:
        parsed = ast.literal_eval(value)
    except (SyntaxError, ValueError) as exc:
        raise ConfigError("invalid TOML string") from exc
    if not isinstance(parsed, str):
        raise ConfigError("expected TOML string")
    return parsed


def _key_path(value: str) -> tuple:
    """Split dotted keys without splitting dots inside quoted table names."""
    parts = []
    token = []
    quote = None
    escaped = False
    for char in value:
        if escaped:
            token.append(char)
            escaped = False
        elif char == "\\" and quote == '"':
            token.append(char)
            escaped = True
        elif quote:
            token.append(char)
            if char == quote:
                quote = None
        elif char in ("'", '"'):
            quote = char
            token.append(char)
        elif char == ".":
            parts.append("".join(token).strip())
            token = []
        else:
            token.append(char)
    if quote:
        raise ConfigError("unterminated TOML key")
    parts.append("".join(token).strip())
    result = []
    for part in parts:
        if BARE_KEY.fullmatch(part):
            result.append(part)
        elif part.startswith(("'", '"')):
            result.append(_parse_string(part))
        else:
            raise ConfigError("invalid TOML key")
    return tuple(result)


def _fallback_load(path: Path) -> dict:
    """Parse only the Codex fields needed for credential selection.

    This deliberately rejects TOML features outside the small supported subset
    instead of guessing when Python predates tomllib.
    """
    data = {}
    section = ()
    seen = set()
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = _strip_comment(raw_line)
        if not line:
            continue
        if line.startswith("["):
            if not line.endswith("]") or line.startswith("[["):
                raise ConfigError("unsupported TOML table")
            section = _key_path(line[1:-1])
            continue
        if "=" not in line:
            raise ConfigError("invalid TOML assignment")
        key, raw_value = (part.strip() for part in line.split("=", 1))
        if not BARE_KEY.fullmatch(key):
            raise ConfigError("unsupported TOML key")
        relevant = (
            (not section and key in {"profile", "model_provider"})
            or (len(section) == 2 and section[0] == "profiles" and key == "model_provider")
            or (len(section) == 2 and section[0] == "model_providers" and key == "env_key")
        )
        if not relevant:
            continue
        location = section + (key,)
        if location in seen:
            raise ConfigError("duplicate relevant TOML key")
        seen.add(location)
        target = data
        for name in section:
            child = target.setdefault(name, {})
            if not isinstance(child, dict):
                raise ConfigError("conflicting TOML table")
            target = child
        target[key] = _parse_string(raw_value)
    return data


def load_config(path: Path) -> dict:
    if os.environ.get("OCTOPUS_FORCE_CODEX_TOML_FALLBACK") != "1":
        try:
            import tomllib
        except ImportError:
            pass
        else:
            with path.open("rb") as handle:
                loaded = tomllib.load(handle)
            if not isinstance(loaded, dict):
                raise ConfigError("Codex config root must be a table")
            return loaded
    return _fallback_load(path)


def effective_env_key(config: dict) -> str:
    profile_name = config.get("profile")
    provider_name = config.get("model_provider", "openai")
    if profile_name is not None:
        if not isinstance(profile_name, str):
            raise ConfigError("active profile name must be a string")
        profiles = config.get("profiles", {})
        if not isinstance(profiles, dict):
            raise ConfigError("profiles must be a table")
        profile = profiles.get(profile_name)
        if not isinstance(profile, dict):
            raise ConfigError("active profile is missing")
        provider_name = profile.get("model_provider", provider_name)
    if not isinstance(provider_name, str) or not provider_name:
        raise ConfigError("effective model provider is invalid")

    providers = config.get("model_providers", {})
    if not isinstance(providers, dict):
        raise ConfigError("model_providers must be a table")
    provider = providers.get(provider_name)
    if provider is None:
        return "OPENAI_API_KEY" if provider_name == "openai" else ""
    if not isinstance(provider, dict):
        raise ConfigError("effective provider must be a table")
    env_key = provider.get("env_key")
    if env_key is None:
        return "OPENAI_API_KEY" if provider_name == "openai" else ""
    if not isinstance(env_key, str) or not ENV_NAME.fullmatch(env_key):
        raise ConfigError("effective provider env_key is invalid")
    return env_key


def main(argv) -> int:
    if len(argv) != 2:
        return 2
    try:
        config = load_config(Path(argv[1]))
        print(effective_env_key(config))
    except (ConfigError, OSError, UnicodeError, ValueError):
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
