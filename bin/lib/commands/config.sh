#!/usr/bin/env bash
# Config management commands
# Manages .swarmcli.yaml — unified configuration and state file.

cmd_config_list() {
  local config_file
  config_file="$(get_config_file)"
  
  if [ ! -f "$config_file" ]; then
    log info "no configuration file found at $config_file"
    log info "run 'swarmcli config init' to create one with defaults"
    return 0
  fi
  
  _run_config_manager list "$config_file"
}

cmd_config_get() {
  local key="${1:-}"
  [ -n "$key" ] || fail "usage: swarmcli config get <key>"
  
  local config_file
  config_file="$(get_config_file)"
  
  local value
  value=$(get_swarmcli_config "$key" "")
  
  if [ -z "$value" ]; then
    fail "key not found: $key"
  fi
  
  echo "$value"
}

cmd_config_set() {
  local key="${1:-}"
  local value="${2:-}"
  [ -n "$key" ] || fail "usage: swarmcli config set <key> <value>"
  [ -n "$value" ] || fail "usage: swarmcli config set <key> <value>"
  
  set_swarmcli_config "$key" "$value"
  log ok "set $key = $value"
}

cmd_config_edit() {
  local config_file
  config_file="$(get_config_file)"
  
  if [ ! -f "$config_file" ]; then
    log info "creating config with defaults..."
    _run_config_manager init "$config_file"
  fi
  
  local editor="${EDITOR:-${VISUAL:-vi}}"
  "$editor" "$config_file"
}

cmd_config_path() {
  get_config_file
}

cmd_config_init() {
  local config_file
  config_file="$(get_config_file)"
  
  if [ -f "$config_file" ]; then
    log info "configuration already exists: $config_file"
    return 0
  fi
  
  _run_config_manager init "$config_file"
  log ok "created $config_file"
  log info "edit with: swarmcli config edit"
}

cmd_config_reset() {
  local config_file
  config_file="$(get_config_file)"
  
  if [ ! -f "$config_file" ]; then
    log info "no configuration file to reset"
    return 0
  fi
  
  local backup="${config_file}.bak"
  cp "$config_file" "$backup"
  rm -f "$config_file"
  _run_config_manager init "$config_file"
  log ok "reset to defaults (backup: $backup)"
}

cmd_config() {
  local sub="${1:-list}"
  shift || true
  
  case "$sub" in
    list|ls)    cmd_config_list ;;
    get)        cmd_config_get "$@" ;;
    set)        cmd_config_set "$@" ;;
    edit)       cmd_config_edit ;;
    path)       cmd_config_path ;;
    init)       cmd_config_init ;;
    reset)      cmd_config_reset ;;
    --help|-h)
      echo "Usage: swarmcli config <subcommand>"
      echo ""
      echo "Subcommands:"
      echo "  list           Show all configuration values"
      echo "  get <key>      Get a specific value (dot notation)"
      echo "  set <key> <v>  Set a value"
      echo "  edit           Open config in \$EDITOR"
      echo "  path           Show config file path"
      echo "  init           Create config with defaults"
      echo "  reset          Reset to defaults (backup created)"
      echo ""
      echo "Examples:"
      echo "  swarmcli config set operations.log_format json"
      echo "  swarmcli config get operations.timeout"
      echo "  swarmcli config set git.auth.http_token \"your-token-here\""
      ;;
    *) fail "unknown config subcommand: $sub (use: list, get, set, edit, path, init, reset)" ;;
  esac
}
