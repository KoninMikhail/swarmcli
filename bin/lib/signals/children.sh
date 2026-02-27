#!/usr/bin/env bash
# Child process tracking: register_child_pid, unregister_child_pid

# Register a child PID for termination on shutdown
# Usage: register_child_pid <pid>
register_child_pid() {
  local pid="$1"
  _CHILD_PIDS+=("$pid")
  [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] registered child PID: $pid" >&2
  return 0
}

# Unregister a child PID (call when process completes normally)
# Usage: unregister_child_pid <pid>
unregister_child_pid() {
  local pid="$1"
  local new_pids=()
  
  for p in "${_CHILD_PIDS[@]}"; do
    [ "$p" != "$pid" ] && new_pids+=("$p")
  done
  
  _CHILD_PIDS=("${new_pids[@]}")
  [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] unregistered child PID: $pid" >&2
  return 0
}

# Run command with signal-aware child tracking
# Usage: run_tracked <command> [args...]
# Returns: exit code of command
run_tracked() {
  local cmd="$1"
  shift
  
  # Run in background and track
  "$cmd" "$@" &
  local pid=$!
  register_child_pid "$pid"
  
  # Wait and capture exit code
  wait "$pid" 2>/dev/null
  local rc=$?
  
  unregister_child_pid "$pid"
  return $rc
}

# ===== Process Group Management =====

# Enable job control for process group management
# Call at script start if using process groups
enable_process_groups() {
  set -m
  [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] job control enabled (set -m)" >&2
  return 0
}

# Kill entire process group on shutdown
# Usage: kill_process_group
kill_process_group() {
  local pgid
  pgid=$(ps -o pgid= $$ 2>/dev/null | tr -d ' ')
  
  if [ -n "$pgid" ]; then
    [ "$SIGNAL_DEBUG" = "1" ] && echo "[signal] killing process group: $pgid" >&2
    kill -TERM -- "-$pgid" 2>/dev/null || true
  fi
}
