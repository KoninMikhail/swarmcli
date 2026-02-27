#!/usr/bin/env bash
# YAML parsing utilities (Bash wrapper for PyYAML)
# Uses yaml_parser.py for reliable YAML parsing with full YAML spec support

# Check PyYAML availability
_check_pyyaml() {
  local python_cmd
  python_cmd="$(get_python_cmd)"
  if [ -z "$python_cmd" ]; then
    fail "Python is not installed (required for YAML parsing)"
    return 1
  fi
  
  if ! $python_cmd -c "import yaml" 2>/dev/null; then
    fail "PyYAML is not installed. Run: pip install pyyaml"
    return 1
  fi
}

# Get path to yaml_parser.py
_get_yaml_parser() {
  echo "$LIB_DIR/utils/yaml_parser.py"
}

# Run yaml_parser.py with python3
# On Windows (Git Bash), scripts cannot be executed directly due to missing execute bit
# This function ensures cross-platform compatibility
# Usage: _run_yaml_parser <command> <file> [args...]
_run_yaml_parser() {
  local python_cmd
  python_cmd="$(get_python_cmd)"
  [ -n "$python_cmd" ] || fail "Python not found (required for YAML parsing)"
  "$python_cmd" "$(_get_yaml_parser)" "$@"
}

# =============================================================================
# Services YAML
# =============================================================================

# Get list of services from services.yaml
# Usage: get_services_list <stack>
# Output: service names, one per line
get_services_list() {
  local stack="$1"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  local f="$stack_dir/services.yaml"
  [ -f "$f" ] || return 0
  
  _run_yaml_parser get_keys "$f" "services" 2>/dev/null || return 0
}

# Get field value for a service (supports nested fields with dot notation)
# Usage: get_service_field <stack> <service> <field>
# Example: get_service_field "my-stack" "api" "build.context"
# Output: field value
get_service_field() {
  local stack="$1" svc="$2" key="$3"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  local f="$stack_dir/services.yaml"
  [ -f "$f" ] || return 1
  
  local path output
  path="services.$svc.$key"
  
  output=$(_run_yaml_parser get_field "$f" "$path" 2>/dev/null)
  if [ $? -eq 0 ] && [ -n "$output" ]; then
    printf '%s\n' "$output"
    return 0
  fi
  return 1
}

# Get service type (git, registry, or none)
# Usage: get_service_type <stack> <service>
# Output: "git", "registry", or "none"
get_service_type() {
  local stack="$1" svc="$2"
  get_service_field "$stack" "$svc" type
}

# Check if service is internal (requires repository) or external (uses public images)
# For new format: type: git = internal, type: registry/none = external
# For legacy format: has repo = internal, no repo = external
# Usage: is_service_internal <stack> <service>
# Returns: 0 if internal (has repo), 1 if external (no repo)
is_service_internal() {
  local stack="$1" svc="$2"
  
  # New format: check type field
  local svc_type
  svc_type="$(get_service_type "$stack" "$svc")"
  if [ "$svc_type" = "git" ]; then
    return 0
  elif [ "$svc_type" = "registry" ] || [ "$svc_type" = "none" ]; then
    return 1
  fi
  
  # Legacy format: check if repo exists
  local repo
  repo="$(get_service_field "$stack" "$svc" repo)"
  [ -n "$repo" ]
}

# Get branch for service (default_branch in services.yaml)
# Usage: get_service_branch <stack> <service>
# Output: branch name
get_service_branch() {
  local stack="$1" svc="$2"
  get_service_field "$stack" "$svc" default_branch
}

# Iterate build_args for a service
# Usage: iter_build_args <stack> <service>
# Output: KEY=VALUE lines
iter_build_args() {
  local stack="$1" svc="$2"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  local f="$stack_dir/services.yaml"
  [ -f "$f" ] || return 0
  
  local path build_args_data
  path="services.$svc.build_args"
  
  # Get build_args section and iterate
  build_args_data=$(_run_yaml_parser get_field "$f" "$path" 2>/dev/null)
  if [ $? -ne 0 ] || [ -z "$build_args_data" ]; then
    return 0
  fi
  
  # Parse YAML output and convert to KEY=VALUE format
  local python_cmd
  python_cmd="$(get_python_cmd)"
  [ -n "$python_cmd" ] || return 0
  
  echo "$build_args_data" | "$python_cmd" -c "
import sys
import yaml
try:
    data = yaml.safe_load(sys.stdin)
    if isinstance(data, dict):
        for key, value in data.items():
            print(f'{key}={value}')
except:
    pass
" 2>/dev/null
}

# Get list of required secrets from externals.yaml
# Usage: get_required_secrets_list <stack>
# Output: secret names, one per line
get_required_secrets_list() {
  local stack="$1"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  local f=""
  if [ -f "$stack_dir/externals.yaml" ]; then
    f="$stack_dir/externals.yaml"
  elif [ -f "$stack_dir/required_secrets.yaml" ]; then
    # DEPRECATED: required_secrets.yaml — rename to externals.yaml
    log warn "required_secrets.yaml is deprecated, rename to externals.yaml" 2>/dev/null || true
    f="$stack_dir/required_secrets.yaml"
  else
    return 0
  fi
  
  _run_yaml_parser get_list "$f" "secrets" 2>/dev/null || return 0
}

# Get list of required configs from externals.yaml
# Usage: get_required_configs_list <stack>
# Output: name<TAB>file pairs, one per line
get_required_configs_list() {
  local stack="$1"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  local f="$stack_dir/externals.yaml"
  [ -f "$f" ] || return 0
  
  _run_yaml_parser get_configs "$f" 2>/dev/null || return 0
}

# Validate services.yaml structure
# Usage: validate_services_yaml <stack>
# Returns: 0 if valid, 1 if invalid
validate_services_yaml() {
  local stack="$1"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  local f="$stack_dir/services.yaml"
  
  if [ ! -f "$f" ]; then
    add_error "services.yaml not found for stack $stack"
    return 1
  fi
  
  local services
  services=$(get_services_list "$stack")
  
  if [ -z "$services" ]; then
    add_error "no services defined in $f"
    return 1
  fi
  
  local valid=0
  while IFS= read -r svc; do
    [ -n "$svc" ] || continue
    
    local svc_type image
    svc_type=$(get_service_type "$stack" "$svc")
    image=$(get_service_field "$stack" "$svc" image)
    
    # type: none - metadata-only service, no image/repo required
    if [ "$svc_type" = "none" ]; then
      continue
    fi
    
    # Image is required for git and registry types
    if [ -z "$image" ]; then
      add_error "service $svc: missing 'image' field"
      valid=1
    fi
    
    # For git services, repo is required
    if [ "$svc_type" = "git" ]; then
      local repo
      repo=$(get_service_field "$stack" "$svc" repo)
      if [ -z "$repo" ]; then
        add_error "service $svc: missing 'repo' field (required for type: git)"
        valid=1
      fi
    fi
  done <<< "$services"
  
  return $valid
}

# Validate that all git services have default_branch defined
# Usage: validate_service_branches <stack>
# Returns: 0 if valid, 1 if invalid
validate_service_branches() {
  local stack="$1"
  local services missing=()
  services=$(get_services_list "$stack")
  
  while IFS= read -r svc; do
    [ -n "$svc" ] || continue
    if is_service_internal "$stack" "$svc"; then
      local branch
      branch=$(get_service_branch "$stack" "$svc")
      if [ -z "$branch" ]; then
        missing+=("$svc")
      fi
    fi
  done <<< "$services"
  
  if [ ${#missing[@]} -gt 0 ]; then
    add_error "missing default_branch for services: ${missing[*]}"
    return 1
  fi
  
  return 0
}

# ===== JSON Parsing (Bash built-in, without jq) =====

# Extract field value from JSON string
# Usage: parse_json_field <json_string> <field_name>
parse_json_field() {
  local json="$1" field="$2"
  echo "$json" | sed -n 's/.*"'"$field"'":"\([^"]*\)".*/\1/p'
}

# Extract array items from JSON (services array)
# Usage: parse_json_services <json_string>
parse_json_services() {
  local json="$1"
  local services_json
  services_json=$(echo "$json" | sed -n 's/.*"services":\[\(.*\)\].*/\1/p')
  echo "$services_json" | sed 's/},{/}\n{/g'
}

# ===== Variables YAML Parsing =====

# Iterate variables from variables.yaml for a specific section
# Usage: iter_variables_yaml <stack> <section>
# Section: common, build, or deploy
# Output: KEY=VALUE lines
iter_variables_yaml() {
  local stack="$1" section="$2"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  local f="$stack_dir/variables.yaml"
  [ -f "$f" ] || return 0
  
  _run_yaml_parser iter_section "$f" "$section" 2>/dev/null || return 0
}

# Load and export variables from variables.yaml for a specific section
# Also merges GitLab CI variables with matching prefixes
# Usage: load_variables_yaml <stack> <section>
# Section: common, build, or deploy
load_variables_yaml() {
  local stack="$1" section="$2"
  local prefix=""
  local tmpfile=""
  
  case "$section" in
    build) prefix="BUILD_" ;;
    deploy) prefix="DEPLOY_" ;;
    common) prefix="COMMON_" ;;
  esac
  
  tmpfile=$(mktemp) || return 1
  trap "rm -f '$tmpfile'" RETURN
  
  # First, load GitLab CI variables with prefixes (highest priority)
  if [ -n "$prefix" ]; then
    while IFS='=' read -r full_key val; do
      [ -n "$full_key" ] || continue
      local key="${full_key#${prefix}}"
      if [ -n "$key" ] && [ -n "$val" ]; then
        printf "%s=%s\n" "$key" "$val" >> "$tmpfile"
      fi
    done < <(env | grep "^${prefix}")
  fi
  
  # Then load from YAML file (only if not already set from CI)
  while IFS='=' read -r key val; do
    [ -n "$key" ] || continue
    if grep -q "^${key}=" "$tmpfile" 2>/dev/null; then
      continue
    fi
    printf "%s=%s\n" "$key" "$val" >> "$tmpfile"
  done < <(iter_variables_yaml "$stack" "$section")
  
  # Safe read loop instead of sourcing tmpfile
  if [ -s "$tmpfile" ]; then
    while IFS='=' read -r key val; do
      [ -n "$key" ] || continue
      [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
      export "$key"="$val"
    done < "$tmpfile"
  fi
}

# ===== Stack Settings =====

# Get stack setting from settings.yaml
# Usage: get_stack_setting <stack> <key> [default]
get_stack_setting() {
  local stack="$1" key="$2" default="${3:-}"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  local f="$stack_dir/settings.yaml"
  
  if [ ! -f "$f" ]; then
    echo "$default"
    return 0
  fi
  
  local output
  output=$(_run_yaml_parser get_field "$f" "$key" 2>/dev/null)
  
  if [ $? -eq 0 ] && [ -n "$output" ]; then
    echo "$output"
    return 0
  fi
  
  echo "$default"
}

# Get list of services to exclude from readiness check (one-shot init jobs)
# Usage: get_readiness_exclude_services <stack>
# Output: service names, one per line (from settings.yaml readiness_exclude)
# Returns: 0 if settings exist, 1 if not
get_readiness_exclude_services() {
  local stack="$1"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  local f="$stack_dir/settings.yaml"
  
  [ -f "$f" ] || return 1
  
  _run_yaml_parser get_list "$f" "readiness_exclude" 2>/dev/null || return 1
}

# Get services ready timeout for stack
# Usage: get_stack_services_ready_timeout <stack>
# Priority: stack settings > profile config > default
get_stack_services_ready_timeout() {
  local stack="$1"
  
  # Try stack setting first
  local timeout
  timeout="$(get_stack_setting "$stack" "services_ready_timeout" "")"
  
  if [ -n "$timeout" ]; then
    echo "$timeout"
    return 0
  fi
  
  # Fall back to profile/default
  echo "${SERVICES_READY_TIMEOUT:-30}"
}

# Get diagnostics logs tail count
# Usage: get_diagnostics_logs_tail <stack>
get_diagnostics_logs_tail() {
  local stack="$1"
  get_stack_setting "$stack" "diagnostics_logs_tail" "30"
}

# Get build timeout for stack
# Usage: get_stack_build_timeout <stack>
# Priority: stack settings > BUILD_TIMEOUT env > default (900)
get_stack_build_timeout() {
  local stack="$1"
  
  # Try stack setting first
  local timeout
  timeout="$(get_stack_setting "$stack" "build_timeout" "")"
  
  if [ -n "$timeout" ]; then
    echo "$timeout"
    return 0
  fi
  
  # Fall back to env/default
  echo "${BUILD_TIMEOUT:-900}"
}

# ===== Globals YAML =====

# Load global variables from globals.yaml
# Usage: load_globals_yaml
# Exports: GLOBAL_* variables
load_globals_yaml() {
  local f="$PROFILE_STACKS_DIR/globals.yaml"
  [ -f "$f" ] || return 0
  
  # Get globals section and export each variable with GLOBAL_ prefix
  while IFS='=' read -r key val; do
    [ -n "$key" ] || continue
    export "GLOBAL_${key}"="$val"
  done < <(_run_yaml_parser iter_section "$f" "globals" 2>/dev/null)
}
