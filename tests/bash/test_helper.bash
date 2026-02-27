#!/usr/bin/env bash
# Common test helper for bats tests
# Loads bats libraries and provides shared setup/teardown

# Load bats libraries (override with BATS_LIB_PREFIX env var)
BATS_LIB_PREFIX="${BATS_LIB_PREFIX:-/usr/local/lib}"
load "${BATS_LIB_PREFIX}/bats-support/load.bash"
load "${BATS_LIB_PREFIX}/bats-assert/load.bash"
load "${BATS_LIB_PREFIX}/bats-file/load.bash"

# Project root (works from both tests/bash/ and tests/integration/)
if [[ "$BATS_TEST_DIRNAME" == */tests/bash* ]]; then
  export PROJECT_ROOT="${BATS_TEST_DIRNAME%/tests/bash*}"
elif [[ "$BATS_TEST_DIRNAME" == */tests/integration* ]]; then
  export PROJECT_ROOT="${BATS_TEST_DIRNAME%/tests/integration*}"
else
  export PROJECT_ROOT="${BATS_TEST_DIRNAME%/tests*}"
fi
export LIB_DIR="$PROJECT_ROOT/bin/lib"
export SCRIPT_PATH="$PROJECT_ROOT/bin/swarm.sh"

# Common test setup
common_setup() {
  export TEST_TMPDIR="$BATS_TEST_TMPDIR"
  export PLATFORM_ROOT="$TEST_TMPDIR"
  export ACTIVE_PROFILE="test-server"
  export LOCKS_DIR="$TEST_TMPDIR/.locks"
  export SECRETS_ROOT="$TEST_TMPDIR/.secrets"
  export PROFILE_DIR="$TEST_TMPDIR/profiles/test-server"
  export PROFILE_STACKS_DIR="$TEST_TMPDIR/profiles/test-server/stacks"

  export FORCE_JSON=""
  export QUIET=""
  export VERBOSE=""
  export COLOR=0
  export NO_COLOR=1
  export DRY_RUN=""
  export LOG_FORMAT="text"
  export EXEC_CONTEXT="script"

  mkdir -p "$LOCKS_DIR" "$SECRETS_ROOT" "$PROFILE_STACKS_DIR"
}

# Create a minimal test profile
create_test_profile() {
  local profile="${1:-test-server}"
  local profile_dir="$TEST_TMPDIR/profiles/$profile"
  mkdir -p "$profile_dir/stacks/test-stack"
  cat > "$profile_dir/config.yaml" <<'YAML'
name: Test Server
description: Test profile for unit tests
swarm:
  services_ready_timeout: 30
  keep_images_count: 10
git:
  default_branch: main
retry:
  enabled: true
  max_attempts: 3
  initial_delay: 2
  max_delay: 30
YAML
}

# Mock docker command
mock_docker() {
  docker() {
    case "$1 $2" in
      "stack ps") echo '{"Name":"svc","CurrentState":"Running"}' ;;
      "image inspect") return 0 ;;
      "stack deploy") return 0 ;;
      "pull "*) return 0 ;;
      *) return 0 ;;
    esac
  }
  export -f docker
}

# Mock git command
mock_git() {
  git() {
    case "$1" in
      "clone") return 0 ;;
      "fetch") return 0 ;;
      "checkout") return 0 ;;
      "-C")
        case "$3" in
          "rev-parse") echo "abc1234" ;;
          "fetch") return 0 ;;
          "checkout") return 0 ;;
          *) return 0 ;;
        esac
        ;;
      *) return 0 ;;
    esac
  }
  export -f git
}

# Source a lib module with minimal dependencies
source_module() {
  local module="$1"
  source "$LIB_DIR/$module"
}
