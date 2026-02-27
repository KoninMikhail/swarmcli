#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup
  source_module "core/output.sh"
  source_module "core/logging.sh"
  source_module "core/utils.sh"
  source_module "config/loader.sh"
}

@test "get_config_file: returns path ending with .swarmcli.yaml" {
  run get_config_file
  assert_success
  assert_output --partial ".swarmcli.yaml"
}

@test "load_swarmcli_config: no file returns 0" {
  run load_swarmcli_config
  assert_success
}

@test "load_swarmcli_config: loads from file" {
  local config_file
  config_file="$(get_config_file)"
  mkdir -p "$(dirname "$config_file")"
  cat > "$config_file" <<'YAML'
config_version: 1
operations:
  log_format: json
  timeout: 600
paths:
  secrets: .secrets
  locks: .locks
YAML
  load_swarmcli_config
  [ "$LOG_FORMAT" = "json" ] || [ "$TIMEOUT_SECONDS" = "600" ]
}

@test "get_swarmcli_config: existing key" {
  local config_file
  config_file="$(get_config_file)"
  mkdir -p "$(dirname "$config_file")"
  cat > "$config_file" <<'YAML'
config_version: 1
operations:
  timeout: 777
YAML
  run get_swarmcli_config "operations.timeout" "900"
  assert_success
  assert_output "777"
}

@test "get_swarmcli_config: non-existing key returns default" {
  run get_swarmcli_config "nonexistent.key" "fallback"
  assert_success
  assert_output "fallback"
}

@test "set_swarmcli_config: sets value that can be read back" {
  local config_file
  config_file="$(get_config_file)"
  mkdir -p "$(dirname "$config_file")"
  cat > "$config_file" <<'YAML'
config_version: 1
YAML
  set_swarmcli_config "operations.timeout" "500"
  run get_swarmcli_config "operations.timeout" ""
  assert_success
  assert_output "500"
}
