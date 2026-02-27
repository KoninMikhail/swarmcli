#!/usr/bin/env bash
# Git operations with security and retry logic

# Get path to service repository within stack
# Usage: get_service_repo_dir <stack> <service>
# Returns: path to service repository directory
get_service_repo_dir() {
  local stack="$1" svc="$2"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  echo "$stack_dir/.repos/$svc"
}

# Resolve git credentials with fallback: stack settings > profile > .swarmcli.yaml/env
# Usage: _get_git_credentials_for_stack [stack]
# Sets _GIT_USER and _GIT_TOKEN for caller
_get_git_credentials_for_stack() {
  local stack="${1:-}"
  _GIT_USER="$GIT_HTTP_USER"
  _GIT_TOKEN="$GIT_HTTP_TOKEN"
  if [ -n "$stack" ]; then
    local stack_user stack_token
    stack_user="$(get_stack_setting "$stack" "git.http_user" "")"
    stack_token="$(get_stack_setting "$stack" "git.http_token" "")"
    [ -n "$stack_user" ] && _GIT_USER="$(safe_interpolate "$stack_user")"
    [ -n "$stack_token" ] && _GIT_TOKEN="$(safe_interpolate "$stack_token")"
  fi
}

# Setup GIT_ASKPASS-based authentication (tokens not visible in ps aux)
# Usage: _setup_git_auth [stack]
# Creates a temporary askpass script and sets environment variables.
# Credentials are passed via env vars, not command-line arguments.
# Call _cleanup_git_auth when done.
_setup_git_auth() {
  local stack="${1:-}"
  
  _get_git_credentials_for_stack "$stack"
  local user="$_GIT_USER"
  local token="$_GIT_TOKEN"
  local password="${GIT_HTTP_PASSWORD:-}"
  
  # Determine effective credentials
  local effective_user="${user:-}"
  local effective_pass="${token:-$password}"
  
  if [ -z "$effective_pass" ]; then
    return 0
  fi
  
  [ -z "$effective_user" ] && effective_user="oauth2"
  
  # Create askpass script that reads from env vars (not embedded in script)
  local askpass_script
  askpass_script=$(mktemp "${TMPDIR:-/tmp}/swarmcli-askpass-XXXXXX")
  cat > "$askpass_script" << 'ASKEOF'
#!/bin/sh
case "$1" in
  Username*|username*) printf '%s\n' "$_SWARMCLI_GIT_USER" ;;
  Password*|password*) printf '%s\n' "$_SWARMCLI_GIT_TOKEN" ;;
esac
ASKEOF
  chmod +x "$askpass_script"
  
  export GIT_ASKPASS="$askpass_script"
  export GIT_TERMINAL_PROMPT=0
  export _SWARMCLI_GIT_USER="$effective_user"
  export _SWARMCLI_GIT_TOKEN="$effective_pass"
  _SWARMCLI_ASKPASS_FILE="$askpass_script"
}

# Clean up GIT_ASKPASS resources
_cleanup_git_auth() {
  [ -n "${_SWARMCLI_ASKPASS_FILE:-}" ] && rm -f "$_SWARMCLI_ASKPASS_FILE"
  unset GIT_ASKPASS GIT_TERMINAL_PROMPT _SWARMCLI_GIT_USER _SWARMCLI_GIT_TOKEN _SWARMCLI_ASKPASS_FILE 2>/dev/null || true
}

# Build URL with username only (no password/token) for GIT_ASKPASS auth
# Usage: _url_with_user_only <url> [stack]
_url_with_user_only() {
  local url="$1" stack="${2:-}"
  
  _get_git_credentials_for_stack "$stack"
  local user="$_GIT_USER"
  local token="$_GIT_TOKEN"
  
  case "$url" in
    http://*|https://*)
      local scheme rest
      if [[ "$url" == https://* ]]; then
        scheme="https://"
        rest="${url#https://}"
      else
        scheme="http://"
        rest="${url#http://}"
      fi
      
      # Embed only the username; password provided by GIT_ASKPASS
      if [ -n "$user" ] && [ -n "$token" ]; then
        echo "${scheme}${user}@${rest}"
        return 0
      elif [ -n "$token" ]; then
        echo "${scheme}oauth2@${rest}"
        return 0
      elif [ -n "$user" ] && [ -n "${GIT_HTTP_PASSWORD:-}" ]; then
        echo "${scheme}${user}@${rest}"
        return 0
      fi
      ;;
  esac
  
  echo "$url"
}

# Sanitize git errors to remove credentials
sanitize_git_error() {
  local error="$1"
  # Remove URLs with credentials
  echo "$error" | sed -E 's|https?://[^@/]*@|https://<REDACTED>@|g'
}

# Clone or update repository with retry logic
# Usage: sync_repo_for_service <stack> <service> <branch> [commit_sha]
# Returns: 0 on success, 2 on git error, 130 on cancellation
# If commit_sha is provided, checkout that commit instead of branch
sync_repo_for_service() {
  local stack="$1" svc="$2" branch="$3" commit_sha="${4:-}"
  
  # Skip external services (no repo required)
  if ! is_service_internal "$stack" "$svc"; then
    log info "skipping repo sync for external service: $svc (no repository required)"
    return 0
  fi
  
  ensure_cmd git
  
  # Check for cancellation before starting
  if declare -f check_cancellation_requested >/dev/null 2>&1; then
    check_cancellation_requested "$stack" || return 130
  fi
  
  local repo auth_url
  repo="$(get_service_field "$stack" "$svc" repo)"
  [ -n "$repo" ] || {
    add_error "repo not defined for internal service $svc"
    return 1
  }
  
  # Use GIT_ASKPASS for auth (tokens not visible in ps aux)
  _setup_git_auth "$stack"
  local _sync_tmp_err=""
  trap '_cleanup_git_auth; [ -n "$_sync_tmp_err" ] && rm -f "$_sync_tmp_err"' RETURN
  auth_url="$(_url_with_user_only "$repo" "$stack")"
  local path
  path="$(get_service_repo_dir "$stack" "$svc")"
  
  # Ensure .repos directory exists
  mkdir -p "$(dirname "$path")" || true
  
  # Clone if not exists
  if [ ! -d "$path/.git" ]; then
    log detail "cloning $svc -> $path"
    
    if [ "$DRY_RUN" = "1" ]; then
      return 0
    fi
    
    # Check for cancellation before clone
    if declare -f check_cancellation_requested >/dev/null 2>&1; then
      check_cancellation_requested "$stack" || return 130
    fi
    
    local tmp_err
    tmp_err=$(mktemp)
    _sync_tmp_err="$tmp_err"
    if ! retry_with_backoff git clone "$auth_url" "$path" >/dev/null 2>"$tmp_err"; then
      local sanitized_err
      sanitized_err=$(sanitize_git_error "$(cat "$tmp_err")")
      rm -f "$tmp_err"; _sync_tmp_err=""
      add_error "git clone failed for $svc after retries: $sanitized_err"
      return 2
    fi
    rm -f "$tmp_err"; _sync_tmp_err=""
    
    # Sanitize remote URL to drop credentials
    if [ "$auth_url" != "$repo" ]; then
      git -C "$path" remote set-url origin "$repo" >/dev/null 2>&1 || true
    fi
  else
    log detail "updating $svc"
  fi
  
  [ "$DRY_RUN" = "1" ] && return 0
  
  # Check for cancellation before fetch/checkout
  if declare -f check_cancellation_requested >/dev/null 2>&1; then
    check_cancellation_requested "$stack" || return 130
  fi
  
  local tmp_err
  tmp_err=$(mktemp)
  _sync_tmp_err="$tmp_err"
  
  # If commit_sha is provided, fetch branch first (to get the commit), then checkout commit
  if [ -n "$commit_sha" ]; then
    log info "fetching branch $branch to get commit $commit_sha for $svc"
    if ! retry_with_backoff git -C "$path" fetch "$auth_url" "$branch" --prune >/dev/null 2>"$tmp_err"; then
      # If branch fetch fails, try fetching all refs
      log warn "could not fetch branch $branch, trying to fetch all refs"
      if ! retry_with_backoff git -C "$path" fetch "$auth_url" --prune --all >/dev/null 2>"$tmp_err"; then
        local sanitized_err
        sanitized_err=$(sanitize_git_error "$(cat "$tmp_err")")
        rm -f "$tmp_err"
        add_error "git fetch failed for $svc branch $branch after retries: $sanitized_err"
        return 2
      fi
    fi
    
    # Check for cancellation after fetch
    if declare -f check_cancellation_requested >/dev/null 2>&1; then
      check_cancellation_requested "$stack" || { rm -f "$tmp_err"; return 130; }
    fi
    
    # Verify commit exists after fetch
    if ! git -C "$path" cat-file -e "$commit_sha" 2>/dev/null; then
      rm -f "$tmp_err"
      add_error "commit $commit_sha not found in repository for $svc after fetch"
      return 2
    fi
    
    log info "checking out commit $commit_sha for $svc"
    if ! git -C "$path" checkout "$commit_sha" >/dev/null 2>"$tmp_err"; then
      local sanitized_err
      sanitized_err=$(sanitize_git_error "$(cat "$tmp_err")")
      rm -f "$tmp_err"
      add_error "git checkout failed for $svc commit $commit_sha: $sanitized_err"
      return 2
    fi
  else
    # Regular fetch for branch checkout
    # Fetch specific branch to ensure we have the latest remote state
    if ! retry_with_backoff git -C "$path" fetch "$auth_url" "$branch" --prune >/dev/null 2>"$tmp_err"; then
      local sanitized_err
      sanitized_err=$(sanitize_git_error "$(cat "$tmp_err" 2>/dev/null || echo "unknown error")")
      rm -f "$tmp_err"
      log error "git fetch failed for $svc branch $branch: $sanitized_err"
      add_error "git fetch failed for $svc branch $branch after retries: $sanitized_err"
      return 2
    fi
    
    # Check for cancellation after fetch
    if declare -f check_cancellation_requested >/dev/null 2>&1; then
      check_cancellation_requested "$stack" || { rm -f "$tmp_err"; return 130; }
    fi
    
    # Checkout to FETCH_HEAD (detached HEAD on latest remote commit)
    # This ensures we always have the latest code from remote, avoiding
    # stale local branch issue where 'git checkout branch' would use
    # outdated local tracking branch instead of fresh remote state
    if ! git -C "$path" checkout FETCH_HEAD >/dev/null 2>"$tmp_err"; then
      local sanitized_err
      sanitized_err=$(sanitize_git_error "$(cat "$tmp_err" 2>/dev/null || echo "unknown error")")
      rm -f "$tmp_err"
      log error "git checkout failed for $svc branch $branch: $sanitized_err"
      add_error "git checkout failed for $svc branch $branch: $sanitized_err"
      return 2
    fi
  fi
  
  rm -f "$tmp_err"; _sync_tmp_err=""
  return 0
}

# Sync repository and return result info for tree display
# Usage: sync_repo_for_service_info <stack> <service> <branch> [commit_sha]
# Output: JSON-like string with sync result
# Returns: 0 on success, non-zero on error
sync_repo_for_service_info() {
  local stack="$1" svc="$2" branch="$3" commit_sha="${4:-}"
  local start_ts
  start_ts=$(date +%s)
  
  # Check if external
  if ! is_service_internal "$stack" "$svc"; then
    # Sync external image
    local error_msg=""
    if ! sync_external_image "$stack" "$svc" 2>&1; then
      local end_ts
      end_ts=$(date +%s)
      local duration
      duration=$((end_ts - start_ts))
      error_msg="${ERROR_STACK[${#ERROR_STACK[@]}-1]:-sync failed}"
      echo "status=failed;type=external;error=$error_msg;time=$duration"
      return 2
    fi
    
    local end_ts
    end_ts=$(date +%s)
    local duration
    duration=$((end_ts - start_ts))
    local full_image
    full_image="$(get_service_field "$stack" "$svc" image 2>/dev/null || echo "")"
    local image_name tag
    if [ -n "$full_image" ]; then
      image_name=$(extract_image_tag "$full_image" | head -1)
      tag=$(extract_image_tag "$full_image" | tail -1)
    fi
    echo "status=ok;type=external;action=pull;image=${image_name}:${tag};time=$duration"
    return 0
  fi
  
  local repo_dir action="fetch"
  repo_dir="$(get_service_repo_dir "$stack" "$svc")"
  
  # Determine action
  if [ ! -d "$repo_dir/.git" ]; then
    action="clone"
  fi
  
  # Run sync (suppress output for tree mode)
  local error_msg=""
  if ! sync_repo_for_service "$stack" "$svc" "$branch" "$commit_sha" 2>&1; then
    local end_ts
    end_ts=$(date +%s)
    local duration
    duration=$((end_ts - start_ts))
    # Get last error from error stack
    error_msg="${ERROR_STACK[${#ERROR_STACK[@]}-1]:-sync failed}"
    echo "status=failed;action=$action;branch=$branch;error=$error_msg;time=$duration"
    return 2
  fi
  
  local end_ts
  end_ts=$(date +%s)
  local duration
  duration=$((end_ts - start_ts))
  
  # Get commit info
  local sha current_branch
  sha=$(get_service_commit_sha "$stack" "$svc")
  current_branch=$(get_service_current_branch "$stack" "$svc")
  
  echo "status=ok;action=$action;branch=$current_branch;commit=$sha;time=$duration"
  return 0
}

# Get short commit SHA for a service
# Usage: get_service_commit_sha <stack> <service>
# Output: short SHA (7 chars)
get_service_commit_sha() {
  local stack="$1" svc="$2"
  local repo_dir
  repo_dir="$(get_service_repo_dir "$stack" "$svc")"
  
  if [ ! -d "$repo_dir/.git" ]; then
    echo "nogit"
    return 0  # Not an error - repo just not cloned yet
  fi
  
  # Use timeout to prevent hanging if Git repository is corrupted or inaccessible
  # Default timeout: 5 seconds (should be fast for local git operations)
  local timeout="${GIT_OPERATION_TIMEOUT:-5}"
  local shortsha
  
  if command -v timeout >/dev/null 2>&1; then
    shortsha="$(timeout "$timeout" git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null)"
  else
    # Fallback: run without timeout (may hang if Git repo is corrupted)
    shortsha="$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null)"
  fi
  
  if [ -z "$shortsha" ]; then
    echo "nogit"
    return 0  # Return placeholder, not error
  fi
  
  echo "$shortsha"
}

# Get current branch for a service
# Usage: get_service_current_branch <stack> <service>
# Output: branch name or "detached" for detached HEAD state
get_service_current_branch() {
  local stack="$1" svc="$2"
  local repo_dir
  repo_dir="$(get_service_repo_dir "$stack" "$svc")"
  
  if [ ! -d "$repo_dir/.git" ]; then
    echo "unknown"
    return 0  # Not an error - repo just not cloned yet
  fi
  
  local branch
  branch=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  
  # For detached HEAD, try to find remote branch name from reflog or show "detached"
  if [ "$branch" = "HEAD" ]; then
    # Try to get branch name from FETCH_HEAD description
    local fetch_head_branch
    fetch_head_branch=$(git -C "$repo_dir" name-rev --name-only FETCH_HEAD 2>/dev/null | sed 's|^remotes/origin/||' | sed 's|~.*||' | sed 's|\^.*||')
    if [ -n "$fetch_head_branch" ] && [ "$fetch_head_branch" != "FETCH_HEAD" ] && [ "$fetch_head_branch" != "undefined" ]; then
      echo "$fetch_head_branch"
    else
      echo "detached"
    fi
  else
    echo "$branch"
  fi
}

# Validate that repo is accessible
# Usage: validate_repo_access <repo_url>
# Returns: 0 if accessible, 1 otherwise
validate_repo_access() {
  local repo="$1"
  
  # Use GIT_ASKPASS for auth (tokens not visible in ps aux)
  _setup_git_auth
  trap '_cleanup_git_auth' RETURN
  local auth_url
  auth_url="$(_url_with_user_only "$repo")"
  
  local tmp_err
  tmp_err=$(mktemp)
  if retry_with_backoff git ls-remote "$auth_url" HEAD >/dev/null 2>"$tmp_err"; then
    rm -f "$tmp_err"
    return 0
  else
    local sanitized_err
    sanitized_err=$(sanitize_git_error "$(cat "$tmp_err")")
    rm -f "$tmp_err"
    add_error "cannot access repo $repo after retries: $sanitized_err"
    return 1
  fi
}

# Extract image name and tag from full image string
# Usage: extract_image_tag <full_image_string>
# Output: IMAGE_NAME:TAG (separated by newline, tag on second line)
# Examples:
#   redis:7-alpine -> redis\n7-alpine
#   nginx:latest -> nginx\nlatest
#   redis -> redis\nlatest
extract_image_tag() {
  local full_image="$1"
  
  # Check if tag is present (contains colon)
  if [[ "$full_image" == *:* ]]; then
    # Extract image name (everything before last colon)
    local image_name="${full_image%:*}"
    # Extract tag (everything after last colon)
    local tag="${full_image##*:}"
    echo "$image_name"
    echo "$tag"
  else
    # No tag specified, default to latest
    echo "$full_image"
    echo "latest"
  fi
}

# Sync external registry image (pull if needed)
# Usage: sync_external_image <stack> <service>
# Returns: 0 on success, 2 on error, 130 on cancellation
# 
# Logic:
# - If image has 'latest' tag: always pull
# - If image has specific tag: check if exists locally, pull if missing
# - If --service is specified: verify tag matches what's specified
sync_external_image() {
  local stack="$1" svc="$2"
  
  # Skip internal services
  if is_service_internal "$stack" "$svc"; then
    return 0
  fi
  
  ensure_cmd docker
  
  # Check for cancellation before starting
  if declare -f check_cancellation_requested >/dev/null 2>&1; then
    check_cancellation_requested "$stack" || return 130
  fi
  
  local full_image
  full_image="$(get_service_field "$stack" "$svc" image 2>/dev/null || echo "")"
  
  if [ -z "$full_image" ]; then
    log warn "no image defined for external service: $svc"
    return 0
  fi
  
  # Extract image name and tag
  local image_name tag
  image_name=$(extract_image_tag "$full_image" | head -1)
  tag=$(extract_image_tag "$full_image" | tail -1)
  
  [ "$DRY_RUN" = "1" ] && {
    log info "dry-run: would sync external image $image_name:$tag for $svc"
    return 0
  }
  
  # Check for cancellation before pull
  if declare -f check_cancellation_requested >/dev/null 2>&1; then
    check_cancellation_requested "$stack" || return 130
  fi
  
  # If tag is 'latest', always pull
  if [ "$tag" = "latest" ]; then
    log info "pulling latest image for external service: $svc ($image_name:$tag)"
    if ! retry_with_backoff docker pull "$image_name:$tag" >/dev/null 2>&1; then
      add_error "docker pull failed for external service $svc: $image_name:$tag"
      return 2
    fi
    log detail "✓ pulled $image_name:$tag"
    return 0
  fi
  
  # For specific tags, check if image exists locally
  if docker image inspect "$image_name:$tag" >/dev/null 2>&1; then
    log detail "external image exists locally: $svc ($image_name:$tag)"
    
    # If --service is specified, verify the tag matches
    if [ ${#SELECTED_SERVICES[@]} -gt 0 ]; then
      local is_selected=0
      for selected_svc in "${SELECTED_SERVICES[@]}"; do
        if [ "$selected_svc" = "$svc" ]; then
          is_selected=1
          break
        fi
      done
      
      if [ $is_selected -eq 1 ]; then
        # Verify tag matches what's in services.yaml
        log detail "verifying tag for selected external service: $svc ($image_name:$tag)"
        # Tag is already verified by checking the image exists with the expected tag
        log detail "✓ tag verified: $image_name:$tag"
      fi
    fi
    return 0
  fi
  
  # Image doesn't exist locally, pull it
  log info "pulling external image for service: $svc ($image_name:$tag)"
  if ! retry_with_backoff docker pull "$image_name:$tag" >/dev/null 2>&1; then
    add_error "docker pull failed for external service $svc: $image_name:$tag"
    return 2
  fi
  log detail "✓ pulled $image_name:$tag"
  return 0
}
