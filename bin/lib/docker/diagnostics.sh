#!/usr/bin/env bash
# Docker service diagnostics

# Get detailed service task info
# Usage: get_service_task_details <service_name>
get_service_task_details() {
  local service_name="$1"
  docker service ps "$service_name" --no-trunc --format "table {{.ID}}\t{{.Name}}\t{{.CurrentState}}\t{{.Error}}\t{{.DesiredState}}" 2>/dev/null | head -10
}

# Get failed tasks for a service
# Usage: get_failed_tasks <service_name>
get_failed_tasks() {
  local service_name="$1"
  docker service ps "$service_name" --no-trunc --format "{{.ID}}\t{{.CurrentState}}\t{{.Error}}" 2>/dev/null | \
    grep -E "(Failed|Rejected|Shutdown)" | head -5
}

# Get service configuration
# Usage: get_service_config <service_name>
get_service_config() {
  local service_name="$1"
  
  local image replicas constraints
  image=$(docker service inspect "$service_name" --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' 2>/dev/null || echo "unknown")
  replicas=$(docker service inspect "$service_name" --format '{{.Spec.Mode.Replicated.Replicas}}' 2>/dev/null || echo "unknown")
  constraints=$(docker service inspect "$service_name" --format '{{json .Spec.TaskTemplate.Placement.Constraints}}' 2>/dev/null || echo "[]")
  
  echo "Image: $image"
  echo "Replicas: $replicas"
  echo "Constraints: $constraints"
}

# Diagnose service failure
# Usage: diagnose_service_failure <service_name> <logs_tail>
diagnose_service_failure() {
  local service_name="$1"
  local logs_tail="${2:-30}"
  
  echo ""
  echo "┌──────────────────────────────────────────────────────────────────────────────┐"
  echo "│ SERVICE FAILURE: $service_name"
  echo "├──────────────────────────────────────────────────────────────────────────────┤"
  
  # Replicas status
  local replicas
  replicas=$(get_service_replicas_status "$service_name")
  echo "│ Replicas: $replicas"
  
  # Error message
  local error
  error=$(get_service_errors "$service_name")
  if [ -n "$error" ]; then
    echo "│ Error: $error"
  fi
  echo "└──────────────────────────────────────────────────────────────────────────────┘"
  
  # Task details
  echo ""
  echo "► Recent Tasks:"
  get_service_task_details "$service_name" | while IFS= read -r line; do
    echo "  $line"
  done
  
  # Failed tasks details
  local failed_tasks
  failed_tasks=$(get_failed_tasks "$service_name")
  if [ -n "$failed_tasks" ]; then
    echo ""
    echo "► Failure Details:"
    echo "$failed_tasks" | while IFS= read -r task_info; do
      [ -n "$task_info" ] || continue
      echo "  $task_info"
    done
  fi
  
  # Configuration
  echo ""
  echo "► Configuration:"
  get_service_config "$service_name" | while IFS= read -r line; do
    echo "  $line"
  done
  
  # Logs
  echo ""
  echo "► Last $logs_tail lines of logs:"
  local logs
  logs=$(docker service logs "$service_name" --tail "$logs_tail" 2>&1 || echo "  (no logs available)")
  echo "$logs" | head -n "$logs_tail" | while IFS= read -r line; do
    echo "  $line"
  done
}
