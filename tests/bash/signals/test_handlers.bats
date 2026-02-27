#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup
  source_module "core/output.sh"
  source_module "core/logging.sh"
  source_module "signals/handlers.sh"
  reset_shutdown_state
}

@test "init_signal_handlers: returns 0" {
  run init_signal_handlers
  assert_success
}

@test "register_cleanup_handler: adds handler to array" {
  register_cleanup_handler "echo cleanup1"
  [ "${#_CLEANUP_HANDLERS[@]}" -eq 1 ]
  register_cleanup_handler "echo cleanup2"
  [ "${#_CLEANUP_HANDLERS[@]}" -eq 2 ]
}

@test "_run_cleanup_handlers: LIFO order" {
  local log_file="$TEST_TMPDIR/cleanup_order.log"

  handler_a() { echo "A" >> "$log_file"; }
  handler_b() { echo "B" >> "$log_file"; }
  export -f handler_a handler_b

  register_cleanup_handler "handler_a"
  register_cleanup_handler "handler_b"
  _run_cleanup_handlers

  local result
  result=$(cat "$log_file")
  [[ "$result" == *"B"*"A"* ]]
}

@test "set_operation_context and clear_operation_context" {
  set_operation_context "building images"
  [ "$_CURRENT_OPERATION" = "building images" ]
  clear_operation_context
  [ -z "$_CURRENT_OPERATION" ]
}

@test "is_shutting_down: default is false" {
  run is_shutting_down
  assert_failure
}

@test "reset_shutdown_state: clears all state" {
  _SHUTDOWN_IN_PROGRESS=1
  _CHILD_PIDS=(123 456)
  _CLEANUP_HANDLERS=("handler1" "handler2")
  _CURRENT_OPERATION="test"

  reset_shutdown_state

  [ "$_SHUTDOWN_IN_PROGRESS" = "0" ]
  [ "${#_CHILD_PIDS[@]}" -eq 0 ]
  [ "${#_CLEANUP_HANDLERS[@]}" -eq 0 ]
  [ -z "$_CURRENT_OPERATION" ]
}

@test "_signal_handler: prevents recursive calls" {
  _SHUTDOWN_IN_PROGRESS=1
  SIGNAL_DEBUG=1
  run _signal_handler INT
  assert_success
  assert_output --partial "ignoring"
}
