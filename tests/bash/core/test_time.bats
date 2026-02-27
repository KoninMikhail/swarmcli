#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup
  source_module "core/output.sh"
  source_module "core/logging.sh"
  source_module "core/time.sh"
}

@test "now_ms: returns a positive number" {
  run now_ms
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -gt 0 ]
}

@test "record_step_time and get_step_time: stores and retrieves" {
  record_step_time "build" 15
  run get_step_time "build"
  assert_success
  assert_output "15"
}

@test "get_step_time: returns 0 for non-existing step" {
  run get_step_time "nonexistent_step"
  assert_success
  assert_output "0"
}

@test "clear_step_times: empties all step times" {
  record_step_time "build" 10
  record_step_time "deploy" 20
  clear_step_times
  run get_step_time "build"
  assert_output "0"
  run get_step_time "deploy"
  assert_output "0"
}

@test "print_deploy_summary: text mode contains stack info" {
  ACTIVE_PROFILE="test-server"
  record_step_time "build" 5
  run print_deploy_summary "mystack" "success" 30 3
  assert_success
  assert_output --partial "mystack"
  assert_output --partial "3"
}

@test "print_deploy_summary: JSON mode outputs valid JSON" {
  FORCE_JSON=1
  clear_step_times
  record_step_time "build" 10
  run print_deploy_summary "mystack" "success" 30 3
  assert_success
  echo "$output" | jq . >/dev/null 2>&1
  echo "$output" | jq -e '.event == "deploy_complete"' >/dev/null
  echo "$output" | jq -e '.stack == "mystack"' >/dev/null
  echo "$output" | jq -e '.status == "success"' >/dev/null
}

@test "print_deploy_summary: verbose mode shows tree" {
  VERBOSE=1
  run print_deploy_summary "mystack" "success" 30 3
  assert_success
  assert_output --partial "Stack:"
  assert_output --partial "mystack"
}

@test "print_deploy_summary: quiet mode outputs nothing" {
  QUIET=1
  run print_deploy_summary "mystack" "success" 30 3
  assert_success
  assert_output ""
}
