#!/usr/bin/env bash
# Output utilities: icon, c, with_spinner, output_result

# --- Pretty output utilities ---
COLOR=1
[ -t 1 ] || COLOR=0
[ -n "${NO_COLOR:-}" ] && COLOR=0

c() { 
  if [ "$COLOR" = "1" ]; then 
    printf "\033[%sm%s\033[0m" "$1" "$2"
  else 
    printf "%s" "$2"
  fi
}

icon() { 
  case "$1" in 
    info) printf "ℹ";;
    warn) printf "⚠";;
    error) printf "✖";;
    ok) printf "✓";;
    deploy) printf "🚀";;
    build) printf "🔨";;
    validate) printf "🔍";;
    sync) printf "🔄";;
    secret) printf "🔐";;
    done) printf "✅";;
    fail) printf "❌";;
    *) printf "•";;
  esac
}

# Enhanced spinner with error output capture and child process tracking
with_spinner() {
  local title="$1"; shift
  
  # Skip spinner for non-interactive or verbose mode
  if [ "$VERBOSE" = "1" ] || [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ] || [ "$QUIET" = "1" ] || [ ! -t 1 ]; then
    "$@"
    return $?
  fi
  
  local tmplog
  tmplog=$(mktemp)
  local pid spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
  
  # Run command in background, capture output
  ( "$@" ) > "$tmplog" 2>&1 & pid=$!
  
  # Register child PID for graceful shutdown (if signals.sh is loaded)
  if declare -f register_child_pid >/dev/null 2>&1; then
    register_child_pid "$pid"
  fi
  
  printf "%s %s" "$(icon info)" "$title"
  while kill -0 $pid 2>/dev/null; do
    i=$(( (i+1) % 10 ))
    printf "\r%s %s %s" "$(icon info)" "$title" "${spin:$i:1}"
    sleep 0.08 2>/dev/null || sleep 1
  done
  
  wait $pid
  local rc=$?
  printf "\r"
  
  # Unregister child PID
  if declare -f unregister_child_pid >/dev/null 2>&1; then
    unregister_child_pid "$pid"
  fi
  
  if [ $rc -eq 0 ]; then
    printf "%s %s\n" "$(c 32 "$(icon ok)")" "$title"
  else
    printf "%s %s\n" "$(c 31 "$(icon error)")" "$title"
    # Show error output
    if [ -s "$tmplog" ]; then
      echo "$(c 90 "─── Error output ───")"
      tail -n 20 "$tmplog" | sed 's/^/  /'
      echo "$(c 90 "────────────────────")"
    fi
  fi
  
  rm -f "$tmplog"
  return $rc
}

# Enhanced result output for n8n
output_result() {
  local status="$1"      # success | error | warning
  local command="$2"     # command name
  local duration_ms="$3" # duration in milliseconds
  shift 3
  local details="$*"     # additional details
  
  if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
    jq -n \
      --arg status "$status" \
      --arg command "$command" \
      --argjson durationMs "$duration_ms" \
      --arg details "$details" \
      --argjson errors "${ERRORS_ACCUMULATED:-[]}" \
      '{status: $status, command: $command, durationMs: $durationMs, details: $details, errors: $errors}'
  else
    case "$status" in
      success) log ok "$command completed in ${duration_ms}ms: $details" ;;
      error)   log error "$command failed after ${duration_ms}ms: $details" ;;
      warning) log warn "$command completed with warnings in ${duration_ms}ms: $details" ;;
    esac
  fi
}
