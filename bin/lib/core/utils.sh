#!/usr/bin/env bash
# General utilities: ensure_cmd, run_with_timeout, safe_load_env

ensure_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

# Centralized Python command discovery (python3 preferred, fallback to python)
# Usage: get_python_cmd
# Returns: python command name or empty string
get_python_cmd() {
  if command -v python3 >/dev/null 2>&1; then
    echo "python3"
  elif command -v python >/dev/null 2>&1; then
    echo "python"
  else
    echo ""
  fi
}

# Run command with timeout
run_with_timeout() {
  local timeout_sec="${TIMEOUT_SECONDS:-900}"
  
  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_sec" "$@" || {
      local rc=$?
      if [ $rc -eq 124 ]; then
        log error "operation timed out after ${timeout_sec}s"
        return 4  # timeout exit code
      fi
      return $rc
    }
  else
    # Fallback if timeout command not available
    "$@"
  fi
}

# Safe variable interpolation (no eval, no code execution)
# Expands ${VAR} and $VAR references in value. Use instead of eval for user-controlled input.
# Usage: safe_interpolate <value>
# Output: interpolated value to stdout
safe_interpolate() {
  local value="$1"
  local max_depth=20
  local depth=0
  # Strip surrounding quotes from value (single or double)
  if [[ "$value" =~ ^\"(.*)\"$ ]]; then
    value="${BASH_REMATCH[1]}"
  elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
    value="${BASH_REMATCH[1]}"
  fi
  # Expand ${VAR} references safely
  depth=0
  while [[ "$value" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
    if [ $((depth++)) -ge $max_depth ]; then
      log warn "variable expansion depth exceeded (possible circular reference)"
      break
    fi
    local var_name="${BASH_REMATCH[1]}"
    local var_value="${!var_name}"
    value="${value/\$\{$var_name\}/$var_value}"
  done
  # Expand $VAR references (without braces)
  depth=0
  while [[ "$value" =~ \$([A-Za-z_][A-Za-z0-9_]*) ]]; do
    if [ $((depth++)) -ge $max_depth ]; then
      log warn "variable expansion depth exceeded (possible circular reference)"
      break
    fi
    local var_name="${BASH_REMATCH[1]}"
    local var_value="${!var_name}"
    value="${value/\$$var_name/$var_value}"
  done
  echo "$value"
}

# Safe loading of .env files (prevents code execution)
# Supports variable expansion: ${VAR} and $VAR references are resolved
safe_load_env() {
  local file="$1"
  [ -f "$file" ] || return 0
  
  while IFS= read -r line; do
    # Strip leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" ]] && continue
    
    # Strip optional 'export ' prefix (handles multiple spaces/tabs)
    if [[ "$line" =~ ^export[[:space:]]+(.+)$ ]]; then
      line="${BASH_REMATCH[1]}"
    fi
    
    # Parse KEY=VALUE format (alphanumeric + underscore keys)
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"
      
      # Strip surrounding quotes from value (single or double)
      if [[ "$value" =~ ^\"(.*)\"$ ]]; then
        value="${BASH_REMATCH[1]}"
      elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
        value="${BASH_REMATCH[1]}"
      fi
      
      # Expand ${VAR} references safely (no eval, no code execution)
      local depth=0
      while [[ "$value" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
        if [ $((depth++)) -ge 20 ]; then
          log warn "variable expansion depth exceeded in $file (possible circular reference for key $key)"
          break
        fi
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${!var_name}"
        value="${value/\$\{$var_name\}/$var_value}"
      done
      
      # Expand $VAR references (without braces)
      depth=0
      while [[ "$value" =~ \$([A-Za-z_][A-Za-z0-9_]*) ]]; do
        if [ $((depth++)) -ge 20 ]; then
          log warn "variable expansion depth exceeded in $file (possible circular reference for key $key)"
          break
        fi
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${!var_name}"
        value="${value/\$$var_name/$var_value}"
      done
      
      export "$key=$value"
    else
      log warn "skipping invalid line in $file: $line"
    fi
  done < "$file"
}
