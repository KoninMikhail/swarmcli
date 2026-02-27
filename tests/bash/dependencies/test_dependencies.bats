#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup
  source_module "core/output.sh"
  source_module "core/logging.sh"
  source_module "core/utils.sh"
  source_module "dependencies.sh"
}

@test "detect_os: returns linux on this system" {
  run detect_os
  assert_success
  assert_output "linux"
}

@test "get_package_manager: returns a valid manager" {
  run get_package_manager
  assert_success
  [[ "$output" =~ ^(apt|dnf|yum|apk|pacman|unknown)$ ]]
}

@test "check_bash: version >= 4.0" {
  run check_bash
  assert_success
}

@test "check_git: installed" {
  run check_git
  assert_success
}

@test "check_jq: installed" {
  run check_jq
  assert_success
}
