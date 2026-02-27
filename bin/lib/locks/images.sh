#!/usr/bin/env bash
# Image tag tracking: set_expected_image_tag, get_expected_image_tag

# Set expected image tag for verification
# Usage: set_expected_image_tag <stack> <service> <tag>
set_expected_image_tag() {
  local stack="$1" service="$2" tag="$3"
  local lock_dir="${LOCKS_DIR:-$PLATFORM_ROOT/.locks}"
  local lock_file="$lock_dir/${ACTIVE_PROFILE}_${stack}.lock"
  
  if [ -d "$lock_file" ]; then
    mkdir -p "$lock_file/expected_tags"
    echo "$tag" > "$lock_file/expected_tags/${service}"
  fi
}

# Get expected image tag for service
# Usage: get_expected_image_tag <stack> <service>
get_expected_image_tag() {
  local stack="$1" service="$2"
  local lock_dir="${LOCKS_DIR:-$PLATFORM_ROOT/.locks}"
  local lock_file="$lock_dir/${ACTIVE_PROFILE}_${stack}.lock"
  
  if [ -f "$lock_file/expected_tags/${service}" ]; then
    cat "$lock_file/expected_tags/${service}"
  fi
}

# Set expected image ID for verification
# Usage: set_expected_image_id <stack> <service> <image_id>
# Image ID is the unique sha256 hash that guarantees exact image version
set_expected_image_id() {
  local stack="$1" service="$2" image_id="$3"
  local lock_dir="${LOCKS_DIR:-$PLATFORM_ROOT/.locks}"
  local lock_file="$lock_dir/${ACTIVE_PROFILE}_${stack}.lock"
  
  if [ -d "$lock_file" ]; then
    mkdir -p "$lock_file/expected_image_ids"
    echo "$image_id" > "$lock_file/expected_image_ids/${service}"
  fi
}

# Get expected image ID for service
# Usage: get_expected_image_id <stack> <service>
get_expected_image_id() {
  local stack="$1" service="$2"
  local lock_dir="${LOCKS_DIR:-$PLATFORM_ROOT/.locks}"
  local lock_file="$lock_dir/${ACTIVE_PROFILE}_${stack}.lock"
  
  if [ -f "$lock_file/expected_image_ids/${service}" ]; then
    cat "$lock_file/expected_image_ids/${service}"
  fi
}
