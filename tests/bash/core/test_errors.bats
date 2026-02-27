#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup
  source_module "core/output.sh"
  source_module "core/logging.sh"
  source_module "core/errors.sh"
}

@test "add_error: adds to ERROR_STACK" {
  clear_errors
  add_error "first error"
  [ "${#ERROR_STACK[@]}" -eq 1 ]
  add_error "second error"
  [ "${#ERROR_STACK[@]}" -eq 2 ]
}

@test "add_error: updates ERRORS_ACCUMULATED as valid JSON" {
  clear_errors
  add_error "test error"
  echo "$ERRORS_ACCUMULATED" | jq . >/dev/null 2>&1
  local count
  count=$(echo "$ERRORS_ACCUMULATED" | jq 'length')
  [ "$count" -eq 1 ]
}

@test "clear_errors: empties the stack" {
  add_error "error1"
  add_error "error2"
  clear_errors
  [ "${#ERROR_STACK[@]}" -eq 0 ]
  [ "$ERRORS_ACCUMULATED" = "[]" ]
}

@test "print_errors: outputs all errors" {
  clear_errors
  add_error "error one"
  add_error "error two"
  run print_errors
  assert_success
  assert_output --partial "error one"
  assert_output --partial "error two"
}

@test "print_errors: empty when no errors" {
  clear_errors
  run print_errors
  assert_success
  assert_output ""
}

@test "print_errors: silent in JSON mode" {
  clear_errors
  add_error "json error"
  FORCE_JSON=1
  run print_errors
  assert_success
  assert_output ""
}

@test "print_errors: silent in quiet mode" {
  clear_errors
  add_error "quiet error"
  QUIET=1
  run print_errors
  assert_success
  assert_output ""
}
