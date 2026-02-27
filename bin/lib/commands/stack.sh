#!/usr/bin/env bash
# Stack commands: ls, ps, inspect, logs, status, down

# Command: swarmcli list
cmd_list() {
  if [ -z "$ACTIVE_PROFILE" ]; then
    fail "no profile loaded. Use --profile <name> or set SWARM_PROFILE"
  fi
  
  if [ ! -d "$PROFILE_STACKS_DIR" ]; then
    fail "stacks directory not found: $PROFILE_STACKS_DIR"
  fi
  
  if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
    local result="[]"
    for d in "$PROFILE_STACKS_DIR"/*; do
      [ -d "$d" ] || continue
      local stack
      stack="$(basename "$d")"
      
      local services_arr="[]"
      local services
      services="$(get_services_list "$stack")"
      
      while IFS= read -r svc; do
        [ -n "$svc" ] || continue
        local sha tag service_type
        if is_service_internal "$stack" "$svc"; then
          service_type="internal"
          sha="$(get_service_commit_sha "$stack" "$svc" 2>/dev/null)"
          if [ -z "$sha" ] || [ "$sha" = "nogit" ]; then
            sha="(not synced)"
            tag="(repo not synced)"
          else
            tag="${ACTIVE_PROFILE}-${sha}"
          fi
        else
          service_type="external"
          sha=""
          tag=""
        fi
        
        services_arr=$(jq -n \
          --argjson arr "$services_arr" \
          --arg service "$svc" \
          --arg type "$service_type" \
          --arg commit "$sha" \
          --arg tag "$tag" \
          '$arr + [{service: $service, type: $type, commit: $commit, tag: $tag}]')
      done <<< "$services"
      
      result=$(jq -n \
        --argjson arr "$result" \
        --arg stack "$stack" \
        --arg profile "$ACTIVE_PROFILE" \
        --argjson services "$services_arr" \
        '$arr + [{stack: $stack, profile: $profile, services: $services}]')
    done
    echo "$result"
  else
    local any=0
    echo "$(c 36 "Profile: $ACTIVE_PROFILE")"
    echo ""
    
    for d in "$PROFILE_STACKS_DIR"/*; do
      [ -d "$d" ] || continue
      any=1
      
      local stack
      stack="$(basename "$d")"
      
      echo "$(c 33 "Stack: $stack")"
      printf "  %-24s │ %-10s │ %-s\n" "Service" "Type" "Tag"
      printf "  %s\n" "──────────────────────── ┼ ────────── ┼ ────────────────────────"
      
      local services
      services="$(get_services_list "$stack")"
      
      if [ -n "$services" ]; then
        while IFS= read -r svc; do
          [ -n "$svc" ] || continue
          
          local svc_display="$svc"
          if [ ${#svc} -gt 24 ]; then
            svc_display="${svc:0:21}..."
          fi
          
          local sha tag service_type service_type_text
          if is_service_internal "$stack" "$svc"; then
            service_type_text="internal"
            service_type="$(c 32 "$service_type_text")"
            sha="$(get_service_commit_sha "$stack" "$svc" 2>/dev/null)"
            if [ -z "$sha" ] || [ "$sha" = "nogit" ]; then
              tag="(not synced)"
            else
              tag="${ACTIVE_PROFILE}-${sha}"
            fi
          else
            service_type_text="external"
            service_type="$(c 33 "$service_type_text")"
            tag="(public image)"
          fi
          
          local type_padding=""
          local type_len=${#service_type_text}
          local padding_needed
          padding_needed=$((10 - type_len))
          if [ $padding_needed -gt 0 ]; then
            type_padding=$(printf "%*s" $padding_needed "")
          fi
          
          printf "  %-24s │ %s%s │ %-s\n" "$svc_display" "$service_type" "$type_padding" "$tag"
        done <<< "$services"
      fi
      echo
    done
    
    if [ $any -eq 0 ]; then
      log info "no stacks found in $PROFILE_STACKS_DIR"
    fi
  fi
}

# Command: swarmcli status <stack>
cmd_status() {
  local stack="$1"
  [ -n "$stack" ] || fail "usage: swarmcli status <STACK> --profile <PROFILE>"
  
  ensure_stack_exists "$stack"
  get_stack_status "$stack"
}

# Command: swarmcli logs <stack> [--service SERVICE] [--tail N]
cmd_logs() {
  local stack="$1"
  shift || true
  
  [ -n "$stack" ] || fail "usage: swarmcli logs <STACK> --profile <PROFILE> [--service SERVICE] [--tail N]"
  
  local service="" tail_n=50
  
  while [ $# -gt 0 ]; do
    case "$1" in
      --service) shift; service="$1" ;;
      --tail) shift; tail_n="$1" ;;
    esac
    shift || true
  done
  
  ensure_stack_exists "$stack"
  
  if [ -n "$service" ]; then
    local full_name="${stack}_${service}"
    docker service logs --tail "$tail_n" --follow "$full_name" 2>&1
  else
    local services
    services=$(docker stack services "$stack" --format "{{.Name}}" 2>/dev/null)
    
    [ -n "$services" ] || fail "no services found for stack $stack"
    
    while IFS= read -r svc; do
      [ -n "$svc" ] || continue
      echo "$(c 36 "=== Logs for $svc ===")"
      docker service logs --tail "$tail_n" "$svc" 2>&1
      echo
    done <<< "$services"
  fi
}

# Command: swarmcli ps (all stacks)
# Show status for all stacks in current profile
cmd_ps_all() {
  if [ -z "$ACTIVE_PROFILE" ]; then
    fail "no profile loaded. Use --profile <name> or set SWARM_PROFILE"
  fi
  
  local stacks
  stacks=$(list_profile_stacks "$ACTIVE_PROFILE")
  
  if [ -z "$stacks" ]; then
    log info "no stacks found in profile: $ACTIVE_PROFILE"
    return 0
  fi
  
  if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
    echo "["
    local first=1
    while IFS= read -r stack; do
      [ -n "$stack" ] || continue
      [ $first -eq 0 ] && echo ","
      
      # Get deployed services
      local services_json="[]"
      if docker stack ls --format "{{.Name}}" 2>/dev/null | grep -q "^${stack}$"; then
        services_json=$(docker stack services "$stack" --format '{"name":"{{.Name}}","replicas":"{{.Replicas}}","image":"{{.Image}}"}' 2>/dev/null | jq -s '.' 2>/dev/null || echo "[]")
      fi
      
      local deployed
      deployed=$(docker stack ls --format "{{.Name}}" 2>/dev/null | grep -q "^${stack}$" && echo "true" || echo "false")
      jq -n \
        --arg stack "$stack" \
        --arg profile "$ACTIVE_PROFILE" \
        --argjson deployed "$deployed" \
        --argjson services "$services_json" \
        '{stack: $stack, profile: $profile, deployed: $deployed, services: $services}'
      
      first=0
    done <<< "$stacks"
    echo "]"
  else
    echo ""
    echo "$(c 36 "Profile: $ACTIVE_PROFILE")"
    echo ""
    
    printf "  %-24s │ %-10s │ %-s\n" "Stack" "Status" "Services"
    printf "  %s\n" "──────────────────────── ┼ ────────── ┼ ────────────────────────"
    
    while IFS= read -r stack; do
      [ -n "$stack" ] || continue
      
      local status status_text services_count
      
      # Check if stack is deployed
      if docker stack ls --format "{{.Name}}" 2>/dev/null | grep -q "^${stack}$"; then
        services_count=$(docker stack services "$stack" --format "{{.Name}}" 2>/dev/null | wc -l)
        
        # Check services health
        local running
        running=$(docker stack services "$stack" --format "{{.Replicas}}" 2>/dev/null | grep -c "^[1-9]" || echo "0")
        
        if [ "$running" -eq "$services_count" ] && [ "$services_count" -gt 0 ]; then
          status="$(c 32 "running")"
          status_text="running"
        elif [ "$running" -gt 0 ]; then
          status="$(c 33 "partial")"
          status_text="partial"
        else
          status="$(c 31 "stopped")"
          status_text="stopped"
        fi
      else
        status="$(c 90 "not deployed")"
        status_text="not deployed"
        services_count="-"
      fi
      
      # Padding for colored text
      local padding_needed
      padding_needed=$((10 - ${#status_text}))
      local status_padding=""
      if [ $padding_needed -gt 0 ]; then
        status_padding=$(printf "%*s" $padding_needed "")
      fi
      
      printf "  %-24s │ %s%s │ %s\n" "$stack" "$status" "$status_padding" "$services_count"
    done <<< "$stacks"
    
    echo ""
  fi
}

# Command: swarmcli inspect <stack>
# Show detailed information about a stack
cmd_stack_inspect() {
  local stack="$1"
  
  [ -n "$stack" ] || fail "usage: swarmcli inspect <STACK>"
  
  ensure_stack_exists "$stack"
  
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
    local deployed="false"
    local services_json="[]"
    local replicas_total=0
    local replicas_running=0
    
    if docker stack ls --format "{{.Name}}" 2>/dev/null | grep -q "^${stack}$"; then
      deployed="true"
      services_json=$(docker stack services "$stack" --format '{"name":"{{.Name}}","replicas":"{{.Replicas}}","image":"{{.Image}}","ports":"{{.Ports}}"}' 2>/dev/null | jq -s '.' 2>/dev/null || echo "[]")
    fi
    
    # Get configured services
    local configured_services="[]"
    if [ -f "$stack_dir/services.yaml" ]; then
      configured_services=$(yaml_get_keys "$stack_dir/services.yaml" "services" 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo "[]")
    fi
    
    jq -n \
      --arg stack "$stack" \
      --arg profile "$ACTIVE_PROFILE" \
      --arg path "$stack_dir" \
      --argjson deployed "$deployed" \
      --argjson configured_services "$configured_services" \
      --argjson running_services "$services_json" \
      '{stack: $stack, profile: $profile, path: $path, deployed: $deployed, configured_services: $configured_services, running_services: $running_services}'
  else
    echo ""
    echo "$(c 36 "Stack: $stack")"
    echo "$(c 90 "Profile: $ACTIVE_PROFILE")"
    echo "$(c 90 "Path: $stack_dir")"
    echo ""
    
    # Deployment status
    echo "$(c 33 "Deployment Status:")"
    if docker stack ls --format "{{.Name}}" 2>/dev/null | grep -q "^${stack}$"; then
      echo "  Status: $(c 32 "deployed")"
      echo ""
      echo "  Services:"
      docker stack services "$stack" --format "    {{.Name}}\t{{.Replicas}}\t{{.Image}}" 2>/dev/null || echo "    (error getting services)"
    else
      echo "  Status: $(c 90 "not deployed")"
    fi
    echo ""
    
    # Configuration files
    echo "$(c 33 "Configuration Files:")"
    for f in services.yaml variables.yaml externals.yaml settings.yaml docker-stack.yml; do
      if [ -f "$stack_dir/$f" ]; then
        echo "  $(c 32 "✓") $f"
      else
        echo "  $(c 90 "○") $f (missing)"
      fi
    done
    echo ""
    
    # Hooks
    echo "$(c 33 "Hooks:")"
    for h in pre-deploy.sh post-deploy.sh; do
      if [ -x "$stack_dir/hooks/$h" ]; then
        echo "  $(c 32 "✓") $h"
      elif [ -f "$stack_dir/hooks/$h" ]; then
        echo "  $(c 33 "○") $h (not executable)"
      else
        echo "  $(c 90 "○") $h (missing)"
      fi
    done
    echo ""
    
    # Configured services
    echo "$(c 33 "Configured Services:")"
    if [ -f "$stack_dir/services.yaml" ]; then
      local services
      services=$(get_services_list "$stack")
      if [ -n "$services" ]; then
        while IFS= read -r svc; do
          [ -n "$svc" ] || continue
          local svc_type="git"
          if ! is_service_internal "$stack" "$svc" 2>/dev/null; then
            svc_type="registry"
          fi
          echo "  • $svc ($(c 90 "$svc_type"))"
        done <<< "$services"
      else
        echo "  (no services configured)"
      fi
    else
      echo "  (services.yaml not found)"
    fi
  fi
}

# Command: swarmcli down <stack>
# Remove a deployed stack from Docker Swarm
cmd_down() {
  local stack="$1"
  shift || true
  
  [ -n "$stack" ] || fail "usage: swarmcli down <STACK> --profile <PROFILE> [--force]"
  
  ensure_stack_exists "$stack"
  
  local force=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --force|-f) force=1 ;;
      *) fail "unknown option: $1" ;;
    esac
    shift
  done
  
  # Check if stack is actually deployed
  if ! docker stack ls --format '{{.Name}}' 2>/dev/null | grep -Fxq "$stack"; then
    log warn "stack '$stack' is not deployed"
    return 0
  fi
  
  # Get services count
  local services_count
  services_count=$(docker stack services "$stack" --format '{{.Name}}' 2>/dev/null | wc -l)
  
  # Confirmation (unless --force)
  if [ "$force" != "1" ] && [ -t 0 ]; then
    echo ""
    echo "This will remove stack: $(c 33 "$stack")"
    echo "  • Services: $services_count"
    echo "  • Profile: $ACTIVE_PROFILE"
    echo ""
    printf "Continue? [y/N]: "
    read -r answer
    case "$answer" in
      [Yy]*) ;;
      *) 
        log info "cancelled"
        return 0
        ;;
    esac
  fi
  
  if [ "$DRY_RUN" = "1" ]; then
    log info "dry-run: would remove stack $stack"
    return 0
  fi
  
  log info "removing stack: $stack"
  
  if docker stack rm "$stack" 2>&1; then
    log ok "stack removed: $stack"
    
    # Wait for services to be removed
    log info "waiting for services to stop..."
    local timeout=30
    local waited=0
    while [ $waited -lt $timeout ]; do
      if ! docker stack ps "$stack" >/dev/null 2>&1; then
        break
      fi
      sleep 1
      waited=$((waited + 1))
    done
    
    log ok "stack '$stack' removed successfully"
  else
    log error "failed to remove stack: $stack"
    return 1
  fi
  
  return 0
}
