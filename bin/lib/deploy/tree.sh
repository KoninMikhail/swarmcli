#!/usr/bin/env bash
# Deploy output functions

# Deploy stack with formatted output (default mode)
# Usage: deploy_stack_tree <stack> <compose_file>
# Returns: 0 on success, non-zero on error
deploy_stack_tree() {
  local stack="$1"
  local compose="$2"
  local start_ts=$(date +%s)
  
  # Check compose file exists
  if [ ! -f "$compose" ]; then
    printf "$(c 31 "ERROR:") docker-stack.yml not found: %s\n" "$compose"
    return 1
  fi
  
  # Get services from compose file
  local services_list
  services_list=$(services_to_process "$stack")
  local services_arr=()
  while IFS= read -r svc; do
    [ -n "$svc" ] && services_arr+=("$svc")
  done <<< "$services_list"
  local total=${#services_arr[@]}
  
  # Header
  printf "\n$(c 90 "─────────────────────────────────────────────────────────────")\n"
  printf "🚀 $(c 1 "Deploying stack:") %s\n" "$stack"
  
  # Show services being deployed
  for svc in "${services_arr[@]}"; do
    local image tag
    image=$(get_service_field "$stack" "$svc" image 2>/dev/null || echo "unknown")
    tag=$(resolve_commit_sha "$stack" "$svc" 2>/dev/null || echo "latest")
    printf "├─ $(c 36 "%s") → %s:%s\n" "$svc" "$image" "${ACTIVE_PROFILE}-${tag}"
  done
  
  # Run docker stack deploy
  printf "\n"
  local deploy_output
  deploy_output=$(docker stack deploy --resolve-image always -c "$compose" "$stack" 2>&1)
  local deploy_rc=$?
  
  # Show deploy output
  if [ -n "$deploy_output" ]; then
    echo "$deploy_output" | while IFS= read -r line; do
      # Color code output
      if echo "$line" | grep -q "Creating service"; then
        printf "$(c 32 "✓") %s\n" "$line"
      elif echo "$line" | grep -q "Updating service"; then
        printf "$(c 32 "✓") %s\n" "$line"
      elif echo "$line" | grep -qi "error\|failed"; then
        printf "$(c 31 "✗") %s\n" "$line"
      else
        printf "  %s\n" "$line"
      fi
    done
  fi
  
  if [ $deploy_rc -ne 0 ]; then
    printf "\n$(c 31 "✗") $(c 31 "Deploy command failed")\n"
    printf "$(c 31 "Error output:")\n"
    echo "$deploy_output"
    return $deploy_rc
  fi
  
  return 0
}

# Wait for services to be ready with formatted output (default mode)
# Usage: wait_for_services_ready_tree <stack> <timeout> [services...]
# Returns: 0 if all services are ready, 1 if timeout or error
wait_for_services_ready_tree() {
  local stack="$1"
  local timeout="${2:-30}"
  shift 2 || true
  local services_to_check=("$@")
  
  local total=${#services_to_check[@]}
  [ $total -eq 0 ] && return 0
  
  printf "\n⏳ $(c 1 "Waiting for services") $(c 90 "(timeout: %ds)")\n" "$timeout"
  
  local start_time=$(date +%s)
  local end_time=$((start_time + timeout))
  local all_ready=0
  local failed_services=()
  local ready_services=()
  
  while [ $(date +%s) -lt $end_time ]; do
    all_ready=1
    failed_services=()
    ready_services=()
    
    for svc in "${services_to_check[@]}"; do
      [ -n "$svc" ] || continue
      local service_name="${stack}_${svc}"
      
      if ! service_exists "$service_name"; then
        all_ready=0
        failed_services+=("$svc:0/?:pending")
        continue
      fi
      
      local replicas
      replicas=$(get_service_replicas_status "$service_name")
      local running="${replicas%%/*}"
      local desired="${replicas##*/}"
      
      if [ "$desired" = "0" ]; then
        ready_services+=("$svc:0/0:disabled")
        continue
      fi
      
      if [ "$running" = "$desired" ]; then
        ready_services+=("$svc:$running/$desired:ready")
      else
        all_ready=0
        failed_services+=("$svc:$running/$desired:waiting")
      fi
    done
    
    if [ $all_ready -eq 1 ]; then
      break
    fi
    
    sleep 2
  done
  
  local elapsed=$(($(date +%s) - start_time))
  
  # Display results
  for svc in "${services_to_check[@]}"; do
    local status="unknown"
    local replicas="?"
    
    for entry in "${ready_services[@]}"; do
      if [[ "$entry" == "$svc:"* ]]; then
        replicas="${entry#*:}"
        replicas="${replicas%%:*}"
        status="ready"
        break
      fi
    done
    for entry in "${failed_services[@]}"; do
      if [[ "$entry" == "$svc:"* ]]; then
        replicas="${entry#*:}"
        replicas="${replicas%%:*}"
        status="failed"
        break
      fi
    done
    
    if [ "$status" = "ready" ]; then
      printf "$(c 32 "✓") $(c 36 "%s"): %s replicas\n" "$svc" "$replicas"
    elif [ "$status" = "failed" ]; then
      printf "$(c 31 "✗") $(c 36 "%s"): %s replicas $(c 31 "(FAILED)")\n" "$svc" "$replicas"
    else
      printf "○ $(c 36 "%s"): skipped\n" "$svc"
    fi
  done
  
  if [ $all_ready -eq 1 ]; then
    # Verify image IDs if we have expected values
    local image_mismatch=0
    local mismatched_services=()
    
    for svc in "${services_to_check[@]}"; do
      [ -n "$svc" ] || continue
      local service_name="${stack}_${svc}"
      
      # Skip external services
      if ! is_service_internal "$stack" "$svc" 2>/dev/null; then
        continue
      fi
      
      local expected_image_id
      expected_image_id=$(get_expected_image_id "$stack" "$svc" 2>/dev/null || echo "")
      
      if [ -n "$expected_image_id" ]; then
        local running_image_id
        running_image_id=$(get_running_service_image_id "$service_name" 2>/dev/null || echo "")
        
        if [ -n "$running_image_id" ] && [ "$running_image_id" != "$expected_image_id" ]; then
          image_mismatch=1
          local short_running="${running_image_id:7:12}"
          local short_expected="${expected_image_id:7:12}"
          mismatched_services+=("$svc:${short_running}:${short_expected}")
        fi
      fi
    done
    
    if [ $image_mismatch -eq 1 ]; then
      printf "\n$(c 31 "⚠️  Image verification failed")\n"
      for entry in "${mismatched_services[@]}"; do
        local svc="${entry%%:*}"
        local rest="${entry#*:}"
        local running="${rest%%:*}"
        local expected="${rest#*:}"
        printf "   $(c 31 "✗") %s: running %s..., expected %s...\n" "$svc" "$running" "$expected"
      done
      printf "   Container may be running old cached image\n"
      printf "   Try: docker service update --force %s_%s\n" "$stack" "${mismatched_services[0]%%:*}"
      return 1
    fi
    
    printf "\n$(c 32 "✓") All %d service(s) running (%ds)\n" "$total" "$elapsed"
    return 0
  else
    # Show error details for failed services
    printf "\n$(c 31 "✗") Service startup failed:\n"
    for entry in "${failed_services[@]}"; do
      local svc="${entry%%:*}"
      local service_name="${stack}_${svc}"
      
      # Get task error
      local task_error
      task_error=$(docker service ps "$service_name" --no-trunc --format '{{.Error}}' 2>/dev/null | head -1)
      
      printf "   $(c 31 "•") %s: " "$svc"
      if [ -n "$task_error" ]; then
        printf "$(c 31 "%s")\n" "$task_error"
      else
        printf "$(c 31 "timeout waiting for replicas")\n"
      fi
      
      # Show recent task logs for debugging
      printf "     Recent tasks:\n"
      docker service ps "$service_name" --no-trunc --format '     {{.CurrentState}}: {{.Error}}' 2>/dev/null | head -3
    done
    
    printf "\n   Debug commands:\n"
    printf "   docker service ps %s_<service> --no-trunc\n" "$stack"
    printf "   docker service logs %s_<service> --tail 50\n" "$stack"
    return 1
  fi
}
