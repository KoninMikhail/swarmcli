#!/usr/bin/env bats

setup() {
  load '../test_helper'
  common_setup
  source_module "core/output.sh"
  source_module "core/logging.sh"
  source_module "core/utils.sh"

  # Stub _run_yaml_parser
  _run_yaml_parser() {
    local python_cmd
    python_cmd="$(get_python_cmd)"
    "$python_cmd" "$LIB_DIR/utils/yaml_parser.py" "$@"
  }
  export -f _run_yaml_parser

  source_module "validation/yaml.sh"
}

@test "validate_yaml_syntax: valid YAML returns 0" {
  local yaml_file="$TEST_TMPDIR/valid.yaml"
  cat > "$yaml_file" <<'YAML'
name: test
version: "1.0"
services:
  api:
    image: test
YAML
  run validate_yaml_syntax "$yaml_file"
  assert_success
}

@test "validate_yaml_syntax: invalid YAML returns 1" {
  local yaml_file="$TEST_TMPDIR/invalid.yaml"
  cat > "$yaml_file" <<'YAML'
name: test
  bad_indent: [unclosed
YAML
  run validate_yaml_syntax "$yaml_file"
  assert_failure
}

@test "validate_yaml_syntax: nonexistent file returns 1" {
  run validate_yaml_syntax "/nonexistent/file.yaml"
  assert_failure
}
