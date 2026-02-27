#!/usr/bin/env bats

setup() {
  load '../bash/test_helper'
  export SWARMCLI="$PROJECT_ROOT/bin/swarm.sh"
  export COLOR=0
  export NO_COLOR=1
  export EXEC_CONTEXT="script"
}

@test "swarmcli help: shows usage and returns 0" {
  run bash "$SWARMCLI" help
  assert_success
  assert_output --partial "swarmcli"
}

@test "swarmcli --help: shows usage" {
  run bash "$SWARMCLI" --help
  assert_success
  assert_output --partial "swarmcli"
}

@test "swarmcli unknown_cmd: returns non-zero" {
  run bash "$SWARMCLI" nonexistent_command_xyz
  assert_failure
}
