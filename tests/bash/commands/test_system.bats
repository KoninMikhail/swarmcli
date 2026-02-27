#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup
  source_module "core/output.sh"
  source_module "core/logging.sh"
  source_module "core/errors.sh"
  source_module "commands/system.sh"

  # Set VERSION from version.txt
  VERSION="$(cat "$PROJECT_ROOT/version.txt" 2>/dev/null || echo "0.0.0")"
  export VERSION
}

@test "cmd_version: text contains VERSION" {
  run cmd_version
  assert_success
  assert_output --partial "$VERSION"
}

@test "cmd_version: JSON output is valid JSON" {
  FORCE_JSON=1
  run cmd_version
  assert_success
  echo "$output" | jq . >/dev/null 2>&1
  echo "$output" | jq -e '.version' >/dev/null
}
