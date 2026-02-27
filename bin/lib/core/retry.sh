#!/usr/bin/env bash
# Retry utilities: retry_with_backoff

# Retry wrapper with exponential backoff and jitter
# Usage: retry_with_backoff <command> [args...]
# Returns: exit code of command (0 on success, original code on failure)
# 
# Configuration via environment variables:
#   RETRY_MAX_ATTEMPTS - max retry attempts (default: 3)
#   RETRY_INITIAL_DELAY - initial delay in seconds (default: 2)
#   RETRY_MAX_DELAY - maximum delay in seconds (default: 30)
#   RETRY_ENABLED - enable/disable retry (default: 1)
retry_with_backoff() {
  # Allow disabling retry for CI/CD or testing
  if [ "${RETRY_ENABLED:-1}" != "1" ]; then
    "$@"
    return $?
  fi
  
  local max_attempts="${RETRY_MAX_ATTEMPTS:-3}"
  local delay="${RETRY_INITIAL_DELAY:-2}"
  local max_delay="${RETRY_MAX_DELAY:-30}"
  local attempt=1
  
  while [ $attempt -le $max_attempts ]; do
    # Run command and capture exit code
    if "$@"; then
      # Success on first attempt - no log needed
      [ $attempt -eq 1 ] || log ok "operation succeeded on attempt $attempt/$max_attempts"
      return 0
    fi
    
    local rc=$?
    
    # If this was the last attempt, fail
    if [ $attempt -eq $max_attempts ]; then
      log error "operation failed after $max_attempts attempts"
      return $rc
    fi
    
    # Calculate jitter: random value between 0 and 5 seconds
    local jitter=$((RANDOM % 6))
    local sleep_time=$((delay + jitter))
    
    log warn "attempt $attempt/$max_attempts failed (exit code: $rc), retrying in ${sleep_time}s..."
    sleep $sleep_time
    
    # Exponential backoff: double the delay
    delay=$((delay * 2))
    [ $delay -gt $max_delay ] && delay=$max_delay
    
    attempt=$((attempt + 1))
  done
  
  # Should not reach here, but return error just in case
  return 1
}
