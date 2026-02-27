#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup
  source_module "core/output.sh"
  source_module "core/logging.sh"
}

# ── now_iso ──

@test "now_iso: returns ISO 8601 format" {
  run now_iso
  assert_success
  assert_output --regexp '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
}

# ── detect_exec_context ──

@test "detect_exec_context: CI environment" {
  CI=true
  run detect_exec_context
  assert_success
  assert_output "ci"
}

@test "detect_exec_context: script mode when stdout is not TTY" {
  unset CI GITLAB_CI GITHUB_ACTIONS
  run detect_exec_context
  assert_success
  assert_output "script"
}

# ── is_ci ──

@test "is_ci: returns 0 when EXEC_CONTEXT=ci" {
  EXEC_CONTEXT="ci"
  run is_ci
  assert_success
}

@test "is_ci: returns 1 when EXEC_CONTEXT=interactive" {
  EXEC_CONTEXT="interactive"
  run is_ci
  assert_failure
}

# ── is_interactive / is_script ──

@test "is_interactive: returns 0 when EXEC_CONTEXT=interactive" {
  EXEC_CONTEXT="interactive"
  run is_interactive
  assert_success
}

@test "is_script: returns 0 when EXEC_CONTEXT=script" {
  EXEC_CONTEXT="script"
  run is_script
  assert_success
}

# ── log ──

@test "log info: outputs to stdout" {
  run log info "test message"
  assert_success
  assert_output --partial "[info]"
  assert_output --partial "test message"
}

@test "log error: outputs to stderr" {
  run log error "error message"
  assert_output --partial "error message"
}

@test "log warn: outputs to stderr" {
  run log warn "warning message"
  assert_output --partial "warning message"
}

@test "log detail: hidden without verbose" {
  VERBOSE=""
  run log detail "detail message"
  assert_success
  assert_output ""
}

@test "log detail: shown with verbose" {
  VERBOSE=1
  run log detail "detail message"
  assert_success
  assert_output --partial "detail message"
}

@test "log info: hidden in quiet mode" {
  QUIET=1
  run log info "quiet message"
  assert_success
  assert_output ""
}

@test "log: JSON mode outputs valid JSON" {
  FORCE_JSON=1
  run log info "json test"
  assert_success
  echo "$output" | jq . >/dev/null 2>&1
  echo "$output" | jq -e '.level == "info"' >/dev/null
  echo "$output" | jq -e '.msg == "json test"' >/dev/null
}

# ── log_json ──

@test "log_json: produces valid JSON" {
  run log_json info "structured message"
  assert_success
  echo "$output" | jq . >/dev/null 2>&1
  echo "$output" | jq -e '.ts' >/dev/null
  echo "$output" | jq -e '.level == "info"' >/dev/null
  echo "$output" | jq -e '.msg == "structured message"' >/dev/null
}

@test "log_json: with extra fields" {
  LOG_EXTRA_JSON='"stack":"test-stack","profile":"dev"'
  run log_json info "with extras"
  assert_success
  echo "$output" | jq -e '.stack == "test-stack"' >/dev/null
}

# ── fail ──

@test "fail: outputs error and exits non-zero" {
  run fail "fatal error"
  assert_failure
  assert_output --partial "fatal error"
}

# ── log_section ──

@test "log_section: outputs section header" {
  run log_section deploy "Building images"
  assert_success
  assert_output --partial "Building images"
}

@test "log_section: JSON mode outputs JSON" {
  FORCE_JSON=1
  run log_section deploy "Deploy stage"
  assert_success
  echo "$output" | jq -e '.msg == "Deploy stage"' >/dev/null
}

@test "log_section: silent in quiet mode" {
  QUIET=1
  run log_section deploy "quiet section"
  assert_success
  assert_output ""
}

# ── log_section_result ──

@test "log_section_result: ok status" {
  run log_section_result ok "completed successfully"
  assert_success
  assert_output --partial "completed successfully"
}

@test "log_section_result: error status" {
  run log_section_result error "something failed"
  assert_success
  assert_output --partial "something failed"
}
