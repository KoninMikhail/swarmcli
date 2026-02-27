#!/usr/bin/env bash
# Timeout utilities: run_with_graceful_timeout

# Run command with timeout and graceful shutdown support
# Usage: run_with_graceful_timeout <timeout_seconds> <command> [args...]
# Returns: 0 on success, 124 on timeout, command exit code on failure
run_with_graceful_timeout() {
  local timeout_sec="$1"
  shift
  
  # Start command in background
  "$@" &
  local pid=$!
  register_child_pid "$pid"
  
  # Start timeout watcher in background
  (
    sleep "$timeout_sec"
    if kill -0 "$pid" 2>/dev/null; then
      log warn "operation timed out after ${timeout_sec}s, sending SIGTERM"
      kill -TERM "$pid" 2>/dev/null
      sleep 5
      if kill -0 "$pid" 2>/dev/null; then
        log warn "process still running, sending SIGKILL"
        kill -KILL "$pid" 2>/dev/null
      fi
    fi
  ) &
  local watcher_pid=$!
  
  # Wait for main command
  wait "$pid" 2>/dev/null
  local rc=$?
  
  # Kill watcher if still running
  kill "$watcher_pid" 2>/dev/null || true
  wait "$watcher_pid" 2>/dev/null || true
  
  unregister_child_pid "$pid"
  
  # Check if we timed out
  if [ $rc -eq 137 ] || [ $rc -eq 143 ]; then
    return 124  # Timeout exit code (like GNU timeout)
  fi
  
  return $rc
}

# Run docker build with tracking and timeout
# Usage: run_docker_build_tracked <timeout_seconds> <build_args...>
# Returns: 0 on success, 124 on timeout, build exit code on failure
run_docker_build_tracked() {
  local timeout_sec="${1:-900}"  # Default 15 minutes
  shift
  
  set_operation_context "docker build"
  
  local result
  run_with_graceful_timeout "$timeout_sec" docker build "$@"
  result=$?
  
  clear_operation_context
  
  if [ $result -eq 124 ]; then
    add_error "docker build timed out after ${timeout_sec}s"
  fi
  
  return $result
}
