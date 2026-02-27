#!/usr/bin/env bats

setup() {
  load '../bash/test_helper'
  export SWARMCLI="$PROJECT_ROOT/bin/swarm.sh"
  export COLOR=0
  export NO_COLOR=1
  export EXEC_CONTEXT="script"

  PROFILES_DIR="$PROJECT_ROOT/profiles"
  TEST_PROFILE_DIR="$PROFILES_DIR/test-integ-profile"
  CONFIG_FILE="$PROJECT_ROOT/.swarmcli.yaml"

  # Back up config if exists
  if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$BATS_TEST_TMPDIR/.swarmcli.yaml.bak"
    RESTORE_CONFIG=1
  else
    RESTORE_CONFIG=0
  fi

  # Create a test profile
  mkdir -p "$TEST_PROFILE_DIR/stacks"
  cat > "$TEST_PROFILE_DIR/config.yaml" <<'YAML'
name: Test Profile
description: Integration test
swarm:
  services_ready_timeout: 30
  keep_images_count: 10
git:
  default_branch: main
retry:
  enabled: true
  max_attempts: 3
  initial_delay: 2
  max_delay: 30
YAML

  # Ensure config exists
  if [ ! -f "$CONFIG_FILE" ]; then
    bash "$SWARMCLI" config init 2>/dev/null
  fi
}

teardown() {
  rm -rf "$TEST_PROFILE_DIR"
  if [ "$RESTORE_CONFIG" = "1" ]; then
    cp "$BATS_TEST_TMPDIR/.swarmcli.yaml.bak" "$CONFIG_FILE"
  else
    rm -f "$CONFIG_FILE"
  fi
}

@test "swarmcli profile ls: lists profiles" {
  run bash "$SWARMCLI" profile ls
  assert_success
  assert_output --partial "test-integ-profile"
}

@test "swarmcli use: sets default profile" {
  run bash "$SWARMCLI" use test-integ-profile
  assert_success
}

@test "swarmcli use --show: shows current profile after set" {
  bash "$SWARMCLI" use test-integ-profile
  run bash "$SWARMCLI" use --show
  assert_success
  assert_output --partial "test-integ-profile"
}

@test "swarmcli use --clear: clears default profile" {
  bash "$SWARMCLI" use test-integ-profile
  run bash "$SWARMCLI" use --clear
  assert_success
}
