#!/usr/bin/env bash
# Docker configs management: configs_sync, config_exists, create_config

# Check if config exists in Swarm
# Usage: config_exists <name>
# Returns: 0 if exists, 1 otherwise
config_exists() {
  docker config ls --format '{{.Name}}' 2>/dev/null | grep -Fxq "$1"
}

# Get config strategy for stack
# Usage: get_config_strategy <stack>
# Output: "simple" (default) or "versioned"
get_config_strategy() {
  local stack="$1"
  get_stack_setting "$stack" "config_strategy" "simple"
}

# Generate versioned config name
# Format: <name>_<profile>_<short_sha>
# Usage: generate_versioned_config_name <name> <stack>
generate_versioned_config_name() {
  local name="$1"
  local stack="$2"
  local profile="${ACTIVE_PROFILE:-unknown}"
  local short_sha=""
  
  # Try to get commit SHA from environment (GitLab CI)
  if [ -n "${CI_COMMIT_SHA:-}" ]; then
    short_sha="${CI_COMMIT_SHA:0:7}"
  elif [ -n "${COMMIT_SHA:-}" ]; then
    short_sha="${COMMIT_SHA:0:7}"
  else
    # Fallback: use timestamp if no commit SHA available
    short_sha="$(date +%s)"
  fi
  
  echo "${name}_${profile}_${short_sha}"
}

# Get current versioned config name for a base name
# Stores mapping in temp file for use during deploy
# Usage: get_current_config_name <base_name>
get_current_config_name() {
  local base_name="$1"
  local mapping_file="${SWARMCLI_CONFIG_MAPPING_FILE:-}"
  
  if [ -n "$mapping_file" ] && [ -f "$mapping_file" ]; then
    grep "^${base_name}=" "$mapping_file" 2>/dev/null | cut -d'=' -f2
  else
    echo "$base_name"
  fi
}

# Save config name mapping for j2 templates
# Usage: save_config_mapping <base_name> <actual_name>
save_config_mapping() {
  local base_name="$1"
  local actual_name="$2"
  local mapping_file="${SWARMCLI_CONFIG_MAPPING_FILE:-}"
  
  [ -n "$mapping_file" ] || return 0
  echo "${base_name}=${actual_name}" >> "$mapping_file"
  
  # Also export as environment variable for templates.py
  local var_name
  var_name="CONFIG_NAME_$(echo "$base_name" | tr '[:lower:]-' '[:upper:]_')"
  export "$var_name"="$actual_name"
}

# Clear config mappings (call at start of deploy)
# Usage: clear_config_mappings
clear_config_mappings() {
  rm -f "${SWARMCLI_CONFIG_MAPPING_FILE:-}" 2>/dev/null || true
  local mapping_file
  mapping_file=$(mktemp)
  export SWARMCLI_CONFIG_MAPPING_FILE="$mapping_file"
}

# Create config from file
# Usage: create_config <name> <file_path>
# Returns: 0 on success, 1 on error
create_config() {
  local name="$1"
  local file_path="$2"
  
  if [ ! -f "$file_path" ]; then
    log error "config file not found: $file_path"
    return 1
  fi
  
  if [ ! -s "$file_path" ]; then
    log error "config file is empty: $file_path"
    return 1
  fi
  
  if retry_with_backoff docker config create "$name" "$file_path" >/dev/null 2>&1; then
    return 0
  else
    log error "failed to create config: $name"
    return 1
  fi
}

# Sync configs for a stack
# Usage: sync_configs <stack>
# Returns: 0 on success, 1 on error
sync_configs() {
  ensure_cmd docker
  
  local stack="$1"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  local strategy
  strategy="$(get_config_strategy "$stack")"
  
  local configs_list
  configs_list=$(get_required_configs_list "$stack")
  
  if [ -z "$configs_list" ]; then
    return 0
  fi
  
  log detail "syncing configs for stack $stack (strategy: $strategy)"
  
  local ok=1
  while IFS=$'\t' read -r name file; do
    [ -n "$name" ] || continue
    
    local file_path="$stack_dir/$file"
    
    if [ ! -f "$file_path" ]; then
      add_error "config file missing: $file (expected at $file_path)"
      log error "config file missing: $file_path"
      ok=0
      continue
    fi
    
    if [ "$strategy" = "versioned" ]; then
      # Versioned strategy: always create new config with unique name
      local versioned_name
      versioned_name="$(generate_versioned_config_name "$name" "$stack")"
      
      log info "creating versioned config: $versioned_name"
      
      if create_config "$versioned_name" "$file_path"; then
        # Save mapping for j2 templates
        save_config_mapping "$name" "$versioned_name"
        log ok "created config: $versioned_name"
      else
        ok=0
      fi
    else
      # Simple strategy: create only if not exists
      if config_exists "$name"; then
        log detail "config already exists: $name"
        save_config_mapping "$name" "$name"
      else
        log info "creating config: $name"
        if create_config "$name" "$file_path"; then
          save_config_mapping "$name" "$name"
          log ok "created config: $name"
        else
          ok=0
        fi
      fi
    fi
  done <<< "$configs_list"
  
  [ $ok -eq 1 ] || return 1
  return 0
}

# Prune old versioned configs for a stack
# Keeps only N latest versions per config name
# Usage: prune_versioned_configs <stack> [keep_count]
prune_versioned_configs() {
  local stack="$1"
  local keep_count="${2:-${KEEP_IMAGES_COUNT:-10}}"
  
  local strategy
  strategy="$(get_config_strategy "$stack")"
  
  if [ "$strategy" != "versioned" ]; then
    return 0
  fi
  
  log detail "pruning old versioned configs for stack: $stack (keeping $keep_count versions)"
  
  local configs_list
  configs_list=$(get_required_configs_list "$stack")
  
  if [ -z "$configs_list" ]; then
    return 0
  fi
  
  local pruned=0
  while IFS=$'\t' read -r name file; do
    [ -n "$name" ] || continue
    
    # Get all configs matching pattern: <name>_<profile>_*
    local pattern="${name}_${ACTIVE_PROFILE}_"
    local all_configs
    all_configs=$(docker config ls --format "{{.Name}}|{{.CreatedAt}}" 2>/dev/null | \
      grep "^${pattern}" | \
      sort -t'|' -k2 -r | \
      cut -d'|' -f1)
    
    if [ -z "$all_configs" ]; then
      continue
    fi
    
    # Skip first N configs, remove the rest
    local count=0
    while IFS= read -r config_name; do
      [ -n "$config_name" ] || continue
      count=$((count + 1))
      
      if [ $count -gt $keep_count ]; then
        log detail "removing old config: $config_name"
        
        if [ "$DRY_RUN" != "1" ]; then
          docker config rm "$config_name" >/dev/null 2>&1 || {
            log detail "failed to remove $config_name (may be in use)"
          }
          pruned=$((pruned + 1))
        fi
      fi
    done <<< "$all_configs"
  done <<< "$configs_list"
  
  log detail "pruned $pruned old configs"
  return 0
}

# List all configs for a stack
# Usage: list_stack_configs <stack>
list_stack_configs() {
  local stack="$1"
  local configs_list
  configs_list=$(get_required_configs_list "$stack")
  
  if [ -z "$configs_list" ]; then
    return 0
  fi
  
  local strategy
  strategy="$(get_config_strategy "$stack")"
  
  while IFS=$'\t' read -r name file; do
    [ -n "$name" ] || continue
    
    if [ "$strategy" = "versioned" ]; then
      # Show all versioned configs
      local pattern="${name}_${ACTIVE_PROFILE}_"
      docker config ls --format "{{.Name}}" 2>/dev/null | grep "^${pattern}" || true
    else
      # Show simple config if exists
      if config_exists "$name"; then
        echo "$name"
      fi
    fi
  done <<< "$configs_list"
}
