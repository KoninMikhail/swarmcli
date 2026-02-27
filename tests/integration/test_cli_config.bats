#!/usr/bin/env bats

setup() {
  load '../bash/test_helper'
  export SWARMCLI="$PROJECT_ROOT/bin/swarm.sh"
  export COLOR=0
  export NO_COLOR=1
  export EXEC_CONTEXT="script"

  # swarm.sh resolves PLATFORM_ROOT from its own path, so config file
  # lives at PROJECT_ROOT/.swarmcli.yaml. Back it up if exists.
  CONFIG_FILE="$PROJECT_ROOT/.swarmcli.yaml"
  if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$BATS_TEST_TMPDIR/.swarmcli.yaml.bak"
    RESTORE_CONFIG=1
  else
    RESTORE_CONFIG=0
  fi
}

teardown() {
  if [ "$RESTORE_CONFIG" = "1" ]; then
    cp "$BATS_TEST_TMPDIR/.swarmcli.yaml.bak" "$CONFIG_FILE"
  else
    rm -f "$CONFIG_FILE"
  fi
}

@test "swarmcli config path: shows file path" {
  run bash "$SWARMCLI" config path
  assert_success
  assert_output --partial ".swarmcli.yaml"
}

@test "swarmcli config init: creates config file" {
  rm -f "$CONFIG_FILE"
  run bash "$SWARMCLI" config init
  assert_success
  assert [ -f "$CONFIG_FILE" ]
}

@test "swarmcli config set and get: roundtrip" {
  rm -f "$CONFIG_FILE"
  bash "$SWARMCLI" config init
  bash "$SWARMCLI" config set operations.timeout 600
  run bash "$SWARMCLI" config get operations.timeout
  assert_success
  assert_output "600"
}

@test "swarmcli config list: shows all keys" {
  rm -f "$CONFIG_FILE"
  bash "$SWARMCLI" config init
  run bash "$SWARMCLI" config list
  assert_success
  assert_output --partial "config_version"
}
