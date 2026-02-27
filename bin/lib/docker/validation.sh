#!/usr/bin/env bash
# Docker image validation

# Validate that all expected images exist locally before deploy
# Usage: validate_images_before_deploy <stack>
# Returns: 0 if all images exist, 1 if any missing
#
# This function checks that for each internal service:
#   1. Expected tag is known (from build or export_service_tags)
#   2. Image with that tag exists locally
#
# This prevents deploying with wrong/missing images.
validate_images_before_deploy() {
  local stack="$1"
  local missing=0
  local validated=0
  local missing_images=()
  
  log info "validating images before deploy..."
  
  local services
  services=$(get_services_list "$stack")
  
  while IFS= read -r svc; do
    [ -n "$svc" ] || continue
    
    # Skip external services
    if ! is_service_internal "$stack" "$svc"; then
      log detail "skipping external service: $svc"
      continue
    fi
    
    local image expected_tag
    image=$(get_service_field "$stack" "$svc" image 2>/dev/null || echo "")
    
    if [ -z "$image" ]; then
      log warn "no image defined for service: $svc"
      continue
    fi
    
    # Get expected tag from lock file or environment variable
    expected_tag=""
    if declare -f get_expected_image_tag >/dev/null 2>&1; then
      expected_tag=$(get_expected_image_tag "$stack" "$svc" 2>/dev/null || echo "")
    fi
    
    # Fallback to TAG_* environment variable
    if [ -z "$expected_tag" ]; then
      local var_name
      var_name="TAG_$(echo "$svc" | tr '[:lower:]-' '[:upper:]_')"
      expected_tag="${!var_name:-}"
    fi
    
    if [ -z "$expected_tag" ]; then
      log warn "no expected tag for service $svc, skipping validation"
      continue
    fi
    
    # Check if image exists locally
    if docker image inspect "${image}:${expected_tag}" >/dev/null 2>&1; then
      log detail "✓ $svc: $image:$expected_tag exists"
      validated=$((validated + 1))
    else
      log error "✗ $svc: $image:$expected_tag NOT FOUND"
      missing_images+=("$svc: $image:$expected_tag")
      missing=$((missing + 1))
    fi
  done <<< "$services"
  
  if [ $missing -gt 0 ]; then
    log error "image validation failed: $missing image(s) missing"
    for img_info in "${missing_images[@]}"; do
      log error "  - $img_info"
    done
    log error ""
    log error "possible causes:"
    log error "  - build was not completed successfully"
    log error "  - image was pruned before deploy"
    log error "  - wrong commit/branch was used"
    log error ""
    log error "to fix: run 'swarmcli build $stack' before deploy"
    return 1
  fi
  
  log ok "all $validated image(s) validated successfully"
  return 0
}

# Validate images with formatted output (default mode)
# Usage: validate_images_tree <stack>
# Returns: 0 if all valid, 1 if any missing
validate_images_tree() {
  local stack="$1"
  local missing=0
  local validated=0
  local missing_images=()
  
  printf "\n$(c 90 "─────────────────────────────────────────────────────────────")\n"
  printf "🔍 $(c 1 "Validating images")\n"
  
  local services
  services=$(get_services_list "$stack")
  
  while IFS= read -r svc; do
    [ -n "$svc" ] || continue
    
    # Skip external services
    if ! is_service_internal "$stack" "$svc"; then
      printf "├─ $(c 36 "%s") $(c 90 "skipped (external)")\n" "$svc"
      continue
    fi
    
    local image expected_tag
    image=$(get_service_field "$stack" "$svc" image 2>/dev/null || echo "")
    
    # Get expected tag
    expected_tag=""
    if declare -f get_expected_image_tag >/dev/null 2>&1; then
      expected_tag=$(get_expected_image_tag "$stack" "$svc" 2>/dev/null || echo "")
    fi
    if [ -z "$expected_tag" ]; then
      local var_name
      var_name="TAG_$(echo "$svc" | tr '[:lower:]-' '[:upper:]_')"
      expected_tag="${!var_name:-}"
    fi
    
    if [ -z "$expected_tag" ]; then
      printf "├─ $(c 36 "%s") $(c 90 "skipped (no tag)")\n" "$svc"
      continue
    fi
    
    if docker image inspect "${image}:${expected_tag}" >/dev/null 2>&1; then
      printf "├─ $(c 32 "✓") $(c 36 "%s") %s:%s\n" "$svc" "$image" "$expected_tag"
      validated=$((validated + 1))
    else
      printf "├─ $(c 31 "✗") $(c 36 "%s") %s:%s $(c 31 "NOT FOUND")\n" "$svc" "$image" "$expected_tag"
      missing_images+=("$svc: $image:$expected_tag")
      missing=$((missing + 1))
    fi
  done <<< "$services"
  
  if [ $missing -gt 0 ]; then
    printf "$(c 31 "✗") Image validation failed: %d missing\n" "$missing"
    printf "\n   Missing images:\n"
    for img_info in "${missing_images[@]}"; do
      printf "   • %s\n" "$img_info"
    done
    printf "\n   Run 'swarmcli build %s' to build missing images\n" "$stack"
    return 1
  fi
  
  printf "$(c 32 "✓") All %d image(s) validated\n" "$validated"
  return 0
}
