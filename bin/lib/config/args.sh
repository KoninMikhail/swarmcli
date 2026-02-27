#!/usr/bin/env bash
# Global argument parsing module

# ============================================================================
# Runtime flags (defaults)
# ============================================================================

export FORCE_JSON=""
export QUIET=""
export VERBOSE=""
export NO_COLOR=""
export DRY_RUN=""
export FORCE_REBUILD="${SWARM_FORCE_DEPLOY:-}"
export WITH_PULL=""
export WITH_SECRETS=""
export NO_BUILD=""
export DO_PRUNE=""
export NO_CACHE=""
export CONFIG_ONLY=""
export SINCE_REF=""
export VERIFY_IMAGE_VERSION=""
export PARALLEL_BUILD=""

# Service selection and per-service branch/commit configuration
declare -g -a SELECTED_SERVICES=()
declare -g -A SERVICE_BRANCHES=()   # SERVICE_BRANCHES[service]="branch"
declare -g -A SERVICE_COMMITS=()    # SERVICE_COMMITS[service]="commit"
export DECLARE_OVERRIDES_INITIALIZED=1  # Prevent re-initialization in ensure_overrides_vars

# Profile argument (set during parsing)
PROFILE_ARG=""

# ============================================================================
# Parse global flags
# ============================================================================

# Parse global flags from command line arguments
# Sets global variables and returns remaining positional arguments
# Usage: parse_global_args "$@"
# After call, REMAINING_ARGS array contains unparsed arguments
#
# Per-service branch/commit syntax:
#   --service NAME --branch BRANCH [--commit SHA]
#   --branch and --commit apply to the preceding --service
#   --commit requires --branch to be specified for the same service
parse_global_args() {
  REMAINING_ARGS=()
  local current_service=""
  
  while [ $# -gt 0 ]; do
    case "$1" in
      --profile)
        shift
        PROFILE_ARG="$1"
        ;;
      --json)
        FORCE_JSON="1"
        ;;
      --quiet)
        QUIET="1"
        ;;
      --no-color)
        NO_COLOR="1"
        COLOR=0
        ;;
      --verbose)
        VERBOSE="1"
        ;;
      --dry-run)
        DRY_RUN="1"
        ;;
      --service)
        shift
        current_service="$1"
        if [ -z "$current_service" ]; then
          echo "error: --service requires a service name" >&2
          exit 1
        fi
        # Service names validated against services.yaml at deploy time
        SELECTED_SERVICES+=("$current_service")
        ;;
      --branch)
        if [ -z "$current_service" ]; then
          echo "error: --branch must follow --service" >&2
          echo "usage: swarmcli deploy STACK --service NAME --branch BRANCH [--commit SHA]" >&2
          exit 1
        fi
        shift
        SERVICE_BRANCHES["$current_service"]="$1"
        ;;
      --commit)
        if [ -z "$current_service" ]; then
          echo "error: --commit must follow --service" >&2
          echo "usage: swarmcli deploy STACK --service NAME --branch BRANCH --commit SHA" >&2
          exit 1
        fi
        shift
        SERVICE_COMMITS["$current_service"]="$1"
        ;;
      --pull)
        WITH_PULL="1"
        ;;
      --force)
        FORCE_REBUILD="1"
        ;;
      --with-secrets)
        WITH_SECRETS="1"
        ;;
      --no-build)
        NO_BUILD="1"
        ;;
      --prune)
        DO_PRUNE="1"
        ;;
      --no-cache)
        NO_CACHE="1"
        ;;
      --config-only)
        CONFIG_ONLY="1"
        ;;
      --verify-images)
        VERIFY_IMAGE_VERSION="1"
        ;;
      --parallel)
        PARALLEL_BUILD="1"
        ;;
      --since)
        shift
        SINCE_REF="$1"
        ;;
      -*)
        # Unknown flag - pass to command
        REMAINING_ARGS+=("$1")
        ;;
      *)
        # Positional argument - collect remaining
        REMAINING_ARGS+=("$1")
        ;;
    esac
    shift
  done
  
  # Post-parse validation: --commit requires --branch
  validate_service_args
}

# Validate service arguments after parsing
# Ensures --commit is only used with --branch for the same service
validate_service_args() {
  local svc
  for svc in "${!SERVICE_COMMITS[@]}"; do
    if [ -z "${SERVICE_BRANCHES[$svc]:-}" ]; then
      echo "error: --commit for service '$svc' requires --branch" >&2
      echo "usage: swarmcli deploy STACK --service $svc --branch BRANCH --commit SHA" >&2
      exit 1
    fi
  done
}

# Validate that --branch and --commit are not used for external services
# This should be called after profile and stack are loaded
# Usage: validate_external_service_args <stack>
# Returns: 0 if valid, exits with 1 if errors found
validate_external_service_args() {
  local stack="$1"
  local errors=0
  
  # Check --branch for external services
  for svc in "${!SERVICE_BRANCHES[@]}"; do
    if ! is_service_internal "$stack" "$svc" 2>/dev/null; then
      echo "error: --branch cannot be used for external service '$svc' (external services use image tags, not git branches)" >&2
      echo "usage: swarmcli deploy $stack --service $svc" >&2
      errors=1
    fi
  done
  
  # Check --commit for external services
  for svc in "${!SERVICE_COMMITS[@]}"; do
    if ! is_service_internal "$stack" "$svc" 2>/dev/null; then
      echo "error: --commit cannot be used for external service '$svc' (external services use image tags, not git commits)" >&2
      echo "usage: swarmcli deploy $stack --service $svc" >&2
      errors=1
    fi
  done
  
  if [ $errors -gt 0 ]; then
    exit 1
  fi
  
  return 0
}

# Resolve profile from various sources
# Priority: --profile > saved default > SWARM_PROFILE
resolve_and_load_profile() {
  if [ -n "$PROFILE_ARG" ]; then
    load_profile "$PROFILE_ARG"
  elif [ -z "${SWARM_PROFILE:-}" ]; then
    # Try to load saved default
    local local_default
    local_default=$(load_default_profile)
    if [ -n "$local_default" ]; then
      load_profile "$local_default"
    fi
  else
    load_profile "$SWARM_PROFILE"
  fi
}

