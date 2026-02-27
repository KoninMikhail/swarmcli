#!/usr/bin/env bash
# Config validation: check_required_configs

# Check required configs for stack
# If config is missing and strategy is simple, try to create it
# Usage: check_required_configs <stack>
# Returns: 0 if all exist/created, 3 if missing files
check_required_configs() {
  ensure_cmd docker
  
  local stack="$1"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  local configs_list
  configs_list=$(get_required_configs_list "$stack")
  
  if [ -z "$configs_list" ]; then
    # No configs required
    return 0
  fi
  
  local strategy
  strategy="$(get_config_strategy "$stack")"
  
  local missing_files=()
  local failed_to_create=()
  
  while IFS=$'\t' read -r name file; do
    [ -n "$name" ] || continue
    
    local file_path="$stack_dir/$file"
    
    # Check if config file exists
    if [ ! -f "$file_path" ]; then
      log error "config file not found: $file_path"
      missing_files+=("$name ($file)")
      continue
    fi
    
    # Check if file is not empty
    if [ ! -s "$file_path" ]; then
      log error "config file is empty: $file_path"
      missing_files+=("$name ($file)")
      continue
    fi
    
    # For simple strategy, check if config exists in Swarm
    # (versioned configs are created during deploy, not validation)
    if [ "$strategy" = "simple" ]; then
      if ! config_exists "$name"; then
        log detail "config '$name' not found in Swarm, will be created during deploy"
      fi
    fi
  done <<< "$configs_list"
  
  # Combine errors
  local all_errors=("${missing_files[@]}" "${failed_to_create[@]}")
  
  if [ ${#all_errors[@]} -gt 0 ]; then
    if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
      local missing_json
      missing_json=$(printf '%s\n' "${all_errors[@]}" | jq -R . | jq -s .)
      jq -n \
        --arg status "missing_config_files" \
        --arg profile "$ACTIVE_PROFILE" \
        --arg stack "$stack" \
        --argjson missing "$missing_json" \
        '{status: $status, profile: $profile, stack: $stack, missing: $missing}'
    fi
    return 3
  fi
  
  return 0
}

# Validate config files exist (for validation command, not deploy)
# Usage: validate_config_files <stack>
# Returns: 0 if all files exist, 1 otherwise
validate_config_files() {
  local stack="$1"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  local configs_list
  configs_list=$(get_required_configs_list "$stack")
  
  if [ -z "$configs_list" ]; then
    return 0
  fi
  
  local errors=0
  while IFS=$'\t' read -r name file; do
    [ -n "$name" ] || continue
    
    local file_path="$stack_dir/$file"
    
    if [ ! -f "$file_path" ]; then
      add_error "config file not found: $file (for config '$name')"
      errors=$((errors + 1))
    elif [ ! -s "$file_path" ]; then
      add_error "config file is empty: $file (for config '$name')"
      errors=$((errors + 1))
    fi
  done <<< "$configs_list"
  
  [ $errors -eq 0 ]
}
