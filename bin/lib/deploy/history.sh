#!/usr/bin/env bash
# Deployment history management

# Get deploy history directory for stack
# Usage: get_deploy_history_dir <stack>
get_deploy_history_dir() {
  local stack="$1"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  echo "$stack_dir/.deploy"
}

# Save deploy state before deployment
# Usage: save_deploy_checkpoint <stack>
save_deploy_checkpoint() {
  local stack="$1"
  local checkpoint_dir
  checkpoint_dir="$(get_deploy_history_dir "$stack")"
  local checkpoint_file="$checkpoint_dir/checkpoint.json"
  
  if ! mkdir -p "$checkpoint_dir" 2>/dev/null; then
    log warn "failed to create checkpoint directory: $checkpoint_dir"
    return 1
  fi
  
  if docker stack ps "$stack" --format json >/dev/null 2>&1; then
    docker stack ps "$stack" --format json 2>/dev/null > "$checkpoint_file" || true
    log detail "checkpoint saved: $checkpoint_file"
  fi
}

# Save deployment history
# Usage: save_deploy_history <stack> <status>
save_deploy_history() {
  local stack="$1" status="$2"
  local history_dir
  history_dir="$(get_deploy_history_dir "$stack")"
  local history_file="$history_dir/history.jsonl"
  
  if ! mkdir -p "$history_dir" 2>/dev/null; then
    log warn "failed to create history directory: $history_dir"
    return 1
  fi
  
  local services_array="[]"

  while IFS= read -r svc; do
    [ -n "$svc" ] || continue

    local branch sha image tag service_type
    image=$(get_service_field "$stack" "$svc" image 2>/dev/null || echo "unknown")

    if is_service_internal "$stack" "$svc" 2>/dev/null; then
      service_type="internal"
      branch=$(get_service_current_branch "$stack" "$svc" 2>/dev/null || echo "unknown")
      sha=$(resolve_commit_sha "$stack" "$svc" 2>/dev/null || echo "unknown")
      [ -n "$sha" ] || sha="unknown"
      tag="${ACTIVE_PROFILE}-${sha}"
    else
      service_type="external"
      branch=""
      sha=""
      tag=""
    fi

    services_array=$(echo "$services_array" | jq \
      --arg svc "$svc" \
      --arg type "$service_type" \
      --arg branch "$branch" \
      --arg commit "$sha" \
      --arg image "$image" \
      --arg tag "$tag" \
      '. += [{"service": $svc, "type": $type, "branch": $branch, "commit": $commit, "image": $image, "tag": $tag}]')
  done < <(get_services_list "$stack")

  local history_entry
  history_entry=$(jq -n \
    --arg timestamp "$(now_iso)" \
    --arg profile "$ACTIVE_PROFILE" \
    --arg status "$status" \
    --argjson services "$services_array" \
    '{timestamp: $timestamp, profile: $profile, status: $status, services: $services}')
  local tmp_append
  tmp_append=$(mktemp)
  if [ -f "$history_file" ]; then
    cp "$history_file" "$tmp_append"
  fi
  echo "$history_entry" >> "$tmp_append"
  mv "$tmp_append" "$history_file"

  # Prune old history entries (keep last N, same as keep_images_count)
  local retention="${KEEP_IMAGES_COUNT:-10}"
  if [ -n "$retention" ] && [ "$retention" -gt 0 ] 2>/dev/null; then
    local temp_file
    temp_file=$(mktemp)
    tail -n "$retention" "$history_file" > "$temp_file" 2>/dev/null && mv "$temp_file" "$history_file"
  fi

  log detail "deploy history saved"
  return 0
}

# Get latest successful deployment
# Usage: get_last_successful_deploy <stack>
get_last_successful_deploy() {
  local stack="$1"
  local history_dir
  history_dir="$(get_deploy_history_dir "$stack")"
  local history_file="$history_dir/history.jsonl"
  
  if [ ! -f "$history_file" ]; then
    echo "{}"
    return 1
  fi
  
  tac "$history_file" | grep '"status":"success"' | head -n1
}
