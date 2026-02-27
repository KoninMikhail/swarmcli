#!/usr/bin/env bash
# SwarmCLI configuration loader
# Loads .swarmcli.yaml and exports values as environment variables.

# Path to config_manager.py
_get_config_manager() {
  echo "$LIB_DIR/config/config_manager.py"
}

# Run config_manager.py
_run_config_manager() {
  local python_cmd
  python_cmd="$(get_python_cmd)"
  [ -n "$python_cmd" ] || fail "Python not found (required for config management)"
  "$python_cmd" "$(_get_config_manager)" "$@"
}

# Get config file path
get_config_file() {
  echo "$PLATFORM_ROOT/.swarmcli.yaml"
}

# Load configuration into environment variables
load_swarmcli_config() {
  local config_file
  config_file="$(get_config_file)"

  # If no config file, use defaults
  if [ ! -f "$config_file" ]; then
    return 0
  fi

  # Export env vars from YAML config
  local line key value
  while IFS='=' read -r key value; do
    [ -n "$key" ] || continue

    # Special handling: relative path resolution for paths
    if [[ "$value" != /* ]] && { [ "$key" = "SECRETS_ROOT" ] || [ "$key" = "LOCKS_DIR" ]; }; then
      value="$PLATFORM_ROOT/$value"
    fi

    export "$key=$value"
  done < <(_run_config_manager export_env "$config_file" 2>/dev/null)
}

# Get a single config value by YAML key path
# Usage: get_swarmcli_config <key> [default]
get_swarmcli_config() {
  local key="$1"
  local default="${2:-}"
  local config_file
  config_file="$(get_config_file)"

  if [ ! -f "$config_file" ]; then
    echo "$default"
    return 0
  fi

  local value
  value=$(_run_config_manager get "$config_file" "$key" 2>/dev/null)
  if [ $? -eq 0 ] && [ -n "$value" ]; then
    echo "$value"
  else
    echo "$default"
  fi
}

# Set a config value by YAML key path
# Usage: set_swarmcli_config <key> <value>
set_swarmcli_config() {
  local key="$1"
  local value="$2"
  local config_file
  config_file="$(get_config_file)"

  _run_config_manager set "$config_file" "$key" "$value"
}
