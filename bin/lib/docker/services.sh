#!/usr/bin/env bash
# Docker service operations

# Get stack status with details
# Usage: get_stack_status <stack>
# Output: JSON or human-readable status
get_stack_status() {
  local stack="$1"
  
  ensure_cmd docker
  
  if ! docker stack ps "$stack" >/dev/null 2>&1; then
    if [ "$FORCE_JSON" = "1" ]; then
      jq -n --arg stack "$stack" '{status: "not_deployed", stack: $stack}'
    else
      echo "Stack not deployed: $stack"
    fi
    return 1
  fi
  
  if [ "$FORCE_JSON" = "1" ] || [ "$LOG_FORMAT" = "json" ]; then
    docker stack ps "$stack" --format json 2>/dev/null || echo '[]'
  else
    docker stack ps "$stack" --format "table {{.Name}}\t{{.Image}}\t{{.CurrentState}}\t{{.Error}}"
  fi
}

# Get service replicas status
# Usage: get_service_replicas_status <service_name>
# Returns: "running/desired" or "0/0" if service not found
get_service_replicas_status() {
  local service_name="$1"
  docker service ls --filter "name=$service_name" --format '{{.Replicas}}' 2>/dev/null || echo "0/0"
}

# Check if service exists
# Usage: service_exists <service_name>
# Returns: 0 if exists, 1 otherwise
service_exists() {
  local service_name="$1"
  docker service inspect "$service_name" >/dev/null 2>&1
}

# Get service errors
# Usage: get_service_errors <service_name>
# Returns: error message or empty string
get_service_errors() {
  local service_name="$1"
  docker service ps "$service_name" --no-trunc --format "{{.Error}}" 2>/dev/null | grep -v "^$" | head -1
}

# Get image ID of running service task container
# Usage: get_running_service_image_id <service_name>
# Returns: image ID (sha256:...) or empty string if not available
# This provides exact verification that the correct image is running
get_running_service_image_id() {
  local service_name="$1"
  
  # Get first running task ID
  local task_id
  task_id=$(docker service ps "$service_name" --filter "desired-state=running" --format '{{.ID}}' 2>/dev/null | head -1)
  
  if [ -z "$task_id" ]; then
    return 1
  fi
  
  # Get container ID from task
  local container_id
  container_id=$(docker inspect "$task_id" --format '{{.Status.ContainerStatus.ContainerID}}' 2>/dev/null)
  
  if [ -z "$container_id" ]; then
    return 1
  fi
  
  # Get image ID from container
  docker container inspect "$container_id" --format '{{.Image}}' 2>/dev/null
}
