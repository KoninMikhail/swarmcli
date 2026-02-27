#!/usr/bin/env bash
# Plugin system for extensibility

PLUGINS_DIR="${PLUGINS_DIR:-$PLATFORM_ROOT/plugins}"

# Discover available plugins
# Usage: discover_plugins
# Output: list of plugin names (without 'swarm-' prefix)
discover_plugins() {
  [ -d "$PLUGINS_DIR" ] || return 0
  
  for plugin_file in "$PLUGINS_DIR"/swarm-*; do
    [ -f "$plugin_file" ] && [ -x "$plugin_file" ] || continue
    
    local plugin_name
    plugin_name=$(basename "$plugin_file")
    plugin_name=${plugin_name#swarm-}
    
    echo "$plugin_name"
  done
}

# Validate plugin name (alphanumeric, hyphens, underscores only)
_validate_plugin_name() {
  local name="$1"
  [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || fail "invalid plugin name: $name"
}

# Check if plugin exists
# Usage: plugin_exists <name>
plugin_exists() {
  local name="$1"
  _validate_plugin_name "$name"
  [ -x "$PLUGINS_DIR/swarm-$name" ]
}

# Execute plugin
# Usage: execute_plugin <name> [args...]
execute_plugin() {
  local name="$1"
  shift
  
  _validate_plugin_name "$name"
  
  local plugin_path="$PLUGINS_DIR/swarm-$name"
  
  # Verify resolved path stays within PLUGINS_DIR
  local resolved_path
  resolved_path="$(realpath "$plugin_path" 2>/dev/null || echo "$plugin_path")"
  local resolved_plugins_dir
  resolved_plugins_dir="$(realpath "$PLUGINS_DIR" 2>/dev/null || echo "$PLUGINS_DIR")"
  
  if [[ "$resolved_path" != "$resolved_plugins_dir"/* ]]; then
    fail "plugin path escapes plugins directory: $name"
  fi
  
  if [ ! -x "$plugin_path" ]; then
    fail "plugin not found or not executable: $name"
  fi
  
  log info "executing plugin: $name"
  
  # Export context for plugin
  export SWARM_PLUGIN_NAME="$name"
  export SWARM_PLATFORM_ROOT="$PLATFORM_ROOT"
  export SWARM_PROFILE="$ACTIVE_PROFILE"
  export SWARM_PROFILE_STACKS_DIR="$PROFILE_STACKS_DIR"
  export SWARM_DRY_RUN="$DRY_RUN"
  export SWARM_QUIET="$QUIET"
  export SWARM_VERBOSE="$VERBOSE"
  export SWARM_FORCE_JSON="$FORCE_JSON"
  export SWARM_LOG_FORMAT="$LOG_FORMAT"
  
  # Execute plugin with return code check
  "$plugin_path" "$@"
  local rc=$?
  if [ $rc -ne 0 ]; then
    log error "plugin '$name' failed (exit code: $rc)"
    return $rc
  fi
}

# Get plugin help
# Usage: plugin_help <name>
plugin_help() {
  local name="$1"
  _validate_plugin_name "$name"
  local plugin_path="$PLUGINS_DIR/swarm-$name"
  
  if [ ! -x "$plugin_path" ]; then
    echo "Plugin not found: $name"
    return 1
  fi
  
  "$plugin_path" --help 2>/dev/null || echo "No help available for plugin: $name"
}

# List all plugins with descriptions
# Usage: list_plugins
list_plugins() {
  local plugins
  plugins=$(discover_plugins)
  
  if [ -z "$plugins" ]; then
    log info "no plugins installed"
    return 0
  fi
  
  if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
    local json_array
    json_array=$(while IFS= read -r plugin; do
      [ -n "$plugin" ] || continue
      jq -n --arg name "$plugin" --arg path "$PLUGINS_DIR/swarm-$plugin" \
        '{name: $name, path: $path}'
    done <<< "$plugins" | jq -s '.')
    echo "$json_array"
  else
    echo "$(c 36 "Available plugins:")"
    while IFS= read -r plugin; do
      [ -n "$plugin" ] || continue
      printf "  • %s\n" "$plugin"
    done <<< "$plugins"
  fi
}

