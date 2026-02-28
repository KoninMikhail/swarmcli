#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup

  source_module "core/output.sh"
  source_module "core/logging.sh"
  source_module "core/errors.sh"

  get_current_stack_dir() { echo "$PROFILE_STACKS_DIR/$1"; }
  export -f get_current_stack_dir

  stack_exists() {
    local stack="$1"
    [ -d "$(get_current_stack_dir "$stack")" ]
  }
  export -f stack_exists

  ensure_stack_exists() {
    stack_exists "$1" || { echo "stack not found: $1" >&2; return 1; }
  }
  export -f ensure_stack_exists

  mkdir -p "$PROFILE_STACKS_DIR/test-stack"

  source_module "commands/stack.sh"
}

# -- Argument validation --

@test "cmd_down: fails without stack argument" {
  run cmd_down ""
  assert_failure
  assert_output --partial "usage:"
}

@test "cmd_down: fails for nonexistent stack" {
  run cmd_down "nonexistent"
  assert_failure
  assert_output --partial "stack not found"
}

@test "cmd_down: fails on unknown option" {
  docker() {
    case "$1 $2" in
      "stack ls") echo "test-stack" ;;
      "stack services") echo "svc1" ;;
    esac
  }
  export -f docker

  run cmd_down "test-stack" "--unknown"
  assert_failure
  assert_output --partial "unknown option"
}

# -- Stack not deployed --

@test "cmd_down: warns when stack is not deployed" {
  docker() {
    case "$1 $2" in
      "stack ls") echo "" ;;
    esac
  }
  export -f docker

  run cmd_down "test-stack"
  assert_success
  assert_output --partial "not deployed"
}

# -- Dry run --

@test "cmd_down: dry-run does not remove stack" {
  DRY_RUN=1

  docker() {
    case "$1 $2" in
      "stack ls") echo "test-stack" ;;
      "stack services") echo "svc1" ;;
    esac
  }
  export -f docker

  run cmd_down "test-stack" "--force"
  assert_success
  assert_output --partial "dry-run"
}

# -- Forced removal --

@test "cmd_down: --force removes stack without confirmation" {
  docker() {
    case "$1 $2" in
      "stack ls") echo "test-stack" ;;
      "stack services") echo "svc1" ;;
      "stack rm") return 0 ;;
      "stack ps") return 1 ;;
    esac
  }
  export -f docker

  run cmd_down "test-stack" "--force"
  assert_success
  assert_output --partial "stack removed"
}

@test "cmd_down: -f shorthand works" {
  docker() {
    case "$1 $2" in
      "stack ls") echo "test-stack" ;;
      "stack services") echo "svc1" ;;
      "stack rm") return 0 ;;
      "stack ps") return 1 ;;
    esac
  }
  export -f docker

  run cmd_down "test-stack" "-f"
  assert_success
  assert_output --partial "stack removed"
}

# -- Docker failure --

@test "cmd_down: reports error when docker stack rm fails" {
  docker() {
    case "$1 $2" in
      "stack ls") echo "test-stack" ;;
      "stack services") echo "svc1" ;;
      "stack rm") return 1 ;;
    esac
  }
  export -f docker

  run cmd_down "test-stack" "--force"
  assert_failure
  assert_output --partial "failed to remove"
}

# -- Cancellation in non-interactive (stdin is not a tty) --

@test "cmd_down: without --force and non-interactive, skips removal" {
  docker() {
    case "$1 $2" in
      "stack ls") echo "test-stack" ;;
      "stack services") echo "svc1" ;;
    esac
  }
  export -f docker

  echo "n" | run cmd_down "test-stack"
  assert_success
}
