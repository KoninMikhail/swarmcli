#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup
  source_module "core/output.sh"
  source_module "core/logging.sh"
  source_module "router.sh"
}

@test "resolve_command_alias: d -> deploy" {
  run resolve_command_alias d
  assert_output "deploy"
}

@test "resolve_command_alias: b -> build" {
  run resolve_command_alias b
  assert_output "build"
}

@test "resolve_command_alias: s -> ps" {
  run resolve_command_alias s
  assert_output "ps"
}

@test "resolve_command_alias: l -> logs" {
  run resolve_command_alias l
  assert_output "logs"
}

@test "resolve_command_alias: list -> ls (backwards compat)" {
  run resolve_command_alias list
  assert_output "ls"
}

@test "resolve_command_alias: status -> ps (backwards compat)" {
  run resolve_command_alias status
  assert_output "ps"
}

@test "resolve_command_alias: unknown command returned as-is" {
  run resolve_command_alias custom_command
  assert_output "custom_command"
}

@test "resolve_command_alias: profiles -> profile" {
  run resolve_command_alias profiles
  assert_output "profile"
}

@test "resolve_command_alias: secrets -> secret" {
  run resolve_command_alias secrets
  assert_output "secret"
}

@test "resolve_command_alias: locks -> lock" {
  run resolve_command_alias locks
  assert_output "lock"
}
