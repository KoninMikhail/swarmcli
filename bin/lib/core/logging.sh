#!/usr/bin/env bash
# Logging utilities: log, log_json, log_section

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ===== Execution Context Detection =====
# Determines how the script is being run (ADR-0017)
#
# Contexts:
#   ci          - Running in CI system (GitLab, GitHub, etc.)
#   interactive - User at terminal (stdin/stdout are TTY)
#   script      - Automation (cron, pipe, etc.)
#
# Note: Context detection is informational only.
# Output format is controlled by --verbose flag, not by context.

detect_exec_context() {
  # CI systems set CI=true (GitLab, GitHub, Travis, CircleCI, etc.)
  if [ "${CI:-}" = "true" ] || [ -n "${GITLAB_CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "ci"
  # Interactive terminal (user at keyboard)
  elif [ -t 0 ] && [ -t 1 ]; then
    echo "interactive"
  # Script/automation (cron, pipe, etc.)
  else
    echo "script"
  fi
}

# Set once at startup (can be overridden via env var)
EXEC_CONTEXT="${EXEC_CONTEXT:-$(detect_exec_context)}"
export EXEC_CONTEXT

# Helper functions for context checks
is_ci() { [ "$EXEC_CONTEXT" = "ci" ]; }
is_interactive() { [ "$EXEC_CONTEXT" = "interactive" ]; }
is_script() { [ "$EXEC_CONTEXT" = "script" ]; }

# Check if verbose mode is enabled
# Verbose mode disables tree-style output and shows plain CLI logs
is_verbose() { [ "$VERBOSE" = "1" ]; }

# JSON-structured logging for n8n integration (jq ensures safe escaping)
log_json() {
  local level="$1"; shift
  local msg="$*"
  local extra_fields="${LOG_EXTRA_JSON:-}"
  local out_fd=1
  [ "$level" = "warn" ] || [ "$level" = "error" ] && out_fd=2
  
  if [ -n "$extra_fields" ]; then
    local base_json
    base_json=$(jq -n --arg ts "$(now_iso)" --arg level "$level" --arg msg "$msg" '{ts: $ts, level: $level, msg: $msg}')
    echo "$base_json" | jq --argjson extra "{$extra_fields}" '. + $extra' 2>/dev/null >&$out_fd || \
      echo "$base_json" >&$out_fd
  else
    jq -n \
      --arg ts "$(now_iso)" \
      --arg level "$level" \
      --arg msg "$msg" \
      '{ts: $ts, level: $level, msg: $msg}' >&$out_fd
  fi
}

log() {
  local level="$1"; shift
  local msg="$*"
  
  # JSON mode for automation
  if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
    # Skip detail logs in JSON mode (they're verbose)
    [ "$level" = "detail" ] && return
    log_json "$level" "$msg"
    return
  fi
  
  # Skip detail logs unless verbose mode is enabled
  [ "$level" = "detail" ] && [ "$VERBOSE" != "1" ] && return
  
  # Skip info logs in quiet mode
  [ "$QUIET" = "1" ] && [ "$level" = "info" ] && return
  
  # Pretty console output
  local col="0"
  case "$level" in
    detail) col="90";;  # gray (less prominent)
    info)   col="34";;  # blue
    warn)   col="33";;  # yellow
    error)  col="31";;  # red
    ok)     col="32";;  # green
  esac
  
  # For detail level, display as [info] but with gray color
  local display_level="$level"
  [ "$level" = "detail" ] && display_level="info"
  
  # warn and error go to stderr so logs don't mix with piped data
  if [ "$level" = "warn" ] || [ "$level" = "error" ]; then
    printf "%s %s %s\n" "$(c 90 "$(now_iso)")" "$(c "$col" "[$display_level]")" "$msg" >&2
  else
    printf "%s %s %s\n" "$(c 90 "$(now_iso)")" "$(c "$col" "[$display_level]")" "$msg"
  fi
}

fail() {
  log error "$*"
  exit 1
}

# Section header for deploy stages
# Usage: log_section <icon_name> <title>
log_section() {
  local icon_name="$1"
  local title="$2"
  
  # JSON mode
  if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
    log_json "info" "$title"
    return
  fi
  
  # Skip in quiet mode
  [ "$QUIET" = "1" ] && return
  
  printf "\n%s %s\n" "$(icon "$icon_name")" "$(c 1 "$title")"
}

# Section result
# Usage: log_section_result <ok|error> <message>
log_section_result() {
  local status="$1"
  local msg="$2"
  
  if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
    log_json "$status" "$msg"
    return
  fi
  
  [ "$QUIET" = "1" ] && return
  
  if [ "$status" = "ok" ]; then
    printf "   %s %s\n" "$(icon done)" "$(c 32 "$msg")"
  else
    printf "   %s %s\n" "$(icon fail)" "$(c 31 "$msg")"
  fi
}
