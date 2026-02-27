#!/usr/bin/env bash
# Deployment cancellation: request_deploy_cancel, is_deploy_cancelled

# Request deployment cancellation
# Creates a cancel flag file in the lock directory to signal the running
# deployment process to stop gracefully.
# Usage: request_deploy_cancel <stack> [reason]
# Returns: 0 on success, 1 if no active deployment
request_deploy_cancel() {
  local stack="$1"
  local reason="${2:-user-requested}"
  local lock_dir="${LOCKS_DIR:-$PLATFORM_ROOT/.locks}"
  local lock_file="$lock_dir/${ACTIVE_PROFILE}_${stack}.lock"
  
  if [ ! -d "$lock_file" ]; then
    log warn "no active deployment to cancel for $stack"
    return 1
  fi
  
  # Create cancel flag
  touch "$lock_file/cancel"
  date +%s > "$lock_file/cancel_timestamp"
  echo "$reason" > "$lock_file/cancel_reason"
  
  local pid
  pid=$(cat "$lock_file/pid" 2>/dev/null || echo "unknown")
  
  log warn "cancellation requested for deployment: $stack (PID: $pid, reason: $reason)"
  
  # Also send SIGTERM to the process as a hint
  if [ "$pid" != "unknown" ] && [ -n "$pid" ]; then
    kill -TERM "$pid" 2>/dev/null || true
  fi
  
  return 0
}

# Check if deployment is cancelled
# Usage: is_deploy_cancelled <stack>
# Returns: 0 if cancelled, 1 if not
is_deploy_cancelled() {
  local stack="$1"
  local lock_dir="${LOCKS_DIR:-$PLATFORM_ROOT/.locks}"
  local lock_file="$lock_dir/${ACTIVE_PROFILE}_${stack}.lock"
  
  [ -f "$lock_file/cancel" ]
}

# Clear cancel flag
# Usage: clear_cancel_flag <stack>
clear_cancel_flag() {
  local stack="$1"
  local lock_dir="${LOCKS_DIR:-$PLATFORM_ROOT/.locks}"
  local lock_file="$lock_dir/${ACTIVE_PROFILE}_${stack}.lock"
  
  rm -f "$lock_file/cancel" "$lock_file/cancel_timestamp" "$lock_file/cancel_reason" 2>/dev/null || true
}

# Get cancel info
# Usage: get_cancel_info <stack>
# Output: timestamp|reason (empty if not cancelled)
get_cancel_info() {
  local stack="$1"
  local lock_dir="${LOCKS_DIR:-$PLATFORM_ROOT/.locks}"
  local lock_file="$lock_dir/${ACTIVE_PROFILE}_${stack}.lock"
  
  if [ -f "$lock_file/cancel" ]; then
    local timestamp reason
    timestamp=$(cat "$lock_file/cancel_timestamp" 2>/dev/null || echo "0")
    reason=$(cat "$lock_file/cancel_reason" 2>/dev/null || echo "unknown")
    echo "${timestamp}|${reason}"
  fi
}
