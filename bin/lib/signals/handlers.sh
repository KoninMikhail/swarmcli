#!/usr/bin/env bash
# Signal handlers: init_signal_handlers, _signal_handler

# ===== Configuration =====

# Maximum time to wait for graceful shutdown before SIGKILL
GRACEFUL_SHUTDOWN_TIMEOUT="${GRACEFUL_SHUTDOWN_TIMEOUT:-10}"

# Enable verbose signal handling logs
SIGNAL_DEBUG="${SIGNAL_DEBUG:-0}"

# ===== State Tracking =====

# Array of child PIDs to terminate on shutdown
declare -g -a _CHILD_PIDS=()

# Array of cleanup functions to call on shutdown
declare -g -a _CLEANUP_HANDLERS=()

# Current operation context for logging
declare -g _CURRENT_OPERATION=""

# Flag to prevent recursive signal handling
declare -g _SHUTDOWN_IN_PROGRESS=0

# ===== Signal Handlers =====

# Main signal handler - orchestrates graceful shutdown
# Called on INT (Ctrl+C), TERM, and optionally on ERR
_signal_handler() {
  local signal="$1"
  
  # Prevent recursive calls
  if [ "$_SHUTDOWN_IN_PROGRESS" = "1" ]; then
    [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] ignoring nested $signal (shutdown in progress)" >&2
    return
  fi
  _SHUTDOWN_IN_PROGRESS=1
  
  echo "" >&2  # New line after ^C
  
  if [ -n "$_CURRENT_OPERATION" ]; then
    log warn "interrupted during: $_CURRENT_OPERATION"
  else
    log warn "received signal: $signal"
  fi
  
  # Step 1: Terminate child processes gracefully
  _terminate_children
  
  # Step 2: Run cleanup handlers (locks, temp files, etc.)
  _run_cleanup_handlers
  
  # Step 3: Exit with appropriate code
  case "$signal" in
    INT)  exit 130 ;;  # 128 + 2 (SIGINT)
    TERM) exit 143 ;;  # 128 + 15 (SIGTERM)
    *)    exit 1 ;;
  esac
}

# Terminate all tracked child processes
_terminate_children() {
  if [ ${#_CHILD_PIDS[@]} -eq 0 ]; then
    [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] no child processes to terminate" >&2
    return
  fi
  
  [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] terminating ${#_CHILD_PIDS[@]} child process(es)" >&2
  
  # First pass: send SIGTERM to all children
  for pid in "${_CHILD_PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] sending SIGTERM to PID $pid" >&2
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  
  # Wait for graceful shutdown (with timeout)
  local waited=0
  while [ $waited -lt "$GRACEFUL_SHUTDOWN_TIMEOUT" ]; do
    local still_running=0
    for pid in "${_CHILD_PIDS[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        still_running=1
        break
      fi
    done
    
    [ $still_running -eq 0 ] && break
    
    sleep 1
    waited=$((waited + 1))
    [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] waiting for children to terminate ($waited/${GRACEFUL_SHUTDOWN_TIMEOUT}s)" >&2
  done
  
  # Second pass: force kill any remaining processes
  for pid in "${_CHILD_PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      log warn "force killing stuck process: PID $pid"
      kill -KILL "$pid" 2>/dev/null || true
      
      # Also try to kill the process group
      kill -KILL -- "-$pid" 2>/dev/null || true
    fi
  done
  
  # Clean up PID list
  _CHILD_PIDS=()
}

# Run all registered cleanup handlers
_run_cleanup_handlers() {
  if [ ${#_CLEANUP_HANDLERS[@]} -eq 0 ]; then
    [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] no cleanup handlers registered" >&2
    return
  fi
  
  [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] running ${#_CLEANUP_HANDLERS[@]} cleanup handler(s)" >&2
  
  # Run handlers in reverse order (LIFO)
  local i
  for ((i=${#_CLEANUP_HANDLERS[@]}-1; i>=0; i--)); do
    local handler="${_CLEANUP_HANDLERS[$i]}"
    [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] running cleanup: $handler" >&2
    
    # Run handler safely: split into command and args, call directly
    local -a parts=()
    read -ra parts <<< "$handler"
    if [ ${#parts[@]} -gt 0 ] && declare -f "${parts[0]}" >/dev/null 2>&1; then
      "${parts[@]}" 2>/dev/null || true
    elif [ ${#parts[@]} -gt 0 ] && command -v "${parts[0]}" >/dev/null 2>&1; then
      "${parts[@]}" 2>/dev/null || true
    else
      [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] skipping unknown handler: ${parts[0]:-empty}" >&2
    fi
  done
  
  _CLEANUP_HANDLERS=()
}

# Initialize signal handlers for graceful shutdown
# Usage: init_signal_handlers
# Call this at the start of long-running operations
init_signal_handlers() {
  trap '_signal_handler INT' INT
  trap '_signal_handler TERM' TERM
  trap '_run_cleanup_handlers' EXIT
  
  [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] handlers initialized" >&2
  return 0
}

# Register a cleanup handler (function or command to run on shutdown)
# Usage: register_cleanup_handler "command arg1 arg2"
# Example: register_cleanup_handler "release_deploy_lock my-stack"
register_cleanup_handler() {
  local handler="$1"
  _CLEANUP_HANDLERS+=("$handler")
  [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] registered cleanup: $handler" >&2
  return 0
}

# Helper: remove a file silently (for use as cleanup handler arg)
_cleanup_rm() {
  rm -f "$@" 2>/dev/null || true
}

# Set current operation context (for logging)
# Usage: set_operation_context <description>
set_operation_context() {
  _CURRENT_OPERATION="$1"
  return 0
}

# Clear operation context
clear_operation_context() {
  _CURRENT_OPERATION=""
  return 0
}

# Check if we're in shutdown mode
is_shutting_down() {
  [ "$_SHUTDOWN_IN_PROGRESS" = "1" ]
}

# Reset shutdown state (for testing or nested operations)
reset_shutdown_state() {
  _SHUTDOWN_IN_PROGRESS=0
  _CHILD_PIDS=()
  _CLEANUP_HANDLERS=()
  _CURRENT_OPERATION=""
}
