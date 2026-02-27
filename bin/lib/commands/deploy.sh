#!/usr/bin/env bash
# Deploy commands

cmd_deploy() {
  local start_ts=$(date +%s)
  local stack="$1"
  shift || true
  
  [ -n "$stack" ] || fail "usage: swarmcli deploy <STACK> --profile <PROFILE> [flags]"
  
  ensure_stack_exists "$stack"
  
  # Validate that --branch and --commit are not used for external services
  # This must be called after stack exists (so we can check service types)
  if [ ${#SELECTED_SERVICES[@]} -gt 0 ]; then
    validate_external_service_args "$stack" || exit 1
  fi
  
  # Initialize step time tracking
  clear_step_times
  local step_start_ts=$(date +%s)
  
  # Determine total steps (depends on flags)
  local total_steps=5  # validate, templates, deploy, verify, complete
  [ "${CONFIG_ONLY:-}" != "1" ] && [ "$DRY_RUN" != "1" ] && total_steps=$((total_steps + 2))  # +sync, +build
  [ "$WITH_SECRETS" = "1" ] && total_steps=$((total_steps + 1))  # +secrets
  local current_step=0
  
  # Step 1: Validate
  current_step=$((current_step + 1))
  set_deploy_step "$stack" "$current_step" "$total_steps" "validate" 2>/dev/null || true
  step_start_ts=$(date +%s)
  
  # Load variables needed for validation and template rendering
  if registry_exists; then
    load_services_registry >/dev/null 2>&1
  fi
  load_globals_yaml 2>/dev/null || true
  load_variables_yaml "$stack" "common" 2>/dev/null || true
  load_variables_yaml "$stack" "deploy" 2>/dev/null || true
  
  # Export service TAG variables (needed for template rendering during validation)
  export_service_tags "$stack"
  
  # Validate configuration before starting
  # Use tree output by default, verbose mode uses plain output
  if [ "$VERBOSE" = "1" ]; then
    if ! validate_deploy_prerequisites "$stack"; then
      print_errors
      fail "configuration validation failed"
    fi
  else
    if ! cmd_validate_tree "$stack"; then
      fail "configuration validation failed"
    fi
  fi
  
  # Record validate step time
  record_step_time "validate" $(($(date +%s) - step_start_ts))
  
  # Acquire deployment lock
  if [ "$DRY_RUN" != "1" ]; then
    if ! acquire_deploy_lock "$stack"; then
      fail "cannot acquire deployment lock"
    fi
    
    # Initialize graceful shutdown handlers
    init_signal_handlers
    register_cleanup_handler "release_deploy_lock $stack"
    set_operation_context "deploy $stack"
    
    # Set stack context for cancellation checks
    if declare -f set_cancel_check_stack >/dev/null 2>&1; then
      set_cancel_check_stack "$stack"
    fi
  fi
  
  local updated_services=0
  
  # Save checkpoint
  if [ "$DRY_RUN" != "1" ]; then
    save_deploy_checkpoint "$stack"
  fi
  
  # Step: Secrets sync (if requested)
  if [ "$WITH_SECRETS" = "1" ]; then
    current_step=$((current_step + 1))
    set_deploy_step "$stack" "$current_step" "$total_steps" "secrets" 2>/dev/null || true
    step_start_ts=$(date +%s)
    
    log_section "secret" "Syncing secrets..."
    secrets_sync || fail "secrets sync failed"
    log_section_result "ok" "Secrets synced"
    
    record_step_time "secrets" $(($(date +%s) - step_start_ts))
  fi
  
  # CONFIG_ONLY or DRY_RUN mode: skip repos sync and build
  if [ "${CONFIG_ONLY:-}" = "1" ] || [ "$DRY_RUN" = "1" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      log info "dry-run: skipping repos sync and build"
    else
      log_section "info" "Config-only mode: skipping sync and build"
    fi
  else
    # Step: Repos sync
    current_step=$((current_step + 1))
    set_deploy_step "$stack" "$current_step" "$total_steps" "sync" 2>/dev/null || true
    step_start_ts=$(date +%s)
    
    cmd_repos_sync "$stack"
    
    record_step_time "sync" $(($(date +%s) - step_start_ts))
    
    # Step: Build
    if [ "$NO_BUILD" != "1" ]; then
      current_step=$((current_step + 1))
      set_deploy_step "$stack" "$current_step" "$total_steps" "build" 2>/dev/null || true
      step_start_ts=$(date +%s)
      
      cmd_build "$stack"
      
      record_step_time "build" $(($(date +%s) - step_start_ts))
    fi
  fi
  
  # Load services registry (generates SERVICE_* variables)
  # Note: registry is already loaded before validation, but reload for consistency
  if registry_exists; then
    load_services_registry
    
    # Validate SERVICE_* references in variables.yaml
    if ! validate_service_references "$stack"; then
      fail "undefined SERVICE_* references found (see errors above)"
    fi
  fi
  
  # Load global and deploy variables
  # Note: variables are already loaded before validation, but reload for consistency
  if [ "$DRY_RUN" != "1" ]; then
    load_globals_yaml
    load_variables_yaml "$stack" "common" || true
    load_variables_yaml "$stack" "deploy" || true
  fi
  
  # Export service TAG variables
  # Note: TAGs are re-exported here because they may have changed after build
  export_service_tags "$stack"
  
  # Count services and save expected image tags for verification
  local services
  services=$(get_services_list "$stack")
  while IFS= read -r svc; do
    [ -n "$svc" ] || continue
    updated_services=$((updated_services+1))
    
    # Save expected image tag for internal services (for verification)
    if [ "$DRY_RUN" != "1" ]; then
      local svc_type image_name
      svc_type=$(get_service_type "$stack" "$svc" 2>/dev/null || echo "")
      image_name=$(get_service_field "$stack" "$svc" "image" 2>/dev/null || echo "")
      
      if [ "$svc_type" = "git" ] && [ -n "$image_name" ]; then
        # Find the latest built image tag for this service
        local latest_tag
        latest_tag=$(docker images --format '{{.Tag}}' "$image_name" 2>/dev/null | grep "^${ACTIVE_PROFILE}-" | head -1)
        if [ -n "$latest_tag" ]; then
          set_expected_image_tag "$stack" "$svc" "$latest_tag" 2>/dev/null || true
        fi
      fi
    fi
  done <<< "$services"
  
  # Run pre-deploy hook
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  run_hook "$stack_dir/hooks/pre-deploy.sh" "$stack"
  
  # Sync configs (creates versioned configs and exports CONFIG_NAME_* variables)
  # Must be done before template rendering so config_name() function works
  if [ "$DRY_RUN" != "1" ]; then
    clear_config_mappings
    local configs_list
    configs_list=$(get_required_configs_list "$stack" 2>/dev/null || echo "")
    if [ -n "$configs_list" ]; then
      log_section "config" "Syncing configs..."
      if ! sync_configs "$stack"; then
        fail "configs sync failed"
      fi
      log_section_result "ok" "Configs synced"
    fi
  fi
  
  # Step: Render templates
  current_step=$((current_step + 1))
  set_deploy_step "$stack" "$current_step" "$total_steps" "templates" 2>/dev/null || true
  step_start_ts=$(date +%s)
  
  # Render Jinja2 templates if templates.yaml exists
  if stack_has_templates "$stack"; then
    if [ "$VERBOSE" = "1" ]; then
      log_section "template" "Rendering Jinja2 templates"
    fi
    if ! ensure_templates_rendered "$stack"; then
      fail "Template rendering failed"
    fi
    if [ "$VERBOSE" = "1" ]; then
      log_section_result "ok" "Templates rendered to .build/"
    fi
  fi
  
  record_step_time "templates" $(($(date +%s) - step_start_ts))
  
  # Get compose file (from .build/ if templates used, otherwise original)
  local compose_original
  compose_original="$(get_rendered_compose_path "$stack")"
  [ -f "$compose_original" ] || fail "docker-stack.yml not found: $compose_original"
  
  local compose_generated=""
  local compose="$compose_original"
  
  if [ "$DRY_RUN" != "1" ]; then
    compose_generated=$(mktemp "${TMPDIR:-/tmp}/swarmcli_compose_XXXXXX.yml") || fail "failed to create temp file for compose"
    # Register cleanup handler for temp file (runs on Ctrl+C)
    register_cleanup_handler "_cleanup_rm $compose_generated"
    
    if generate_compose_with_resources "$stack" "$compose_generated"; then
      compose="$compose_generated"
    else
      log warn "using original compose file without resource injection"
      compose="$compose_original"
    fi
  fi
  
  # Step: Deploy
  current_step=$((current_step + 1))
  set_deploy_step "$stack" "$current_step" "$total_steps" "deploy" 2>/dev/null || true
  step_start_ts=$(date +%s)
  
  # Check for cancellation before docker stack deploy
  if declare -f check_cancellation_requested >/dev/null 2>&1; then
    check_cancellation_requested "$stack" || exit 130
  fi
  
  # Validate images before deploy (skip in CONFIG_ONLY mode - no build happens)
  if [ "${CONFIG_ONLY:-}" != "1" ] && [ "$DRY_RUN" != "1" ]; then
    if [ "$VERBOSE" = "1" ]; then
      if ! validate_images_before_deploy "$stack"; then
        fail "image validation failed: required images not found locally"
      fi
    else
      if ! validate_images_tree "$stack"; then
        fail "image validation failed: required images not found locally"
      fi
    fi
  fi
  
  local deploy_status="failed"
  if [ "$DRY_RUN" = "1" ]; then
    printf "\n$(c 90 "─────────────────────────────────────────────────────────────")\n"
    printf "🚀 $(c 1 "Deploying stack:") %s $(c 90 "(dry-run)")\n" "$stack"
    printf "○ would run docker stack deploy\n"
    deploy_status="dry-run"
    record_step_time "deploy" $(($(date +%s) - step_start_ts))
  else
    # Prepare services list for readiness check
    local services_to_check
    services_to_check=$(services_to_process "$stack")
    local services_array=()
    while IFS= read -r svc; do
      [ -n "$svc" ] || continue
      services_array+=("$svc")
    done <<< "$services_to_check"
    
    # Exclude one-shot init services from readiness check (e.g. superset_init)
    local exclude_services
    exclude_services=$(get_readiness_exclude_services "$stack" 2>/dev/null || true)
    if [ -n "$exclude_services" ]; then
      local excluded=()
      while IFS= read -r ex; do
        [ -n "$ex" ] || continue
        excluded+=("$ex")
      done <<< "$exclude_services"
      local filtered=()
      for svc in "${services_array[@]}"; do
        local skip=0
        for ex in "${excluded[@]}"; do
          [ "$svc" = "$ex" ] && skip=1 && break
        done
        [ $skip -eq 0 ] && filtered+=("$svc")
      done
      services_array=("${filtered[@]}")
    fi
    
    local stack_timeout
    stack_timeout="$(get_stack_services_ready_timeout "$stack")"
    
    if [ "$VERBOSE" = "1" ]; then
      # Verbose mode: plain CLI output
      log_section "deploy" "Deploying stack..."
      log info "running: docker stack deploy --resolve-image always -c <compose> $stack"
      
      if retry_with_backoff docker stack deploy --resolve-image always -c "$compose" "$stack"; then
        log ok "docker stack deploy completed successfully"
        record_step_time "deploy" $(($(date +%s) - step_start_ts))
        
        # Step: Verify services
        current_step=$((current_step + 1))
        set_deploy_step "$stack" "$current_step" "$total_steps" "verify" 2>/dev/null || true
        step_start_ts=$(date +%s)
        
        local verify_flag="${VERIFY_IMAGE_VERSION:-0}"
        [ "$verify_flag" = "1" ] && export VERIFY_IMAGE_VERSION=1
        
        log info "verifying services are ready..."
        if ! wait_for_services_ready "$stack" "$stack_timeout" "${services_array[@]}"; then
          deploy_status="failed"
          log error "deployment failed: services did not become ready"
          save_deploy_history "$stack" "$deploy_status"
          [ -n "$compose_generated" ] && [ -f "$compose_generated" ] && cleanup_generated_compose "$compose_generated"
          release_deploy_lock "$stack"
          exit 2
        fi
        
        record_step_time "verify" $(($(date +%s) - step_start_ts))
        deploy_status="success"
      else
        deploy_status="failed"
        save_deploy_history "$stack" "$deploy_status"
        [ -n "$compose_generated" ] && [ -f "$compose_generated" ] && cleanup_generated_compose "$compose_generated"
        release_deploy_lock "$stack"
        exit 2
      fi
    else
      # Default mode: formatted output
      if ! deploy_stack_tree "$stack" "$compose"; then
        deploy_status="failed"
        save_deploy_history "$stack" "$deploy_status"
        [ -n "$compose_generated" ] && [ -f "$compose_generated" ] && cleanup_generated_compose "$compose_generated"
        release_deploy_lock "$stack"
        exit 2
      fi
      record_step_time "deploy" $(($(date +%s) - step_start_ts))
      
      # Step: Verify services
      current_step=$((current_step + 1))
      set_deploy_step "$stack" "$current_step" "$total_steps" "verify" 2>/dev/null || true
      step_start_ts=$(date +%s)
      
      if ! wait_for_services_ready_tree "$stack" "$stack_timeout" "${services_array[@]}"; then
        deploy_status="failed"
        printf "\n❌ $(c 31 "Deploy failed"): services not ready\n"
        save_deploy_history "$stack" "$deploy_status"
        [ -n "$compose_generated" ] && [ -f "$compose_generated" ] && cleanup_generated_compose "$compose_generated"
        release_deploy_lock "$stack"
        exit 2
      fi
      
      record_step_time "verify" $(($(date +%s) - step_start_ts))
      deploy_status="success"
    fi
  fi
  
  # Run post-deploy hook
  run_hook "$stack_dir/hooks/post-deploy.sh" "$stack"
  
  # Save history (including dry-run)
  if [ "$deploy_status" = "success" ] || [ "$deploy_status" = "dry-run" ]; then
    save_deploy_history "$stack" "$deploy_status"
  fi
  
  # Cleanup generated compose file
  if [ -n "$compose_generated" ] && [ -f "$compose_generated" ]; then
    cleanup_generated_compose "$compose_generated"
  fi
  
  # Prune old images and configs if requested
  if [ "$DO_PRUNE" = "1" ]; then
    printf "\n$(c 90 "─────────────────────────────────────────────────────────────")\n"
    printf "🧹 $(c 1 "Cleaning up old images") $(c 90 "(keeping %s versions)")\n" "${KEEP_IMAGES_COUNT:-10}"
    smart_prune_stack_images "$stack"
    # Also prune old versioned configs
    prune_versioned_configs "$stack"
    printf "$(c 32 "✓") cleanup completed\n"
  fi
  
  local end_ts=$(date +%s)
  local duration=$((end_ts-start_ts))
  
  # Clear operation context (graceful shutdown)
  if declare -f clear_operation_context >/dev/null 2>&1; then
    clear_operation_context
  fi
  
  # Release deployment lock
  if [ "$DRY_RUN" != "1" ]; then
    release_deploy_lock "$stack"
  fi
  
  # Print detailed summary
  print_deploy_summary "$stack" "$deploy_status" "$duration" "$updated_services"
}

# Command: swarmcli secrets check <stack>
cmd_secrets_check() {
  local stack="$1"
  
  [ -n "$stack" ] || fail "usage: swarmcli secrets check <STACK> --profile <PROFILE>"
  
  ensure_stack_exists "$stack"
  
  if check_required_secrets "$stack"; then
    if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
      printf '{"status":"ok","profile":"%s","stack":"%s"}\n' "$ACTIVE_PROFILE" "$stack"
    else
      log info "all required secrets exist"
    fi
  else
    exit 3
  fi
}

# Command: swarmcli deploy (interactive)
# Deploy changed stacks or select interactively
cmd_deploy_interactive() {
  if [ -z "$ACTIVE_PROFILE" ]; then
    fail "no profile loaded. Use --profile <name> or set SWARM_PROFILE"
  fi
  
  local since_ref="${SINCE_REF:-HEAD~1}"
  
  # Check for changed stacks first
  local changed_stacks
  changed_stacks=$(get_changed_stacks "$since_ref" 2>/dev/null || echo "")
  
  if [ -n "$changed_stacks" ]; then
    local count
    count=$(echo "$changed_stacks" | wc -l)
    
    echo ""
    echo "$(c 33 "Found $count stack(s) with config changes since $since_ref:")"
    echo ""
    
    while IFS= read -r stack; do
      [ -n "$stack" ] || continue
      echo "  $(c 32 "●") $stack"
    done <<< "$changed_stacks"
    
    echo ""
    printf "Deploy changed stacks? [y/N/select]: "
    read -r answer
    
    case "$answer" in
      [Yy]|[Yy]es)
        # Deploy all changed stacks
        export CONFIG_ONLY="1"
        local success=0 failed=0
        
        while IFS= read -r stack; do
          [ -n "$stack" ] || continue
          log info "deploying: $stack"
          if cmd_deploy "$stack"; then
            success=$((success + 1))
          else
            failed=$((failed + 1))
          fi
        done <<< "$changed_stacks"
        
        echo ""
        log info "deploy completed: $success succeeded, $failed failed"
        return 0
        ;;
      [Ss]|[Ss]elect)
        # Fall through to interactive selection
        ;;
      *)
        log info "cancelled"
        return 0
        ;;
    esac
  fi
  
  # Interactive stack selection
  local stacks
  stacks=$(list_profile_stacks "$ACTIVE_PROFILE")
  
  if [ -z "$stacks" ]; then
    fail "no stacks found in profile: $ACTIVE_PROFILE"
  fi
  
  echo ""
  echo "$(c 36 "Select stack to deploy:")"
  echo ""
  
  local i=1
  while IFS= read -r stack; do
    [ -z "$stack" ] && continue
    
    # Check deployment status
    local status_indicator
    if docker stack ls --format "{{.Name}}" 2>/dev/null | grep -q "^${stack}$"; then
      status_indicator="$(c 32 "●")"
    else
      status_indicator="$(c 90 "○")"
    fi
    
    printf "  $(c 36 "%2d") │ %s %s\n" "$i" "$status_indicator" "$stack"
    i=$((i+1))
  done <<< "$stacks"
  
  echo ""
  printf "  Enter number (or 'q' to cancel): "
  read -r choice
  
  if [ "$choice" = "q" ] || [ "$choice" = "Q" ]; then
    log info "cancelled"
    return 0
  fi
  
  # Validate input
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    fail "invalid selection: $choice"
  fi
  
  # Get selected stack
  i=1
  local selected_stack=""
  while IFS= read -r stack; do
    [ -z "$stack" ] && continue
    if [ "$i" -eq "$choice" ]; then
      selected_stack="$stack"
      break
    fi
    i=$((i+1))
  done <<< "$stacks"
  
  if [ -z "$selected_stack" ]; then
    fail "invalid selection: $choice"
  fi
  
  cmd_deploy "$selected_stack"
}
