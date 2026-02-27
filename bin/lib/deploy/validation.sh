#!/usr/bin/env bash
# Deployment validation

# Validate deployment prerequisites
# Usage: validate_deploy_prerequisites <stack>
# Returns: 0 if valid, 1 if issues found
validate_deploy_prerequisites() {
  local stack="$1"
  
  log_section "validate" "Validating configuration..."
  
  local issues=0
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  # Check stack directory
  if [ ! -d "$stack_dir" ]; then
    add_error "stack directory not found: $stack"
    issues=1
  fi
  
  # Render templates if needed before checking docker-stack.yml
  if stack_has_templates "$stack"; then
    local compose_file
    compose_file="$(get_rendered_compose_path "$stack")"
    if [ ! -f "$compose_file" ]; then
      log info "rendering templates before validation"
      if ! ensure_templates_rendered "$stack"; then
        add_error "failed to render templates for validation"
        issues=1
      fi
    fi
  fi
  
  # Check docker-stack.yml (or .build/docker-stack.yml for templates)
  local compose_file
  compose_file="$(get_rendered_compose_path "$stack" 2>/dev/null || echo "$stack_dir/docker-stack.yml")"
  if [ ! -f "$compose_file" ]; then
    add_error "docker-stack.yml not found for $stack"
    issues=1
  fi
  
  # Validate services.yaml
  if ! validate_services_yaml "$stack"; then
    issues=1
  fi
  
  # Validate branches
  if ! validate_service_branches "$stack"; then
    issues=1
  fi
  
  # Check secrets
  if ! check_required_secrets "$stack"; then
    issues=1
  fi
  
  if [ $issues -gt 0 ]; then
    log_section_result "error" "Validation error ($issues issues)"
    return 1
  fi
  
  log_section_result "ok" "Configuration valid"
  return 0
}
