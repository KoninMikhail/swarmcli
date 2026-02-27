#!/usr/bin/env bash
# System commands: version, health, update

# Command: swarmcli version
cmd_version() {
  if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
    cat <<JSON
{
  "version": "${VERSION}",
  "buildDate": "${BUILD_DATE}",
  "runtime": {
    "docker": "$(docker --version 2>/dev/null || echo 'not found')",
    "git": "$(git --version 2>/dev/null || echo 'not found')",
    "bash": "${BASH_VERSION}"
  }
}
JSON
  else
    cat <<EOF
swarmcli v${VERSION}
Build date: ${BUILD_DATE}

Runtime:
  Docker: $(docker --version 2>/dev/null || echo 'not found')
  Git: $(git --version 2>/dev/null || echo 'not found')
  Bash: ${BASH_VERSION}

Active profile: ${ACTIVE_PROFILE:-none}
EOF
  fi
}

# Command: swarmcli self-update
# Usage: swarmcli self-update [branch]
# Returns: 0 if updated or already up-to-date, 1 on error
cmd_self_update() {
  local branch="${1:-main}"
  
  log info "checking for swarmcli updates..."
  
  if [ ! -d "$PLATFORM_ROOT/.git" ]; then
    log error "not a git repository: $PLATFORM_ROOT"
    return 1
  fi
  
  local remote_url
  remote_url=$(git -C "$PLATFORM_ROOT" config --get remote.origin.url 2>/dev/null || echo "")
  
  if [ -z "$remote_url" ]; then
    log error "remote origin not configured"
    return 1
  fi
  
  [ "$VERBOSE" = "1" ] && log info "remote: $remote_url"
  
  # Get current local commit
  local local_commit
  local_commit=$(git -C "$PLATFORM_ROOT" rev-parse HEAD 2>/dev/null || echo "unknown")
  local local_short="${local_commit:0:7}"
  
  [ "$VERBOSE" = "1" ] && log info "local commit: $local_short"
  
  # Setup GIT_ASKPASS auth (tokens not visible in ps aux)
  _setup_git_auth
  trap '_cleanup_git_auth' RETURN
  local auth_url
  auth_url="$(_url_with_user_only "$remote_url")"
  
  # Fetch remote changes first (this is the key step!)
  log info "fetching from origin/$branch..."
  local fetch_output
  if ! fetch_output=$(git -C "$PLATFORM_ROOT" fetch "$auth_url" "$branch:refs/remotes/origin/$branch" 2>&1); then
    # Sanitize error output (remove credentials)
    fetch_output=$(echo "$fetch_output" | sed -E 's|https://[^@]+@|https://***@|g')
    log error "git fetch failed: $fetch_output"
    return 1
  fi
  
  # Get remote commit after fetch
  local remote_commit
  remote_commit=$(git -C "$PLATFORM_ROOT" rev-parse "origin/$branch" 2>/dev/null || echo "unknown")
  local remote_short="${remote_commit:0:7}"
  
  [ "$VERBOSE" = "1" ] && log info "remote commit: $remote_short"
  
  # Check if update needed
  if [ "$local_commit" = "$remote_commit" ]; then
    log ok "swarmcli already up to date ($local_short)"
    return 0
  fi
  
  # Show how many commits behind
  local behind_count
  behind_count=$(git -C "$PLATFORM_ROOT" rev-list --count HEAD..origin/$branch 2>/dev/null || echo "?")
  log info "local is $behind_count commit(s) behind remote"
  log info "updating: $local_short -> $remote_short"
  
  # Try fast-forward merge first
  if git -C "$PLATFORM_ROOT" merge --ff-only "origin/$branch" >/dev/null 2>&1; then
    # Ensure executable permissions on main script (in case they were lost)
    chmod +x "$PLATFORM_ROOT/bin/swarm.sh" 2>/dev/null || true
    log ok "swarmcli updated: $local_short -> $remote_short"
    return 0
  fi
  
  # Fast-forward failed, try reset (for dirty state or diverged history)
  log warn "fast-forward failed, trying hard reset..."
  
  if git -C "$PLATFORM_ROOT" reset --hard "origin/$branch" >/dev/null 2>&1; then
    # Ensure executable permissions after reset (critical!)
    chmod +x "$PLATFORM_ROOT/bin/swarm.sh" 2>/dev/null || true
    log ok "swarmcli updated (reset): $local_short -> $remote_short"
    return 0
  fi
  
  log error "failed to update swarmcli"
  return 1
}
