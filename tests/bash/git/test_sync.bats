#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup
  source_module "core/output.sh"
  source_module "core/logging.sh"
  source_module "core/errors.sh"

  # Stub dependencies
  get_current_stack_dir() { echo "$PROFILE_STACKS_DIR/$1"; }
  export -f get_current_stack_dir

  source_module "git/sync.sh"
}

@test "get_service_repo_dir: correct path" {
  mkdir -p "$PROFILE_STACKS_DIR/test-stack"
  run get_service_repo_dir "test-stack" "api"
  assert_success
  assert_output --partial ".repos/api"
}

@test "sanitize_git_error: removes credentials from URL" {
  run sanitize_git_error "fatal: could not access https://user:token@github.com/repo.git"
  assert_success
  refute_output --partial "user:token"
  assert_output --partial "<REDACTED>"
}

@test "extract_image_tag: with tag" {
  run extract_image_tag "redis:7-alpine"
  assert_success
  local lines
  IFS=$'\n' read -d '' -ra lines <<< "$output" || true
  [ "${lines[0]}" = "redis" ]
  [ "${lines[1]}" = "7-alpine" ]
}

@test "extract_image_tag: without tag defaults to latest" {
  run extract_image_tag "redis"
  assert_success
  local lines
  IFS=$'\n' read -d '' -ra lines <<< "$output" || true
  [ "${lines[0]}" = "redis" ]
  [ "${lines[1]}" = "latest" ]
}

@test "extract_image_tag: complex tag" {
  run extract_image_tag "registry.example.com/myapp:v1.2.3-beta"
  assert_success
  local lines
  IFS=$'\n' read -d '' -ra lines <<< "$output" || true
  [ "${lines[0]}" = "registry.example.com/myapp" ]
  [ "${lines[1]}" = "v1.2.3-beta" ]
}

@test "get_service_commit_sha: no repo returns nogit" {
  mkdir -p "$PROFILE_STACKS_DIR/test-stack"
  run get_service_commit_sha "test-stack" "api"
  assert_success
  assert_output "nogit"
}

@test "get_service_commit_sha: with git repo returns short SHA" {
  local repo_dir="$PROFILE_STACKS_DIR/test-stack/.repos/api"
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"
  echo "test" > "$repo_dir/file.txt"
  git -C "$repo_dir" add . && git -C "$repo_dir" commit -q -m "init"

  run get_service_commit_sha "test-stack" "api"
  assert_success
  [[ "$output" =~ ^[a-f0-9]{7}$ ]]
}

@test "get_service_current_branch: no repo returns unknown" {
  mkdir -p "$PROFILE_STACKS_DIR/test-stack"
  run get_service_current_branch "test-stack" "api"
  assert_success
  assert_output "unknown"
}

@test "_url_with_user_only: https with user+token" {
  GIT_HTTP_USER="myuser"
  GIT_HTTP_TOKEN="mytoken"
  _get_git_credentials_for_stack() {
    _GIT_USER="$GIT_HTTP_USER"
    _GIT_TOKEN="$GIT_HTTP_TOKEN"
  }
  run _url_with_user_only "https://github.com/org/repo.git"
  assert_success
  assert_output "https://myuser@github.com/org/repo.git"
}

@test "_url_with_user_only: only token uses oauth2" {
  GIT_HTTP_USER=""
  GIT_HTTP_TOKEN="mytoken"
  _get_git_credentials_for_stack() {
    _GIT_USER=""
    _GIT_TOKEN="$GIT_HTTP_TOKEN"
  }
  run _url_with_user_only "https://github.com/org/repo.git"
  assert_success
  assert_output "https://oauth2@github.com/org/repo.git"
}

@test "_url_with_user_only: no credentials returns URL unchanged" {
  GIT_HTTP_USER=""
  GIT_HTTP_TOKEN=""
  GIT_HTTP_PASSWORD=""
  _get_git_credentials_for_stack() {
    _GIT_USER=""
    _GIT_TOKEN=""
  }
  run _url_with_user_only "https://github.com/org/repo.git"
  assert_success
  assert_output "https://github.com/org/repo.git"
}
