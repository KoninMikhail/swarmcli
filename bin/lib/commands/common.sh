#!/usr/bin/env bash
# Common helper functions for commands

# Branch resolution with priority:
#   1. --service svc --branch xxx (SERVICE_BRANCHES)
#   2. services.yaml::default_branch
#   3. DEFAULT_BRANCH (main)
# Usage: resolve_branch <stack> <service>
resolve_branch() {
  local stack="$1" svc="$2"
  
  ensure_overrides_vars
  
  # Priority 1: --service svc --branch xxx (per-service syntax)
  if [ -n "${SERVICE_BRANCHES[$svc]:-}" ]; then
    echo "${SERVICE_BRANCHES[$svc]}"
    return 0
  fi
  
  # Priority 2: services.yaml default_branch
  local b
  b="$(get_service_branch "$stack" "$svc")"
  if [ -n "$b" ]; then
    echo "$b"
    return 0
  fi
  
  # Priority 3: default
  echo "${DEFAULT_BRANCH:-main}"
}

# Commit SHA resolution with priority:
#   1. --service svc --commit xxx (SERVICE_COMMITS)
#   2. CI_COMMIT_SHA environment variable
#   3. COMMIT_SHA environment variable
#   4. HEAD of resolved branch
# Usage: resolve_commit_sha <stack> <service>
# Returns: short SHA (7 chars) or full SHA if specified
resolve_commit_sha() {
  local stack="$1" svc="$2"
  
  # Priority 1: --service svc --commit xxx (new per-service syntax)
  if [ -n "${SERVICE_COMMITS[$svc]:-}" ]; then
    local repo_dir
    repo_dir="$(get_service_repo_dir "$stack" "$svc")"
    if [ -d "$repo_dir/.git" ]; then
      local short_sha
      short_sha="$(git -C "$repo_dir" rev-parse --short "${SERVICE_COMMITS[$svc]}" 2>/dev/null || echo "${SERVICE_COMMITS[$svc]:0:7}")"
      echo "$short_sha"
      return 0
    else
      echo "${SERVICE_COMMITS[$svc]:0:7}"
      return 0
    fi
  fi
  
  # Priority 2: CI_COMMIT_SHA environment variable
  if [ -n "${CI_COMMIT_SHA:-}" ]; then
    local repo_dir
    repo_dir="$(get_service_repo_dir "$stack" "$svc")"
    if [ -d "$repo_dir/.git" ]; then
      local short_sha
      short_sha="$(git -C "$repo_dir" rev-parse --short "${CI_COMMIT_SHA}" 2>/dev/null || echo "${CI_COMMIT_SHA:0:7}")"
      echo "$short_sha"
      return 0
    else
      echo "${CI_COMMIT_SHA:0:7}"
      return 0
    fi
  fi
  
  # Priority 3: COMMIT_SHA environment variable
  if [ -n "${COMMIT_SHA:-}" ]; then
    local repo_dir
    repo_dir="$(get_service_repo_dir "$stack" "$svc")"
    if [ -d "$repo_dir/.git" ]; then
      local short_sha
      short_sha="$(git -C "$repo_dir" rev-parse --short "${COMMIT_SHA}" 2>/dev/null || echo "${COMMIT_SHA:0:7}")"
      echo "$short_sha"
      return 0
    else
      echo "${COMMIT_SHA:0:7}"
      return 0
    fi
  fi
  
  # Priority 4: read from HEAD
  get_service_commit_sha "$stack" "$svc"
}

# Get services to process (filtered or all)
# Usage: services_to_process <stack>
services_to_process() {
  local stack="$1"
  
  if [ ${#SELECTED_SERVICES[@]} -gt 0 ]; then
    printf "%s\n" "${SELECTED_SERVICES[@]}"
  else
    get_services_list "$stack"
  fi
}

# Override tracking - ensure all service override arrays are initialized
ensure_overrides_vars() {
  if [ ${DECLARE_OVERRIDES_INITIALIZED:-0} -eq 0 ]; then
    declare -g -A SERVICE_BRANCHES=()
    declare -g -A SERVICE_COMMITS=()
    export DECLARE_OVERRIDES_INITIALIZED=1
  fi
}
