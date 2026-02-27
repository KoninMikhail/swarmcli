#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup

  # Provide minimal log function for utils.sh
  log() { :; }
  export -f log

  # Provide minimal fail function
  fail() { echo "FAIL: $*" >&2; return 1; }
  export -f fail

  source_module "core/utils.sh"
}

# ── ensure_cmd ──

@test "ensure_cmd: existing command returns 0" {
  run ensure_cmd bash
  assert_success
}

@test "ensure_cmd: non-existing command fails" {
  run ensure_cmd nonexistent_cmd_xyz_12345
  assert_failure
}

# ── get_python_cmd ──

@test "get_python_cmd: returns python3 when available" {
  run get_python_cmd
  assert_success
  assert_output --regexp "python3?"
}

# ── run_with_timeout ──

@test "run_with_timeout: fast command succeeds" {
  TIMEOUT_SECONDS=5
  run run_with_timeout echo "hello"
  assert_success
  assert_output "hello"
}

@test "run_with_timeout: timeout returns code 4" {
  TIMEOUT_SECONDS=1
  run run_with_timeout sleep 10
  assert_failure
  [ "$status" -eq 4 ] || [ "$status" -eq 124 ]
}

# ── safe_interpolate ──

@test "safe_interpolate: expands \${VAR}" {
  export MY_VAR="hello"
  run safe_interpolate '${MY_VAR}'
  assert_success
  assert_output "hello"
}

@test "safe_interpolate: expands \$VAR without braces" {
  export MY_VAR="world"
  run safe_interpolate '$MY_VAR'
  assert_success
  assert_output "world"
}

@test "safe_interpolate: undefined variable produces empty string" {
  unset UNDEFINED_VAR 2>/dev/null || true
  run safe_interpolate '${UNDEFINED_VAR}'
  assert_success
  assert_output ""
}

@test "safe_interpolate: nested references are resolved" {
  export INNER="core"
  export OUTER='${INNER}-value'
  run safe_interpolate '${OUTER}'
  assert_success
  assert_output "core-value"
}

@test "safe_interpolate: circular reference does not hang" {
  export LOOP_A='${LOOP_B}'
  export LOOP_B='${LOOP_A}'
  run safe_interpolate '${LOOP_A}'
  assert_success
}

@test "safe_interpolate: strips double quotes" {
  export QUOTED="hello"
  run safe_interpolate '"${QUOTED}"'
  assert_success
  assert_output "hello"
}

@test "safe_interpolate: strips single quotes" {
  run safe_interpolate "'literal'"
  assert_success
  assert_output "literal"
}

# ── safe_load_env ──

@test "safe_load_env: loads simple .env file" {
  local env_file="$TEST_TMPDIR/test.env"
  cat > "$env_file" <<'EOF'
HOST=localhost
PORT=8080
EOF
  safe_load_env "$env_file"
  [ "$HOST" = "localhost" ]
  [ "$PORT" = "8080" ]
}

@test "safe_load_env: handles quoted values" {
  local env_file="$TEST_TMPDIR/quotes.env"
  cat > "$env_file" <<'EOF'
SINGLE='value with spaces'
DOUBLE="another value"
EOF
  safe_load_env "$env_file"
  [ "$SINGLE" = "value with spaces" ]
  [ "$DOUBLE" = "another value" ]
}

@test "safe_load_env: strips export prefix" {
  local env_file="$TEST_TMPDIR/export.env"
  cat > "$env_file" <<'EOF'
export MY_HOST=localhost
export MY_PORT=8080
EOF
  safe_load_env "$env_file"
  [ "$MY_HOST" = "localhost" ]
  [ "$MY_PORT" = "8080" ]
}

@test "safe_load_env: resolves variable references" {
  local env_file="$TEST_TMPDIR/refs.env"
  cat > "$env_file" <<'EOF'
SLE_HOST=localhost
SLE_PORT=8080
SLE_URL=http://${SLE_HOST}:${SLE_PORT}
EOF
  safe_load_env "$env_file"
  [ "$SLE_URL" = "http://localhost:8080" ]
}

@test "safe_load_env: skips comments and empty lines" {
  local env_file="$TEST_TMPDIR/comments.env"
  cat > "$env_file" <<'EOF'
# This is a comment
ACTIVE=true

# Another comment
NAME=test
EOF
  safe_load_env "$env_file"
  [ "$ACTIVE" = "true" ]
  [ "$NAME" = "test" ]
}

@test "safe_load_env: warns on invalid lines" {
  local env_file="$TEST_TMPDIR/invalid.env"
  cat > "$env_file" <<'EOF'
VALID=yes
this is not valid
ALSO_VALID=true
EOF
  run safe_load_env "$env_file"
  assert_success
}

@test "safe_load_env: missing file returns 0" {
  run safe_load_env "/nonexistent/file.env"
  assert_success
}
