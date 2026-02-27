#!/usr/bin/env bash
# Compose file generation

# Generate compose file (copy from source)
# For stacks with j2 templates, resources/env/labels are already injected by templates.py
# For legacy stacks, they will be migrated to j2 templates
# Usage: generate_compose_with_resources <stack> <output_file>
# Returns: 0 on success, 1 on error
generate_compose_with_resources() {
  local stack="$1"
  local output_file="$2"
  
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  # Use .build/docker-stack.yml if templates are used, otherwise original
  local compose_file
  compose_file="$(get_rendered_compose_path "$stack")"
  
  if [ ! -f "$compose_file" ]; then
    log error "docker-stack.yml not found: $compose_file"
    return 1
  fi
  
  # Copy compose file (resources/env/labels already injected by templates.py for j2 stacks)
  if ! cp "$compose_file" "$output_file"; then
    log error "failed to copy compose file: $compose_file → $output_file"
    return 1
  fi
  return 0
}

# Cleanup generated compose file
# Usage: cleanup_generated_compose <file>
cleanup_generated_compose() {
  local file="$1"
  rm -f "$file" 2>/dev/null || true
  return 0
}
