#!/usr/bin/env bash
# Service readiness checking

# Wait for services to be ready (all replicas running)
# Usage: wait_for_services_ready <stack> <timeout_seconds> [service1 service2 ...]
# Returns: 0 if all services are ready, 1 if timeout or error
# Environment:
#   VERIFY_IMAGE_VERSION=1 - also verify that services are running with expected image tags
wait_for_services_ready() {
  local stack="$1" timeout="${2:-${SERVICES_READY_TIMEOUT:-30}}"
  shift 2 || true
  local services_to_check=("$@")
  
  if [ "$DRY_RUN" = "1" ]; then
    log info "dry-run: would wait for services to be ready"
    return 0
  fi
  
  if [ ${#services_to_check[@]} -eq 0 ]; then
    local all_services
    all_services=$(get_services_list "$stack")
    while IFS= read -r svc; do
      [ -n "$svc" ] || continue
      services_to_check+=("$svc")
    done <<< "$all_services"
  fi
  
  if [ ${#services_to_check[@]} -eq 0 ]; then
    log warn "no services to check"
    return 0
  fi
  
  local verify_image="${VERIFY_IMAGE_VERSION:-0}"
  if [ "$verify_image" = "1" ]; then
    log info "waiting for services to be ready with image verification (timeout: ${timeout}s)"
  else
    log info "waiting for services to be ready (timeout: ${timeout}s)"
  fi
  
  local start_time
  start_time=$(date +%s)
  local end_time
  end_time=$((start_time + timeout))
  local all_ready=0
  local check_count=0
  
  while [ "$(date +%s)" -lt "$end_time" ]; do
    # Check for cancellation at the start of each iteration
    if declare -f check_cancellation_requested >/dev/null 2>&1; then
      check_cancellation_requested "$stack" || return 130
    fi
    
    all_ready=1
    check_count=$((check_count + 1))
    
    local should_show_status=0
    if [ "$VERBOSE" = "1" ] || [ $((check_count % 5)) -eq 0 ]; then
      should_show_status=1
    fi
    
    local waiting_services=()
    local outdated_services=()
    
    for svc in "${services_to_check[@]}"; do
      [ -n "$svc" ] || continue
      
      local service_name="${stack}_${svc}"
      
      if ! service_exists "$service_name"; then
        log warn "service $service_name not found, skipping"
        continue
      fi
      
      local replicas
      replicas=$(get_service_replicas_status "$service_name")
      
      local running="${replicas%%/*}"
      local desired="${replicas##*/}"
      
      if [ "$desired" = "0" ]; then
        [ "$VERBOSE" = "1" ] && log info "$service_name: 0/0 (disabled, skipping)"
        continue
      fi
      
      # Check 1: Replicas ready?
      if [ "$running" != "$desired" ]; then
        all_ready=0
        waiting_services+=("$service_name: $running/$desired")
        [ "$should_show_status" = "1" ] && log info "$service_name: $running/$desired (waiting...)"
        continue
      fi
      
      # Check 2: Image verification (if enabled)
      # First check image ID (most reliable), then fall back to tag
      if [ "$verify_image" = "1" ]; then
        local expected_image_id expected_tag
        expected_image_id=$(get_expected_image_id "$stack" "$svc" 2>/dev/null || echo "")
        expected_tag=$(get_expected_image_tag "$stack" "$svc" 2>/dev/null || echo "")
        
        if [ -n "$expected_image_id" ]; then
          # Verify by image ID (most reliable - exact match)
          local running_image_id
          running_image_id=$(get_running_service_image_id "$service_name" 2>/dev/null || echo "")
          
          if [ -n "$running_image_id" ]; then
            if [ "$running_image_id" = "$expected_image_id" ]; then
              [ "$VERBOSE" = "1" ] && log ok "$service_name: $running/$desired, image ID verified"
            else
              all_ready=0
              local short_running="${running_image_id:7:12}"
              local short_expected="${expected_image_id:7:12}"
              outdated_services+=("$service_name: ${short_running}... (expected: ${short_expected}...)")
              [ "$should_show_status" = "1" ] && log warn "$service_name: $running/$desired, wrong image ID (${short_running}... != ${short_expected}...)"
            fi
          else
            # Could not get running image ID, fall back to tag check
            [ "$VERBOSE" = "1" ] && log info "$service_name: $running/$desired (image ID unavailable, checking tag)"
            # Continue to tag check below
            expected_image_id=""
          fi
        fi
        
        # Fall back to tag verification if image ID not available
        if [ -z "$expected_image_id" ] && [ -n "$expected_tag" ]; then
          local current_image
          current_image=$(docker service inspect "$service_name" --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' 2>/dev/null || echo "")
          
          if [ -n "$current_image" ]; then
            # Extract tag (handle both image:tag and image:tag@sha256:... formats)
            local current_tag="${current_image##*:}"
            current_tag="${current_tag%%@*}"
            
            if [ "$current_tag" = "$expected_tag" ]; then
              [ "$VERBOSE" = "1" ] && log ok "$service_name: $running/$desired, tag: $current_tag (updated)"
            else
              all_ready=0
              outdated_services+=("$service_name: $current_tag (expected: $expected_tag)")
              [ "$should_show_status" = "1" ] && log warn "$service_name: $running/$desired, tag: $current_tag (expected: $expected_tag)"
            fi
          fi
        elif [ -z "$expected_image_id" ] && [ -z "$expected_tag" ]; then
          [ "$VERBOSE" = "1" ] && log info "$service_name: $running/$desired (ready, no verification data)"
        fi
      else
        [ "$VERBOSE" = "1" ] && log info "$service_name: $running/$desired (ready)"
      fi
    done
    
    if [ $all_ready -eq 1 ]; then
      log ok "all services are ready"
      return 0
    fi
    
    if [ "$should_show_status" = "1" ]; then
      local elapsed
      elapsed=$(( $(date +%s) - start_time ))
      local remaining
      remaining=$((timeout - elapsed))
      
      if [ ${#waiting_services[@]} -gt 0 ]; then
        log info "waiting for ${#waiting_services[@]} service(s) to become ready (${elapsed}s/${timeout}s)"
      fi
      
      if [ ${#outdated_services[@]} -gt 0 ]; then
        log info "waiting for ${#outdated_services[@]} service(s) to update image (${elapsed}s/${timeout}s)"
      fi
    fi
    
    sleep 2
  done
  
  # Timeout - run diagnostics
  log error "timeout waiting for services to be ready"
  
  if [ ${#outdated_services[@]} -gt 0 ]; then
    log error "services with outdated images:"
    for svc_info in "${outdated_services[@]}"; do
      log error "  - $svc_info"
    done
  fi
  
  diagnose_deploy_failure "$stack" "${services_to_check[@]}"
  
  return 1
}

# Diagnose deployment failure
# Usage: diagnose_deploy_failure <stack> [service1 service2 ...]
diagnose_deploy_failure() {
  local stack="$1"
  shift
  local services_to_check=("$@")
  
  local logs_tail
  logs_tail=$(get_diagnostics_logs_tail "$stack")
  
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════════════╗"
  echo "║              DEPLOYMENT FAILURE DIAGNOSTICS                                  ║"
  echo "╚══════════════════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Stack: $stack"
  echo "Failed services: ${#services_to_check[@]}"
  
  for svc in "${services_to_check[@]}"; do
    [ -n "$svc" ] || continue
    local service_name="${stack}_${svc}"
    
    if ! service_exists "$service_name"; then
      log error "$service_name: SERVICE NOT FOUND"
      continue
    fi
    
    local replicas
    replicas=$(get_service_replicas_status "$service_name")
    local running="${replicas%%/*}"
    local desired="${replicas##*/}"
    
    if [ "$running" != "$desired" ] && [ "$desired" != "0" ]; then
      diagnose_service_failure "$service_name" "$logs_tail"
    fi
  done
  
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════════════╗"
  echo "║                        TROUBLESHOOTING HINTS                                 ║"
  echo "╚══════════════════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "1. Check task errors: docker service ps ${stack}_<service> --no-trunc"
  echo "2. View service logs: docker service logs ${stack}_<service> --tail 50"
  echo "3. Force service update: docker service update --force ${stack}_<service>"
  echo "4. Test container manually: docker run --rm -it <image> /bin/sh"
  echo ""
}
