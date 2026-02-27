#!/usr/bin/env bash
# Images commands

cmd_images_list() {
  local stack="$1"
  [ -n "$stack" ] || fail "usage: swarmcli images ls <STACK>"
  
  ensure_stack_exists "$stack"
  
  local services
  services=$(get_services_list "$stack")
  
  echo ""
  printf "  %-20s %-10s %-40s %-12s\n" "SERVICE" "TYPE" "IMAGE" "STATUS"
  printf "  %-20s %-10s %-40s %-12s\n" "-------" "----" "-----" "------"
  
  while IFS= read -r svc; do
    [ -n "$svc" ] || continue
    
    local svc_type image_name status
    svc_type=$(get_service_type "$stack" "$svc")
    image_name=$(get_service_field "$stack" "$svc" "image" 2>/dev/null || echo "-")
    
    if [ "$svc_type" = "git" ]; then
      # For internal services, check if image exists locally
      local expected_tag="${ACTIVE_PROFILE}-*"
      local found_image
      found_image=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep "^${image_name}:${ACTIVE_PROFILE}-" | head -1)
      
      if [ -n "$found_image" ]; then
        local tag="${found_image##*:}"
        status="local: $tag"
      else
        status="not built"
      fi
    else
      # External service - check if image is available
      if docker image inspect "$image_name" >/dev/null 2>&1; then
        status="available"
      else
        status="not pulled"
      fi
    fi
    
    printf "  %-20s %-10s %-40s %-12s\n" "$svc" "$svc_type" "$image_name" "$status"
  done <<< "$services"
  
  echo ""
}

# Verify images are built/available for stack
# Usage: cmd_images_verify <stack> [--sha <commit_sha>]
cmd_images_verify() {
  local stack="$1"
  shift || true
  
  [ -n "$stack" ] || fail "usage: swarmcli images verify <STACK> [--sha <SHA>]"
  
  ensure_stack_exists "$stack"
  
  # Parse optional --sha argument
  local expected_sha=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --sha) expected_sha="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  
  local services
  services=$(get_services_list "$stack")
  
  local all_ok=1
  local missing_images=()
  local found_images=()
  
  log_section "verify" "Verifying images for stack: $stack"
  
  while IFS= read -r svc; do
    [ -n "$svc" ] || continue
    
    local svc_type image_name
    svc_type=$(get_service_type "$stack" "$svc")
    image_name=$(get_service_field "$stack" "$svc" "image" 2>/dev/null || echo "")
    
    [ -n "$image_name" ] || continue
    
    if [ "$svc_type" = "git" ]; then
      # Internal service - check for locally built image with profile tag
      local expected_tag
      if [ -n "$expected_sha" ]; then
        local short_sha="${expected_sha:0:7}"
        expected_tag="${ACTIVE_PROFILE}-${short_sha}"
      else
        expected_tag="${ACTIVE_PROFILE}-"
      fi
      
      local found_image
      found_image=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep "^${image_name}:${expected_tag}" | head -1)
      
      if [ -n "$found_image" ]; then
        log ok "$svc: $found_image"
        found_images+=("$svc:$found_image")
        
        # Save expected tag for deployment verification
        local tag="${found_image##*:}"
        set_expected_image_tag "$stack" "$svc" "$tag" 2>/dev/null || true
      else
        log error "$svc: missing image ${image_name}:${expected_tag}*"
        missing_images+=("$svc:${image_name}:${expected_tag}*")
        all_ok=0
      fi
    else
      # External service - just check if image reference is valid (skip pull check)
      log info "$svc: external image $image_name (skipped)"
    fi
  done <<< "$services"
  
  echo ""
  
  if [ $all_ok -eq 1 ]; then
    log_section_result "ok" "All internal images verified (${#found_images[@]} found)"
    return 0
  else
    log_section_result "fail" "Missing images: ${#missing_images[@]}"
    echo ""
    echo "  Missing images:"
    for img in "${missing_images[@]}"; do
      echo "    - $img"
    done
    echo ""
    echo "  Run 'swarmcli build $stack' to build missing images."
    return 1
  fi
}

# Prune old images for stack
# Usage: cmd_images_prune <stack> [--keep <count>]
cmd_images_prune() {
  local stack="$1"
  shift || true
  
  [ -n "$stack" ] || fail "usage: swarmcli images prune <STACK> [--keep <N>]"
  
  ensure_stack_exists "$stack"
  
  local keep_count="${KEEP_IMAGES_COUNT:-10}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --keep) keep_count="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  
  with_spinner "Cleaning up old images (keeping $keep_count versions)" \
    smart_prune_stack_images "$stack" "$keep_count"
  
  # Also prune old versioned configs
  prune_versioned_configs "$stack" "$keep_count"
}
