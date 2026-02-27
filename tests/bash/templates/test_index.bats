#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup
  source_module "core/output.sh"
  source_module "core/logging.sh"

  get_current_stack_dir() { echo "$PROFILE_STACKS_DIR/$1"; }
  export -f get_current_stack_dir

  source_module "templates/index.sh"
}

@test "stack_has_templates: with templates.yaml returns 0" {
  local stack_dir="$PROFILE_STACKS_DIR/test-stack"
  mkdir -p "$stack_dir"
  touch "$stack_dir/templates.yaml"
  run stack_has_templates "test-stack"
  assert_success
}

@test "stack_has_templates: without templates.yaml returns 1" {
  local stack_dir="$PROFILE_STACKS_DIR/test-stack"
  mkdir -p "$stack_dir"
  run stack_has_templates "test-stack"
  assert_failure
}

@test "get_rendered_compose_path: returns .build path when templates exist" {
  local stack_dir="$PROFILE_STACKS_DIR/test-stack"
  mkdir -p "$stack_dir"
  touch "$stack_dir/templates.yaml"
  run get_rendered_compose_path "test-stack"
  assert_success
  assert_output --partial ".build/docker-stack.yml"
}

@test "get_rendered_compose_path: returns docker-stack.yml without templates" {
  local stack_dir="$PROFILE_STACKS_DIR/test-stack2"
  mkdir -p "$stack_dir"
  run get_rendered_compose_path "test-stack2"
  assert_success
  assert_output --partial "docker-stack.yml"
  refute_output --partial ".build"
}
