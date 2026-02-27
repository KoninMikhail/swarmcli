#!/usr/bin/env bash
# Sync commands

_run_repos_sync() {
  local stack="$1"
  local services any_err br svc commit_sha
  services=$(services_to_process "$stack")
  any_err=0
  
  while IFS= read -r svc; do
    [ -n "$svc" ] || continue
    
    # Handle external services (registry images)
    if ! is_service_internal "$stack" "$svc"; then
      sync_external_image "$stack" "$svc" || any_err=2
      continue
    fi
    
    # Handle internal services (git repositories)
    br="$(resolve_branch "$stack" "$svc")"
    
    # Get per-service commit SHA if specified, otherwise fallback to env vars
    commit_sha=""
    if [ -n "${SERVICE_COMMITS[$svc]:-}" ]; then
      commit_sha="${SERVICE_COMMITS[$svc]}"
    elif [ -n "${CI_COMMIT_SHA:-}" ]; then
      commit_sha="$CI_COMMIT_SHA"
    elif [ -n "${COMMIT_SHA:-}" ]; then
      commit_sha="$COMMIT_SHA"
    fi
    
    sync_repo_for_service "$stack" "$svc" "$br" "$commit_sha" || any_err=2
  done <<< "$services"
  return $any_err
}

# Helper: run build for spinner (sequential)
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
  local total_batches
  total_batches=$(( (total + batch_size - 1) / batch_size ))
  
  # Ensure log directory exists
  local build_log_dir="${HOME}/.swarm-deploy/logs"
  mkdir -p "$build_log_dir" 2>/dev/null || build_log_dir="/tmp"
  
  log info "parallel build: $total services in $total_batches batch(es) (max $batch_size concurrent)"
  
  # Process services in batches
  while [ $current_batch -lt $total ]; do
    local pids=()
    local log_files=()
    local service_names=()
    local batch_end
    batch_end=$((current_batch + batch_size))
    [ $batch_end -gt $total ] && batch_end=$total
    local batch_count
    batch_count=$((batch_end - current_batch))
    
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
cmd_repos_sync() {
  local start_ts
  start_ts=$(date +%s)
  local stack="$1"
  local tree_mode="${SYNC_TREE:-0}"
  local verbose_mode="${VERBOSE:-0}"
  shift || true
  
  # Parse flags
  while [ $# -gt 0 ]; do
    case "$1" in
      --tree|-t) tree_mode=1 ;;
      --verbose|-v) verbose_mode=1 ;;
    esac
    shift
  done
  
  [ -n "$stack" ] || fail "usage: swarmcli repos sync <STACK> --profile <PROFILE> [--tree] [--verbose]"
  
  ensure_stack_exists "$stack"
  
  # Use tree mode if requested or in CI
  if [ "$tree_mode" = "1" ] || is_ci; then
    cmd_repos_sync_tree "$stack" "$verbose_mode"
    return $?
  fi
  
  _run_repos_sync "$stack"
  local rc=$?
  if [ $rc -ne 0 ]; then
    print_errors
    exit $rc
  fi
  
  local end_ts
  end_ts=$(date +%s)
  log ok "repos sync completed in $((end_ts-start_ts))s"
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

# Command: swarmcli repos sync <stack> --tree
# Tree-style output for CI and pretty display
cmd_repos_sync_tree() {
  local stack="$1"
  local verbose="${2:-0}"
  local start_ms
  start_ms=$(now_ms)
  
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
  
  # Header (with separator for CI readability)
  printf "\n$(c 90 "─────────────────────────────────────────────────────────────")\n\n"
  printf "🔄 $(c 1 "Syncing repositories:") %s $(c 90 "(profile: %s)")\n" "$stack" "$ACTIVE_PROFILE"
  printf "\n"
  
  # Services section
  printf "%s 📦 $(c 1 "Services") $(c 90 "(%d git, %d external)")\n" "$_sync_tree_branch" "$git_count" "$ext_count"
  local svc_prefix="$_sync_tree_pipe"
  
  local errors=0
  local synced=0
  local skipped=0
  local failed_services=()
  
  local idx=0
  for svc in "${services_arr[@]}"; do
    idx=$((idx + 1))
    local is_last_svc
    is_last_svc=$( [ $idx -eq $total ] && echo "1" || echo "0" )
    
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
      _sync_tree_item "$svc_sub_prefix" "1" "$(c 90 "○")" "external $(c 90 "(skipped)")"
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
      commit_source="service override"
    elif [ -n "${CI_COMMIT_SHA:-}" ]; then
      commit_source="CI"
    elif [ -n "${COMMIT_SHA:-}" ]; then
      commit_source="env"
    fi
    
    # Show target: branch and commit if specified
    if [ -n "$commit_sha" ]; then
      _sync_tree_item "$svc_sub_prefix" "0" "$(c 90 "○")" "target: $branch @ $(c 33 "${commit_sha:0:7}") $(c 90 "($commit_source)")"
    else
      _sync_tree_item "$svc_sub_prefix" "0" "$(c 90 "○")" "target: $branch $(c 90 "(default branch)")"
    fi
    
    # Verbose: show repo path
    if [ "$verbose" = "1" ]; then
      local repo_dir
      repo_dir="$(get_service_repo_dir "$stack" "$svc")"
      _sync_tree_item "$svc_sub_prefix" "0" "$(c 90 "○")" "path: $(c 90 "$repo_dir")"
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
    [ "$action" = "fetch" ] && action_display="fetch + checkout"
    
    if [ "$status" = "ok" ]; then
      # Show action
      _sync_tree_item "$svc_sub_prefix" "0" "$(c 32 "✓")" "action: $action_display"
      
      # Show result
      _sync_tree_item "$svc_sub_prefix" "1" "$(c 32 "✓")" "result: $(c 32 "$result_commit") $(c 90 "(${duration}s)")"
      synced=$((synced + 1))
    else
      errors=$((errors + 1))
      failed_services+=("$svc")
      
      _sync_tree_item "$svc_sub_prefix" "0" "$(c 31 "✗")" "$(c 31 "FAILED")"
      
      # Show error details (always show on failure)
      local err_prefix="$svc_sub_prefix$_sync_tree_space"
      printf "%s$(c 31 "🔴") Error details:\n" "$err_prefix"
      
      local repo_url
      repo_url="$(get_service_field "$stack" "$svc" repo 2>/dev/null || echo "unknown")"
      # Sanitize URL for display (remove credentials)
      repo_url=$(echo "$repo_url" | sed 's|://[^@]*@|://***@|g')
      
      _sync_tree_item "$err_prefix" "0" "$(c 90 "•")" "repo: $(c 90 "$repo_url")"
      _sync_tree_item "$err_prefix" "0" "$(c 90 "•")" "branch: $(c 90 "$branch")"
      _sync_tree_item "$err_prefix" "0" "$(c 90 "•")" "action: $(c 90 "$action")"
      _sync_tree_item "$err_prefix" "1" "$(c 31 "•")" "error: $(c 31 "$error_msg")"
    fi
  done
  
  printf "\n"
  
  # Result
  local end_ms
  end_ms=$(now_ms)
  local duration_ms
  duration_ms=$((end_ms - start_ms))
  local duration_s
  duration_s=$((duration_ms / 1000))
  
  if [ $errors -eq 0 ]; then
    printf "✅ $(c 32 "Sync completed") in %ds (%d synced, %d skipped)\n\n" "$duration_s" "$synced" "$skipped"
    return 0
  else
    printf "❌ $(c 31 "Sync failed"): %d error(s), %d synced, %d skipped\n" "$errors" "$synced" "$skipped"
    
    # Hints section
    printf "\n"
    printf "   💡 $(c 1 "Hints:")\n"
    printf "   %s Check SSH key / CI_JOB_TOKEN has access to repositories\n" "$_sync_tree_branch"
    printf "   %s Verify branch names in services.yaml\n" "$_sync_tree_branch"
    printf "   %s Run with --verbose for detailed output\n" "$_sync_tree_last"
    printf "\n"
    return 1
  fi
}

# ============================================
# Tree-style build output
# ============================================

# Tree drawing characters for build (same as sync)
_build_tree_branch="├─"
_build_tree_last="└─"
_build_tree_pipe="│ "
_build_tree_space="  "

# Print tree item for build
_build_tree_item() {
  local prefix="$1" is_last="$2" icon="$3" text="$4"
  if [ "$is_last" = "1" ]; then
    printf "%s%s %s %s\n" "$prefix" "$_build_tree_last" "$icon" "$text"
  else
    printf "%s%s %s %s\n" "$prefix" "$_build_tree_branch" "$icon" "$text"
  fi
}

# Command: swarmcli build <stack> --tree
# Tree-style output for CI and pretty display
cmd_build_tree() {
  local stack="$1"
  local verbose="${2:-0}"
  local start_ms
  start_ms=$(now_ms)
  
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
  
  # Header (with separator for CI readability)
  printf "\n$(c 90 "─────────────────────────────────────────────────────────────")\n\n"
  printf "🔨 $(c 1 "Building images:") %s $(c 90 "(profile: %s)")\n" "$stack" "$ACTIVE_PROFILE"
  printf "\n"
  
  # Services section
  printf "%s 📦 $(c 1 "Services") $(c 90 "(%d to build, %d external)")\n" "$_build_tree_branch" "$build_count" "$ext_count"
  local svc_prefix="$_build_tree_pipe"
  
  local errors=0
  local built=0
  local skipped=0
  local failed_services=()
  
  local idx=0
  for svc in "${services_arr[@]}"; do
    idx=$((idx + 1))
    local is_last_svc
    is_last_svc=$( [ $idx -eq $total ] && echo "1" || echo "0" )
    
    # Service name line
    if [ "$is_last_svc" = "1" ]; then
      printf "%s%s $(c 36 "%s")\n" "$svc_prefix" "$_build_tree_last" "$svc"
      local svc_sub_prefix="$svc_prefix$_build_tree_space"
    else
      printf "%s%s $(c 36 "%s")\n" "$svc_prefix" "$_build_tree_branch" "$svc"
      local svc_sub_prefix="$svc_prefix$_build_tree_pipe"
    fi
    
    # Check if external
    if ! is_service_internal "$stack" "$svc"; then
      _build_tree_item "$svc_sub_prefix" "1" "$(c 90 "○")" "external $(c 90 "(skipped)")"
      skipped=$((skipped + 1))
      continue
    fi
    
    # Get image info for display
    local image context dockerfile shortsha tag
    image="$(get_service_field "$stack" "$svc" image)"
    context="$(get_service_field "$stack" "$svc" build.context)"
    dockerfile="$(get_service_field "$stack" "$svc" build.dockerfile)"
    [ -z "$context" ] && context="$(get_service_field "$stack" "$svc" context)"
    [ -z "$dockerfile" ] && dockerfile="$(get_service_field "$stack" "$svc" dockerfile)"
    [ -z "$context" ] && context="."
    [ -z "$dockerfile" ] && dockerfile="Dockerfile"
    shortsha="$(resolve_commit_sha "$stack" "$svc")"
    tag="${ACTIVE_PROFILE}-${shortsha}"
    
    # Show image info
    _build_tree_item "$svc_sub_prefix" "0" "$(c 90 "○")" "image: $(c 33 "$image:$tag")"
    
    # Verbose: show context
    if [ "$verbose" = "1" ]; then
      _build_tree_item "$svc_sub_prefix" "0" "$(c 90 "○")" "context: $(c 90 "$context ($dockerfile)")"
    fi
    
    # Get branch for build
    local branch
    branch="$(resolve_branch "$stack" "$svc")"
    
    # Run build and capture result
    local build_output build_rc
    build_output=$(build_for_service_info "$stack" "$svc" "$branch" 2>&1)
    build_rc=$?
    
    # Parse result
    local status action reason build_image build_tag duration error_msg log_file
    status=$(echo "$build_output" | sed -n 's/.*status=\([^;]*\).*/\1/p')
    action=$(echo "$build_output" | sed -n 's/.*action=\([^;]*\).*/\1/p')
    reason=$(echo "$build_output" | sed -n 's/.*reason=\([^;]*\).*/\1/p')
    duration=$(echo "$build_output" | sed -n 's/.*time=\([^;]*\).*/\1/p')
    error_msg=$(echo "$build_output" | sed -n 's/.*error=\([^;]*\).*/\1/p')
    log_file=$(echo "$build_output" | sed -n 's/.*log=\([^;]*\).*/\1/p')
    
    if [ "$status" = "ok" ]; then
      # Show action and result
      _build_tree_item "$svc_sub_prefix" "0" "$(c 32 "✓")" "action: $action"
      _build_tree_item "$svc_sub_prefix" "1" "$(c 32 "✓")" "result: $(c 32 "built") in ${duration}s"
      built=$((built + 1))
    elif [ "$status" = "skipped" ]; then
      if [ "$reason" = "exists" ]; then
        _build_tree_item "$svc_sub_prefix" "1" "$(c 33 "○")" "skipped $(c 90 "(image exists)")"
      else
        _build_tree_item "$svc_sub_prefix" "1" "$(c 90 "○")" "skipped $(c 90 "($reason)")"
      fi
      skipped=$((skipped + 1))
    else
      errors=$((errors + 1))
      failed_services+=("$svc")
      
      _build_tree_item "$svc_sub_prefix" "0" "$(c 31 "✗")" "action: $action"
      _build_tree_item "$svc_sub_prefix" "0" "$(c 31 "✗")" "$(c 31 "FAILED") $(c 90 "(${duration}s)")"
      
      # Show error details
      local err_prefix="$svc_sub_prefix$_build_tree_space"
      printf "%s$(c 31 "🔴") Error: %s\n" "$err_prefix" "$error_msg"
      
      # Show last lines of build log
      if [ -n "$log_file" ] && [ -f "$log_file" ]; then
        printf "%s$(c 90 "Last 10 lines of log:")\n" "$err_prefix"
        get_build_log_tail "$log_file" 10
        _build_tree_item "$err_prefix" "1" "$(c 90 "•")" "full log: $(c 90 "$log_file")"
      fi
    fi
  done
  
  printf "\n"
  
  # Result
  local end_ms
  end_ms=$(now_ms)
  local duration_ms
  duration_ms=$((end_ms - start_ms))
  local duration_s
  duration_s=$((duration_ms / 1000))
  
  if [ $errors -eq 0 ]; then
    printf "✅ $(c 32 "Build completed") in %ds (%d built, %d skipped)\n\n" "$duration_s" "$built" "$skipped"
    return 0
  else
    printf "❌ $(c 31 "Build failed"): %d error(s), %d built, %d skipped\n" "$errors" "$built" "$skipped"
    
    # Show failed services
    printf "   Failed services: "
    local first=1
    for svc in "${failed_services[@]}"; do
      [ $first -eq 1 ] || printf ", "
      printf "$(c 31 "%s")" "$svc"
      first=0
    done
    printf "\n\n"
    
    return 1
  fi
}
