#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup
  source_module "core/output.sh"
}

# ── c() ──

@test "c: with color enabled outputs ANSI escape" {
  COLOR=1
  run c 32 "green text"
  assert_success
  assert_output --partial "green text"
  assert_output --partial $'\033['
}

@test "c: with color disabled outputs plain text" {
  COLOR=0
  run c 32 "plain text"
  assert_success
  assert_output "plain text"
}

# ── icon ──

@test "icon: info returns ℹ" {
  run icon info
  assert_success
  assert_output "ℹ"
}

@test "icon: warn returns ⚠" {
  run icon warn
  assert_success
  assert_output "⚠"
}

@test "icon: error returns ✖" {
  run icon error
  assert_success
  assert_output "✖"
}

@test "icon: ok returns ✓" {
  run icon ok
  assert_success
  assert_output "✓"
}

@test "icon: deploy returns rocket emoji" {
  run icon deploy
  assert_success
  assert_output "🚀"
}

@test "icon: build returns hammer emoji" {
  run icon build
  assert_success
  assert_output "🔨"
}

@test "icon: unknown type returns bullet" {
  run icon unknown_type
  assert_success
  assert_output "•"
}

# ── output_result ──

@test "output_result: success in text mode" {
  ERRORS_ACCUMULATED="[]"
  log() {
    echo "$*"
  }
  export -f log
  run output_result success "deploy" 1500 "3 services"
  assert_success
  assert_output --partial "completed"
}

@test "output_result: error in text mode" {
  ERRORS_ACCUMULATED="[]"
  log() {
    echo "$*" >&2
  }
  export -f log
  run output_result error "deploy" 2000 "timeout"
  assert_output --partial "failed"
}

@test "output_result: JSON mode outputs valid JSON" {
  FORCE_JSON=1
  ERRORS_ACCUMULATED="[]"
  run output_result success "deploy" 1500 "ok"
  assert_success
  echo "$output" | jq . >/dev/null 2>&1
  echo "$output" | jq -e '.status == "success"' >/dev/null
  echo "$output" | jq -e '.command == "deploy"' >/dev/null
  echo "$output" | jq -e '.durationMs == 1500' >/dev/null
}
