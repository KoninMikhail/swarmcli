#!/usr/bin/env python3
"""
SwarmCLI Configuration Manager

Manages .swarmcli.yaml — unified configuration and state file.
Supports: read, write, get, set, list.

Usage:
    python3 config_manager.py get <file> <key>
    python3 config_manager.py set <file> <key> <value>
    python3 config_manager.py list <file>
    python3 config_manager.py export_env <file>
    python3 config_manager.py init <file>
    python3 config_manager.py repair <file>
"""

import sys

if sys.version_info < (3, 6):
    sys.exit("SwarmCLI requires Python 3.6+. Current: {}.{}".format(*sys.version_info[:2]))

import os
import tempfile
from pathlib import Path
from typing import Any, Optional

try:
    from ruamel.yaml import YAML as _RuamelYAML
    _HAS_RUAMEL = True
except ImportError:
    _HAS_RUAMEL = False

import yaml


DEFAULTS = {
    "config_version": 1,
    "state": {
        "default_profile": None,
    },
    "paths": {
        "secrets": ".secrets",
        "locks": ".locks",
    },
    "operations": {
        "log_format": "text",
        "timeout": 900,
        "lock_timeout": 3600,
    },
    "git": {
        "auth": {
            "http_user": None,
            "http_token": None,
            "http_password": None,
        },
    },
}

# YAML key -> environment variable mapping
# Note: default_branch, keep_images_count, services_ready_timeout belong to profile config.yaml
ENV_MAP = {
    "paths.secrets":                      "SECRETS_ROOT",
    "paths.locks":                        "LOCKS_DIR",
    "operations.log_format":              "LOG_FORMAT",
    "operations.timeout":                 "TIMEOUT_SECONDS",
    "operations.lock_timeout":            "LOCK_TIMEOUT",
    "git.auth.http_user":                 "GIT_HTTP_USER",
    "git.auth.http_token":                "GIT_HTTP_TOKEN",
    "git.auth.http_password":             "GIT_HTTP_PASSWORD",
    "state.default_profile":              "SWARMCLI_DEFAULT_PROFILE",
}

# Sensitive keys — masked in `list` output
SENSITIVE_KEYS = {"git.auth.http_token", "git.auth.http_password"}


def load_config(file_path: str) -> dict:
    """Load YAML config file, return empty dict if missing or corrupt."""
    path = Path(file_path)
    if not path.exists():
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    except yaml.YAMLError as e:
        sys.stderr.write(
            f"Warning: invalid YAML in {file_path}: {e}\n"
            f"Using default configuration. Run 'swarmcli config repair' to fix.\n"
        )
        return {}


def _load_ruamel(file_path: str):
    """Load YAML via ruamel.yaml preserving comments. Returns (data, yaml_instance)."""
    ry = _RuamelYAML()
    ry.preserve_quotes = True
    path = Path(file_path)
    if path.exists():
        with open(path, "r", encoding="utf-8") as f:
            data = ry.load(f)
        return (data if isinstance(data, dict) else {}), ry
    return {}, ry


def save_config(file_path: str, data: dict) -> None:
    """Write config dict to YAML file atomically (temp file + rename).

    Uses ruamel.yaml when available to preserve user comments.
    """
    path = Path(file_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(
        dir=str(path.parent), suffix=".tmp", prefix=".swarmcli_"
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            if _HAS_RUAMEL:
                existing_data, ry = _load_ruamel(file_path)
                _deep_update_ruamel(existing_data, data)
                ry.dump(existing_data, f)
            else:
                f.write("# SwarmCLI configuration\n")
                f.write("# Managed by: swarmcli config set <key> <value>\n")
                f.write("# Docs: swarmcli config --help\n\n")
                yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, str(path))
    except BaseException:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def _deep_update_ruamel(base: dict, overlay: dict) -> None:
    """Update base dict in-place with overlay values, preserving ruamel metadata."""
    for k, v in overlay.items():
        if k in base and isinstance(base[k], dict) and isinstance(v, dict):
            _deep_update_ruamel(base[k], v)
        else:
            base[k] = v


def get_nested(data: dict, key_path: str) -> Optional[Any]:
    """Get value by dot-notation path."""
    keys = key_path.split(".")
    current = data
    for k in keys:
        if isinstance(current, dict) and k in current:
            current = current[k]
        else:
            return None
    return current


def set_nested(data: dict, key_path: str, value: Any) -> dict:
    """Set value by dot-notation path, creating intermediate dicts."""
    keys = key_path.split(".")
    current = data
    for k in keys[:-1]:
        if k not in current or not isinstance(current.get(k), dict):
            current[k] = {}
        current = current[k]
    current[keys[-1]] = value
    return data


def coerce_value(raw: str) -> Any:
    """Convert string value to appropriate Python type."""
    if raw.lower() in ("true", "yes"):
        return True
    if raw.lower() in ("false", "no"):
        return False
    if raw.lower() in ("null", "none", "~"):
        return None
    try:
        return int(raw)
    except ValueError:
        pass
    try:
        return float(raw)
    except ValueError:
        pass
    return raw


def mask_value(value: Any) -> str:
    """Mask sensitive values for display."""
    s = str(value)
    if len(s) <= 4:
        return "****"
    return "****" + s[-4:]


def merge_defaults(data: dict) -> dict:
    """Return data with defaults filled in for missing keys."""
    def _merge(base: dict, overlay: dict) -> dict:
        result = dict(base)
        for k, v in overlay.items():
            if k in result and isinstance(result[k], dict) and isinstance(v, dict):
                result[k] = _merge(result[k], v)
            elif k not in result:
                result[k] = v
        return result
    return _merge(data, DEFAULTS)


# =========================================================================
# Commands
# =========================================================================

def cmd_get(file_path: str, key: str) -> None:
    data = merge_defaults(load_config(file_path))
    value = get_nested(data, key)
    if value is None:
        sys.exit(1)
    if isinstance(value, dict):
        print(yaml.dump(value, default_flow_style=False).rstrip())
    elif isinstance(value, bool):
        print("true" if value else "false")
    else:
        print(value)


def _get_valid_keys(d: dict, prefix: str = "") -> set:
    """Build set of valid dot-notation keys from DEFAULTS structure."""
    keys: set = set()
    for k, v in d.items():
        full = f"{prefix}.{k}" if prefix else k
        if isinstance(v, dict):
            keys.update(_get_valid_keys(v, full))
        else:
            keys.add(full)
    return keys


VALID_SET_KEYS = _get_valid_keys(DEFAULTS)


def cmd_set(file_path: str, key: str, raw_value: str) -> None:
    if key not in VALID_SET_KEYS:
        sys.stderr.write(f"Error: unknown key '{key}'\n")
        sys.stderr.write("Valid keys:\n")
        for k in sorted(VALID_SET_KEYS):
            sys.stderr.write(f"  {k}\n")
        sys.exit(1)
    data = load_config(file_path)
    value = coerce_value(raw_value)
    set_nested(data, key, value)
    save_config(file_path, data)


def cmd_list(file_path: str) -> None:
    data = merge_defaults(load_config(file_path))

    def _flatten(d: dict, prefix: str = "") -> list:
        items = []
        for k, v in d.items():
            full = f"{prefix}.{k}" if prefix else k
            if isinstance(v, dict):
                items.extend(_flatten(v, full))
            else:
                items.append((full, v))
        return items

    for key, value in _flatten(data):
        if value is None:
            display = "(not set)"
        elif key in SENSITIVE_KEYS and value:
            display = mask_value(value)
        else:
            display = str(value)
        print(f"{key} = {display}")


def cmd_export_env(file_path: str) -> None:
    """Output KEY=VALUE lines for bash eval, resolving relative paths."""
    data = merge_defaults(load_config(file_path))
    platform_root = os.environ.get("PLATFORM_ROOT", "")

    for yaml_key, env_var in ENV_MAP.items():
        value = get_nested(data, yaml_key)
        if value is None:
            continue

        str_value = str(value)

        # Resolve relative paths for path-type keys
        if yaml_key.startswith("paths.") and not os.path.isabs(str_value):
            resolved = os.path.abspath(os.path.join(platform_root, str_value))
            if platform_root and not resolved.startswith(os.path.abspath(platform_root)):
                sys.stderr.write(
                    f"Warning: path '{str_value}' for {yaml_key} escapes platform root, skipping\n"
                )
                continue
            str_value = resolved

        print(f"{env_var}={str_value}")


def cmd_init(file_path: str) -> None:
    """Create config with defaults (non-destructive — won't overwrite)."""
    if Path(file_path).exists():
        sys.stderr.write(f"{file_path} already exists. Use 'config set' to modify.\n")
        sys.exit(1)
    save_config(file_path, {"config_version": 1})
    print(f"Created {file_path}")


def cmd_repair(file_path: str) -> None:
    """Repair a corrupt config file by re-creating it with defaults.

    If the existing file is valid YAML, preserves its data.
    If corrupt, backs up the broken file and creates a fresh one.
    """
    path = Path(file_path)
    data: dict = {}

    if path.exists():
        try:
            with open(path, "r", encoding="utf-8") as f:
                loaded = yaml.safe_load(f)
            if isinstance(loaded, dict):
                data = loaded
                print(f"Config is valid YAML. Re-writing with defaults merged.")
            else:
                raise yaml.YAMLError("root is not a mapping")
        except yaml.YAMLError:
            backup = str(path) + ".bak"
            try:
                import shutil
                shutil.copy2(str(path), backup)
                print(f"Corrupt config backed up to {backup}")
            except OSError as e:
                sys.stderr.write(f"Warning: could not create backup: {e}\n")
            data = {}

    data = merge_defaults(data)
    data.setdefault("config_version", 1)
    save_config(file_path, data)
    print(f"Repaired {file_path}")


# =========================================================================
# Main
# =========================================================================

def main():
    if len(sys.argv) < 3:
        sys.stderr.write(
            "Usage: config_manager.py <command> <file> [key] [value]\n"
            "Commands: get, set, list, export_env, init, repair\n"
        )
        sys.exit(1)

    command = sys.argv[1]
    file_path = sys.argv[2]

    if command == "get":
        if len(sys.argv) < 4:
            sys.stderr.write("Usage: config_manager.py get <file> <key>\n")
            sys.exit(1)
        cmd_get(file_path, sys.argv[3])

    elif command == "set":
        if len(sys.argv) < 5:
            sys.stderr.write("Usage: config_manager.py set <file> <key> <value>\n")
            sys.exit(1)
        cmd_set(file_path, sys.argv[3], sys.argv[4])

    elif command == "list":
        cmd_list(file_path)

    elif command == "export_env":
        cmd_export_env(file_path)

    elif command == "init":
        cmd_init(file_path)

    elif command == "repair":
        cmd_repair(file_path)

    else:
        sys.stderr.write(f"Unknown command: {command}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
