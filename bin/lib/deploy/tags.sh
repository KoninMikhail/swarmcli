#!/usr/bin/env bash
# Service tag export for docker-compose

# Export TAG variables for docker-compose
# Usage: export_service_tags <stack>
# 
# Priority for tag resolution:
#   1. Saved expected tag from build (get_expected_image_tag) - most reliable
#   2. For selected services: resolve from commit SHA
#   3. For non-selected: current running service tag
#   4. Fallback: resolve from commit SHA
export_service_tags() {
  local stack="$1"
  
  local all_services
  all_services=$(get_services_list "$stack")
  
  local selected_services
  selected_services=$(services_to_process "$stack")
  
  local selected_array=()
  while IFS= read -r svc; do
    [ -n "$svc" ] || continue
    selected_array+=("$svc")
  done <<< "$selected_services"
  
  is_selected() {
    local svc="$1"
    local s
    for s in "${selected_array[@]}"; do
      if [ "$s" = "$svc" ]; then
        return 0
      fi
    done
    return 1
  }
  
  get_current_service_tag() {
    local svc="$1"
    local service_name="${stack}_${svc}"
    local image
    
    image=$(docker service inspect "$service_name" --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' 2>/dev/null || echo "")
    
    if [ -n "$image" ]; then
      echo "$image" | sed 's/.*://' || echo ""
    else
      echo ""
    fi
  }
  
  local exported=0
  while IFS= read -r svc; do
    [ -n "$svc" ] || continue
    
    if ! is_service_internal "$stack" "$svc"; then
      log info "skipping TAG export for external service: $svc (uses public Docker image)"
      continue
    fi
    
    local sha tag var
    
    # DRY_RUN mode: use placeholder tag
    if [ "$DRY_RUN" = "1" ]; then
      sha=$(resolve_commit_sha "$stack" "$svc" 2>/dev/null || echo "dry-run")
      [ -n "$sha" ] || sha="dry-run"
      tag="${ACTIVE_PROFILE}-${sha}"
    # CONFIG_ONLY mode: always use current running tag
    elif [ "${CONFIG_ONLY:-}" = "1" ]; then
      tag=$(get_current_service_tag "$svc")
      if [ -z "$tag" ]; then
        sha="$(resolve_commit_sha "$stack" "$svc")"
        tag="${ACTIVE_PROFILE}-${sha}"
        log warn "service $svc not running, using commit SHA tag: $tag"
      else
        log info "config-only: using current tag for $svc: $tag"
      fi
    else
      # Priority 1: Use saved expected tag from build (most reliable)
      if declare -f get_expected_image_tag >/dev/null 2>&1; then
        tag=$(get_expected_image_tag "$stack" "$svc" 2>/dev/null || echo "")
      fi
      
      if [ -n "$tag" ]; then
        log detail "using saved expected tag for $svc: $tag"
      elif is_selected "$svc"; then
        # Priority 2: For selected services, resolve from commit SHA
        sha="$(resolve_commit_sha "$stack" "$svc")"
        tag="${ACTIVE_PROFILE}-${sha}"
      else
        # Priority 3: For non-selected, try current running tag
        tag=$(get_current_service_tag "$svc")
        if [ -z "$tag" ]; then
          # Priority 4: Fallback to commit SHA
          sha="$(resolve_commit_sha "$stack" "$svc")"
          tag="${ACTIVE_PROFILE}-${sha}"
          log warn "service $svc not running, using commit SHA tag: $tag"
        else
          log info "using current tag for $svc: $tag"
        fi
      fi
    fi
    
    var="TAG_$(echo "$svc" | tr '[:lower:]-' '[:upper:]_')"
    
    export "$var"="$tag"
    log detail "exported $var=$tag"
    
    exported=$((exported+1))
  done <<< "$all_services"
  
  return 0
}
