#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup

  log() {
    local level="$1"; shift
    echo "[$level] $*" >&2
  }
  export -f log

  source_module "core/retry.sh"
  export RETRY_ENABLED=1
  export RETRY_INITIAL_DELAY=0
  export RETRY_MAX_DELAY=0
}

@test "retry: success on first attempt" {
  run retry_with_backoff true
  assert_success
}

@test "retry: success on second attempt" {
  local counter_file="$TEST_TMPDIR/counter"
  echo "0" > "$counter_file"

  attempt_cmd() {
    local count
    count=$(cat "$counter_file")
    count=$((count + 1))
    echo "$count" > "$counter_file"
    [ "$count" -ge 2 ]
  }
  export -f attempt_cmd

  RETRY_MAX_ATTEMPTS=3
  run retry_with_backoff attempt_cmd
  assert_success
}

@test "retry: all attempts fail and logs error" {
  RETRY_MAX_ATTEMPTS=2
  run retry_with_backoff false
  assert_output --partial "failed after 2 attempts"
}

@test "retry: RETRY_ENABLED=0 disables retry" {
  RETRY_ENABLED=0
  run retry_with_backoff false
  assert_failure
}

@test "retry: RETRY_MAX_ATTEMPTS is configurable" {
  local counter_file="$TEST_TMPDIR/retry_counter"
  echo "0" > "$counter_file"

  count_cmd() {
    local count
    count=$(cat "$counter_file")
    count=$((count + 1))
    echo "$count" > "$counter_file"
    return 1
  }
  export -f count_cmd

  RETRY_MAX_ATTEMPTS=4
  run retry_with_backoff count_cmd

  local final_count
  final_count=$(cat "$counter_file")
  [ "$final_count" -eq 4 ]
}
