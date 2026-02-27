#!/usr/bin/env bash
# Deployment hooks execution

# Run deployment hooks
# Usage: run_hook <hook_path> <stack>
run_hook() {
  local hook_path="$1" stack="$2"
  
  if [ ! -f "$hook_path" ]; then
    return 0
  fi
  
  # Validate hook path stays within expected directory (prevent path traversal)
  local resolved_hook
  resolved_hook="$(realpath "$hook_path" 2>/dev/null || echo "$hook_path")"
  local resolved_platform
  resolved_platform="$(realpath "${PLATFORM_ROOT:-.}" 2>/dev/null || echo "${PLATFORM_ROOT:-.}")"
  
  if [[ "$resolved_hook" != "$resolved_platform"/* ]]; then
    log error "hook path escapes platform root: $hook_path"
    return 1
  fi
  
  local hook_name
  hook_name=$(basename "$hook_path")
  local use_bash_fallback=0
  
  if [ ! -x "$hook_path" ]; then
    log warn "hook not executable, attempting to fix: $hook_path"
    
    local chmod_error
    chmod_error=$(chmod +x "$hook_path" 2>&1)
    local chmod_rc=$?
    
    if [ $chmod_rc -eq 0 ]; then
      log info "hook permissions fixed: $hook_path"
    else
      log warn "failed to fix hook permissions: $hook_path"
      if [ -n "$chmod_error" ]; then
        log warn "chmod error: $chmod_error"
      fi
      
      if head -n1 "$hook_path" | grep -qE "^#!.*bash"; then
        log info "hook is a bash script, will execute via bash directly"
        use_bash_fallback=1
      else
        log warn "skipping hook: $hook_path"
        return 0
      fi
    fi
  fi
  
  # Hook display name
  local hook_display_name
  case "$hook_name" in
    pre-deploy.sh)  hook_display_name="Pre-deploy hook" ;;
    post-deploy.sh) hook_display_name="Post-deploy hook" ;;
    *)              hook_display_name="Hook: $hook_name" ;;
  esac
  
  # Verbose mode: plain CLI output
  if [ "$VERBOSE" = "1" ]; then
    log info "running hook: $hook_name"
    
    if [ "$DRY_RUN" = "1" ]; then
      log info "dry-run: would run $hook_name"
      return 0
    fi
    
    local start_ts=$(date +%s)
    
    if [ $use_bash_fallback -eq 1 ]; then
      STACK="$stack" SWARM_PROFILE="$ACTIVE_PROFILE" bash "$hook_path" "$stack" 2>&1 | while IFS= read -r line; do
        log info "[$hook_name] $line"
      done
      local -a ps=("${PIPESTATUS[@]}")
    else
      STACK="$stack" SWARM_PROFILE="$ACTIVE_PROFILE" "$hook_path" "$stack" 2>&1 | while IFS= read -r line; do
        log info "[$hook_name] $line"
      done
      local -a ps=("${PIPESTATUS[@]}")
    fi
    
    local rc=${ps[0]}
    local end_ts=$(date +%s)
    local duration=$((end_ts - start_ts))
    
    if [ $rc -ne 0 ]; then
      add_error "hook $hook_name failed with exit code $rc"
      log error "hook failed: $hook_name (exit code $rc)"
      return $rc
    fi
    
    return 0
  fi
  
  # Default mode: formatted output
  printf "\n$(c 90 "─────────────────────────────────────────────────────────────")\n"
  printf "🔧 $(c 1 "Running %s...")\n" "$hook_display_name"
  
  if [ "$DRY_RUN" = "1" ]; then
    printf "○ dry-run: would run %s\n" "$hook_name"
    return 0
  fi
  
  local start_ts=$(date +%s)
  
  if [ $use_bash_fallback -eq 1 ]; then
    STACK="$stack" SWARM_PROFILE="$ACTIVE_PROFILE" bash "$hook_path" "$stack" 2>&1 | while IFS= read -r line; do
      printf "%s\n" "$line"
    done
    local -a ps=("${PIPESTATUS[@]}")
  else
    STACK="$stack" SWARM_PROFILE="$ACTIVE_PROFILE" "$hook_path" "$stack" 2>&1 | while IFS= read -r line; do
      printf "%s\n" "$line"
    done
    local -a ps=("${PIPESTATUS[@]}")
  fi
  
  local rc=${ps[0]}
  local end_ts=$(date +%s)
  local duration=$((end_ts - start_ts))
  
  if [ $rc -ne 0 ]; then
    add_error "hook $hook_name failed with exit code $rc"
    printf "$(c 31 "✗") $(c 31 "%s failed") (exit code %d)\n" "$hook_display_name" "$rc"
    return $rc
  fi
  
  printf "$(c 32 "✓") $(c 32 "%s completed") $(c 90 "(%ds)")\n" "$hook_display_name" "$duration"
  
  return 0
}
