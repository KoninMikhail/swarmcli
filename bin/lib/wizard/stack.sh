#!/usr/bin/env bash
# Wizard: Create Stack

# ============================================================================
# WIZARD: Create Stack
# ============================================================================
_wizard_create_stack() {
  _wiz_step "Create New Stack"
  
  # Select profile
  local profiles
  profiles=$(list_profiles)
  
  if [ -z "$profiles" ]; then
    _wiz_error "No profiles found. Create a profile first."
    return 1
  fi
  
  echo "  Select profile:"
  echo ""
  local selected_profile
  if ! _wiz_select "$profiles" selected_profile; then
    return 1
  fi
  
  echo ""
  echo "  Selected: $(_wiz_green "$selected_profile")"
  
  # Stack name
  local stack_name
  _wiz_prompt "Stack name" "" stack_name
  [ -z "$stack_name" ] && { _wiz_error "Stack name is required"; return 1; }
  
  # Check if exists
  local stack_dir="$PLATFORM_ROOT/profiles/$selected_profile/stacks/$stack_name"
  if [ -d "$stack_dir" ]; then
    if ! _wiz_confirm "Stack '$stack_name' already exists. Overwrite?" "n"; then
      echo "  Cancelled."
      return 1
    fi
  fi
  
  # Stack settings
  local services_timeout logs_tail
  echo ""
  echo "  $(_wiz_bold "Stack settings (leave empty for profile defaults):")"
  _wiz_prompt "Services ready timeout (seconds)" "" services_timeout
  _wiz_prompt "Diagnostics log tail lines" "" logs_tail
  
  # Create stack directory structure
  mkdir -p "$stack_dir/hooks"
  # Note: .build/ and .deploy/ are created automatically when needed
  # and are in .gitignore (server-only directories)
  
  # Generate services.yaml
  cat > "$stack_dir/services.yaml" <<'EOF'
# Services configuration
# 
# Service types:
#   type: git      - Internal service with git repository (requires build)
#   type: registry - External service from Docker registry (no build)
#   type: none     - Metadata-only service (for dozzle labels, no image/repo required)
#
# Git service example:
#   api:
#     type: git
#     repo: https://github.com/your-org/api.git
#     default_branch: develop
#     build:
#       context: .
#       dockerfile: Dockerfile
#     image: local/api
#     meta:
#       group: core
#       description: Main API service
#
# Registry service example:
#   redis:
#     type: registry
#     image: redis:7-alpine
#     meta:
#       group: infrastructure
#       description: Redis cache
#
# None service example (metadata-only):
#   helper_service:
#     type: none
#     meta:
#       group: infrastructure
#       name: Helper Service

services:
EOF

  # Generate variables.yaml
  cat > "$stack_dir/variables.yaml" <<'EOF'
# Variables for this stack
# Priority: GitLab CI variables (BUILD_*, RUNTIME_*, COMMON_*) > YAML variables
#
# You can reference:
#   - Global variables from globals.yaml
#   - Service endpoints from endpoints.yaml: ${SERVICE_*}
#   - Environment variables: ${ENV_VAR}

# Common variables (available for both build and runtime)
common:
  TZ: Europe/Moscow

# Build variables (passed to Dockerfile via --build-arg)
build:
  # Example:
  # NODE_ENV: production

# Runtime env (auto-injected via {{ inject_env_vars() }} in templates)
runtime:
  env:
    # Example:
    # LOG_LEVEL: info
    # API_URL: ${SERVICE_CORE_BACKEND_API_URL}
EOF

  # Generate externals.yaml
  cat > "$stack_dir/externals.yaml" <<'EOF'
# External dependencies: Docker secrets and configs
# Docs: docs/03-reference/config/06-externals-yaml.md

# ============================================================================
# SECRETS
# ============================================================================
# Docker secrets required for this stack (checked before deploy)
# Files are stored in global .secrets/ directory
#
# Example:
#   secrets:
#     - pg_password
#     - jwt_secret
#     - api_key

secrets: []

# ============================================================================
# CONFIGS (optional)
# ============================================================================
# Docker configs for this stack
# Files are stored in stack directory (e.g., configs/nginx.conf)
#
# Format:
#   configs:
#     - name: config_name    # Name in Docker Swarm
#       file: path/to/file   # Path relative to stack directory
#
# Example:
#   configs:
#     - name: nginx_config
#       file: configs/nginx.conf
#     - name: app_settings
#       file: configs/settings.json
#
# Strategy (set in settings.yaml):
#   config_strategy: simple     # Create once, check existence (default)
#   config_strategy: versioned  # Create new config each deploy with commit SHA
#
# For versioned configs, use config_name() in j2 templates:
#   {{ config_name('nginx_config') }}  →  nginx_config_server-dev_abc1234

# configs: []
EOF

  # Generate settings.yaml
  local settings_content="# Stack-specific settings
# These override profile-level settings
"
  
  if [ -n "$services_timeout" ]; then
    settings_content+="
# Timeout for waiting services to be ready (seconds)
services_ready_timeout: $services_timeout
"
  else
    settings_content+="
# Timeout for waiting services to be ready (seconds)
# Default: uses profile setting or 30s
# services_ready_timeout: 60
"
  fi

  if [ -n "$logs_tail" ]; then
    settings_content+="
# Number of log lines to show in diagnostics
diagnostics_logs_tail: $logs_tail
"
  else
    settings_content+="
# Number of log lines to show in diagnostics
# Default: 30
# diagnostics_logs_tail: 50
"
  fi

  settings_content+="
# Docker configs strategy (see externals.yaml)
# simple    - create config once, check existence on deploy (default)
# versioned - create new config each deploy with profile + commit SHA suffix
# config_strategy: simple
"

  echo "$settings_content" > "$stack_dir/settings.yaml"

  # Generate docker-stack.yml
  cat > "$stack_dir/docker-stack.yml" <<'EOF'
# Docker Swarm stack configuration
# 
# Image tags are exported as TAG_<SERVICE> variables:
#   image: local/api:${TAG_API}
#
# Resources are injected automatically from resources.yaml
# Variables from variables.yaml runtime.env (inject_env_vars)

services:
  # Example service:
  # app:
  #   image: local/app:${TAG_APP}
  #   environment:
  #     TZ: ${TZ:-Europe/Moscow}
  #     LOG_LEVEL: ${LOG_LEVEL:-info}
  #   deploy:
  #     replicas: 1
  #     update_config:
  #       parallelism: 1
  #       delay: 10s
  #       failure_action: rollback
  #     restart_policy:
  #       condition: on-failure
  #       delay: 5s
  #       max_attempts: 3
  #   networks:
  #     - default
  #
  # Example external service:
  # redis:
  #   image: redis:7-alpine
  #   deploy:
  #     replicas: 1
  #   networks:
  #     - default

networks:
  default:
    driver: overlay
    attachable: true

# Secrets (must be created in Docker Swarm first):
# secrets:
#   pg_password:
#     external: true
EOF

  # Generate hooks
  cat > "$stack_dir/hooks/pre-deploy.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Pre-deploy hook
# Runs before docker stack deploy
#
# Available variables:
#   $1 - stack name
#   $SWARM_PROFILE - active profile name
#   $PROFILE_DIR - profile directory path
#
# Use cases:
#   - Run database migrations
#   - Create required directories
#   - Validate configuration
#   - Send notifications

STACK="${1:-unknown}"

echo "[pre-deploy] running for stack: $STACK, profile: ${SWARM_PROFILE}"

# Add your pre-deploy logic here:
EOF
  chmod +x "$stack_dir/hooks/pre-deploy.sh"

  cat > "$stack_dir/hooks/post-deploy.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Post-deploy hook
# Runs after successful docker stack deploy
#
# Available variables:
#   $1 - stack name
#   $SWARM_PROFILE - active profile name
#   $PROFILE_DIR - profile directory path
#
# Use cases:
#   - Health checks
#   - Cache warming
#   - Send success notifications
#   - Cleanup temporary files

STACK="${1:-unknown}"

echo "[post-deploy] completed for stack: $STACK, profile: ${SWARM_PROFILE}"

# Add your post-deploy logic here:
EOF
  chmod +x "$stack_dir/hooks/post-deploy.sh"

  _wiz_success "Stack created: $stack_dir"
  echo ""
  echo "  Files created:"
  echo "    • services.yaml (service definitions)"
  echo "    • variables.yaml (build/deploy variables)"
  echo "    • externals.yaml (secrets and configs)"
  echo "    • settings.yaml (stack settings)"
  echo "    • docker-stack.yml (Docker Compose for Swarm)"
  echo "    • hooks/pre-deploy.sh"
  echo "    • hooks/post-deploy.sh"
  echo ""
  echo "  Server-only directories (created automatically):"
  echo "    • .build/ — generated docker-stack.yml from templates"
  echo "    • .deploy/ — deployment history"
  echo ""
  echo "  Next: run '$(_wiz_cyan "swarmcli create")' to add services"
  
  return 0
}
