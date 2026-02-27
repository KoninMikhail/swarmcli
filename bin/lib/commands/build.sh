#!/usr/bin/env bash
# Build commands

_run_build() {
  local stack="$1"
  local services any_err br svc
  services=$(services_to_process "$stack")
  any_err=0
  while IFS= read -r svc; do
    [ -n "$svc" ] || continue
    br="$(resolve_branch "$stack" "$svc")"
    build_for_service "$stack" "$svc" "$br" || any_err=2
  done <<< "$services"
  return $any_err
}

# Helper: run parallel build with batching
# Builds services in parallel batches of 4 for better resource utilization
# Usage: _run_build_parallel <stack>
# Returns: 0 on success, 2 if any build failed
_run_build_parallel() {
  local stack="$1"
  local services any_err=0
  services=$(services_to_process "$stack")
  
  # Convert services list to array
  local svc_array=()
  while IFS= read -r svc; do
    [ -n "$svc" ] || continue
    svc_array+=("$svc")
  done <<< "$services"
  
  local total=${#svc_array[@]}
  
  # If only 1 service, use sequential build
  if [ "$total" -le 1 ]; then
    _run_build "$stack"
    return $?
  fi
  
  local batch_size=4
  local current_batch=0
  local batch_num=1
  local total_batches=$(( (total + batch_size - 1) / batch_size ))
  
  # Ensure log directory exists
  local build_log_dir="${HOME}/.swarm-deploy/logs"
  mkdir -p "$build_log_dir" 2>/dev/null || build_log_dir="/tmp"
  
  log info "parallel build: $total services in $total_batches batch(es) (max $batch_size concurrent)"
  
  # Process services in batches
  while [ $current_batch -lt $total ]; do
    local pids=()
    local log_files=()
    local service_names=()
    local batch_end=$((current_batch + batch_size))
    [ $batch_end -gt $total ] && batch_end=$total
    local batch_count=$((batch_end - current_batch))
    
    log info "batch $batch_num/$total_batches: building $batch_count service(s)..."
    
    # Start builds in background
    local i
    for ((i=current_batch; i<batch_end; i++)); do
      local svc="${svc_array[$i]}"
      local br
      br="$(resolve_branch "$stack" "$svc")"
      local build_log="${build_log_dir}/build_${svc}_$$.log"
      
      # Clear previous log if exists
      : > "$build_log"
      
      # Start build in background with output redirected to log file
      (
        build_for_service "$stack" "$svc" "$br"
      ) > "$build_log" 2>&1 &
      local pid=$!
      
      pids+=("$pid")
      log_files+=("$build_log")
      service_names+=("$svc")
      
      # Register for graceful shutdown (if signals.sh is loaded)
      if declare -f register_child_pid >/dev/null 2>&1; then
        register_child_pid "$pid"
      fi
      
      log info "  started: $svc (PID: $pid)"
    done
    
    # Wait for all builds in this batch and collect results
    local batch_failed=0
    for i in "${!pids[@]}"; do
      local pid="${pids[$i]}"
      local svc="${service_names[$i]}"
      local log_file="${log_files[$i]}"
      
      # Wait for process to complete
      wait "$pid" 2>/dev/null
      local rc=$?
      
      # Unregister child PID
      if declare -f unregister_child_pid >/dev/null 2>&1; then
        unregister_child_pid "$pid"
      fi
      
      if [ $rc -eq 0 ]; then
        log ok "  completed: $svc"
        # Show summary from log (last few lines with image info)
        if [ -f "$log_file" ]; then
          local image_line
          image_line=$(grep -E "(buildx:|build:).*:${ACTIVE_PROFILE}-" "$log_file" | tail -1)
          if [ -n "$image_line" ]; then
            echo "    ${image_line##*] }"
          fi
        fi
      elif [ $rc -eq 130 ]; then
        # Interrupted (Ctrl+C)
        log warn "  cancelled: $svc"
        any_err=130
        batch_failed=1
      else
        log error "  failed: $svc (exit code: $rc)"
        # Show error log (buffered output)
        if [ -f "$log_file" ] && [ -s "$log_file" ]; then
          printf "    %s\n" "$(c 90 "─── Build error log: $svc ───")"
          tail -n 30 "$log_file" | sed 's/^/    /'
          printf "    %s\n" "$(c 90 "─────────────────────────────")"
        fi
        any_err=2
        batch_failed=1
      fi
      
      # Cleanup log file
      rm -f "$log_file" 2>/dev/null || true
    done
    
    # If batch failed and we were interrupted, stop processing more batches
    if [ $any_err -eq 130 ]; then
      log warn "build interrupted, stopping remaining batches"
      break
    fi
    
    current_batch=$batch_end
    batch_num=$((batch_num + 1))
  done
  
  return $any_err
}

# Command: swarmcli repos sync <stack>
# Tree mode is default, --verbose switches to plain CLI output
cmd_repos_sync() {
  local start_ts=$(date +%s)
  local stack="$1"
  shift || true
  
  # Parse flags
  while [ $# -gt 0 ]; do
    case "$1" in
      --verbose|-v) VERBOSE=1 ;;
    esac
    shift
  done
  
  [ -n "$stack" ] || fail "usage: swarmcli repos sync <STACK> --profile <PROFILE> [--verbose]"
  
  ensure_stack_exists "$stack"
  
  # Verbose mode: plain CLI output
  if [ "$VERBOSE" = "1" ]; then
    _run_repos_sync "$stack"
    local rc=$?
    [ $rc -eq 0 ] || exit $rc
    
    local end_ts=$(date +%s)
    log ok "repos sync completed in $((end_ts-start_ts))s"
    return $rc
  fi
  
  # Default: tree mode
  cmd_repos_sync_tree "$stack"
  return $?
}

# ============================================
# Tree-style sync output
# ============================================

# Tree drawing characters (compact style like Deployment info)
_sync_tree_branch="├─"
_sync_tree_last="└─"
_sync_tree_pipe="│ "
_sync_tree_space="  "

# Print tree item for sync
_sync_tree_item() {
  local prefix="$1"
  local is_last="$2"
  local icon="$3"
  local text="$4"
  
  if [ "$is_last" = "1" ]; then
    printf "%s%s %s %s\n" "$prefix" "$_sync_tree_last" "$icon" "$text"
  else
    printf "%s%s %s %s\n" "$prefix" "$_sync_tree_branch" "$icon" "$text"
  fi
}

# Sync repositories with tree-style output (default mode)
# Usage: cmd_repos_sync_tree <stack>
cmd_repos_sync_tree() {
  local stack="$1"
  local start_ms=$(now_ms)
  
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  # Collect services info
  local services
  services=$(get_services_list "$stack")
  local services_arr=()
  while IFS= read -r svc; do
    [ -n "$svc" ] && services_arr+=("$svc")
  done <<< "$services"
  
  local total=${#services_arr[@]}
  local git_count=0
  local ext_count=0
  
  # Count git vs external
  for svc in "${services_arr[@]}"; do
    if is_service_internal "$stack" "$svc"; then
      git_count=$((git_count + 1))
    else
      ext_count=$((ext_count + 1))
    fi
  done
  
  # Header
  printf "\n$(c 90 "─────────────────────────────────────────────────────────────")\n"
  printf "🔄 $(c 1 "Syncing repositories:") %s $(c 90 "(profile: %s)")\n" "$stack" "$ACTIVE_PROFILE"
  
  # Services section
  printf "%s $(c 1 "Services") $(c 90 "(%d git, %d external)")\n" "$_sync_tree_branch" "$git_count" "$ext_count"
  local svc_prefix="$_sync_tree_pipe"
  
  local errors=0
  local synced=0
  local skipped=0
  local failed_services=()
  
  local idx=0
  for svc in "${services_arr[@]}"; do
    idx=$((idx + 1))
    local is_last_svc=$( [ $idx -eq $total ] && echo "1" || echo "0" )
    
    # Service name line
    if [ "$is_last_svc" = "1" ]; then
      printf "%s%s $(c 36 "%s")\n" "$svc_prefix" "$_sync_tree_last" "$svc"
      local svc_sub_prefix="$svc_prefix$_sync_tree_space"
    else
      printf "%s%s $(c 36 "%s")\n" "$svc_prefix" "$_sync_tree_branch" "$svc"
      local svc_sub_prefix="$svc_prefix$_sync_tree_pipe"
    fi
    
    # Check if external
    if ! is_service_internal "$stack" "$svc"; then
      _sync_tree_item "$svc_sub_prefix" "1" "○" "external $(c 90 "(skipped)")"
      skipped=$((skipped + 1))
      continue
    fi
    
    # Get branch info
    local branch
    branch="$(resolve_branch "$stack" "$svc")"
    
    # Get commit SHA if specified
    local commit_sha=""
    if [ -n "${SERVICE_COMMITS[$svc]:-}" ]; then
      commit_sha="${SERVICE_COMMITS[$svc]}"
    elif [ -n "${CI_COMMIT_SHA:-}" ]; then
      commit_sha="$CI_COMMIT_SHA"
    elif [ -n "${COMMIT_SHA:-}" ]; then
      commit_sha="$COMMIT_SHA"
    fi
    
    # Determine commit source for display
    local commit_source=""
    if [ -n "${SERVICE_COMMITS[$svc]:-}" ]; then
      commit_source="--commit"
    elif [ -n "${CI_COMMIT_SHA:-}" ]; then
      commit_source="CI"
    elif [ -n "${COMMIT_SHA:-}" ]; then
      commit_source="env"
    fi
    
    # Show target: branch and commit if specified
    if [ -n "$commit_sha" ]; then
      _sync_tree_item "$svc_sub_prefix" "0" "○" "target: $branch @ $(c 33 "${commit_sha:0:7}") $(c 90 "($commit_source)")"
    else
      _sync_tree_item "$svc_sub_prefix" "0" "○" "target: $branch"
    fi
    
    # Run sync and capture result
    local sync_output sync_rc
    sync_output=$(sync_repo_for_service_info "$stack" "$svc" "$branch" "$commit_sha" 2>&1)
    sync_rc=$?
    
    # Parse result (using sed for portability - grep -P not available everywhere)
    local status action result_branch result_commit duration error_msg
    status=$(echo "$sync_output" | sed -n 's/.*status=\([^;]*\).*/\1/p')
    action=$(echo "$sync_output" | sed -n 's/.*action=\([^;]*\).*/\1/p')
    result_branch=$(echo "$sync_output" | sed -n 's/.*branch=\([^;]*\).*/\1/p')
    result_commit=$(echo "$sync_output" | sed -n 's/.*commit=\([^;]*\).*/\1/p')
    duration=$(echo "$sync_output" | sed -n 's/.*time=\([^;]*\).*/\1/p')
    error_msg=$(echo "$sync_output" | sed -n 's/.*error=\([^;]*\).*/\1/p')
    
    # Format action for display
    local action_display="$action"
    [ "$action" = "clone" ] && action_display="clone"
    [ "$action" = "fetch" ] && action_display="checkout"
    
    if [ "$status" = "ok" ]; then
      # Show result
      _sync_tree_item "$svc_sub_prefix" "1" "$(c 32 "✓")" "$action_display: $(c 32 "$result_commit") $(c 90 "(${duration}s)")"
      synced=$((synced + 1))
    else
      errors=$((errors + 1))
      failed_services+=("$svc")
      
      _sync_tree_item "$svc_sub_prefix" "0" "$(c 31 "✗")" "$(c 31 "FAILED")"
      
      # Show error details (always show on failure)
      local err_prefix="$svc_sub_prefix$_sync_tree_space"
      
      local repo_url
      repo_url="$(get_service_field "$stack" "$svc" repo 2>/dev/null || echo "unknown")"
      # Sanitize URL for display (remove credentials)
      repo_url=$(echo "$repo_url" | sed 's|://[^@]*@|://***@|g')
      
      _sync_tree_item "$err_prefix" "0" "•" "repo: $(c 90 "$repo_url")"
      _sync_tree_item "$err_prefix" "0" "•" "branch: $(c 90 "$branch")"
      _sync_tree_item "$err_prefix" "1" "•" "error: $(c 31 "$error_msg")"
    fi
  done
  
  # Result
  local end_ms=$(now_ms)
  local duration_ms=$((end_ms - start_ms))
  local duration_s=$((duration_ms / 1000))
  
  if [ $errors -eq 0 ]; then
    printf "✅ $(c 32 "Sync completed") in %ds (%d synced, %d skipped)\n" "$duration_s" "$synced" "$skipped"
    return 0
  else
    printf "❌ $(c 31 "Sync failed"): %d error(s)\n" "$errors"
    printf "   Check repository access and branch names\n"
    return 1
  fi
}

# Command: swarmcli build <stack>
# Flags:
#   --parallel  Build services in parallel (batches of 4)
#   --pull      Sync repos before build
#   --force     Force rebuild even if image exists
#   --no-cache  Disable Docker build cache
#   --verbose   Show all logs (default: shows build output)
cmd_build() {
  local start_ts=$(date +%s)
  local stack="$1"
  shift || true
  
  # Parse flags
  while [ $# -gt 0 ]; do
    case "$1" in
      --verbose|-v) VERBOSE=1 ;;
    esac
    shift
  done
  
  [ -n "$stack" ] || fail "usage: swarmcli build <STACK> --profile <PROFILE> [--parallel] [flags]"
  
  ensure_stack_exists "$stack"
  
  # Sync repos if --pull flag
  if [ "$WITH_PULL" = "1" ]; then
    cmd_repos_sync "$stack"
  fi
  
  # Load services registry (generates SERVICE_* variables from endpoints.yaml)
  # Required for variable substitution in build variables
  if registry_exists; then
    load_services_registry
  fi
  
  # Load build variables
  if [ "$DRY_RUN" != "1" ]; then
    load_variables_yaml "$stack" "common" || true
    load_variables_yaml "$stack" "build" || true
  fi
  
  # Build with full output (shows Docker build logs)
  cmd_build_with_output "$stack"
  local rc=$?
  [ $rc -eq 0 ] || exit $rc
  
  local end_ts=$(date +%s)
  printf "✅ $(c 32 "Build completed") in %ds\n" "$((end_ts-start_ts))"
}

# Build images with full Docker output
# Usage: cmd_build_with_output <stack>
cmd_build_with_output() {
  local stack="$1"
  local start_ms=$(now_ms)
  
  # Collect services info
  local services
  services=$(services_to_process "$stack")
  local services_arr=()
  while IFS= read -r svc; do
    [ -n "$svc" ] && services_arr+=("$svc")
  done <<< "$services"
  
  local total=${#services_arr[@]}
  local build_count=0
  local ext_count=0
  
  # Count build vs external
  for svc in "${services_arr[@]}"; do
    if is_service_internal "$stack" "$svc"; then
      build_count=$((build_count + 1))
    else
      ext_count=$((ext_count + 1))
    fi
  done
  
  # Header
  printf "\n$(c 90 "─────────────────────────────────────────────────────────────")\n"
  printf "🔨 $(c 1 "Building images:") %s $(c 90 "(%d to build, %d external)")\n" "$stack" "$build_count" "$ext_count"
  
  local errors=0
  local built=0
  local skipped=0
  local failed_services=()
  
  for svc in "${services_arr[@]}"; do
    # Check if external
    if ! is_service_internal "$stack" "$svc"; then
      printf "├─ $(c 36 "%s") $(c 90 "skipped (external)")\n" "$svc"
      skipped=$((skipped + 1))
      continue
    fi
    
    # Get image info
    local image shortsha tag
    image="$(get_service_field "$stack" "$svc" image)"
    shortsha="$(resolve_commit_sha "$stack" "$svc")"
    tag="${ACTIVE_PROFILE}-${shortsha}"
    
    # Check if image exists (skip unless force)
    if [ "$FORCE_REBUILD" != "1" ] && image_tag_exists "$image" "$tag"; then
      printf "├─ $(c 36 "%s") $(c 90 "skipped (exists: %s:%s)")\n" "$svc" "$image" "$tag"
      # Save expected tag for verification
      if declare -f set_expected_image_tag >/dev/null 2>&1; then
        set_expected_image_tag "$stack" "$svc" "$tag"
      fi
      if declare -f set_expected_image_id >/dev/null 2>&1; then
        local image_id
        image_id=$(docker image inspect "${image}:${tag}" --format '{{.Id}}' 2>/dev/null || echo "")
        [ -n "$image_id" ] && set_expected_image_id "$stack" "$svc" "$image_id"
      fi
      skipped=$((skipped + 1))
      continue
    fi
    
    printf "\n$(c 90 "─────────────────────────────────────────────────────────────")\n"
    printf "🔨 $(c 1 "Building:") $(c 36 "%s") → %s:%s\n\n" "$svc" "$image" "$tag"
    
    # Get branch for build
    local branch
    branch="$(resolve_branch "$stack" "$svc")"
    
    # Run build with full output
    local build_start=$(date +%s)
    if build_for_service "$stack" "$svc" "$branch"; then
      local build_duration=$(($(date +%s) - build_start))
      printf "\n$(c 32 "✓") $(c 36 "%s") built in %ds\n" "$svc" "$build_duration"
      built=$((built + 1))
    else
      local build_rc=$?
      local build_duration=$(($(date +%s) - build_start))
      printf "\n$(c 31 "✗") $(c 36 "%s") $(c 31 "FAILED") after %ds\n" "$svc" "$build_duration"
      errors=$((errors + 1))
      failed_services+=("$svc")
      
      # Continue to next service (don't fail immediately)
      # This allows seeing all build errors at once
    fi
  done
  
  printf "\n$(c 90 "─────────────────────────────────────────────────────────────")\n"
  
  if [ $errors -eq 0 ]; then
    return 0
  else
    printf "❌ $(c 31 "Build failed"): %d error(s)\n" "$errors"
    printf "   Failed: %s\n" "${failed_services[*]}"
    return 1
  fi
}
