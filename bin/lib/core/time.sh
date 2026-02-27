#!/usr/bin/env bash
# Time utilities: now_ms, now_iso, record_step_time, print_deploy_summary

# Portable millisecond timestamp (macOS lacks date +%s%N)
now_ms() {
  if date +%s%N >/dev/null 2>&1 && [ "$(date +%s%N)" != "%s%N" ]; then
    echo $(( $(date +%s%N) / 1000000 ))
  else
    echo $(( $(date +%s) * 1000 ))
  fi
}

# ============================================
# Step Time Tracking for Deploy Summary
# ============================================

# Global associative array for step times
declare -g -A STEP_TIMES

# Record step time
# Usage: record_step_time <step_name> <duration_seconds>
record_step_time() {
  local step_name="$1"
  local duration="$2"
  STEP_TIMES["$step_name"]="$duration"
}

# Get recorded step time
# Usage: get_step_time <step_name>
get_step_time() {
  local step_name="$1"
  echo "${STEP_TIMES[$step_name]:-0}"
}

# Clear all step times
clear_step_times() {
  STEP_TIMES=()
}

# Print detailed deployment summary
# Usage: print_deploy_summary <stack> <status> <duration> <updated_services>
# Reads step times from global STEP_TIMES array
print_deploy_summary() {
  local stack="$1" status="$2" duration="$3" updated_services="$4"
  
  # JSON mode - compact output (jq ensures safe escaping)
  if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
    local step_times_json
    step_times_json=$(for step in "${!STEP_TIMES[@]}"; do
      jq -n -c --arg k "$step" --argjson v "${STEP_TIMES[$step]}" '{($k): $v}'
    done | jq -s 'add')
    [ "$step_times_json" = "null" ] && step_times_json="{}"
    jq -n \
      --arg event "deploy_complete" \
      --arg stack "$stack" \
      --arg status "$status" \
      --argjson duration "$duration" \
      --argjson services "$updated_services" \
      --argjson step_times "$step_times_json" \
      '{event: $event, stack: $stack, status: $status, duration: $duration, services: $services, step_times: $step_times}'
    return
  fi
  
  # Skip in quiet mode
  [ "$QUIET" = "1" ] && return
  
  # Verbose mode - simple summary
  if [ "$VERBOSE" = "1" ]; then
    printf "\n"
    printf "   %s %s\n" "$(icon done)" "$(c 32 "Deploy completed successfully")"
    printf "   ├─ Stack: %s\n" "$stack"
    printf "   ├─ Services: %s\n" "$updated_services"
    printf "   └─ Time: %ss\n" "$duration"
    return
  fi
  
  # Default mode - structured box output
  printf "\n"
  printf "╔════════════════════════════════════════════════════════════════╗\n"
  if [ "$status" = "success" ]; then
    printf "║                    DEPLOYMENT SUCCESSFUL                       ║\n"
  else
    printf "║                      DEPLOYMENT %s                       ║\n" "$(printf '%-10s' "$status")"
  fi
  printf "╚════════════════════════════════════════════════════════════════╝\n"
  printf "\n"
  printf "  $(c 1 "Summary:")\n"
  printf "    Stack:    %s\n" "$stack"
  printf "    Profile:  %s\n" "${ACTIVE_PROFILE}"
  printf "    Services: %s deployed\n" "$updated_services"
  printf "    Total:    %ds\n" "$duration"
  printf "\n"
  
  # Show timeline if we have step times
  if [ ${#STEP_TIMES[@]} -gt 0 ]; then
    printf "  $(c 1 "Timeline:")\n"
    
    # Display steps in logical order
    local step_names=("validate" "secrets" "sync" "build" "templates" "deploy" "verify")
    for step in "${step_names[@]}"; do
      if [ -n "${STEP_TIMES[$step]:-}" ] && [ "${STEP_TIMES[$step]}" -gt 0 ]; then
        printf "    %-10s %3ds\n" "$step:" "${STEP_TIMES[$step]}"
      fi
    done
    printf "\n"
  fi
}
