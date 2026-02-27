#!/usr/bin/env bats

setup() {
  load '../bash/test_helper'
  export SWARMCLI="$PROJECT_ROOT/bin/swarm.sh"
  export COLOR=0
  export NO_COLOR=1
  export EXEC_CONTEXT="script"
}

@test "swarmcli system version: outputs version string" {
  run bash "$SWARMCLI" system version
  assert_success
  assert_output --partial "swarmcli"
}

@test "swarmcli system version --json: outputs valid JSON" {
  run bash "$SWARMCLI" system version --json
  assert_success
  echo "$output" | jq . >/dev/null 2>&1
  echo "$output" | jq -e '.version' >/dev/null
}

@test "swarmcli system health: lists dependencies" {
  run bash "$SWARMCLI" system health
  assert_output --partial "Bash"
}
