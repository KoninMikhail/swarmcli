#!/usr/bin/env bash
# Templates module - Jinja2 template rendering for swarmcli
#
# Provides commands:
#   template init <stack>   - Initialize templates from existing docker-stack.yml
#   template render <stack> - Render templates to .build/
#   template vars <stack>   - Show all variables and sources

# ===== Template Functions =====

# Check if Jinja2 is available
# Returns: 0 if available, 1 if not
check_jinja2_available() {
  local python_cmd
  python_cmd="$(get_python_cmd)"
  [ -n "$python_cmd" ] || return 1
  $python_cmd -c "import jinja2" 2>/dev/null
}

# Check if stack has templates.yaml
# Usage: stack_has_templates <stack>
stack_has_templates() {
  local stack="$1"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  [ -f "$stack_dir/templates.yaml" ]
}

# Get path to rendered docker-stack.yml
# Usage: get_rendered_compose_path <stack>
# Returns: path to .build/docker-stack.yml or original docker-stack.yml
get_rendered_compose_path() {
  local stack="$1"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  if stack_has_templates "$stack"; then
    echo "$stack_dir/.build/docker-stack.yml"
  else
    echo "$stack_dir/docker-stack.yml"
  fi
}

# Initialize templates for a stack
# Usage: template_init <stack>
template_init() {
  local stack="$1"
  local python_cmd
  
  python_cmd="$(get_python_cmd)"
  if [ -z "$python_cmd" ]; then
    fail "Python not found. Install Python 3.x to use templates."
  fi
  
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  if [ ! -d "$stack_dir" ]; then
    fail "Stack not found: $stack"
  fi
  
  log info "Initializing templates for stack: $stack"
  
  $python_cmd "$LIB_DIR/templates/templates.py" init "$PROFILE_STACKS_DIR" "$stack_dir"
}

# Render templates for a stack
# Usage: template_render <stack> [--verbose]
template_render() {
  local stack="$1"
  local verbose="${2:-}"
  local python_cmd
  
  python_cmd="$(get_python_cmd)"
  if [ -z "$python_cmd" ]; then
    fail "Python not found. Install Python 3.x to use templates."
  fi
  
  if ! check_jinja2_available; then
    fail "Jinja2 not installed. Run: pip install jinja2"
  fi
  
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  if [ ! -d "$stack_dir" ]; then
    fail "Stack not found: $stack"
  fi
  
  if [ ! -f "$stack_dir/templates.yaml" ]; then
    fail "templates.yaml not found. Run: swarmcli template init $stack"
  fi
  
  local verbose_flag=""
  [ "$verbose" = "--verbose" ] || [ "$verbose" = "-v" ] && verbose_flag="--verbose"
  
  $python_cmd "$LIB_DIR/templates/templates.py" render "$PROFILE_STACKS_DIR" "$stack_dir" $verbose_flag
}

# Show variables for a stack
# Usage: template_vars <stack>
template_vars() {
  local stack="$1"
  local python_cmd
  
  python_cmd="$(get_python_cmd)"
  if [ -z "$python_cmd" ]; then
    fail "Python not found. Install Python 3.x to use templates."
  fi
  
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  if [ ! -d "$stack_dir" ]; then
    fail "Stack not found: $stack"
  fi
  
  $python_cmd "$LIB_DIR/templates/templates.py" vars "$PROFILE_STACKS_DIR" "$stack_dir"
}

# Render templates before deploy (if templates.yaml exists)
# Usage: ensure_templates_rendered <stack>
# Returns: 0 on success or if no templates, 1 on error
ensure_templates_rendered() {
  local stack="$1"
  
  if ! stack_has_templates "$stack"; then
    return 0
  fi
  
  log detail "Rendering templates for stack: $stack"
  
  # Don't use verbose in CI (too much output)
  if is_ci; then
    template_render "$stack"
  else
    template_render "$stack" "--verbose"
  fi
}

