#!/usr/bin/env bash
# Profile management for server configurations

# Validate resource name (profile or stack) against path traversal
# Usage: _validate_resource_name <name> <type>
_validate_resource_name() {
  local name="$1" type="$2"
  if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
    fail "invalid $type name: $name (only alphanumeric, hyphens and underscores allowed)"
  fi
}

# Get profiles directory
get_profiles_dir() {
  echo "$PLATFORM_ROOT/profiles"
}

# Get specific profile directory
get_profile_dir() {
  local profile="$1"
  echo "$(get_profiles_dir)/$profile"
}

# Get stacks directory for profile
get_profile_stacks_dir() {
  local profile="$1"
  echo "$(get_profile_dir "$profile")/stacks"
}

# Get stack directory within profile
get_stack_dir() {
  local profile="$1"
  local stack="$2"
  echo "$(get_profile_stacks_dir "$profile")/$stack"
}

# Check if profile exists
profile_exists() {
  local profile="$1"
  local profile_dir
  profile_dir="$(get_profile_dir "$profile")"
  [ -d "$profile_dir" ] && [ -f "$profile_dir/config.yaml" ]
}

# List all available profiles
list_profiles() {
  local profiles_dir
  profiles_dir="$(get_profiles_dir)"
  
  if [ ! -d "$profiles_dir" ]; then
    return 0
  fi
  
  for dir in "$profiles_dir"/*; do
    [ -d "$dir" ] || continue
    local profile_name
    profile_name=$(basename "$dir")
    
    # Check if it has config.yaml
    if [ -f "$dir/config.yaml" ]; then
      echo "$profile_name"
    fi
  done
}

# Get config value from profile config.yaml
# Usage: get_profile_config <profile> <path> [default]
# Example: get_profile_config "server-dev" "swarm.keep_images_count" "10"
get_profile_config() {
  local profile="$1"
  local key_path="$2"
  local default="${3:-}"
  local config_file
  config_file="$(get_profile_dir "$profile")/config.yaml"
  
  if [ ! -f "$config_file" ]; then
    echo "$default"
    return 0
  fi
  
  # Use PyYAML parser for reliable YAML parsing
  local output
  output=$(_run_yaml_parser get_field "$config_file" "$key_path" 2>/dev/null)
  
  if [ $? -eq 0 ] && [ -n "$output" ]; then
    echo "$output"
    return 0
  fi
  
  echo "$default"
}

# Validate profile config.yaml structure
# Warns about unknown keys and missing required fields
# Usage: validate_profile_config <profile>
# Returns: 0 always (warnings only, does not block loading)
validate_profile_config() {
  local profile="$1"
  local config_file
  config_file="$(get_profile_dir "$profile")/config.yaml"

  if [ ! -f "$config_file" ]; then
    log error "config.yaml not found for profile: $profile"
    return 1
  fi

  local valid_keys="name description swarm git retry"
  local valid_swarm_keys="services_ready_timeout keep_images_count"
  local valid_git_keys="default_branch http_user http_token ssh_key"
  local valid_retry_keys="enabled max_attempts initial_delay max_delay"
  local errors=0

  local top_keys
  top_keys=$(_run_yaml_parser get_keys "$config_file" "" 2>/dev/null)

  while IFS= read -r key; do
    [ -n "$key" ] || continue
    case " $valid_keys " in
      *" $key "*) ;;
      *) log warn "profile '$profile': unknown key '$key' in config.yaml (valid: $valid_keys)"
         errors=$((errors + 1)) ;;
    esac
  done <<< "$top_keys"

  local swarm_keys
  swarm_keys=$(_run_yaml_parser get_keys "$config_file" "swarm" 2>/dev/null)
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    case " $valid_swarm_keys " in
      *" $key "*) ;;
      *) log warn "profile '$profile': unknown key 'swarm.$key' (valid: $valid_swarm_keys)" ;;
    esac
  done <<< "$swarm_keys"

  local git_keys
  git_keys=$(_run_yaml_parser get_keys "$config_file" "git" 2>/dev/null)
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    case " $valid_git_keys " in
      *" $key "*) ;;
      *) log warn "profile '$profile': unknown key 'git.$key' (valid: $valid_git_keys)" ;;
    esac
  done <<< "$git_keys"

  local retry_keys
  retry_keys=$(_run_yaml_parser get_keys "$config_file" "retry" 2>/dev/null)
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    case " $valid_retry_keys " in
      *" $key "*) ;;
      *) log warn "profile '$profile': unknown key 'retry.$key' (valid: $valid_retry_keys)" ;;
    esac
  done <<< "$retry_keys"

  local name_val
  name_val=$(get_profile_config "$profile" "name" "")
  if [ -z "$name_val" ]; then
    log warn "profile '$profile': missing required key 'name' in config.yaml"
  fi

  return 0
}

# Load profile configuration into environment variables
# Usage: load_profile <profile>
load_profile() {
  local profile="$1"
  _validate_resource_name "$profile" "profile"
  
  if ! profile_exists "$profile"; then
    fail "profile not found: $profile"
  fi

  validate_profile_config "$profile"
  
  local profile_dir
  profile_dir="$(get_profile_dir "$profile")"
  
  # Export profile-related paths
  export ACTIVE_PROFILE="$profile"
  export PROFILE_DIR="$profile_dir"
  PROFILE_STACKS_DIR="$(get_profile_stacks_dir "$profile")"
  export PROFILE_STACKS_DIR
  
  # Load config values
  local name description
  name=$(get_profile_config "$profile" "name" "$profile")
  description=$(get_profile_config "$profile" "description" "")
  
  export PROFILE_NAME="$name"
  export PROFILE_DESCRIPTION="$description"
  
  # Swarm settings
  SERVICES_READY_TIMEOUT=$(get_profile_config "$profile" "swarm.services_ready_timeout" "${SERVICES_READY_TIMEOUT:-30}")
  export SERVICES_READY_TIMEOUT
  KEEP_IMAGES_COUNT=$(get_profile_config "$profile" "swarm.keep_images_count" "${KEEP_IMAGES_COUNT:-10}")
  export KEEP_IMAGES_COUNT
  
  # Git settings
  DEFAULT_BRANCH=$(get_profile_config "$profile" "git.default_branch" "${DEFAULT_BRANCH:-main}")
  export DEFAULT_BRANCH
  local git_user git_token
  git_user=$(get_profile_config "$profile" "git.http_user" "")
  git_token=$(get_profile_config "$profile" "git.http_token" "")
  if [ -n "$git_user" ]; then
    git_user="$(safe_interpolate "$git_user")"
    export GIT_HTTP_USER="$git_user"
  fi
  if [ -n "$git_token" ]; then
    git_token="$(safe_interpolate "$git_token")"
    export GIT_HTTP_TOKEN="$git_token"
  fi
  
  # Retry settings
  local retry_enabled
  retry_enabled=$(get_profile_config "$profile" "retry.enabled" "true")
  if [ "$retry_enabled" = "true" ] || [ "$retry_enabled" = "1" ]; then
    export RETRY_ENABLED=1
  else
    export RETRY_ENABLED=0
  fi
  
  RETRY_MAX_ATTEMPTS=$(get_profile_config "$profile" "retry.max_attempts" "${RETRY_MAX_ATTEMPTS:-3}")
  export RETRY_MAX_ATTEMPTS
  RETRY_INITIAL_DELAY=$(get_profile_config "$profile" "retry.initial_delay" "${RETRY_INITIAL_DELAY:-2}")
  export RETRY_INITIAL_DELAY
  RETRY_MAX_DELAY=$(get_profile_config "$profile" "retry.max_delay" "${RETRY_MAX_DELAY:-30}")
  export RETRY_MAX_DELAY
  
  log detail "loaded profile: $profile"
  
  return 0
}

# Get stack path for current profile
# Usage: get_current_stack_dir <stack>
get_current_stack_dir() {
  local stack="$1"
  _validate_resource_name "$stack" "stack"
  
  if [ -z "$ACTIVE_PROFILE" ]; then
    fail "no profile loaded"
  fi
  
  get_stack_dir "$ACTIVE_PROFILE" "$stack"
}

# Check if stack exists in current profile
stack_exists() {
  local stack="$1"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  [ -d "$stack_dir" ]
}

# Ensure stack exists
ensure_stack_exists() {
  local stack="$1"
  
  if ! stack_exists "$stack"; then
    fail "stack not found: $stack (profile: $ACTIVE_PROFILE)"
  fi
}

# List stacks in profile
list_profile_stacks() {
  local profile="$1"
  local stacks_dir
  stacks_dir="$(get_profile_stacks_dir "$profile")"
  
  if [ ! -d "$stacks_dir" ]; then
    return 0
  fi
  
  for dir in "$stacks_dir"/*; do
    [ -d "$dir" ] || continue
    basename "$dir"
  done
}

# Get profile info as JSON
get_profile_info_json() {
  local profile="$1"
  
  if ! profile_exists "$profile"; then
    echo '{"error":"profile not found"}'
    return 1
  fi
  
  local name description stacks_count
  name=$(get_profile_config "$profile" "name" "$profile")
  description=$(get_profile_config "$profile" "description" "")
  stacks_count=$(list_profile_stacks "$profile" | wc -l)
  
  jq -n \
    --arg profile "$profile" \
    --arg name "$name" \
    --arg description "$description" \
    --argjson stacks_count "$stacks_count" \
    '{profile: $profile, name: $name, description: $description, stacks_count: $stacks_count}'
}

# Command: profiles list
cmd_profiles_list() {
  local profiles
  profiles=$(list_profiles)
  
  if [ -z "$profiles" ]; then
    log info "no profiles found"
    return 0
  fi
  
  if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
    echo "["
    local first=1
    while IFS= read -r profile; do
      [ -n "$profile" ] || continue
      [ $first -eq 0 ] && echo ","
      get_profile_info_json "$profile"
      first=0
    done <<< "$profiles"
    echo "]"
  else
    echo "$(c 36 "Available profiles:")"
    echo ""
    while IFS= read -r profile; do
      [ -n "$profile" ] || continue
      local name description stacks_count
      name=$(get_profile_config "$profile" "name" "$profile")
      description=$(get_profile_config "$profile" "description" "")
      stacks_count=$(list_profile_stacks "$profile" | wc -l)
      
      echo "$(c 32 "●") $(c 36 "$profile")"
      [ -n "$description" ] && echo "    Description: $description"
      echo "    Stacks: $stacks_count"
      echo ""
    done <<< "$profiles"
  fi
}

# Command: profile info <profile>
cmd_profile_info() {
  local profile="$1"
  
  [ -n "$profile" ] || fail "usage: swarmcli profile info <PROFILE>"
  
  if ! profile_exists "$profile"; then
    fail "profile not found: $profile"
  fi
  
  if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
    get_profile_info_json "$profile"
  else
    local name description
    name=$(get_profile_config "$profile" "name" "$profile")
    description=$(get_profile_config "$profile" "description" "")
    
    echo "$(c 36 "Profile: $profile")"
    echo ""
    echo "Name: $name"
    [ -n "$description" ] && echo "Description: $description"
    echo ""
    echo "Configuration:"
    echo "  Services Ready Timeout: $(get_profile_config "$profile" "swarm.services_ready_timeout" "30")s"
    echo "  Keep Images Count: $(get_profile_config "$profile" "swarm.keep_images_count" "10")"
    echo "  Default Branch: $(get_profile_config "$profile" "git.default_branch" "main")"
    echo ""
    echo "Stacks:"
    local stacks
    stacks=$(list_profile_stacks "$profile")
    if [ -z "$stacks" ]; then
      echo "  (no stacks)"
    else
      while IFS= read -r stack; do
        [ -n "$stack" ] || continue
        echo "  • $stack"
      done <<< "$stacks"
    fi
  fi
}

# Detect profile from hostname or config
detect_active_profile() {
  # Priority:
  # 1. --profile flag (already handled in main)
  # 2. SWARM_PROFILE environment variable
  # 3. state.default_profile from .swarmcli.yaml
  # 4. First available profile
  
  if [ -n "${SWARM_PROFILE:-}" ]; then
    echo "$SWARM_PROFILE"
    return 0
  fi
  
  local saved
  saved=$(load_default_profile)
  if [ -n "$saved" ]; then
    echo "$saved"
    return 0
  fi
  
  # Return first available profile (no explicit default set)
  local first
  first=$(list_profiles | head -n1)
  if [ -n "$first" ]; then
    log warn "no default profile set, using first found: $first"
  fi
  echo "$first"
}

# ============================================================================
# State management (default profile) — stored in .swarmcli.yaml
# ============================================================================

# Save default profile to .swarmcli.yaml
# IMPORTANT: This function should ONLY be called from cmd_use()
save_default_profile() {
  local profile="$1"
  set_swarmcli_config "state.default_profile" "$profile"
}

# Load default profile from .swarmcli.yaml
load_default_profile() {
  local profile
  profile=$(get_swarmcli_config "state.default_profile" "")
  if [ -n "$profile" ] && profile_exists "$profile"; then
    echo "$profile"
  fi
}

# Clear default profile
clear_default_profile() {
  set_swarmcli_config "state.default_profile" "null"
}

# Command: use
cmd_use() {
  local arg="${1:-}"
  
  case "$arg" in
    --show|"")
      local current
      current=$(load_default_profile)
      if [ -n "$current" ]; then
        if [ "$FORCE_JSON" = "1" ]; then
          jq -n --arg profile "$current" '{default_profile: $profile}'
        else
          echo "Current default profile: $(c 36 "$current")"
        fi
      else
        if [ "$FORCE_JSON" = "1" ]; then
          echo '{"default_profile":null}'
        else
          echo "No default profile set. Use: swarmcli use <profile>"
          echo ""
          echo "Available profiles:"
          list_profiles | while read -r p; do
            echo "  • $p"
          done
        fi
      fi
      ;;
    --clear)
      clear_default_profile
      log ok "default profile cleared"
      ;;
    *)
      _validate_resource_name "$arg" "profile"
      if ! profile_exists "$arg"; then
        fail "profile not found: $arg"
      fi
      save_default_profile "$arg"
      log ok "default profile set to: $arg"
      ;;
  esac
}

