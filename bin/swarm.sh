#!/usr/bin/env bash
#===============================================================================
# swarmcli v0.1.0 - Docker Swarm CI/CD CLI with Profile-based Architecture
#
# Usage:
#   swarmcli <command> [options]
#   swarmcli --profile <profile> <command> [stack] [flags]
#
# System Commands:
#   system version              Show version information
#   system health               Check system dependencies
#   system update [branch]      Update swarmcli from git
#   system config list          Show current configuration
#   system config get <key>     Get configuration value
#   system config set <key> <v> Set configuration value
#   system config edit          Open config in $EDITOR
#   system config path          Show config file path
#   system config init          Create config with defaults
#   system config reset         Reset config to defaults (backup created)
#
# Global Commands:
#   help                    Show this help
#   create                  Interactive wizard to create profile/stack/service
#   use <profile>           Set default profile (saved to .swarmcli.yaml)
#   use --show              Show current default profile
#   use --clear             Clear saved default profile
#
# Profile Commands:
#   profile ls              List all available profiles
#   profile inspect [name]  Show profile details (current if omitted)
#
# Stack Commands (require --profile or default):
#   ls                      List stacks in profile
#   ps [stack]              Show stack status (all if omitted)
#   logs [stack]            Show service logs
#   inspect <stack>         Show detailed stack info
#   check [stack]           Validate stack configuration
#
# Build & Deploy:
#   sync [stack]            Sync git repositories for services
#   build [stack]           Build Docker images for services
#   deploy [stack]          Deploy stack to Docker Swarm
#   rollback [stack]        Rollback to previous deployment
#
# Configuration:
#   diff                    Show stacks with changed configs (git diff)
#   apply                   Apply config changes to affected stacks
#
# Secrets:
#   secret ls               List all secrets
#   secret check [stack]    Check required secrets for stack
#   secret sync             Sync secrets from configuration
#   secret create <name>    Create secret (file + Docker secret)
#   secret rm <name>        Remove secret
#   secret generate <name>  Generate random secret
#
# Locks:
#   lock ls                 List active deployment locks
#   lock prune              Remove stale locks
#   lock rm <stack>         Force release lock for stack
#
# Registry:
#   registry ls             List services in registry
#   registry check          Validate SERVICE_* references
#
# Templates (Jinja2):
#   template init <stack>   Initialize templates from docker-stack.yml
#   template render <stack> Render templates to .build/
#   template vars <stack>   Show all variables and their sources
#
# Plugins:
#   plugin [name]           List or run plugins
#
# Global Flags:
#   --profile <name>        Server profile to use (or use `swarmcli use`)
#   --json                  Output in JSON format (for automation)
#   --quiet                 Suppress info messages
#   --no-color              Disable colored output
#   --verbose               Enable verbose output
#   --dry-run               Preview actions without executing
#
# Deploy/Build Flags:
#   --service <svc>         Target specific service(s)
#   --branch <name>         Override branch for preceding --service
#   --commit <sha>          Override commit SHA for preceding --service
#   --pull                  Update repos before build
#   --force                 Force rebuild images
#   --with-secrets          Sync secrets before deploy
#   --no-build              Skip build step during deploy
#   --prune                 Prune old images after deploy
#   --no-cache              Disable Docker build cache
#   --config-only           Deploy without rebuilding images (use current tags)
#   --since <ref>           Git ref for diff/apply (default: HEAD~1)
#
# Shortcuts:
#   d                       Alias for deploy
#   b                       Alias for build
#   s                       Alias for ps (status)
#   l                       Alias for logs
#
# Examples:
#   swarmcli system version                    Show CLI version
#   swarmcli system health                     Check dependencies
#   swarmcli use server-dev                    Set default profile
#   swarmcli ls                                List stacks (uses default profile)
#   swarmcli deploy my-stack                   Deploy stack
#   swarmcli deploy                            Deploy changed stacks (interactive)
#   swarmcli ps                                Show status of all stacks
#   swarmcli --profile server-prod deploy my-stack
#   swarmcli profile ls
#   swarmcli diff --since HEAD~1
#
#===============================================================================
set -euo pipefail

# Version info
VERSION="0.2.1" # x-release-please-version
BUILD_DATE="2026-02-26"

# Resolve paths
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
BIN_DIR="$(dirname "$SCRIPT_PATH")"
PLATFORM_ROOT="$(dirname "$BIN_DIR")"
LIB_DIR="$BIN_DIR/lib"

# Export core paths (SCRIPT_PATH needed for show_help in router.sh)
export SCRIPT_PATH
export PLATFORM_ROOT

# Default values
export LOG_FORMAT="${LOG_FORMAT:-text}"
export DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
export TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"
export LOCK_TIMEOUT="${LOCK_TIMEOUT:-3600}"
export KEEP_IMAGES_COUNT="${KEEP_IMAGES_COUNT:-10}"
export SERVICES_READY_TIMEOUT="${SERVICES_READY_TIMEOUT:-30}"

# ============================================================================
# Load library modules
# ============================================================================

# Core utilities (must be loaded first)
. "$LIB_DIR/core/logging.sh"
. "$LIB_DIR/core/output.sh"
. "$LIB_DIR/core/errors.sh"
. "$LIB_DIR/core/time.sh"
. "$LIB_DIR/core/retry.sh"
. "$LIB_DIR/core/utils.sh"

# Signal handling
. "$LIB_DIR/signals/handlers.sh"
. "$LIB_DIR/signals/children.sh"
. "$LIB_DIR/signals/timeout.sh"
. "$LIB_DIR/signals/cancellation.sh"

# Utilities (must be loaded early)
. "$LIB_DIR/utils/index.sh"

# Configuration and parsing
. "$LIB_DIR/config/index.sh"

# Profiles
. "$LIB_DIR/profiles/index.sh"

# Git operations
. "$LIB_DIR/git/index.sh"

# Docker operations
. "$LIB_DIR/docker/build.sh"
. "$LIB_DIR/docker/images.sh"
. "$LIB_DIR/docker/services.sh"
. "$LIB_DIR/docker/validation.sh"
. "$LIB_DIR/docker/diagnostics.sh"

# Deployment locks
. "$LIB_DIR/locks/deploy.sh"
. "$LIB_DIR/locks/steps.sh"
. "$LIB_DIR/locks/images.sh"
. "$LIB_DIR/locks/cancellation.sh"

# Templates
. "$LIB_DIR/templates/index.sh"

# Deployment
. "$LIB_DIR/deploy/history.sh"
. "$LIB_DIR/deploy/rollback.sh"
. "$LIB_DIR/deploy/hooks.sh"
. "$LIB_DIR/deploy/tags.sh"
. "$LIB_DIR/deploy/compose.sh"
. "$LIB_DIR/deploy/readiness.sh"
. "$LIB_DIR/deploy/tree.sh"
. "$LIB_DIR/deploy/validation.sh"

# Secrets
. "$LIB_DIR/secrets/management.sh"
. "$LIB_DIR/secrets/commands.sh"
. "$LIB_DIR/secrets/validation.sh"

# Configs
. "$LIB_DIR/configs/management.sh"
. "$LIB_DIR/configs/validation.sh"

# Plugins
. "$LIB_DIR/plugins/index.sh"

# Validation
. "$LIB_DIR/validation/yaml.sh"
. "$LIB_DIR/validation/stack.sh"
. "$LIB_DIR/validation/tree.sh"

# Registry
. "$LIB_DIR/registry/index.sh"

# Commands (common helpers first)
. "$LIB_DIR/commands/common.sh"
. "$LIB_DIR/commands/system.sh"
. "$LIB_DIR/commands/stack.sh"
. "$LIB_DIR/commands/build.sh"
. "$LIB_DIR/commands/deploy.sh"
. "$LIB_DIR/commands/sync.sh"
. "$LIB_DIR/commands/diff.sh"
. "$LIB_DIR/commands/rollback.sh"
. "$LIB_DIR/commands/images.sh"
. "$LIB_DIR/commands/config.sh"

# Wizard (loads modules and defines cmd_create)
. "$LIB_DIR/wizard.sh"

# Router and dependencies (must be loaded last)
. "$LIB_DIR/dependencies.sh"
. "$LIB_DIR/router.sh"

# ============================================================================
# Main entry point
# ============================================================================

main() {
  # Parse global flags
  parse_global_args "$@"
  
  # Get command from remaining args
  local command="${REMAINING_ARGS[0]:-help}"
  
  # Remove command from remaining args, prepare subcommand args
  local -a cmd_args=()
  if [ ${#REMAINING_ARGS[@]} -gt 1 ]; then
    cmd_args=("${REMAINING_ARGS[@]:1}")
  fi
  
  # Resolve command alias
  command=$(resolve_command_alias "$command")
  
  # help/--help/-h work without jq, Python, or config
  case "$command" in
    help|--help|-h)
      route_command "$command" "${cmd_args[@]}"
      return $?
      ;;
  esac
  
  # All other commands require jq and config
  ensure_cmd jq
  
  # Unset SECRETS_ROOT from environment to ensure it only comes from .swarmcli.yaml
  unset SECRETS_ROOT
  
  # Load configuration from .swarmcli.yaml
  load_swarmcli_config
  
  # If SECRETS_ROOT still not set, use default
  if [ -z "${SECRETS_ROOT:-}" ]; then
    export SECRETS_ROOT="$PLATFORM_ROOT/.secrets"
  fi
  
  # If LOCKS_DIR still not set, use default
  if [ -z "${LOCKS_DIR:-}" ]; then
    export LOCKS_DIR="$PLATFORM_ROOT/.locks"
  fi
  
  # Resolve and load profile
  resolve_and_load_profile
  
  # Route to command handler
  route_command "$command" "${cmd_args[@]}"
}

main "$@"
