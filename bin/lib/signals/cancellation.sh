#!/usr/bin/env bash
# Cancellation detection: check_cancellation_requested, run_with_cancellation_check

# Global variable to track current stack for cancellation checks
declare -g _CANCEL_CHECK_STACK=""

# Set the stack context for cancellation checks
# Usage: set_cancel_check_stack <stack>
set_cancel_check_stack() {
  _CANCEL_CHECK_STACK="$1"
}

# Get the current stack for cancellation checks
get_cancel_check_stack() {
  echo "$_CANCEL_CHECK_STACK"
}

# Check if deployment cancellation was requested
# Usage: check_cancellation_requested [stack]
# Returns: 0 if NOT cancelled (continue), exits with 130 if cancelled
check_cancellation_requested() {
  local stack="${1:-$_CANCEL_CHECK_STACK}"
  
  if [ -z "$stack" ]; then
    return 0  # No stack context, can't check
  fi
  
  # Check cancel flag using locks.sh function
  if declare -f is_deploy_cancelled >/dev/null 2>&1; then
    if is_deploy_cancelled "$stack"; then
      # Get cancel info
      local cancel_info reason
      if declare -f get_cancel_info >/dev/null 2>&1; then
        cancel_info=$(get_cancel_info "$stack")
        reason="${cancel_info##*|}"
        log warn "deployment cancellation detected (reason: $reason)"
      else
        log warn "deployment cancellation detected"
      fi
      
      # Get current step for cleanup
      local current_step="unknown"
      if declare -f get_deploy_step >/dev/null 2>&1; then
        local step_info
        step_info=$(get_deploy_step "$stack")
        if [ -n "$step_info" ]; then
          current_step=$(echo "$step_info" | cut -d'|' -f3)
        fi
      fi
      
      # Cleanup and exit
      cleanup_on_cancel "$stack" "$current_step"
      
      log warn "deployment cancelled at step: $current_step"
      exit 130  # SIGINT exit code
    fi
  fi
  
  return 0
}

# Cleanup after cancellation
# Performs smart cleanup based on current step:
# - build: removes dangling images
# - deploy: notes that Swarm state may be partial
# - other: generic cleanup
# Usage: cleanup_on_cancel <stack> <current_step>
cleanup_on_cancel() {
  local stack="$1"
  local current_step="${2:-unknown}"
  
  log warn "cleaning up after cancellation (step: $current_step)"
  
  # Step-specific cleanup
  case "$current_step" in
    "build")
      log info "removing dangling build artifacts..."
      docker image prune -f 2>/dev/null || true
      ;;
    "deploy")
      log info "deployment step was interrupted (Swarm state may be partial)"
      ;;
    "sync")
      log info "repository sync was interrupted"
      ;;
    *)
      [ "$SIGNAL_DEBUG" = "1" ] && log info "no specific cleanup needed for step: $current_step"
      ;;
  esac
  
  # Run standard cleanup handlers (releases lock, etc)
  _run_cleanup_handlers
  
  log info "cleanup completed"
}

# Run command with periodic cancellation checks
# Executes command in background and monitors for cancellation flag
# Usage: run_with_cancellation_check <stack> <check_interval> <command> [args...]
# Returns: command exit code or 130 if cancelled
run_with_cancellation_check() {
  local stack="$1"
  local check_interval="${2:-1}"  # Default: check every 1 second
  shift 2
  
  # Start command in background
  "$@" &
  local cmd_pid=$!
  
  # Register for cleanup
  register_child_pid "$cmd_pid"
  
  [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] started command PID $cmd_pid with cancellation checks (interval: ${check_interval}s)" >&2
  
  # Monitor command with cancellation checks
  while kill -0 "$cmd_pid" 2>/dev/null; do
    # Check for cancellation (but don't exit, handle it here)
    if declare -f is_deploy_cancelled >/dev/null 2>&1; then
      if is_deploy_cancelled "$stack"; then
        [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] cancellation detected, killing PID $cmd_pid" >&2
        
        # Get cancel info for logging
        local cancel_info reason
        if declare -f get_cancel_info >/dev/null 2>&1; then
          cancel_info=$(get_cancel_info "$stack")
          reason="${cancel_info##*|}"
          log warn "cancellation detected during command execution (reason: $reason)"
        fi
        
        # Kill command gracefully first
        kill -TERM "$cmd_pid" 2>/dev/null || true
        
        # Wait a bit for graceful termination
        local term_waited=0
        while [ $term_waited -lt 5 ] && kill -0 "$cmd_pid" 2>/dev/null; do
          sleep 1
          term_waited=$((term_waited + 1))
        done
        
        # Force kill if still running
        if kill -0 "$cmd_pid" 2>/dev/null; then
          log warn "force killing command after SIGTERM timeout"
          kill -KILL "$cmd_pid" 2>/dev/null || true
        fi
        
        wait "$cmd_pid" 2>/dev/null || true
        unregister_child_pid "$cmd_pid"
        return 130
      fi
    fi
    
    sleep "$check_interval"
  done
  
  # Command finished - get exit code
  wait "$cmd_pid" 2>/dev/null
  local rc=$?
  
  unregister_child_pid "$cmd_pid"
  
  [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] command PID $cmd_pid finished with exit code $rc" >&2
  
  return $rc
}

# Wrapper for run_with_graceful_timeout with cancellation checks
# Combines timeout and cancellation monitoring
# Usage: run_with_timeout_and_cancel_check <stack> <timeout> <command> [args...]
run_with_timeout_and_cancel_check() {
  local stack="$1"
  local timeout_sec="$2"
  shift 2
  
  # Set stack context for cancellation
  set_cancel_check_stack "$stack"
  
  # Run with both timeout and cancellation monitoring
  # Use subshell to combine features
  (
    # Start command in background
    "$@" &
    local cmd_pid=$!
    
    # Start timeout watcher
    (
      sleep "$timeout_sec"
      if kill -0 "$cmd_pid" 2>/dev/null; then
        log warn "operation timed out after ${timeout_sec}s"
        kill -TERM "$cmd_pid" 2>/dev/null || true
      fi
    ) &
    local watcher_pid=$!
    
    # Monitor for cancellation
    while kill -0 "$cmd_pid" 2>/dev/null; do
      if declare -f is_deploy_cancelled >/dev/null 2>&1 && is_deploy_cancelled "$stack"; then
        kill "$watcher_pid" 2>/dev/null || true
        kill -TERM "$cmd_pid" 2>/dev/null || true
        wait "$cmd_pid" 2>/dev/null || true
        exit 130
      fi
      sleep 1
    done
    
    # Command finished
    wait "$cmd_pid" 2>/dev/null
    local rc=$?
    
    kill "$watcher_pid" 2>/dev/null || true
    wait "$watcher_pid" 2>/dev/null || true
    
    exit $rc
  )
  
  return $?
}
