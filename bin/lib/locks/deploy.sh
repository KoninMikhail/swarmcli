#!/usr/bin/env bash
# Deployment locks: acquire_deploy_lock, release_deploy_lock

# Acquire deployment lock for stack+profile combination
# Usage: acquire_deploy_lock <stack>
# Returns: 0 on success, 1 on failure
acquire_deploy_lock() {
  local stack="$1"
  local lock_timeout="${LOCK_TIMEOUT:-3600}"  # Default: 1 hour (consistent with swarm.sh)
  local lock_dir="${LOCKS_DIR:-$PLATFORM_ROOT/.locks}"
  local lock_file="$lock_dir/${ACTIVE_PROFILE}_${stack}.lock"
  
  if ! mkdir -p "$lock_dir" 2>/dev/null; then
    add_error "failed to create lock directory: $lock_dir"
    return 1
  fi
  
  # Try to create lock directory atomically
  if ! mkdir "$lock_file" 2>/dev/null; then
    # Lock exists, check if it's stale
    if [ -f "$lock_file/timestamp" ]; then
      local lock_ts
      lock_ts=$(cat "$lock_file/timestamp" 2>/dev/null || echo 0)
      local now_ts
      now_ts=$(date +%s)
      local lock_age=$((now_ts - lock_ts))
      
      # Check if process is still running
      local lock_pid
      lock_pid=$(cat "$lock_file/pid" 2>/dev/null || echo "")
      local process_alive=0
      
      if [ -n "$lock_pid" ]; then
        # Check if PID is still alive
        if kill -0 "$lock_pid" 2>/dev/null; then
          process_alive=1
        fi
      fi
      
      # Lock is stale if: timeout exceeded OR process is not alive
      if [ $lock_age -gt $lock_timeout ] || [ $process_alive -eq 0 ]; then
        if [ $process_alive -eq 0 ]; then
          log warn "stale lock detected (process $lock_pid not running)"
        else
          log warn "stale lock detected (age: ${lock_age}s > ${lock_timeout}s)"
        fi
        
        # Show stale lock info
        if [ -f "$lock_file/pid" ]; then
          local stale_pid
          stale_pid=$(cat "$lock_file/pid" 2>/dev/null)
          log warn "stale lock was held by PID: $stale_pid"
        fi
        
        # Atomic lock replacement: rename stale → old, create new, remove old
        local old_lock="${lock_file}.old.$$"
        if mv "$lock_file" "$old_lock" 2>/dev/null; then
          if mkdir "$lock_file" 2>/dev/null; then
            rm -rf "$old_lock" 2>/dev/null
            echo $$ > "$lock_file/pid"
            date +%s > "$lock_file/timestamp"
            echo "$stack" > "$lock_file/stack"
            echo "$ACTIVE_PROFILE" > "$lock_file/profile"
            echo "$USER" > "$lock_file/user"
            log detail "acquired deployment lock for $stack (profile: $ACTIVE_PROFILE)"
            log detail "lock file: $lock_file"
            return 0
          fi
          mv "$old_lock" "$lock_file" 2>/dev/null || true
        fi
        add_error "failed to acquire lock after removing stale lock"
        return 1
      else
        # Active lock exists with alive process
        local lock_pid lock_ts_human
        lock_pid=$(cat "$lock_file/pid" 2>/dev/null || echo "unknown")
        lock_ts_human=$(date -d "@$lock_ts" 2>/dev/null || echo "unknown")
        
        add_error "another deployment is in progress for $stack (profile: $ACTIVE_PROFILE)"
        log error "lock is held by PID $lock_pid since $lock_ts_human"
        log error "lock age: ${lock_age}s (timeout: ${lock_timeout}s)"
        log info "if this is a stuck lock, remove it manually: rm -rf \"$lock_file\""
        log info "or set LOCK_TIMEOUT to a lower value"
        
        return 1
      fi
    else
      # Lock exists but no timestamp - corrupted lock
      log warn "corrupted lock detected (no timestamp)"
      
      # Atomic lock replacement for corrupted lock
      local old_lock="${lock_file}.old.$$"
      if mv "$lock_file" "$old_lock" 2>/dev/null; then
        if mkdir "$lock_file" 2>/dev/null; then
          rm -rf "$old_lock" 2>/dev/null
          echo $$ > "$lock_file/pid"
          date +%s > "$lock_file/timestamp"
          echo "$stack" > "$lock_file/stack"
          echo "$ACTIVE_PROFILE" > "$lock_file/profile"
          echo "$USER" > "$lock_file/user"
          log detail "acquired deployment lock for $stack (profile: $ACTIVE_PROFILE)"
          log detail "lock file: $lock_file"
          return 0
        fi
        mv "$old_lock" "$lock_file" 2>/dev/null || true
      fi
      add_error "failed to acquire lock after removing corrupted lock"
      return 1
    fi
  fi
  
  # Lock acquired - save metadata
  echo $$ > "$lock_file/pid"
  date +%s > "$lock_file/timestamp"
  echo "$stack" > "$lock_file/stack"
  echo "$ACTIVE_PROFILE" > "$lock_file/profile"
  echo "$USER" > "$lock_file/user"
  
  log detail "acquired deployment lock for $stack (profile: $ACTIVE_PROFILE)"
  log detail "lock file: $lock_file"
  
  return 0
}

# Release deployment lock
# Usage: release_deploy_lock <stack>
release_deploy_lock() {
  local stack="$1"
  local lock_dir="${LOCKS_DIR:-$PLATFORM_ROOT/.locks}"
  local lock_file="$lock_dir/${ACTIVE_PROFILE}_${stack}.lock"
  
  if [ -d "$lock_file" ]; then
    # Verify we own this lock
    if [ -f "$lock_file/pid" ]; then
      local lock_pid
      lock_pid=$(cat "$lock_file/pid" 2>/dev/null)
      
      if [ "$lock_pid" != "$$" ]; then
        log warn "lock was held by PID $lock_pid, but we are $$"
      fi
    fi
    
    rm -rf "$lock_file" 2>/dev/null || true
    log detail "released deployment lock for $stack (profile: $ACTIVE_PROFILE)"
  fi
}

# Force release deployment lock (for emergency use)
# Usage: force_release_deploy_lock <stack>
force_release_deploy_lock() {
  local stack="$1"
  local lock_dir="${LOCKS_DIR:-$PLATFORM_ROOT/.locks}"
  local lock_file="$lock_dir/${ACTIVE_PROFILE}_${stack}.lock"
  
  if [ -d "$lock_file" ]; then
    log warn "force releasing lock for $stack (profile: $ACTIVE_PROFILE)"
    
    # Log lock info before removing
    if [ -f "$lock_file/pid" ]; then
      local lock_pid
      lock_pid=$(cat "$lock_file/pid" 2>/dev/null || echo "unknown")
      log warn "lock was held by PID: $lock_pid"
    fi
    
    rm -rf "$lock_file"
    log ok "lock forcefully released"
  else
    log info "no lock exists for $stack (profile: $ACTIVE_PROFILE)"
  fi
}

# List all active locks
# Usage: list_active_locks
list_active_locks() {
  local lock_dir="${LOCKS_DIR:-$PLATFORM_ROOT/.locks}"
  
  if [ ! -d "$lock_dir" ]; then
    log info "no locks directory found"
    return 0
  fi
  
  local found=0
  for lock_file in "$lock_dir"/*.lock; do
    [ -d "$lock_file" ] || continue
    
    found=1
    local stack profile pid timestamp user
    stack=$(cat "$lock_file/stack" 2>/dev/null || echo "unknown")
    profile=$(cat "$lock_file/profile" 2>/dev/null || echo "unknown")
    pid=$(cat "$lock_file/pid" 2>/dev/null || echo "unknown")
    timestamp=$(cat "$lock_file/timestamp" 2>/dev/null || echo "0")
    user=$(cat "$lock_file/user" 2>/dev/null || echo "unknown")
    
    local age_s=$(($(date +%s) - timestamp))
    local age_human
    if [ $age_s -lt 60 ]; then
      age_human="${age_s}s"
    elif [ $age_s -lt 3600 ]; then
      age_human="$((age_s / 60))m"
    else
      age_human="$((age_s / 3600))h"
    fi
    
    # Check if process is still running
    local status="active"
    if ! kill -0 "$pid" 2>/dev/null; then
      status="stale (process not running)"
    fi
    
    # Check if cancellation was requested
    local cancel_info=""
    if [ -f "$lock_file/cancel" ]; then
      local cancel_reason
      cancel_reason=$(cat "$lock_file/cancel_reason" 2>/dev/null || echo "unknown")
      cancel_info="cancellation requested ($cancel_reason)"
      status="cancelling"
    fi
    
    # Get current step info
    local step_num step_total step_name step_info=""
    if [ -f "$lock_file/step_num" ]; then
      step_num=$(cat "$lock_file/step_num" 2>/dev/null || echo "0")
      step_total=$(cat "$lock_file/step_total" 2>/dev/null || echo "0")
      step_name=$(cat "$lock_file/step_name" 2>/dev/null || echo "unknown")
      step_info="${step_num}/${step_total}: ${step_name}"
    fi
    
    if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
      local lock_json
      lock_json=$(jq -n \
        --arg stack "$stack" \
        --arg profile "$profile" \
        --argjson pid "$pid" \
        --arg user "$user" \
        --argjson age "$age_s" \
        --arg status "$status" \
        '{stack: $stack, profile: $profile, pid: $pid, user: $user, age: $age, status: $status}')
      if [ -n "$step_info" ]; then
        lock_json=$(echo "$lock_json" | jq \
          --argjson step_num "$step_num" \
          --argjson step_total "$step_total" \
          --arg step_name "$step_name" \
          '. + {step_num: $step_num, step_total: $step_total, step_name: $step_name}')
      fi
      if [ -n "$cancel_info" ]; then
        local cancel_reason
        cancel_reason=$(cat "$lock_file/cancel_reason" 2>/dev/null || echo "unknown")
        lock_json=$(echo "$lock_json" | jq \
          --arg cancel_reason "$cancel_reason" \
          '. + {cancel_requested: true, cancel_reason: $cancel_reason}')
      fi
      echo "$lock_json"
    else
      printf "Lock: %s/%s\n" "$profile" "$stack"
      printf "  PID: %s\n" "$pid"
      printf "  User: %s\n" "$user"
      printf "  Age: %s\n" "$age_human"
      printf "  Status: %s\n" "$status"
      if [ -n "$step_info" ]; then
        printf "  Step: %s\n" "$step_info"
      fi
      if [ -n "$cancel_info" ]; then
        printf "  Cancel: %s\n" "$cancel_info"
      fi
      printf "  Path: %s\n\n" "$lock_file"
    fi
  done
  
  if [ $found -eq 0 ]; then
    log info "no active locks"
  fi
}

# Cleanup stale locks (for maintenance)
# Usage: cleanup_stale_locks
cleanup_stale_locks() {
  local lock_dir="${LOCKS_DIR:-$PLATFORM_ROOT/.locks}"
  local lock_timeout="${LOCK_TIMEOUT:-3600}"
  local now_ts
  now_ts=$(date +%s)
  local cleaned=0
  
  if [ ! -d "$lock_dir" ]; then
    log info "no locks directory found"
    return 0
  fi
  
  for lock_file in "$lock_dir"/*.lock; do
    [ -d "$lock_file" ] || continue
    
    local timestamp
    timestamp=$(cat "$lock_file/timestamp" 2>/dev/null || echo 0)
    local age=$((now_ts - timestamp))
    
    if [ $age -gt $lock_timeout ]; then
      local stack profile pid
      stack=$(cat "$lock_file/stack" 2>/dev/null || echo "unknown")
      profile=$(cat "$lock_file/profile" 2>/dev/null || echo "unknown")
      pid=$(cat "$lock_file/pid" 2>/dev/null || echo "unknown")
      
      log warn "removing stale lock: $profile/$stack (age: ${age}s, PID: $pid)"
      rm -rf "$lock_file"
      cleaned=$((cleaned + 1))
    fi
  done
  
  if [ $cleaned -gt 0 ]; then
    log ok "cleaned $cleaned stale lock(s)"
  else
    log info "no stale locks found"
  fi
}
