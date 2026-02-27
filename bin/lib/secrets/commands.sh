#!/usr/bin/env bash
# Secret CLI commands: cmd_secret_create, cmd_secret_rm, cmd_secret_generate

# Create or update a secret
# Usage: cmd_secret_create <name> [options]
# Options:
#   --value <val>       Set secret value directly
#   --from-file <path>  Read value from file
#   --stdin             Read value from stdin
#   --no-docker         Only create file, don't update Docker secret
#   --force             Overwrite existing file without confirmation
cmd_secret_create() {
  local name="${1:-}"
  shift || true
  
  [ -n "$name" ] || fail "usage: swarmcli secret create <NAME> [--value <val>|--from-file <path>|--stdin] [--force]"
  
  # Validate name (alphanumeric, dash, underscore)
  if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
    fail "invalid secret name: $name (use alphanumeric, dash, underscore; must start with letter)"
  fi
  
  local value=""
  local from_file=""
  local from_stdin=0
  local no_docker=0
  local force=0
  
  # Parse options
  while [ $# -gt 0 ]; do
    case "$1" in
      --value)
        shift
        value="$1"
        ;;
      --from-file)
        shift
        from_file="$1"
        ;;
      --stdin)
        from_stdin=1
        ;;
      --no-docker)
        no_docker=1
        ;;
      --force)
        force=1
        ;;
      *)
        fail "unknown option: $1"
        ;;
    esac
    shift
  done
  
  local secrets_dir="$SECRETS_ROOT"
  local secret_file="$secrets_dir/$name"
  
  # Ensure secrets directory exists
  if [ ! -d "$secrets_dir" ]; then
    mkdir -p "$secrets_dir"
    chmod 700 "$secrets_dir"
    log info "created secrets directory: $secrets_dir"
  fi
  
  # Check if file already exists
  if [ -f "$secret_file" ] && [ "$force" != "1" ]; then
    if [ -t 0 ]; then
      echo ""
      echo "Secret file already exists: $secret_file"
      printf "Overwrite? [y/N]: "
      read -r answer
      case "$answer" in
        [Yy]*) ;;
        *) 
          log info "cancelled"
          return 0
          ;;
      esac
    else
      fail "secret file already exists: $secret_file (use --force to overwrite)"
    fi
  fi
  
  # Get secret value
  if [ -n "$from_file" ]; then
    # Read from file
    if [ ! -f "$from_file" ]; then
      fail "file not found: $from_file"
    fi
    value=$(cat "$from_file")
  elif [ "$from_stdin" = "1" ]; then
    # Read from stdin
    value=$(cat)
  elif [ -z "$value" ]; then
    # Interactive input
    if [ -t 0 ]; then
      echo ""
      echo "Enter secret value for '$name' (press Enter, then Ctrl+D when done):"
      echo "Or enter single line and press Enter twice:"
      echo ""
      
      # Read password-style (hidden) for single line
      printf "Value: "
      read -rs value
      echo ""
      
      if [ -z "$value" ]; then
        fail "empty secret value"
      fi
    else
      fail "no value provided. Use --value, --from-file, or --stdin"
    fi
  fi
  
  # Validate value
  if [ -z "$value" ]; then
    fail "secret value cannot be empty"
  fi
  
  # Write to file
  if [ "$DRY_RUN" = "1" ]; then
    log info "dry-run: would create file $secret_file"
  else
    echo -n "$value" > "$secret_file"
    chmod 600 "$secret_file"
    log ok "created secret file: $secret_file"
  fi
  
  # Create/update Docker secret
  if [ "$no_docker" != "1" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      if secret_exists "$name"; then
        log info "dry-run: would update Docker secret: $name"
      else
        log info "dry-run: would create Docker secret: $name"
      fi
    else
      if secret_exists "$name"; then
        # Check if secret is in use
        local in_use
        in_use=$(docker service ls --format '{{.Name}}' 2>/dev/null | while read -r svc; do
          docker service inspect "$svc" --format '{{range .Spec.TaskTemplate.ContainerSpec.Secrets}}{{.SecretName}} {{end}}' 2>/dev/null | grep -qw "$name" && echo "$svc"
        done | head -1) || true
        
        if [ -n "$in_use" ]; then
          log warn "secret '$name' is in use by service(s). Cannot update directly."
          log info "to update, you need to:"
          log info "  1. Remove secret from services"
          log info "  2. Run: swarmcli secret create $name --force"
          log info "  3. Re-deploy affected services"
          return 1
        fi
        
        # Remove old secret and create new
        log info "updating Docker secret: $name"
        docker secret rm "$name" >/dev/null 2>&1 || true
      else
        log info "creating Docker secret: $name"
      fi
      
      if docker secret create "$name" "$secret_file" >/dev/null 2>&1; then
        log ok "Docker secret created/updated: $name"
      else
        log error "failed to create Docker secret: $name"
        return 1
      fi
    fi
  fi
  
  return 0
}

# Remove a secret
# Usage: cmd_secret_rm <name> [options]
# Options:
#   --keep-file         Don't remove the file from .secrets/
#   --force             Don't ask for confirmation
cmd_secret_rm() {
  local name="${1:-}"
  shift || true
  
  [ -n "$name" ] || fail "usage: swarmcli secret rm <NAME> [--keep-file] [--force]"
  
  local keep_file=0
  local force=0
  
  while [ $# -gt 0 ]; do
    case "$1" in
      --keep-file) keep_file=1 ;;
      --force) force=1 ;;
      *) fail "unknown option: $1" ;;
    esac
    shift
  done
  
  local secrets_dir="$SECRETS_ROOT"
  local secret_file="$secrets_dir/$name"
  local has_file=0
  local has_docker=0
  
  [ -f "$secret_file" ] && has_file=1
  secret_exists "$name" && has_docker=1
  
  if [ "$has_file" = "0" ] && [ "$has_docker" = "0" ]; then
    fail "secret not found: $name"
  fi
  
  # Confirmation
  if [ "$force" != "1" ] && [ -t 0 ]; then
    echo ""
    echo "This will remove:"
    [ "$has_docker" = "1" ] && echo "  • Docker secret: $name"
    [ "$has_file" = "1" ] && [ "$keep_file" = "0" ] && echo "  • File: $secret_file"
    echo ""
    printf "Continue? [y/N]: "
    read -r answer
    case "$answer" in
      [Yy]*) ;;
      *) 
        log info "cancelled"
        return 0
        ;;
    esac
  fi
  
  # Check if secret is in use
  if [ "$has_docker" = "1" ]; then
    local in_use
    in_use=$(docker service ls --format '{{.Name}}' 2>/dev/null | while read -r svc; do
      docker service inspect "$svc" --format '{{range .Spec.TaskTemplate.ContainerSpec.Secrets}}{{.SecretName}} {{end}}' 2>/dev/null | grep -qw "$name" && echo "$svc"
    done | head -1) || true
    
    if [ -n "$in_use" ]; then
      fail "secret '$name' is in use. Remove it from services first."
    fi
  fi
  
  # Remove Docker secret
  if [ "$has_docker" = "1" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      log info "dry-run: would remove Docker secret: $name"
    else
      if docker secret rm "$name" >/dev/null 2>&1; then
        log ok "removed Docker secret: $name"
      else
        log error "failed to remove Docker secret: $name"
      fi
    fi
  fi
  
  # Remove file
  if [ "$has_file" = "1" ] && [ "$keep_file" = "0" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      log info "dry-run: would remove file: $secret_file"
    else
      rm -f "$secret_file"
      log ok "removed file: $secret_file"
    fi
  fi
  
  return 0
}

# Generate random secret
# Usage: cmd_secret_generate <name> [--length N] [--chars CHARS]
cmd_secret_generate() {
  local name="${1:-}"
  shift || true
  
  [ -n "$name" ] || fail "usage: swarmcli secret generate <NAME> [--length N]"
  
  local length=32
  local chars="A-Za-z0-9"
  
  while [ $# -gt 0 ]; do
    case "$1" in
      --length)
        shift
        length="$1"
        if ! [[ "$length" =~ ^[0-9]+$ ]] || [ "$length" -lt 1 ]; then
          fail "--length must be a positive integer, got: $length"
        fi
        ;;
      --chars)
        shift
        chars="$1"
        ;;
      *)
        # Pass remaining args to create
        break
        ;;
    esac
    shift
  done
  
  # Generate random value
  local value
  value=$(LC_ALL=C tr -dc "$chars" < /dev/urandom | head -c "$length" 2>/dev/null || \
          openssl rand -base64 "$length" 2>/dev/null | tr -dc "$chars" | head -c "$length")
  
  if [ -z "$value" ]; then
    fail "failed to generate random value"
  fi
  
  log info "generated $length character secret"
  
  # Create secret with generated value
  cmd_secret_create "$name" --value "$value" "$@"
}
