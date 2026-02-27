#!/usr/bin/env bash
# Stack validation: validate_stack_all, validate_services_yaml

# Validate all configurations for a stack
# Usage: validate_stack_all <stack>
# Returns: 0 if all valid, 1 if any invalid
validate_stack_all() {
  local stack="$1"
  local errors=0
  
  log info "validating all configurations for stack: $stack"
  
  # Validate services.yaml
  local services_file
  services_file="$(get_current_stack_dir "$stack")/services.yaml"
  if [ -f "$services_file" ]; then
    log info "validating services.yaml"
    if ! validate_yaml_syntax "$services_file"; then
      errors=$((errors + 1))
    elif ! validate_services_yaml "$stack"; then
      errors=$((errors + 1))
    else
      log ok "services.yaml is valid"
    fi
  fi
  
  # Validate docker-stack.yml
  if ! validate_docker_stack_yml "$stack"; then
    errors=$((errors + 1))
  fi
  
  # Validate variables.yaml
  local variables_file
  variables_file="$(get_current_stack_dir "$stack")/variables.yaml"
  if [ -f "$variables_file" ]; then
    log info "validating variables.yaml"
    if ! validate_yaml_syntax "$variables_file"; then
      errors=$((errors + 1))
    else
      log ok "variables.yaml is valid"
    fi
  fi
  
  # Validate SERVICE_* references if registry exists
  if registry_exists; then
    log info "validating SERVICE_* references"
    load_services_registry >/dev/null 2>&1
    if ! validate_service_references "$stack"; then
      errors=$((errors + 1))
    else
      log ok "SERVICE_* references are valid"
    fi
  fi
  
  if [ $errors -gt 0 ]; then
    log error "validation failed with $errors error(s)"
    return 1
  fi
  
  log ok "all configurations are valid"
  return 0
}
