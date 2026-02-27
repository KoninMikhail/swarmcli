#!/usr/bin/env bash
# Rollback command

# Command: swarmcli rollback <stack>
cmd_rollback() {
  local stack="$1"
  shift || true
  
  [ -n "$stack" ] || fail "usage: swarmcli rollback <STACK> --profile <PROFILE> [--to-version N]"
  
  ensure_stack_exists "$stack"
  
  # Acquire deployment lock (skip in dry-run mode)
  if [ "$DRY_RUN" != "1" ]; then
    if ! acquire_deploy_lock "$stack"; then
      fail "cannot acquire deployment lock for rollback"
    fi
    
    # Initialize graceful shutdown handlers
    init_signal_handlers
    register_cleanup_handler "release_deploy_lock $stack"
    set_operation_context "rollback $stack"
  fi
  
  rollback_deploy "$stack" "$@"
  local rc=$?
  
  # Release deployment lock
  if [ "$DRY_RUN" != "1" ]; then
    release_deploy_lock "$stack"
  fi
  
  return $rc
}
