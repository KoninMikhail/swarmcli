#!/usr/bin/env bash
# Command routing module

# ============================================================================
# Command aliases (backwards compatibility + shortcuts)
# ============================================================================

resolve_command_alias() {
  local cmd="$1"
  case "$cmd" in
    # Shortcuts
    d) echo "deploy" ;;
    b) echo "build" ;;
    s) echo "ps" ;;
    l) echo "logs" ;;
    
    # Backwards compatibility
    list) echo "ls" ;;
    status) echo "ps" ;;
    profiles) echo "profile" ;;
    secrets) echo "secret" ;;
    locks) echo "lock" ;;
    repos) echo "repo" ;;
    cfg) echo "config" ;;
    
    *) echo "$cmd" ;;
  esac
}

# ============================================================================
# Help
# ============================================================================

show_help() {
  sed -n '2,/^#====/{ /^#/s/^# \?//p }' "$SCRIPT_PATH"
}

# ============================================================================
# Interactive stack selection
# ============================================================================

# Select stack interactively or return single stack
# Usage: select_stack_interactive [stack_arg]
# Returns: stack name on stdout, exits 1 if cancelled
select_stack_interactive() {
  local stack_arg="${1:-}"
  
  # If stack provided, use it
  if [ -n "$stack_arg" ]; then
    echo "$stack_arg"
    return 0
  fi
  
  # Ensure profile is loaded
  if [ -z "$ACTIVE_PROFILE" ]; then
    fail "no profile loaded. Use --profile <name> or: swarmcli use <profile>"
  fi
  
  # Get stacks list
  local stacks
  stacks=$(list_profile_stacks "$ACTIVE_PROFILE")
  
  if [ -z "$stacks" ]; then
    fail "no stacks found in profile: $ACTIVE_PROFILE"
  fi
  
  # Count stacks
  local count
  count=$(echo "$stacks" | wc -l)
  
  # If only one stack, use it automatically
  if [ "$count" -eq 1 ]; then
    echo "$stacks"
    return 0
  fi
  
  # Interactive selection
  echo "" >&2
  echo "$(c 36 "Select stack:")" >&2
  echo "" >&2
  
  local i=1
  while IFS= read -r stack; do
    [ -z "$stack" ] && continue
    printf "  $(c 36 "%2d") │ %s\n" "$i" "$stack" >&2
    i=$((i+1))
  done <<< "$stacks"
  
  echo "" >&2
  printf "  Enter number (or 'q' to cancel): " >&2
  read -r choice
  
  if [ "$choice" = "q" ] || [ "$choice" = "Q" ]; then
    fail "cancelled"
  fi
  
  # Validate input
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    fail "invalid selection: $choice"
  fi
  
  # Get selected stack
  i=1
  while IFS= read -r stack; do
    [ -z "$stack" ] && continue
    if [ "$i" -eq "$choice" ]; then
      echo "$stack"
      return 0
    fi
    i=$((i+1))
  done <<< "$stacks"
  
  fail "invalid selection: $choice"
}

# ============================================================================
# Main command router
# ============================================================================

route_command() {
  local command="$1"
  shift
  
  case "$command" in
    # ====== System commands (no profile needed) ======
    system)
      local sub="${1:-version}"
      shift || true
      case "$sub" in
        version) cmd_version ;;
        health) cmd_check_deps ;;
        update) cmd_self_update "$@" ;;
        *) fail "unknown system subcommand: $sub (use: version, health, update)" ;;
      esac
      ;;
      
    # ====== Global commands (no profile needed) ======
    help|--help|-h)
      show_help
      ;;
    create)
      cmd_create
      ;;
    use)
      cmd_use "$@"
      ;;
    config|cfg)
      cmd_config "$@"
      ;;
      
    # ====== Profile commands ======
    profile)
      local sub="${1:-ls}"
      shift || true
      case "$sub" in
        ls|list) cmd_profiles_list ;;
        inspect|info)
          local profile_arg="${1:-$ACTIVE_PROFILE}"
          [ -n "$profile_arg" ] || fail "usage: swarmcli profile inspect [PROFILE]"
          cmd_profile_info "$profile_arg"
          ;;
        *) fail "unknown profile subcommand: $sub (use: ls, inspect)" ;;
      esac
      ;;
      
    # ====== Stack commands ======
    ls)
      cmd_list
      ;;
    ps)
      local stack="${1:-}"
      if [ -n "$stack" ]; then
        ensure_stack_exists "$stack"
        cmd_status "$stack"
      else
        # Show status for all stacks
        cmd_ps_all
      fi
      ;;
    logs)
      local stack
      stack=$(select_stack_interactive "${1:-}")
      shift || true
      cmd_logs "$stack" "$@"
      ;;
    inspect)
      local stack="${1:-}"
      [ -n "$stack" ] || fail "usage: swarmcli inspect <STACK>"
      cmd_stack_inspect "$stack"
      ;;
    validate)
      local stack
      stack=$(select_stack_interactive "${1:-}")
      cmd_validate "$stack"
      ;;
      
    # ====== Build & Deploy ======
    sync|pull|repo)
      # Handle 'sync', 'pull' (alias), and 'repo sync'
      if [ "$command" = "repo" ]; then
        local sub="${1:-sync}"
        shift || true
        [ "$sub" = "sync" ] || fail "unknown repo subcommand: $sub (use: sync)"
      fi
      local stack
      stack=$(select_stack_interactive "${1:-}")
      cmd_repos_sync "$stack"
      ;;
    build)
      local stack
      stack=$(select_stack_interactive "${1:-}")
      cmd_build "$stack"
      ;;
    deploy)
      local stack="${1:-}"
      if [ -z "$stack" ]; then
        # No stack specified - check for changed stacks
        cmd_deploy_interactive
      else
        cmd_deploy "$stack"
      fi
      ;;
    down|rm|remove)
      local stack
      stack=$(select_stack_interactive "${1:-}")
      shift || true
      cmd_down "$stack" "$@"
      ;;
    rollback)
      local stack
      stack=$(select_stack_interactive "${1:-}")
      shift || true
      cmd_rollback "$stack" "$@"
      ;;
      
    # ====== Configuration ======
    diff)
      cmd_diff "$@"
      ;;
    apply)
      cmd_apply "$@"
      ;;
      
    # ====== Secrets ======
    secret)
      local sub="${1:-ls}"
      shift || true
      case "$sub" in
        ls|list) list_secrets ;;
        check)
          local stack
          stack=$(select_stack_interactive "${1:-}")
          cmd_secrets_check "$stack"
          ;;
        sync) with_spinner "secrets sync" secrets_sync ;;
        create)
          cmd_secret_create "$@"
          ;;
        rm|remove|delete)
          cmd_secret_rm "$@"
          ;;
        generate|gen)
          cmd_secret_generate "$@"
          ;;
        *) fail "unknown secret subcommand: $sub (use: ls, check, sync, create, rm, generate)" ;;
      esac
      ;;
      
    # ====== Locks ======
    lock)
      local sub="${1:-ls}"
      shift || true
      case "$sub" in
        ls|list) list_active_locks ;;
        prune|cleanup) cleanup_stale_locks ;;
        rm|release)
          local stack="${1:-}"
          [ -n "$stack" ] || fail "usage: swarmcli lock rm <STACK>"
          force_release_deploy_lock "$stack"
          ;;
        *) fail "unknown lock subcommand: $sub (use: ls, prune, rm)" ;;
      esac
      ;;
      
    # ====== Templates ======
    template)
      local sub="${1:-}"
      shift || true
      [ -n "$sub" ] || fail "usage: swarmcli template <init|render|vars> <STACK>"
      case "$sub" in
        init)
          local stack
          stack=$(select_stack_interactive "${1:-}")
          template_init "$stack"
          ;;
        render)
          local stack
          stack=$(select_stack_interactive "${1:-}")
          shift || true
          template_render "$stack" "$@"
          ;;
        vars)
          local stack
          stack=$(select_stack_interactive "${1:-}")
          template_vars "$stack"
          ;;
        *) fail "unknown template subcommand: $sub (use: init, render, vars)" ;;
      esac
      ;;
      
    # ====== Registry ======
    registry)
      local sub="${1:-ls}"
      shift || true
      case "$sub" in
        ls|list) cmd_registry_list ;;
        check|validate) cmd_registry_validate ;;
        *) fail "unknown registry subcommand: $sub (use: ls, check)" ;;
      esac
      ;;
      
    # ====== Plugins ======
    plugin)
      local name="${1:-}"
      shift || true
      [ -n "$name" ] || {
        list_plugins
        return 0
      }
      execute_plugin "$name" "$@" || return $?
      ;;
      
    # ====== Unknown - try as plugin ======
    *)
      if plugin_exists "$command"; then
        execute_plugin "$command" "$@" || return $?
      else
        log error "unknown command: $command"
        echo ""
        echo "Run 'swarmcli help' for usage."
        return 1
      fi
      ;;
  esac
}

