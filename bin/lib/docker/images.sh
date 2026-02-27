#!/usr/bin/env bash
# Docker image management

# Check if image tag exists locally
# Usage: image_tag_exists <image> <tag>
# Returns: 0 if exists, 1 otherwise
image_tag_exists() {
  # Use timeout to prevent hanging if Docker daemon is unresponsive
  # Default timeout: 5 seconds (should be fast for local image check)
  local timeout="${IMAGE_CHECK_TIMEOUT:-5}"
  
  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout" docker image inspect "$1:$2" >/dev/null 2>&1
  else
    # Fallback: run without timeout (may hang if Docker daemon is unresponsive)
    docker image inspect "$1:$2" >/dev/null 2>&1
  fi
}

# Prune old images
# Usage: prune_images
prune_images() {
  log info "pruning unused images"
  docker image prune -f >/dev/null 2>&1 || true
}

# Smart prune - keep only N latest versions per service
# Usage: smart_prune_stack_images <stack> [keep_count]
smart_prune_stack_images() {
  local stack="$1"
  local keep_count="${2:-${KEEP_IMAGES_COUNT:-10}}"
  
  log detail "pruning old images for stack: $stack (keeping $keep_count versions)"
  
  local services
  services=$(get_services_list "$stack")
  
  local pruned=0
  while IFS= read -r svc; do
    [ -n "$svc" ] || continue
    
    local image
    image=$(get_service_field "$stack" "$svc" image)
    
    if [ -z "$image" ]; then
      log warn "no image defined for service: $svc"
      continue
    fi
    
    # Get all tags for this image, sorted by creation time
    local all_tags
    all_tags=$(docker images --format "{{.Tag}}|{{.CreatedAt}}" "$image" 2>/dev/null)
    if [ $? -ne 0 ]; then
      log warn "failed to list images for $image (docker daemon issue?)"
      continue
    fi
    all_tags=$(echo "$all_tags" | \
      grep -E "^(${ACTIVE_PROFILE})-" | \
      sort -t'|' -k2 -r | \
      cut -d'|' -f1)
    
    if [ -z "$all_tags" ]; then
      continue
    fi
    
    # Skip first N tags, remove the rest
    local count=0
    while IFS= read -r tag; do
      [ -n "$tag" ] || continue
      count=$((count + 1))
      
      if [ $count -gt $keep_count ]; then
        log detail "removing old image: $image:$tag"
        
        if [ "$DRY_RUN" != "1" ]; then
          docker rmi "$image:$tag" >/dev/null 2>&1 || {
            log detail "failed to remove $image:$tag (may be in use)"
          }
          pruned=$((pruned + 1))
        fi
      fi
    done <<< "$all_tags"
  done <<< "$services"
  
  log detail "pruned $pruned old images"
  docker image prune -f >/dev/null 2>&1 || true
  
  return 0
}
