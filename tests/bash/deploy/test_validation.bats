#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup
  source_module "core/output.sh"
  source_module "core/logging.sh"
  source_module "core/errors.sh"

  get_current_stack_dir() { echo "$PROFILE_STACKS_DIR/$1"; }
  export -f get_current_stack_dir

  # Stub stack_exists
  stack_exists() {
    local stack="$1"
    [ -d "$(get_current_stack_dir "$stack")" ]
  }
  export -f stack_exists

  # Stub ensure_stack_exists
  ensure_stack_exists() {
    stack_exists "$1" || { echo "stack not found: $1" >&2; return 1; }
  }
  export -f ensure_stack_exists
}

@test "stack exists check: valid stack returns 0" {
  mkdir -p "$PROFILE_STACKS_DIR/test-stack"
  run stack_exists "test-stack"
  assert_success
}

@test "stack exists check: missing stack returns 1" {
  run stack_exists "nonexistent"
  assert_failure
}

@test "ensure_stack_exists: valid stack passes" {
  mkdir -p "$PROFILE_STACKS_DIR/test-stack"
  run ensure_stack_exists "test-stack"
  assert_success
}

@test "ensure_stack_exists: missing stack fails" {
  run ensure_stack_exists "nonexistent"
  assert_failure
  assert_output --partial "stack not found"
}
