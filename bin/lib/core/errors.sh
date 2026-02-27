#!/usr/bin/env bash
# Error handling: fail, add_error, print_errors

# Error accumulation for JSON output
declare -g -a ERROR_STACK=()

add_error() {
  local error_msg="$1"
  ERROR_STACK+=("$error_msg")
  
  # Update JSON field for log_json (jq ensures safe escaping)
  ERRORS_ACCUMULATED="$(printf '%s\0' "${ERROR_STACK[@]}" | jq -Rs 'split("\u0000") | map(select(length > 0))')"
  export ERRORS_ACCUMULATED
}

clear_errors() {
  ERROR_STACK=()
  export ERRORS_ACCUMULATED="[]"
}

# Print accumulated errors
# Usage: print_errors
print_errors() {
  if [ ${#ERROR_STACK[@]} -eq 0 ]; then
    return
  fi
  
  # In JSON mode, errors are already included in ERRORS_ACCUMULATED
  if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
    return
  fi
  
  # Skip in quiet mode
  [ "$QUIET" = "1" ] && return
  
  # Print each error
  for err in "${ERROR_STACK[@]}"; do
    printf "   %s %s\n" "$(icon error)" "$(c 31 "$err")"
  done
}
