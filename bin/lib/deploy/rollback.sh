#!/usr/bin/env bash
# Rollback deployment operations

# Rebuild service from specific commit (for rollback)
# Usage: rebuild_service_at_commit <stack> <service> <commit>
rebuild_service_at_commit() {
  local stack="$1" svc="$2" commit="$3"
  
  if ! is_service_internal "$stack" "$svc"; then
    log info "skipping rebuild for external service: $svc (uses public Docker image)"
    return 0
  fi
  
  log info "rebuilding $svc from commit $commit"
  
  local repo_dir
  repo_dir="$(get_service_repo_dir "$stack" "$svc")"
  
  if [ ! -d "$repo_dir/.git" ]; then
    add_error "repository not found: $repo_dir"
    return 1
  fi
  
  local current_ref
  current_ref=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
  
  if ! git -C "$repo_dir" cat-file -e "$commit" 2>/dev/null; then
    add_error "commit $commit not found in $svc repository"
    return 1
  fi
  
  log info "checking out commit $commit in $svc"
  git -C "$repo_dir" checkout "$commit" >/dev/null 2>&1 || {
    add_error "failed to checkout $commit"
    return 1
  }
  
  local image context dockerfile
  image=$(get_service_field "$stack" "$svc" image)
  context=$(get_service_field "$stack" "$svc" build.context)
  dockerfile=$(get_service_field "$stack" "$svc" build.dockerfile)
  
  [ -n "$context" ] || context=$(get_service_field "$stack" "$svc" context)
  [ -n "$dockerfile" ] || dockerfile=$(get_service_field "$stack" "$svc" dockerfile)
  [ -n "$context" ] || context="."
  [ -n "$dockerfile" ] || dockerfile="Dockerfile"
  
  local sha
  sha=$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null)
  local tag="${ACTIVE_PROFILE}-${sha}"
  
  log info "building $image:$tag from $commit"
  
  local build_ctx="$repo_dir/$context"
  local -a build_cmd=(docker build)
  
  if command -v docker-buildx >/dev/null 2>&1 || docker buildx version >/dev/null 2>&1; then
    build_cmd=(docker buildx build --load)
  fi
  
  local -a ba_flags=()
  while IFS= read -r kv; do
    [ -n "$kv" ] || continue
    ba_flags+=("--build-arg" "$kv")
  done < <(iter_build_args "$stack" "$svc")
  
  for section in "common" "build"; do
    while IFS='=' read -r key val; do
      [ -n "$key" ] || continue
      local interpolated_val
      interpolated_val="$(safe_interpolate "$val")"
      ba_flags+=("--build-arg" "${key}=${interpolated_val}")
    done < <(iter_variables_yaml "$stack" "$section")
  done
  
  export DOCKER_BUILDKIT=1
  export BUILDKIT_PROGRESS=plain
  
  local cache_bust
  cache_bust="${sha}-$(date +%s)"
  ba_flags+=("--build-arg" "CACHE_BUST=${cache_bust}")
  
  _rebuild_cmd() {
    "${build_cmd[@]}" \
      -f "$repo_dir/$dockerfile" \
      -t "$image:$tag" \
      "${ba_flags[@]}" \
      "$build_ctx"
  }
  
  if ! retry_with_backoff _rebuild_cmd; then
    add_error "build failed for $svc after retries"
    git -C "$repo_dir" checkout "$current_ref" >/dev/null 2>&1 || true
    return 1
  fi
  
  log ok "rebuilt $image:$tag"
  
  log info "restoring $svc to $current_ref"
  git -C "$repo_dir" checkout "$current_ref" >/dev/null 2>&1 || {
    log warn "failed to restore original ref, staying at $commit"
  }
  
  return 0
}

# Rollback to previous deployment
# Usage: rollback_deploy <stack> [--to-version N]
rollback_deploy() {
  local stack="$1"
  shift
  
  local version_offset=1
  while [ $# -gt 0 ]; do
    case "$1" in
      --to-version)
        shift
        version_offset="$1"
        ;;
    esac
    shift || true
  done
  
  log warn "rolling back $stack to version -$version_offset"
  
  local history_dir
  history_dir="$(get_deploy_history_dir "$stack")"
  local history_file="$history_dir/history.jsonl"
  
  if [ ! -f "$history_file" ]; then
    add_error "no deploy history found for $stack"
    return 1
  fi
  
  local target_deploy
  target_deploy=$(tac "$history_file" | grep '"status":"success"' | sed -n "${version_offset}p")
  
  if [ -z "$target_deploy" ]; then
    add_error "no deployment found at offset $version_offset"
    return 1
  fi
  
  log info "target deployment found"
  
  local deploy_time
  deploy_time=$(parse_json_field "$target_deploy" "timestamp")
  log info "rollback target: $deploy_time"
  
  if [ "$DRY_RUN" = "1" ]; then
    echo "Would rollback to:"
    echo "  Timestamp: $deploy_time"
    echo "  Services:"
    
    local services_json
    services_json=$(parse_json_services "$target_deploy")
    
    while IFS= read -r svc_json; do
      [ -n "$svc_json" ] || continue
      local svc_name svc_tag svc_commit
      svc_name=$(parse_json_field "$svc_json" "service")
      svc_tag=$(parse_json_field "$svc_json" "tag")
      svc_commit=$(parse_json_field "$svc_json" "commit")
      echo "    - $svc_name: $svc_tag (commit: $svc_commit)"
    done <<< "$services_json"
    
    return 0
  fi
  
  local services_json
  services_json=$(parse_json_services "$target_deploy")
  
  local all_images_ready=1
  local missing_services=()
  
  while IFS= read -r svc_json; do
    [ -n "$svc_json" ] || continue
    
    local svc image tag commit
    svc=$(parse_json_field "$svc_json" "service")
    image=$(parse_json_field "$svc_json" "image")
    tag=$(parse_json_field "$svc_json" "tag")
    commit=$(parse_json_field "$svc_json" "commit")
    
    log info "checking $svc: $image:$tag"
    
    if docker image inspect "${image}:${tag}" >/dev/null 2>&1; then
      log ok "image exists: $image:$tag"
    else
      log warn "image not found: $image:$tag, will rebuild from commit $commit"
      
      if rebuild_service_at_commit "$stack" "$svc" "$commit"; then
        log ok "successfully rebuilt $image:$tag"
      else
        log error "failed to rebuild $svc from commit $commit"
        missing_services+=("$svc")
        all_images_ready=0
      fi
    fi
  done <<< "$services_json"
  
  if [ $all_images_ready -eq 0 ]; then
    add_error "some images could not be prepared: ${missing_services[*]}"
    return 1
  fi
  
  log info "exporting TAG variables for rollback"
  
  while IFS= read -r svc_json; do
    [ -n "$svc_json" ] || continue
    
    local svc tag
    svc=$(parse_json_field "$svc_json" "service")
    tag=$(parse_json_field "$svc_json" "tag")
    
    local var_name
    var_name="TAG_$(echo "$svc" | tr '[:lower:]-' '[:upper:]_')"
    export "$var_name"="$tag"
    log detail "exported $var_name=$tag"
  done <<< "$services_json"
  
  load_variables_yaml "$stack" "common" || true
  load_variables_yaml "$stack" "deploy" || true
  
  # Render Jinja2 templates if stack uses them (needed for correct compose path)
  if stack_has_templates "$stack"; then
    if ! ensure_templates_rendered "$stack"; then
      add_error "template rendering failed during rollback"
      return 1
    fi
  fi
  
  local compose
  compose="$(get_rendered_compose_path "$stack")"
  
  log info "deploying stack with rollback tags"
  
  if ! retry_with_backoff docker stack deploy --resolve-image always -c "$compose" "$stack"; then
    add_error "rollback deployment failed after retries"
    return 2
  fi
  
  save_deploy_history "$stack" "success"
  
  log ok "rollback completed successfully"
  return 0
}
