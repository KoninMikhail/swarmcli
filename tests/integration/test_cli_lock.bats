#!/usr/bin/env bats

setup() {
  load '../bash/test_helper'
  export SWARMCLI="$PROJECT_ROOT/bin/swarm.sh"
  export COLOR=0
  export NO_COLOR=1
  export EXEC_CONTEXT="script"
  
  CONFIG_FILE="$PROJECT_ROOT/.swarmcli.yaml"
  if [ ! -f "$CONFIG_FILE" ]; then
    bash "$SWARMCLI" config init 2>/dev/null || true
  fi
}

@test "swarmcli lock ls: runs without error" {
  run bash "$SWARMCLI" lock ls
  assert_success
}

@test "swarmcli lock prune: runs without error" {
  run bash "$SWARMCLI" lock prune
  assert_success
}
