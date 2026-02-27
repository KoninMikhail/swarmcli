#!/usr/bin/env bash
# Secret validation: check_required_secrets

# Check required secrets for stack
# If secret is missing, try to create it from file in SECRETS_ROOT directory
# Usage: check_required_secrets <stack>
# Returns: 0 if all exist, 3 if missing
check_required_secrets() {
  ensure_cmd docker
  
  local stack="$1"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  local req_file=""
  if [ -f "$stack_dir/externals.yaml" ]; then
    req_file="$stack_dir/externals.yaml"
  elif [ -f "$stack_dir/required_secrets.yaml" ]; then
    # DEPRECATED: required_secrets.yaml — rename to externals.yaml
    log warn "required_secrets.yaml is deprecated, rename to externals.yaml" 2>/dev/null || true
    req_file="$stack_dir/required_secrets.yaml"
  else
    # No secrets file - that's OK
    return 0
  fi
  
  local missing=()
  local failed_to_create=()
  
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    
    if ! secret_exists "$name" && ! secret_exists "${name}_latest"; then
      # Check if secret file exists and is not empty
      if secret_file_exists_and_not_empty "$name"; then
        # Try to create secret from file
        if ! create_secret_from_file "$name"; then
          failed_to_create+=("$name")
        fi
      else
        # File doesn't exist or is empty
        local path="$SECRETS_ROOT/$name"
        if [ ! -f "$path" ]; then
          log error "secret file not found: $path"
        else
          log error "secret file is empty: $path"
        fi
        missing+=("$name")
      fi
    fi
  done < <(get_required_secrets_list "$stack")
  
  # Combine missing and failed to create
  local all_errors=("${missing[@]}" "${failed_to_create[@]}")
  
  if [ ${#all_errors[@]} -gt 0 ]; then
    if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
      local missing_json
      missing_json=$(printf '%s\n' "${all_errors[@]}" | jq -R . | jq -s .)
      jq -n \
        --arg status "missing_secrets" \
        --arg profile "$ACTIVE_PROFILE" \
        --arg stack "$stack" \
        --argjson missing "$missing_json" \
        '{status: $status, profile: $profile, stack: $stack, missing: $missing}'
    fi
    return 3
  fi
  
  return 0
}
