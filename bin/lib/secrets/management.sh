#!/usr/bin/env bash
# Secrets management: secrets_sync, secret_exists, list_secrets

# Scan SECRETS_ROOT directory and iterate over secret files
# Usage: secrets_manifest_iter
# Output: name<TAB>file pairs
secrets_manifest_iter() {
  local secrets_dir="$SECRETS_ROOT"
  [ -d "$secrets_dir" ] || return 0
  
  find "$secrets_dir" -maxdepth 1 -type f 2>/dev/null | while IFS= read -r filepath; do
    local filename
    filename=$(basename "$filepath")
    
    # Skip hidden files
    case "$filename" in
      .*) continue ;;
      README.md) continue ;;
    esac
    
    local secret_name="$filename"
    printf '%s\t%s\n' "$secret_name" "$filepath"
  done
}

# Check if secret exists in Swarm
# Usage: secret_exists <name>
# Returns: 0 if exists, 1 otherwise
secret_exists() {
  docker secret ls --format '{{.Name}}' 2>/dev/null | grep -Fxq "$1"
}

# Find services that use a specific Docker secret
# Usage: _find_services_using_secret <secret_name>
# Output: service names, one per line
_find_services_using_secret() {
  local secret_name="$1"
  docker service ls -q 2>/dev/null | while IFS= read -r svc_id; do
    [ -n "$svc_id" ] || continue
    local svc_secrets
    svc_secrets=$(docker service inspect "$svc_id" \
      --format '{{range .Spec.TaskTemplate.ContainerSpec.Secrets}}{{.SecretName}} {{end}}' 2>/dev/null || true)
    if [[ " $svc_secrets" == *" ${secret_name} "* ]]; then
      docker service inspect "$svc_id" --format '{{.Spec.Name}}' 2>/dev/null
    fi
  done
}

# Atomic secret rotation via versioned name + docker service update
# Flow:
#   1. Create {name}_v{ts} with new content
#   2. Update each service: --secret-rm {name} --secret-add source={name}_v{ts},target={name}
#   3. Remove old {name} (now unused by any service)
#   4. Re-create {name} with new content (for future docker stack deploy)
#   5. Services keep running on {name}_v{ts} until next deploy reconciles to {name}
#
# Usage: _rotate_secret <name> <file_path>
# Returns: 0 on success, 1 on error
_rotate_secret() {
  local name="$1" path="$2"
  local ts
  ts=$(date +%s)
  local new_name="${name}_v${ts}"

  # Step 1: create versioned secret
  if ! retry_with_backoff docker secret create "$new_name" "$path" >/dev/null 2>&1; then
    add_error "failed to create versioned secret $new_name"
    return 1
  fi

  # Step 2: find services using old secret and rotate
  local services
  services=$(_find_services_using_secret "$name")
  local rotated=0

  if [ -n "$services" ]; then
    while IFS= read -r svc; do
      [ -n "$svc" ] || continue
      log detail "rotating secret in service $svc: $name → $new_name"
      if docker service update --quiet \
        --secret-rm "$name" \
        --secret-add "source=${new_name},target=${name}" \
        "$svc" >/dev/null 2>&1; then
        rotated=$((rotated + 1))
      else
        add_error "failed to rotate secret in service $svc"
        log error "failed to update service $svc with new secret version"
        docker secret rm "$new_name" >/dev/null 2>&1 || true
        return 1
      fi
    done <<< "$services"
  fi

  # Step 3: remove old secret (now unused)
  docker secret rm "$name" >/dev/null 2>&1 || true

  # Step 4: re-create with original name for future docker stack deploy
  if ! retry_with_backoff docker secret create "$name" "$path" >/dev/null 2>&1; then
    log warn "re-created versioned $new_name but failed to re-create $name"
    log warn "next 'docker stack deploy' may need manual secret creation"
  fi

  log detail "secret $name rotated ($rotated service(s) updated)"
  return 0
}

# Clean up orphaned versioned secrets ({name}_v{ts}) that are no longer used
# Usage: _cleanup_versioned_secrets <name>
_cleanup_versioned_secrets() {
  local name="$1"
  docker secret ls --format '{{.Name}}' 2>/dev/null | while IFS= read -r sname; do
    [[ "$sname" =~ ^${name}_v[0-9]+$ ]] || continue
    local users
    users=$(_find_services_using_secret "$sname")
    if [ -z "$users" ]; then
      log detail "removing orphaned versioned secret: $sname"
      docker secret rm "$sname" >/dev/null 2>&1 || true
    fi
  done
}

# Sync secrets to Docker Swarm
# Usage: secrets_sync
# Returns: 0 on success, 1 on error
secrets_sync() {
  ensure_cmd docker
  
  local ok=1
  while IFS=$'\t' read -r name file; do
    [ -n "$name" ] || continue
    
    local path="$file"
    if [ ! -f "$path" ]; then
      add_error "secret file missing: $file"
      log error "secret file missing: $file"
      ok=0
      continue
    fi
    
    if secret_exists "$name"; then
      log info "updating secret: $name"
      if ! _rotate_secret "$name" "$path"; then
        ok=0
        continue
      fi
      _cleanup_versioned_secrets "$name"
    else
      log info "creating secret: $name"
      if ! retry_with_backoff docker secret create "$name" "$path" >/dev/null 2>&1; then
        add_error "failed to create secret $name after retries"
        log error "failed to create secret $name after retries"
        ok=0
      fi
    fi
  done < <(secrets_manifest_iter)
  
  [ $ok -eq 1 ] || return 1
  return 0
}

# Check if secret file exists and is not empty
# Usage: secret_file_exists_and_not_empty <name>
# Returns: 0 if file exists and not empty, 1 otherwise
secret_file_exists_and_not_empty() {
  local name="$1"
  local path="$SECRETS_ROOT/$name"
  
  # Check if file exists
  if [ ! -f "$path" ]; then
    return 1
  fi
  
  # Check if file is not empty
  if [ ! -s "$path" ]; then
    return 1
  fi
  
  return 0
}

# Create secret from file
# Usage: create_secret_from_file <name>
# Returns: 0 on success, 1 on error
create_secret_from_file() {
  local name="$1"
  local path="$SECRETS_ROOT/$name"
  
  if retry_with_backoff docker secret create "$name" "$path" >/dev/null 2>&1; then
    return 0
  else
    log error "failed to create secret: $name"
    return 1
  fi
}

# List all secrets with metadata
# Usage: list_secrets [--json]
list_secrets() {
  ensure_cmd docker
  
  if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
    docker secret ls --format json 2>/dev/null || echo '[]'
  else
    docker secret ls --format "table {{.ID}}\t{{.Name}}\t{{.CreatedAt}}\t{{.UpdatedAt}}"
  fi
}
