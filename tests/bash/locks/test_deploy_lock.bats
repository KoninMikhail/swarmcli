#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup
  source_module "core/output.sh"
  source_module "core/logging.sh"
  source_module "core/errors.sh"
  source_module "locks/deploy.sh"

  clear_errors
}

@test "acquire_deploy_lock: success creates lock directory" {
  run acquire_deploy_lock "test-stack"
  assert_success
  assert [ -d "$LOCKS_DIR/${ACTIVE_PROFILE}_test-stack.lock" ]
}

@test "acquire_deploy_lock: lock contains metadata files" {
  acquire_deploy_lock "test-stack"
  local lock_dir="$LOCKS_DIR/${ACTIVE_PROFILE}_test-stack.lock"
  assert [ -f "$lock_dir/pid" ]
  assert [ -f "$lock_dir/timestamp" ]
  assert [ -f "$lock_dir/stack" ]
  assert [ -f "$lock_dir/profile" ]
}

@test "acquire_deploy_lock: duplicate lock returns conflict" {
  acquire_deploy_lock "test-stack"
  run acquire_deploy_lock "test-stack"
  assert_failure
}

@test "acquire_deploy_lock: stale lock with dead PID replaced" {
  local lock_dir="$LOCKS_DIR/${ACTIVE_PROFILE}_test-stack.lock"
  mkdir -p "$lock_dir"
  echo "99999999" > "$lock_dir/pid"
  echo "1000000" > "$lock_dir/timestamp"
  echo "test-stack" > "$lock_dir/stack"

  run acquire_deploy_lock "test-stack"
  assert_success
}

@test "acquire_deploy_lock: corrupted lock without timestamp replaced" {
  local lock_dir="$LOCKS_DIR/${ACTIVE_PROFILE}_test-stack.lock"
  mkdir -p "$lock_dir"

  run acquire_deploy_lock "test-stack"
  assert_success
}

@test "release_deploy_lock: removes lock directory" {
  acquire_deploy_lock "test-stack"
  release_deploy_lock "test-stack"
  assert [ ! -d "$LOCKS_DIR/${ACTIVE_PROFILE}_test-stack.lock" ]
}

@test "release_deploy_lock: other PID warns but still removes" {
  local lock_dir="$LOCKS_DIR/${ACTIVE_PROFILE}_test-stack.lock"
  mkdir -p "$lock_dir"
  echo "12345" > "$lock_dir/pid"
  echo "$(date +%s)" > "$lock_dir/timestamp"

  release_deploy_lock "test-stack"
  assert [ ! -d "$lock_dir" ]
}

@test "force_release_deploy_lock: removes lock unconditionally" {
  local lock_dir="$LOCKS_DIR/${ACTIVE_PROFILE}_test-stack.lock"
  mkdir -p "$lock_dir"
  echo "99999" > "$lock_dir/pid"

  run force_release_deploy_lock "test-stack"
  assert_success
  assert [ ! -d "$lock_dir" ]
}

@test "list_active_locks: shows existing locks" {
  local lock_dir="$LOCKS_DIR/${ACTIVE_PROFILE}_test-stack.lock"
  mkdir -p "$lock_dir"
  echo "$$" > "$lock_dir/pid"
  echo "$(date +%s)" > "$lock_dir/timestamp"
  echo "test-stack" > "$lock_dir/stack"
  echo "test-server" > "$lock_dir/profile"
  echo "$USER" > "$lock_dir/user"

  run list_active_locks
  assert_success
  assert_output --partial "test-stack"
}

@test "list_active_locks: JSON mode outputs valid JSON" {
  local lock_dir="$LOCKS_DIR/${ACTIVE_PROFILE}_test-stack.lock"
  mkdir -p "$lock_dir"
  echo "$$" > "$lock_dir/pid"
  echo "$(date +%s)" > "$lock_dir/timestamp"
  echo "test-stack" > "$lock_dir/stack"
  echo "test-server" > "$lock_dir/profile"
  echo "$USER" > "$lock_dir/user"

  FORCE_JSON=1
  run list_active_locks
  assert_success
  echo "$output" | jq . >/dev/null 2>&1
}

@test "list_active_locks: no locks message" {
  rm -rf "$LOCKS_DIR"/*.lock 2>/dev/null || true
  run list_active_locks
  assert_success
  assert_output --partial "no"
}

@test "cleanup_stale_locks: removes stale locks" {
  local lock_dir="$LOCKS_DIR/${ACTIVE_PROFILE}_stale.lock"
  mkdir -p "$lock_dir"
  echo "99999999" > "$lock_dir/pid"
  echo "1000000" > "$lock_dir/timestamp"
  echo "stale" > "$lock_dir/stack"
  echo "test-server" > "$lock_dir/profile"

  LOCK_TIMEOUT=1
  run cleanup_stale_locks
  assert_success
  assert_output --partial "cleaned"
  assert [ ! -d "$lock_dir" ]
}

@test "cleanup_stale_locks: no stale locks message" {
  rm -rf "$LOCKS_DIR"/*.lock 2>/dev/null || true
  run cleanup_stale_locks
  assert_success
  assert_output --partial "no stale"
}
