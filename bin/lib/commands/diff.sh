#!/usr/bin/env bash
# Diff and apply commands

# Get list of changed stacks based on git diff
# Usage: get_changed_stacks [since_ref]
# Output: list of stack names (one per line)
get_changed_stacks() {
  local since_ref="${1:-HEAD~1}"
  
  if [ ! -d "$PLATFORM_ROOT/.git" ]; then
    log error "not a git repository: $PLATFORM_ROOT"
    return 1
  fi
  
  if [ -z "$ACTIVE_PROFILE" ]; then
    log error "no profile loaded"
    return 1
  fi
  
  # Get relative path to stacks directory
  local stacks_rel_path="profiles/$ACTIVE_PROFILE/stacks"
  
  # Get list of changed files in stacks directory
  local changed_files
  changed_files=$(git -C "$PLATFORM_ROOT" diff --name-only "$since_ref" HEAD -- "$stacks_rel_path" 2>/dev/null || echo "")
  
  if [ -z "$changed_files" ]; then
    return 0
  fi
  
  # Extract unique stack names from changed file paths
  local stacks=()
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    
    # Extract stack name from path like: profiles/server-dev/stacks/core-backend/variables.yaml
    local stack_name
    stack_name=$(echo "$file" | sed -n "s|^${stacks_rel_path}/\([^/]*\)/.*|\1|p")
    
    # Skip non-stack files (like endpoints.yaml, globals.yaml, resources.yaml)
    if [ -n "$stack_name" ] && [ -d "$PROFILE_STACKS_DIR/$stack_name" ]; then
      # Check if already in array
      local found=0
      for s in "${stacks[@]}"; do
        if [ "$s" = "$stack_name" ]; then
          found=1
          break
        fi
      done
      
      if [ $found -eq 0 ]; then
        stacks+=("$stack_name")
      fi
    fi
  done <<< "$changed_files"
  
  # Output unique stacks
  printf "%s\n" "${stacks[@]}"
}

# Get changed files for a specific stack
# Usage: get_stack_changed_files <stack> [since_ref]
# Output: list of changed files (relative to stack dir)
get_stack_changed_files() {
  local stack="$1"
  local since_ref="${2:-HEAD~1}"
  
  local stacks_rel_path="profiles/$ACTIVE_PROFILE/stacks/$stack"
  
  git -C "$PLATFORM_ROOT" diff --name-only "$since_ref" HEAD -- "$stacks_rel_path" 2>/dev/null | \
    sed "s|^${stacks_rel_path}/||" | \
    sort
}

# Command: swarmcli diff
# Shows stacks with changed configurations
cmd_diff() {
  if [ -z "$ACTIVE_PROFILE" ]; then
    fail "no profile loaded. Use --profile <name> or set SWARM_PROFILE"
  fi
  
  local since_ref="${SINCE_REF:-HEAD~1}"
  
  log info "comparing configs: $since_ref..HEAD"
  
  local changed_stacks
  changed_stacks=$(get_changed_stacks "$since_ref")
  
  if [ -z "$changed_stacks" ]; then
    if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
      jq -n \
        --arg profile "$ACTIVE_PROFILE" \
        --arg since "$since_ref" \
        '{profile: $profile, since: $since, changed_stacks: []}'
    else
      log info "no config changes detected since $since_ref"
    fi
    return 0
  fi
  
  if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
    local changed_json
    changed_json=$(while IFS= read -r stack; do
      [ -n "$stack" ] || continue
      local files
      files=$(get_stack_changed_files "$stack" "$since_ref")
      local files_arr
      files_arr=$(printf '%s' "$files" | jq -R -s 'split("\n") | map(select(length > 0))')
      jq -n -c --arg stack "$stack" --argjson files "$files_arr" '{stack: $stack, files: $files}'
    done <<< "$changed_stacks" | jq -s '.')
    jq -n \
      --arg profile "$ACTIVE_PROFILE" \
      --arg since "$since_ref" \
      --argjson changed_stacks "${changed_json:-[]}" \
      '{profile: $profile, since: $since, changed_stacks: $changed_stacks}'
  else
    echo ""
    echo "$(c 36 "Profile: $ACTIVE_PROFILE")"
    echo "$(c 90 "Comparing: $since_ref..HEAD")"
    echo ""
    echo "$(c 33 "Changed stacks:")"
    echo ""
    
    while IFS= read -r stack; do
      [ -n "$stack" ] || continue
      
      echo "  $(c 32 "●") $stack"
      
      local files
      files=$(get_stack_changed_files "$stack" "$since_ref")
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        echo "      $(c 90 "└─") $f"
      done <<< "$files"
      echo ""
    done <<< "$changed_stacks"
    
    local count
    count=$(echo "$changed_stacks" | grep -c . || echo "0")
    log info "total: $count stack(s) with config changes"
  fi
}

# Command: swarmcli apply
# Apply config changes to affected stacks (redeploy with current images)
cmd_apply() {
  if [ -z "$ACTIVE_PROFILE" ]; then
    fail "no profile loaded. Use --profile <name> or set SWARM_PROFILE"
  fi
  
  local since_ref="${SINCE_REF:-HEAD~1}"
  
  log info "applying config changes since $since_ref"
  
  local changed_stacks
  changed_stacks=$(get_changed_stacks "$since_ref")
  
  if [ -z "$changed_stacks" ]; then
    log info "no config changes detected since $since_ref"
    return 0
  fi
  
  local count
  count=$(echo "$changed_stacks" | grep -c . || echo "0")
  log info "found $count stack(s) with config changes"
  
  if [ "$DRY_RUN" = "1" ]; then
    log info "dry-run: would apply config changes to:"
    while IFS= read -r stack; do
      [ -n "$stack" ] || continue
      echo "  - $stack"
    done <<< "$changed_stacks"
    return 0
  fi
  
  local success=0
  local failed=0
  local failed_stacks=()
  
  while IFS= read -r stack; do
    [ -n "$stack" ] || continue
    
    log info "applying config to: $stack"
    
    # Set CONFIG_ONLY mode for deploy
    export CONFIG_ONLY="1"
    
    if cmd_deploy "$stack"; then
      success=$((success + 1))
      log ok "applied: $stack"
    else
      failed=$((failed + 1))
      failed_stacks+=("$stack")
      log error "failed: $stack"
    fi
  done <<< "$changed_stacks"
  
  echo ""
  log info "apply completed: $success succeeded, $failed failed"
  
  if [ $failed -gt 0 ]; then
    log error "failed stacks: ${failed_stacks[*]}"
    return 1
  fi
  
  return 0
}
