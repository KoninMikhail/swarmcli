#!/usr/bin/env bash
# Docker image build operations

# Build image for a service
# Usage: build_for_service <stack> <service> <branch>
# Returns: 0 on success, 1 on config error, 2 on build error
# Shows full Docker build output in real-time
build_for_service() {
  local stack="$1" svc="$2" branch="$3"
  
  ensure_cmd docker
  
  # Skip external services (no build required, uses public images)
  if ! is_service_internal "$stack" "$svc"; then
    log info "skipping build for external service: $svc (uses public Docker image)"
    return 0
  fi
  
  # Get service config (supporting both new and legacy formats)
  local image context dockerfile
  image="$(get_service_field "$stack" "$svc" image)"
  
  # New format: build.context and build.dockerfile
  context="$(get_service_field "$stack" "$svc" build.context)"
  dockerfile="$(get_service_field "$stack" "$svc" build.dockerfile)"
  
  # Legacy format fallback
  if [ -z "$context" ]; then
    context="$(get_service_field "$stack" "$svc" context)"
  fi
  if [ -z "$dockerfile" ]; then
    dockerfile="$(get_service_field "$stack" "$svc" dockerfile)"
  fi
  
  [ -n "$context" ] || context="."
  [ -n "$dockerfile" ] || dockerfile="Dockerfile"
  
  # Check repo exists
  local repo_dir
  repo_dir="$(get_service_repo_dir "$stack" "$svc")"
  if [ ! -d "$repo_dir/.git" ]; then
    printf "$(c 31 "ERROR:") Repository missing for %s at %s\n" "$svc" "$repo_dir"
    printf "       Run 'swarmcli sync' first.\n"
    add_error "repository missing for $svc at $repo_dir"
    return 1
  fi
  
  # Get commit SHA
  local shortsha
  shortsha="$(resolve_commit_sha "$stack" "$svc")"
  
  # Generate tag with SHA (format: profile-sha)
  local tag="${ACTIVE_PROFILE}-${shortsha}"
  
  # Build paths
  local ctx_path="$repo_dir/$context"
  local df_path="$ctx_path/$dockerfile"
  
  # Check Dockerfile exists (important error to show clearly)
  if [ ! -f "$df_path" ]; then
    printf "$(c 31 "ERROR:") Dockerfile not found: %s\n" "$df_path"
    printf "       Context: %s\n" "$ctx_path"
    printf "       Dockerfile: %s\n" "$dockerfile"
    add_error "Dockerfile not found: $df_path"
    return 1
  fi
  
  # Skip if exists (unless force rebuild) - this check is done in cmd_build_with_output
  # but keep it here for direct calls to build_for_service
  if [ "$FORCE_REBUILD" != "1" ] && image_tag_exists "$image" "$tag"; then
    log info "image exists, skipping: $image:$tag"
    if declare -f set_expected_image_tag >/dev/null 2>&1; then
      set_expected_image_tag "$stack" "$svc" "$tag"
    fi
    if declare -f set_expected_image_id >/dev/null 2>&1; then
      local image_id
      image_id=$(timeout "${IMAGE_CHECK_TIMEOUT:-5}" docker image inspect "${image}:${tag}" --format '{{.Id}}' 2>/dev/null || echo "")
      [ -n "$image_id" ] && set_expected_image_id "$stack" "$svc" "$image_id"
    fi
    return 0
  fi
  
  # Collect build args from services.yaml
  local build_args=()
  local build_args_keys=""
  while IFS= read -r kv; do
    [ -n "$kv" ] || continue
    build_args+=("--build-arg" "$kv")
    local key="${kv%%=*}"
    build_args_keys="${build_args_keys}${key} "
  done < <(iter_build_args "$stack" "$svc")
  
  # Add build variables from variables.yaml
  # Note: values may contain ${VAR} references that need interpolation
  for section in "common" "build"; do
    while IFS='=' read -r key val; do
      [ -n "$key" ] || continue
      case " ${build_args_keys} " in
        *" ${key} "*) continue ;;
      esac
      # Interpolate ${VAR} references in value (safe, no eval)
      # This allows using SERVICE_* variables from endpoints.yaml
      local interpolated_val
      interpolated_val="$(safe_interpolate "$val")"
      build_args+=("--build-arg" "${key}=${interpolated_val}")
    done < <(iter_variables_yaml "$stack" "$section")
  done
  
  # Build configuration
  local use_cache=""
  local cache_from_args=()
  
  export DOCKER_BUILDKIT=1
  export BUILDKIT_PROGRESS=plain
  
  # Add CACHE_BUST build arg
  local cache_bust
  cache_bust="${shortsha}-$(date +%s)"
  build_args+=("--build-arg" "CACHE_BUST=${cache_bust}")
  
  if [ "$NO_CACHE" = "1" ]; then
    use_cache="--no-cache"
    printf "$(c 33 "Warning:") using --no-cache (disables BuildKit cache mounts)\n"
  else
    local cache_image="${image}:${ACTIVE_PROFILE}-cache"
    if docker image inspect "$cache_image" >/dev/null 2>&1; then
      cache_from_args=("--cache-from" "$cache_image")
      [ "$VERBOSE" = "1" ] && printf "Using cache from: %s\n" "$cache_image"
    fi
  fi
  
  if [ "$DRY_RUN" = "1" ]; then
    printf "$(c 90 "dry-run:") would build %s:%s\n" "$image" "$tag"
    return 0
  fi
  
  # Check for cancellation before starting build
  if declare -f check_cancellation_requested >/dev/null 2>&1; then
    check_cancellation_requested "$stack" || return 130
  fi
  
  # Set operation context for graceful shutdown
  if declare -f set_operation_context >/dev/null 2>&1; then
    set_operation_context "docker build $svc"
  fi
  
  # Get build timeout from stack settings or env (priority: stack > env > default)
  local build_timeout
  if declare -f get_stack_build_timeout >/dev/null 2>&1; then
    build_timeout="$(get_stack_build_timeout "$stack")"
  else
    build_timeout="${BUILD_TIMEOUT:-900}"
  fi
  
  # Build command - output goes directly to stdout (real-time)
  local build_rc=0
  local -a cache_flag=()
  [ -n "$use_cache" ] && cache_flag=("$use_cache")

  if docker buildx version >/dev/null 2>&1; then
    timeout "$build_timeout" docker buildx build "${cache_flag[@]}" --load \
      "${cache_from_args[@]}" \
      -t "$image:$tag" \
      -f "$df_path" \
      "$ctx_path" \
      "${build_args[@]}" || build_rc=$?
  else
    timeout "$build_timeout" docker build "${cache_flag[@]}" \
      "${cache_from_args[@]}" \
      -t "$image:$tag" \
      -f "$df_path" \
      "$ctx_path" \
      "${build_args[@]}" || build_rc=$?
  fi
  
  # Handle build result
  if [ $build_rc -ne 0 ]; then
    if [ $build_rc -eq 124 ]; then
      add_error "build timed out for $svc (timeout: ${build_timeout}s)"
      return 2
    fi
    if [ $build_rc -eq 130 ]; then
      printf "$(c 33 "Warning:") build cancelled for %s\n" "$svc"
      return 130
    fi
    add_error "build failed for $svc"
    return 2
  fi
  
  # Tag as cache source
  if [ "$NO_CACHE" != "1" ]; then
    local cache_image="${image}:${ACTIVE_PROFILE}-cache"
    if ! docker tag "$image:$tag" "$cache_image" >/dev/null 2>&1; then
      log warn "failed to tag cache image: $cache_image (non-critical)"
    fi
  fi
  
  # Save expected image tag for verification during deploy
  if declare -f set_expected_image_tag >/dev/null 2>&1; then
    set_expected_image_tag "$stack" "$svc" "$tag"
  fi
  
  # Save expected image ID for exact verification
  if declare -f set_expected_image_id >/dev/null 2>&1; then
    local image_id
    image_id=$(timeout "${IMAGE_CHECK_TIMEOUT:-5}" docker image inspect "${image}:${tag}" --format '{{.Id}}' 2>/dev/null || echo "")
    [ -n "$image_id" ] && set_expected_image_id "$stack" "$svc" "$image_id"
  fi
  
  return 0
}

# Build image for a service and return result info for tree display
# Usage: build_for_service_info <stack> <service> <branch>
# Output: semicolon-separated key=value string with build result
# Returns: 0 on success, non-zero on error
build_for_service_info() {
  local stack="$1" svc="$2" branch="$3"
  local start_ts
  start_ts=$(date +%s)
  
  # Check if external
  if ! is_service_internal "$stack" "$svc"; then
    echo "status=skipped;reason=external;time=0"
    return 0
  fi
  
  # Get image info
  local image context dockerfile
  image="$(get_service_field "$stack" "$svc" image)"
  context="$(get_service_field "$stack" "$svc" build.context)"
  dockerfile="$(get_service_field "$stack" "$svc" build.dockerfile)"
  [ -z "$context" ] && context="$(get_service_field "$stack" "$svc" context)"
  [ -z "$dockerfile" ] && dockerfile="$(get_service_field "$stack" "$svc" dockerfile)"
  [ -z "$context" ] && context="."
  [ -z "$dockerfile" ] && dockerfile="Dockerfile"
  
  # Get commit SHA and tag
  local shortsha tag
  shortsha="$(resolve_commit_sha "$stack" "$svc")"
  tag="${ACTIVE_PROFILE}-${shortsha}"
  
  # Check if image exists (skip unless force)
  if [ "$FORCE_REBUILD" != "1" ] && image_tag_exists "$image" "$tag"; then
    local end_ts
    end_ts=$(date +%s)
    echo "status=skipped;reason=exists;image=$image;tag=$tag;time=$((end_ts - start_ts))"
    return 0
  fi
  
  # Determine build method
  local build_method="docker"
  docker buildx version >/dev/null 2>&1 && build_method="buildx"
  
  # Build log path
  local build_log_dir="${HOME}/.swarm-deploy/logs"
  if ! mkdir -p "$build_log_dir" 2>/dev/null; then
    log warn "cannot create log directory $build_log_dir, falling back to ${TMPDIR:-/tmp}"
    build_log_dir="${TMPDIR:-/tmp}"
  fi
  local build_log="${build_log_dir}/build_${svc}.log"
  
  # Run actual build (suppress output, capture in log)
  local build_rc=0
  if ! build_for_service "$stack" "$svc" "$branch" >/dev/null 2>&1; then
    build_rc=$?
  fi
  
  local end_ts
  end_ts=$(date +%s)
  local duration
  duration=$((end_ts - start_ts))
  
  if [ $build_rc -eq 0 ]; then
    echo "status=ok;action=$build_method;image=$image;tag=$tag;time=$duration"
    return 0
  else
    local error_msg="build failed"
    [ $build_rc -eq 124 ] && error_msg="timeout"
    [ $build_rc -eq 130 ] && error_msg="cancelled"
    echo "status=failed;action=$build_method;image=$image;tag=$tag;error=$error_msg;log=$build_log;time=$duration"
    return $build_rc
  fi
}

# Get last N lines from build log (for error display)
# Usage: get_build_log_tail <log_file> [lines]
# Output: last N lines of log file
get_build_log_tail() {
  local log_file="$1"
  local lines="${2:-10}"
  
  if [ -f "$log_file" ]; then
    tail -n "$lines" "$log_file" 2>/dev/null | sed 's/^/        > /'
  else
    echo "        > (log file not found)"
  fi
}

# Force update all services in a stack
# Usage: force_update_services <stack>
force_update_services() {
  local stack="$1"
  
  if [ "$DRY_RUN" = "1" ]; then
    log info "dry-run: would force update services for stack $stack"
    return 0
  fi
  
  log info "force updating services for stack: $stack"
  
  local services
  services=$(docker stack services "$stack" --format "{{.Name}}" 2>/dev/null)
  
  if [ -z "$services" ]; then
    log warn "no services found for stack $stack"
    return 0
  fi
  
  local updated=0 failed=0
  while IFS= read -r service; do
    [ -n "$service" ] || continue
    
    log info "force updating service: $service"
    
    if retry_with_backoff docker service update --force "$service" >/dev/null 2>&1; then
      updated=$((updated+1))
    else
      log error "failed to force update service: $service after retries"
      failed=$((failed+1))
    fi
  done <<< "$services"
  
  log info "force updated $updated services ($failed failed)"
  return $failed
}
