#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup
  source_module "core/output.sh"
  source_module "core/logging.sh"

  # Stub validate_service_args to avoid dependency issues
  validate_service_args() { :; }
  export -f validate_service_args

  source_module "config/args.sh"
}

@test "parse_global_args: --profile sets PROFILE_ARG" {
  parse_global_args --profile my-server
  [ "$PROFILE_ARG" = "my-server" ]
}

@test "parse_global_args: --json sets FORCE_JSON" {
  parse_global_args --json
  [ "$FORCE_JSON" = "1" ]
}

@test "parse_global_args: --quiet sets QUIET" {
  parse_global_args --quiet
  [ "$QUIET" = "1" ]
}

@test "parse_global_args: --verbose sets VERBOSE" {
  parse_global_args --verbose
  [ "$VERBOSE" = "1" ]
}

@test "parse_global_args: --dry-run sets DRY_RUN" {
  parse_global_args --dry-run
  [ "$DRY_RUN" = "1" ]
}

@test "parse_global_args: --no-color disables color" {
  parse_global_args --no-color
  [ "$COLOR" = "0" ]
}

@test "parse_global_args: --service adds to SELECTED_SERVICES" {
  parse_global_args --service api
  [ "${SELECTED_SERVICES[0]}" = "api" ]
}

@test "parse_global_args: --branch binds to --service" {
  parse_global_args --service api --branch develop
  [ "${SERVICE_BRANCHES[api]}" = "develop" ]
}

@test "parse_global_args: --branch without --service fails" {
  run parse_global_args --branch develop
  assert_failure
  assert_output --partial "error"
}

@test "parse_global_args: --commit with --branch succeeds" {
  parse_global_args --service api --branch develop --commit abc1234
  [ "${SERVICE_COMMITS[api]}" = "abc1234" ]
}

@test "parse_global_args: positional args go to REMAINING_ARGS" {
  parse_global_args deploy mystack --json
  [ "${REMAINING_ARGS[0]}" = "deploy" ]
  [ "${REMAINING_ARGS[1]}" = "mystack" ]
  [ "$FORCE_JSON" = "1" ]
}

@test "parse_global_args: all flags combined" {
  parse_global_args --profile srv --json --quiet --verbose --dry-run --no-color
  [ "$PROFILE_ARG" = "srv" ]
  [ "$FORCE_JSON" = "1" ]
  [ "$QUIET" = "1" ]
  [ "$VERBOSE" = "1" ]
  [ "$DRY_RUN" = "1" ]
}

@test "parse_global_args: --force sets FORCE_REBUILD" {
  parse_global_args --force
  [ "$FORCE_REBUILD" = "1" ]
}

@test "parse_global_args: --pull sets WITH_PULL" {
  parse_global_args --pull
  [ "$WITH_PULL" = "1" ]
}

@test "parse_global_args: --prune sets DO_PRUNE" {
  parse_global_args --prune
  [ "$DO_PRUNE" = "1" ]
}

@test "parse_global_args: --since sets SINCE_REF" {
  parse_global_args --since HEAD~3
  [ "$SINCE_REF" = "HEAD~3" ]
}

@test "validate_service_args: --commit without --branch fails" {
  # Restore real validate_service_args
  unset -f validate_service_args
  source_module "config/args.sh"

  SELECTED_SERVICES=("api")
  SERVICE_COMMITS=([api]="abc123")
  SERVICE_BRANCHES=()
  run validate_service_args
  assert_failure
}
