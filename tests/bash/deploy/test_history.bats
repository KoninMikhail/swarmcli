#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup
  source_module "core/output.sh"
  source_module "core/logging.sh"

  get_current_stack_dir() { echo "$PROFILE_STACKS_DIR/$1"; }
  export -f get_current_stack_dir

  source_module "deploy/history.sh"
}

@test "get_deploy_history_dir: path ends with .deploy" {
  mkdir -p "$PROFILE_STACKS_DIR/test-stack"
  run get_deploy_history_dir "test-stack"
  assert_success
  assert_output --partial ".deploy"
}

@test "get_last_successful_deploy: no file returns empty JSON" {
  mkdir -p "$PROFILE_STACKS_DIR/test-stack"
  run get_last_successful_deploy "test-stack"
  assert_failure
  assert_output "{}"
}

@test "get_last_successful_deploy: finds last success" {
  mkdir -p "$PROFILE_STACKS_DIR/test-stack/.deploy"
  local history_file="$PROFILE_STACKS_DIR/test-stack/.deploy/history.jsonl"
  echo '{"timestamp":"2024-01-01T00:00:00Z","status":"error"}' > "$history_file"
  echo '{"timestamp":"2024-01-02T00:00:00Z","status":"success","services":[]}' >> "$history_file"
  echo '{"timestamp":"2024-01-03T00:00:00Z","status":"error"}' >> "$history_file"

  run get_last_successful_deploy "test-stack"
  assert_success
  echo "$output" | jq -e '.status == "success"' >/dev/null
}
