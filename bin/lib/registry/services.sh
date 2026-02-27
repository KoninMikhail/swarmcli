#!/usr/bin/env bash
# =============================================================================
# Services Registry - Parsing and validation of inter-service dependencies
# =============================================================================
#
# Functions:
#   - Parsing services-registry.yaml
#   - Generating SERVICE_* environment variables
#   - Validating ${SERVICE_*} usage in variables.yaml
#
# =============================================================================

# Get path to endpoints file
# Usage: get_registry_file
# Output: path to endpoints.yaml
get_registry_file() {
  echo "$PROFILE_STACKS_DIR/endpoints.yaml"
}

# Check if services registry exists
# Usage: registry_exists
# Returns: 0 if exists, 1 if not
registry_exists() {
  local f
  f="$(get_registry_file)"
  [ -f "$f" ]
}

# Parse services registry and export SERVICE_* variables
# Usage: load_services_registry
# Exports:
#   SERVICE_<CATEGORY>_<NAME>_HOST
#   SERVICE_<CATEGORY>_<NAME>_PORT
#   SERVICE_<CATEGORY>_<NAME>_URL
#   SERVICE_<CATEGORY>_<NAME>_NETWORK
load_services_registry() {
  local f
  f="$(get_registry_file)"
  
  if [ ! -f "$f" ]; then
    log warn "endpoints.yaml not found, skipping SERVICE_* variables"
    return 0
  fi
  
  log detail "loading services registry"
  
  # Get list of categories
  local categories
  categories=$(_run_yaml_parser get_keys "$f" "endpoints" 2>/dev/null)
  if [ $? -ne 0 ] || [ -z "$categories" ]; then
    log warn "no endpoints found in endpoints.yaml"
    return 0
  fi
  
  local exported=0
  
  # Iterate over categories
  while IFS= read -r category; do
    [ -n "$category" ] || continue
    
    # Get list of services in this category
    local services
    services=$(_run_yaml_parser get_keys "$f" "endpoints.$category" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$services" ]; then
      continue
    fi
    
    # Iterate over services
    while IFS= read -r service; do
      [ -n "$service" ] || continue
      
      # Get service properties
      local host port network public_host database
      host=$(_run_yaml_parser get_field "$f" "endpoints.$category.$service.host" 2>/dev/null || echo "")
      port=$(_run_yaml_parser get_field "$f" "endpoints.$category.$service.port" 2>/dev/null || echo "")
      network=$(_run_yaml_parser get_field "$f" "endpoints.$category.$service.network" 2>/dev/null || echo "")
      public_host=$(_run_yaml_parser get_field "$f" "endpoints.$category.$service.public_host" 2>/dev/null || echo "")
      database=$(_run_yaml_parser get_field "$f" "endpoints.$category.$service.database" 2>/dev/null || echo "")
      
      # Export if host is present
      if [ -n "$host" ]; then
        _export_service_vars "$category" "$service" "$host" "$port" "$network" "$public_host" "$database"
        exported=$((exported+1))
      fi
    done <<< "$services"
  done <<< "$categories"
  
  log detail "loaded $exported service endpoints"
  return 0
}

# Helper: Export SERVICE_* variables for a single service
# Usage: _export_service_vars <category> <service> <host> <port> <network> <public_host> <database>
_export_service_vars() {
  local category="$1" service="$2" host="$3" port="$4" network="$5" public_host="$6" database="$7"
  
  # Convert to uppercase and replace - with _
  local cat_upper svc_upper prefix
  cat_upper=$(echo "$category" | tr '[:lower:]-' '[:upper:]_')
  svc_upper=$(echo "$service" | tr '[:lower:]-' '[:upper:]_')
  prefix="SERVICE_${cat_upper}_${svc_upper}"
  
  # Export variables
  export "${prefix}_HOST"="$host"
  [ -n "$port" ] && export "${prefix}_PORT"="$port"
  [ -n "$network" ] && export "${prefix}_NETWORK"="$network"
  [ -n "$public_host" ] && export "${prefix}_PUBLIC_HOST"="$public_host"
  [ -n "$database" ] && export "${prefix}_DATABASE"="$database"
  
  # Generate URL if host and port are available
  if [ -n "$host" ] && [ -n "$port" ]; then
    export "${prefix}_URL"="http://${host}:${port}"
  elif [ -n "$host" ]; then
    export "${prefix}_URL"="http://${host}"
  fi
  
  if [ "${VERBOSE:-0}" = "1" ]; then
    log info "exported ${prefix}_HOST=$host"
  fi
}

# Get all registered SERVICE_* variable names
# Usage: get_registered_service_vars
# Output: list of variable names (one per line)
get_registered_service_vars() {
  env | grep "^SERVICE_" | cut -d= -f1 | sort
}

# Validate that all ${SERVICE_*} references in variables.yaml exist in registry
# Usage: validate_service_references <stack>
# Returns: 0 if valid, 1 if errors found
validate_service_references() {
  local stack="$1"
  local variables_file
  variables_file="$(get_current_stack_dir "$stack")/variables.yaml"
  
  if [ ! -f "$variables_file" ]; then
    return 0
  fi
  
  # Ensure registry is loaded
  if ! env | grep -q "^SERVICE_"; then
    load_services_registry
  fi
  
  local errors=0
  local missing_vars=()
  
  # Find all ${SERVICE_*} references in variables.yaml (excluding comments)
  # Note: grep -v '^\s*#' filters out comment lines before searching for references
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    
    # Extract variable name from ${SERVICE_XXX} or ${SERVICE_XXX:-default}
    local var_name
    var_name=$(echo "$ref" | sed 's/\${//' | sed 's/}.*//' | sed 's/:-.*$//')
    
    # Check if variable is exported
    if ! env | grep -q "^${var_name}="; then
      missing_vars+=("$var_name")
      errors=$((errors+1))
    fi
  done < <(grep -v '^\s*#' "$variables_file" 2>/dev/null | grep -oE '\$\{SERVICE_[A-Z_]+[^}]*\}' | sort -u)
  
  if [ $errors -gt 0 ]; then
    for var in "${missing_vars[@]}"; do
      add_error "undefined service reference in $stack/variables.yaml: \${$var}"
    done
    log error "found $errors undefined SERVICE_* references"
    return 1
  fi
  
  return 0
}

# Validate all stacks in current profile for SERVICE_* references
# Usage: validate_all_service_references
# Returns: 0 if all valid, 1 if errors found
validate_all_service_references() {
  if ! registry_exists; then
    log info "no services-registry.yaml found, skipping validation"
    return 0
  fi
  
  # Load registry first
  load_services_registry
  
  local errors=0
  local stacks
  stacks=$(list_profile_stacks "$ACTIVE_PROFILE")
  
  while IFS= read -r stack; do
    [ -n "$stack" ] || continue
    
    if ! validate_service_references "$stack"; then
      errors=$((errors+1))
    fi
  done <<< "$stacks"
  
  if [ $errors -gt 0 ]; then
    log error "validation failed for $errors stacks"
    return 1
  fi
  
  log ok "all SERVICE_* references are valid"
  return 0
}

# List all services in registry
# Usage: list_registry_services
# Output: category/service lines
list_registry_services() {
  local f
  f="$(get_registry_file)"
  
  if [ ! -f "$f" ]; then
    return 0
  fi
  
  # Get list of categories
  local categories
  categories=$(_run_yaml_parser get_keys "$f" "endpoints" 2>/dev/null)
  if [ $? -ne 0 ] || [ -z "$categories" ]; then
    return 0
  fi
  
  # Iterate over categories
  while IFS= read -r category; do
    [ -n "$category" ] || continue
    
    # Get list of services in this category
    local services
    services=$(_run_yaml_parser get_keys "$f" "endpoints.$category" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$services" ]; then
      continue
    fi
    
    # Output category/service pairs
    while IFS= read -r service; do
      [ -n "$service" ] || continue
      echo "${category}/${service}"
    done <<< "$services"
  done <<< "$categories"
}

# Get service info from registry
# Usage: get_registry_service_info <category> <service>
# Output: JSON-like string with host, port, network
get_registry_service_info() {
  local category="$1" service="$2"
  
  local cat_upper svc_upper prefix
  cat_upper=$(echo "$category" | tr '[:lower:]-' '[:upper:]_')
  svc_upper=$(echo "$service" | tr '[:lower:]-' '[:upper:]_')
  prefix="SERVICE_${cat_upper}_${svc_upper}"
  
  if [[ ! "$prefix" =~ ^[A-Z0-9_]+$ ]]; then
    echo "{}"
    return 1
  fi
  
  local host_var="${prefix}_HOST"
  local port_var="${prefix}_PORT"
  local network_var="${prefix}_NETWORK"
  local url_var="${prefix}_URL"
  
  local host port network url
  host="${!host_var:-}"
  port="${!port_var:-}"
  network="${!network_var:-}"
  url="${!url_var:-}"
  
  if [ -n "$host" ]; then
    jq -n \
      --arg host "$host" \
      --arg port "$port" \
      --arg network "$network" \
      --arg url "$url" \
      '{host: $host, port: $port, network: $network, url: $url}'
  else
    echo "{}"
    return 1
  fi
}

# Command: registry list
# Shows all registered services
cmd_registry_list() {
  if ! registry_exists; then
    log warn "endpoints.yaml not found in current profile"
    return 1
  fi
  
  # Load registry
  load_services_registry
  
  echo "$(c 36 "Services Registry") (profile: $ACTIVE_PROFILE)"
  echo ""
  
  local current_cat=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    
    local cat svc
    cat="${line%%/*}"
    svc="${line#*/}"
    
    if [ "$cat" != "$current_cat" ]; then
      [ -n "$current_cat" ] && echo ""
      echo "$(c 33 "[$cat]")"
      current_cat="$cat"
    fi
    
    local info
    info=$(get_registry_service_info "$cat" "$svc")
    
    local host port
    host=$(echo "$info" | sed -n 's/.*"host":"\([^"]*\)".*/\1/p')
    port=$(echo "$info" | sed -n 's/.*"port":"\([^"]*\)".*/\1/p')
    
    echo "  $(c 32 "●") $svc"
    echo "    URL: $(c 36 "http://${host}:${port}")"
    
    local cat_upper svc_upper
    cat_upper=$(echo "$cat" | tr '[:lower:]-' '[:upper:]_')
    svc_upper=$(echo "$svc" | tr '[:lower:]-' '[:upper:]_')
    echo "    Var: \${SERVICE_${cat_upper}_${svc_upper}_URL}"
  done < <(list_registry_services)
  
  echo ""
}

# Command: registry validate
# Validates all SERVICE_* references in all stacks
cmd_registry_validate() {
  if ! registry_exists; then
    log warn "endpoints.yaml not found in current profile"
    return 1
  fi
  
  log info "validating SERVICE_* references in all stacks"
  
  if validate_all_service_references; then
    log ok "all references are valid"
    return 0
  else
    return 1
  fi
}

