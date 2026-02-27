#!/usr/bin/env bash
# YAML validation: validate_yaml_syntax, validate_docker_stack_yml

# Validate YAML syntax using PyYAML
# Usage: validate_yaml_syntax <file>
# Returns: 0 if valid, 1 if invalid
validate_yaml_syntax() {
  local file="$1"
  
  if [ ! -f "$file" ]; then
    add_error "file not found: $file"
    return 1
  fi
  
  _validate_yaml_with_python "$file"
}

# Validate YAML with Python (PyYAML)
_validate_yaml_with_python() {
  local file="$1"
  local python_cmd
  python_cmd="$(get_python_cmd)"
  [ -n "$python_cmd" ] || { add_error "Python not found"; return 1; }
  
  # Escape single quotes in path to prevent injection
  local escaped_file
  escaped_file=$(printf '%s' "$file" | sed "s/'/'\\\\''/g")
  
  local output
  if ! output=$($python_cmd -c "
import yaml
import sys
try:
    with open('$escaped_file', 'r') as f:
        yaml.safe_load(f)
    sys.exit(0)
except yaml.YAMLError as e:
    print(f'YAML syntax error: {e}', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1); then
    add_error "YAML syntax error in $file: $output"
    return 1
  fi
  
  return 0
}

# Validate docker-stack.yml
# Usage: validate_docker_stack_yml <stack>
# Returns: 0 if valid, 1 if invalid
validate_docker_stack_yml() {
  local stack="$1"
  local file
  file="$(get_current_stack_dir "$stack")/docker-stack.yml"
  
  log info "validating docker-stack.yml for stack: $stack"
  
  if [ ! -f "$file" ]; then
    add_error "docker-stack.yml not found: $file"
    return 1
  fi
  
  # Validate syntax
  if ! validate_yaml_syntax "$file"; then
    return 1
  fi
  
  # Check for services section
  if ! grep -q "^services:" "$file"; then
    add_error "docker-stack.yml: missing 'services' section"
    return 1
  fi
  
  log ok "docker-stack.yml is valid"
  return 0
}

# Get validator info
get_validator_info() {
  echo "Python PyYAML - ✓ installed (required)"
}
