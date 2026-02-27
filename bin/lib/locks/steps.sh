#!/usr/bin/env bash
# Deployment step tracking: set_deploy_step, get_deploy_step

# Set current deployment step (for progress tracking)
# Usage: set_deploy_step <stack> <step_number> <step_total> <step_name>
set_deploy_step() {
  local stack="$1" step_num="$2" step_total="$3" step_name="$4"
  local lock_dir="${LOCKS_DIR:-$PLATFORM_ROOT/.locks}"
  local lock_file="$lock_dir/${ACTIVE_PROFILE}_${stack}.lock"
  
  if [ -d "$lock_file" ]; then
    echo "$step_num" > "$lock_file/step_num"
    echo "$step_total" > "$lock_file/step_total"
    echo "$step_name" > "$lock_file/step_name"
    date +%s > "$lock_file/step_started"
  fi
}

# Get current deployment step info
# Usage: get_deploy_step <stack>
# Output: step_num|step_total|step_name|step_started
get_deploy_step() {
  local stack="$1"
  local lock_dir="${LOCKS_DIR:-$PLATFORM_ROOT/.locks}"
  local lock_file="$lock_dir/${ACTIVE_PROFILE}_${stack}.lock"
  
  if [ -d "$lock_file" ] && [ -f "$lock_file/step_num" ]; then
    local step_num step_total step_name step_started
    step_num=$(cat "$lock_file/step_num" 2>/dev/null || echo "0")
    step_total=$(cat "$lock_file/step_total" 2>/dev/null || echo "0")
    step_name=$(cat "$lock_file/step_name" 2>/dev/null || echo "unknown")
    step_started=$(cat "$lock_file/step_started" 2>/dev/null || echo "0")
    echo "${step_num}|${step_total}|${step_name}|${step_started}"
  fi
}
