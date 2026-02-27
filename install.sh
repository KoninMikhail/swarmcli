#!/usr/bin/env bash
#===============================================================================
# swarmcli - Interactive Installer
#
# Usage:
#   ./install.sh [options]
#
# Options:
#   --yes, -y           Non-interactive mode (accept defaults)
#   --dry-run           Preview mode - show what would be done without changes
#   --force             Overwrite existing .swarmcli.yaml
#   --no-symlink        Don't create symlink in PATH
#   --help, -h          Show this help
#
#===============================================================================
set -euo pipefail

# ===== Configuration =====
VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.swarmcli.yaml"

# Defaults
AUTO_YES=0
DRY_RUN=0
FORCE_OVERWRITE=0
NO_SYMLINK=0
CLI_NAME="swarmcli"  # Default CLI command name

# ===== Colors & Output =====
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' BOLD='' DIM='' NC=''
fi

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}                    swarmcli v${VERSION} Installer                     ${NC}${CYAN}║${NC}"
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "${CYAN}║${NC}              ${MAGENTA}${BOLD}DRY RUN MODE - no changes will be made${NC}             ${CYAN}║${NC}"
    fi
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    local step="$1"
    local total="$2"
    local title="$3"
    echo ""
    echo -e "${BOLD}[${step}/${total}] ${title}${NC}"
}

print_ok() {
    echo -e "      ${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "      ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "      ${RED}✗${NC} $1"
}

print_info() {
    echo -e "      ${BLUE}ℹ${NC} $1"
}

print_skip() {
    echo -e "      ${DIM}○${NC} $1"
}

print_dry() {
    echo -e "      ${MAGENTA}▸${NC} ${DIM}[dry-run]${NC} $1"
}

# Execute command or show what would be done in dry-run mode
# Usage: run_cmd "description" command [args...]
run_cmd() {
    local desc="$1"
    shift
    
    if [ "$DRY_RUN" = "1" ]; then
        print_dry "$desc"
        print_dry "  → $*"
        return 0
    else
        "$@"
    fi
}

# ===== Utility Functions =====

# Ask yes/no question
# Usage: ask_yes_no "Question?" [default: y/n]
ask_yes_no() {
    local question="$1"
    local default="${2:-y}"
    
    if [ "$AUTO_YES" = "1" ]; then
        [ "$default" = "y" ] && return 0 || return 1
    fi
    
    local prompt
    if [ "$default" = "y" ]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    
    while true; do
        echo -n -e "      ${question} ${prompt}: "
        read -r answer
        answer="${answer:-$default}"
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "      Please answer y or n" ;;
        esac
    done
}

# Ask for input with default value
# Usage: ask_input "Prompt" "default_value" [masked]
ask_input() {
    local prompt="$1"
    local default="$2"
    local masked="${3:-}"
    local display_default="$default"
    
    if [ "$AUTO_YES" = "1" ]; then
        echo "$default"
        return 0
    fi
    
    # Mask default for sensitive values
    if [ -n "$masked" ] && [ -n "$default" ]; then
        display_default="****${default: -4}"
    fi
    
    # NOTE: Output prompt to stderr to avoid capturing it in $()
    if [ -n "$display_default" ]; then
        echo -n -e "      ${prompt} [${display_default}]: " >&2
    else
        echo -n -e "      ${prompt}: " >&2
    fi
    
    if [ -n "$masked" ]; then
        read -rs answer
        echo "" >&2
    else
        read -r answer
    fi
    
    echo "${answer:-$default}"
}

# Detect operating system
detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "macos" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

# Get package manager
get_package_manager() {
    local os
    os=$(detect_os)
    
    case "$os" in
        linux)
            if command -v apt >/dev/null 2>&1; then echo "apt"
            elif command -v yum >/dev/null 2>&1; then echo "yum"
            elif command -v dnf >/dev/null 2>&1; then echo "dnf"
            elif command -v pacman >/dev/null 2>&1; then echo "pacman"
            elif command -v apk >/dev/null 2>&1; then echo "apk"
            else echo "unknown"
            fi
            ;;
        macos)
            if command -v brew >/dev/null 2>&1; then echo "brew"
            else echo "unknown"
            fi
            ;;
        windows)
            if command -v choco >/dev/null 2>&1; then echo "choco"
            elif command -v scoop >/dev/null 2>&1; then echo "scoop"
            else echo "unknown"
            fi
            ;;
        *) echo "unknown" ;;
    esac
}

# ===== Dependency Checks =====

check_bash_version() {
    local required_major=4
    local current_major="${BASH_VERSION%%.*}"
    
    if [ "$current_major" -ge "$required_major" ]; then
        print_ok "Bash ${BASH_VERSION}"
        return 0
    else
        print_error "Bash ${BASH_VERSION} (required 4.0+)"
        return 1
    fi
}

check_git() {
    if ! command -v git >/dev/null 2>&1; then
        print_error "Git is not installed"
        return 1
    fi
    
    local version
    version=$(git --version 2>&1 | head -1)
    print_ok "$version"
    return 0
}

check_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        print_error "jq is not installed"
        return 1
    fi
    
    local version
    version=$(jq --version 2>&1)
    print_ok "$version"
    return 0
}

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker is not installed"
        return 1
    fi
    
    local version
    version=$(docker --version 2>&1 | head -1)
    
    if ! docker info >/dev/null 2>&1; then
        print_warn "$version (daemon not running)"
        return 2
    fi
    
    if docker info 2>/dev/null | grep -q "Swarm: active"; then
        print_ok "$version (Swarm active)"
        return 0
    else
        print_warn "$version (Swarm not initialized)"
        return 3
    fi
}

check_python_required() {
    local python_cmd=""
    
    if command -v python3 >/dev/null 2>&1; then
        python_cmd="python3"
    elif command -v python >/dev/null 2>&1; then
        python_cmd="python"
    else
        print_error "Python is not installed"
        return 1
    fi
    
    # Verify Python 3.6+ (f-strings, typing support)
    if ! $python_cmd -c "import sys; assert sys.version_info >= (3, 6)" 2>/dev/null; then
        local found_ver
        found_ver=$($python_cmd -c "import sys; print('{}.{}'.format(*sys.version_info[:2]))" 2>/dev/null || echo "unknown")
        print_error "Python 3.6+ required, found $found_ver"
        return 1
    fi
    
    local version
    version=$($python_cmd --version 2>&1)
    
    # Check Jinja2
    if ! $python_cmd -c "import jinja2" 2>/dev/null; then
        print_error "$version - Jinja2 module missing"
        return 2
    fi
    
    # Check PyYAML
    if ! $python_cmd -c "import yaml" 2>/dev/null; then
        print_error "$version - PyYAML module missing"
        return 3
    fi
    
    local jinja_version
    jinja_version=$($python_cmd -c "import jinja2; print(jinja2.__version__)" 2>/dev/null || echo "unknown")
    
    local yaml_version
    yaml_version=$($python_cmd -c "import yaml; print(yaml.__version__)" 2>/dev/null || echo "unknown")
    
    print_ok "$version + Jinja2 $jinja_version + PyYAML $yaml_version"
    return 0
}

# Check Docker permissions via user group (no resource creation)
check_permissions() {
    local os
    os=$(detect_os)

    if [ "$DRY_RUN" = "1" ]; then
        print_dry "Check: user in docker group or root"
        return 0
    fi

    case "$os" in
        linux)
            # Root has full access
            if [ "$(id -u)" = "0" ]; then
                print_ok "Running as root"
                return 0
            fi
            # Check if user is in docker group
            if id -nG 2>/dev/null | grep -q '\bdocker\b'; then
                print_ok "User in docker group"
                return 0
            fi
            # Not in docker group - block installation
            print_error "User not in docker group"
            print_info "Add user: sudo usermod -aG docker $USER"
            print_info "Then log out and back in, or run: newgrp docker"
            return 1
            ;;
        macos|windows)
            # Docker Desktop handles permissions
            print_ok "Docker Desktop (permissions handled by Desktop)"
            return 0
            ;;
        *)
            print_skip "Unknown platform - skipping group check"
            return 0
            ;;
    esac
}

# ===== Installation Functions =====

# ===== .swarmcli.yaml Setup =====

create_config() {
    local git_token=""
    local git_user=""
    local secrets_root=""
    
    echo ""
    echo -e "      ${BOLD}Configuring .swarmcli.yaml${NC}"
    echo ""
    
    # Git Token
    echo ""
    echo -e "      ${DIM}Git HTTP Token is used for accessing private repositories.${NC}"
    echo -e "      ${DIM}For GitLab: Settings → Access Tokens → create token with read_repository${NC}"
    echo -e "      ${DIM}For Deploy Token: use gitlab+deploy-token-XXX as username${NC}"
    git_token=$(ask_input "Git HTTP Token" "" "masked")
    
    # Git User (optional)
    echo ""
    echo -e "      ${DIM}Git Username is only needed for Deploy Token or Basic Auth.${NC}"
    echo -e "      ${DIM}For Personal Access Token you can leave it empty.${NC}"
    git_user=$(ask_input "Git Username (optional)" "")
    
    # Secrets Root
    echo ""
    echo -e "      ${DIM}Directory for Docker secrets files.${NC}"
    echo -e "      ${DIM}Structure: <secrets_dir>/<secret-name>${NC}"
    echo -e "      ${DIM}Default: .secrets (relative to platform root)${NC}"
    secrets_root=$(ask_input "Secrets directory" ".secrets")
    
    # Dry-run mode
    if [ "$DRY_RUN" = "1" ]; then
        print_dry "Create .swarmcli.yaml with the following content:"
        echo -e "      ${DIM}───────────────────────────────────────${NC}"
        echo -e "      ${DIM}# swarmcli configuration${NC}"
        [ -n "$git_token" ] && echo -e "      ${DIM}git.auth.http_token: ****${git_token: -4}${NC}"
        [ -n "$git_user" ] && echo -e "      ${DIM}git.auth.http_user: $git_user${NC}"
        echo -e "      ${DIM}paths.secrets: $secrets_root${NC}"
        echo -e "      ${DIM}───────────────────────────────────────${NC}"
        print_dry "chmod 600 .swarmcli.yaml"
        return 0
    fi
    
    # Create backup if exists
    if [ -f "$CONFIG_FILE" ]; then
        local backup="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$CONFIG_FILE" "$backup"
        print_info "Backup created: $backup"
    fi
    
    # Build YAML content
    local python_cmd="python3"
    if ! command -v python3 >/dev/null 2>&1; then
        python_cmd="python"
    fi
    
    if ! "$python_cmd" "$SCRIPT_DIR/bin/lib/config/config_manager.py" init "$CONFIG_FILE" 2>&1; then
        print_error "Failed to initialize .swarmcli.yaml"
        return 1
    fi

    # Set default paths (user can change later via swarmcli config set)
    if ! "$python_cmd" "$SCRIPT_DIR/bin/lib/config/config_manager.py" set "$CONFIG_FILE" "paths.locks" ".locks" 2>&1; then
        print_error "Failed to set paths.locks in .swarmcli.yaml"
    fi

    # Set values via config manager
    if [ -n "$secrets_root" ] && [ "$secrets_root" != ".secrets" ]; then
        "$python_cmd" "$SCRIPT_DIR/bin/lib/config/config_manager.py" set "$CONFIG_FILE" "paths.secrets" "$secrets_root"
    fi
    
    if [ -n "$git_token" ]; then
        "$python_cmd" "$SCRIPT_DIR/bin/lib/config/config_manager.py" set "$CONFIG_FILE" "git.auth.http_token" "$git_token"
    fi
    
    if [ -n "$git_user" ]; then
        "$python_cmd" "$SCRIPT_DIR/bin/lib/config/config_manager.py" set "$CONFIG_FILE" "git.auth.http_user" "$git_user"
    fi

    chmod 600 "$CONFIG_FILE"
    print_ok "Created .swarmcli.yaml"
}

# ===== Directory Setup =====

setup_directories() {
    # Default paths outside swarmcli for isolation
    local secrets_dir="$(dirname "$SCRIPT_DIR")/secrets"
    local locks_dir="$SCRIPT_DIR/.locks"
    
    # Try to read paths from .swarmcli.yaml
    if [ -f "$CONFIG_FILE" ]; then
        local python_cmd="python3"
        if ! command -v python3 >/dev/null 2>&1; then python_cmd="python"; fi
        local custom_secrets custom_locks
        custom_secrets=$("$python_cmd" "$SCRIPT_DIR/bin/lib/config/config_manager.py" get "$CONFIG_FILE" "paths.secrets" 2>/dev/null || echo "")
        custom_locks=$("$python_cmd" "$SCRIPT_DIR/bin/lib/config/config_manager.py" get "$CONFIG_FILE" "paths.locks" 2>/dev/null || echo "")
        if [ -n "$custom_secrets" ]; then
            if [[ "$custom_secrets" != /* ]]; then
                custom_secrets="$SCRIPT_DIR/$custom_secrets"
            fi
            secrets_dir="$custom_secrets"
        fi
        if [ -n "$custom_locks" ]; then
            if [[ "$custom_locks" != /* ]]; then
                custom_locks="$SCRIPT_DIR/$custom_locks"
            fi
            locks_dir="$custom_locks"
        fi
    fi
    
    # Dry-run mode
    if [ "$DRY_RUN" = "1" ]; then
        [ ! -d "$secrets_dir" ] && print_dry "mkdir -p $secrets_dir" || print_ok "Directory exists: $secrets_dir"
        [ ! -d "$locks_dir" ] && print_dry "mkdir -p $locks_dir" || print_ok "Directory exists: $locks_dir"
        return 0
    fi
    
    # Create secrets directory
    if [ ! -d "$secrets_dir" ]; then
        if mkdir -p "$secrets_dir" 2>/dev/null; then
            print_ok "Created directory: $secrets_dir"
        else
            print_error "Failed to create: $secrets_dir"
        fi
    else
        print_ok "Directory exists: $secrets_dir"
    fi
    
    # Create locks directory
    if [ ! -d "$locks_dir" ]; then
        if mkdir -p "$locks_dir" 2>/dev/null; then
            print_ok "Created directory: $locks_dir"
        else
            print_error "Failed to create: $locks_dir"
        fi
    else
        print_ok "Directory exists: $locks_dir"
    fi
}

# ===== CLI Setup Functions =====

# Get shell rc file
get_shell_rc() {
    case "$SHELL" in
        */bash) echo "$HOME/.bashrc" ;;
        */zsh)  echo "$HOME/.zshrc" ;;
        */fish) echo "$HOME/.config/fish/config.fish" ;;
        *)      echo "" ;;
    esac
}

# Setup local symlink (~/.local/bin)
setup_local_symlink() {
    local swarm_script="$SCRIPT_DIR/bin/swarm.sh"
    local target_dir="$HOME/.local/bin"
    local target_path="$target_dir/$CLI_NAME"
    
    # Dry-run mode
    if [ "$DRY_RUN" = "1" ]; then
        [ ! -d "$target_dir" ] && print_dry "mkdir -p $target_dir"
        print_dry "ln -s $swarm_script $target_path"
        if ! echo "$PATH" | grep -q "$target_dir"; then
            local shell_rc=$(get_shell_rc)
            [ -n "$shell_rc" ] && print_dry "Add PATH to $shell_rc"
        fi
        return 0
    fi
    
    # Create directory if needed
    if [ ! -d "$target_dir" ]; then
        mkdir -p "$target_dir" 2>/dev/null || {
            print_error "Failed to create $target_dir"
            return 1
        }
    fi
    
    # Remove existing symlink if points elsewhere
    if [ -L "$target_path" ]; then
        local current_target
        current_target=$(readlink "$target_path")
        if [ "$current_target" = "$swarm_script" ]; then
            print_ok "Symlink already exists: $target_path"
        else
            rm -f "$target_path"
            ln -s "$swarm_script" "$target_path"
            print_ok "Updated symlink: $target_path"
        fi
    elif [ -f "$target_path" ]; then
        print_error "$target_path already exists (not a symlink)"
        return 1
    else
        ln -s "$swarm_script" "$target_path" || {
            print_error "Failed to create symlink"
            return 1
        }
        print_ok "Created symlink: $target_path"
    fi
    
    # Check if in PATH
    if ! echo "$PATH" | grep -q "$target_dir"; then
        print_warn "$target_dir is not in PATH"
        
        local shell_rc
        shell_rc=$(get_shell_rc)
        
        if [ -n "$shell_rc" ] && [ -f "$shell_rc" ]; then
            if ask_yes_no "Add $target_dir to PATH ($shell_rc)?" "y"; then
                echo "" >> "$shell_rc"
                echo "# swarmcli - local bin" >> "$shell_rc"
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$shell_rc"
                print_ok "Added to $shell_rc"
                print_info "Run: source $shell_rc"
            fi
        else
            print_info "Add manually: export PATH=\"\$HOME/.local/bin:\$PATH\""
        fi
    fi
    
    return 0
}

# Setup global symlink (/usr/local/bin, requires sudo)
setup_global_symlink() {
    local swarm_script="$SCRIPT_DIR/bin/swarm.sh"
    local target_dir="/usr/local/bin"
    local target_path="$target_dir/$CLI_NAME"
    
    # Dry-run mode
    if [ "$DRY_RUN" = "1" ]; then
        print_dry "sudo ln -s $swarm_script $target_path"
        return 0
    fi
    
    if [ ! -d "$target_dir" ]; then
        print_error "$target_dir does not exist"
        return 1
    fi
    
    # Check if already exists
    if [ -L "$target_path" ]; then
        local current_target
        current_target=$(readlink "$target_path")
        if [ "$current_target" = "$swarm_script" ]; then
            print_ok "Symlink already exists: $target_path"
            return 0
        fi
    fi
    
    print_info "Sudo privileges required..."
    
    # Remove old symlink/file if exists
    if [ -e "$target_path" ]; then
        sudo rm -f "$target_path" 2>/dev/null || {
            print_error "Failed to remove existing $target_path"
            return 1
        }
    fi
    
    if sudo ln -s "$swarm_script" "$target_path" 2>/dev/null; then
        print_ok "Created global symlink: $target_path"
        return 0
    else
        print_error "Failed to create symlink (sudo failed)"
        return 1
    fi
}

# Setup shell alias
setup_shell_alias() {
    local swarm_script="$SCRIPT_DIR/bin/swarm.sh"
    local shell_rc
    shell_rc=$(get_shell_rc)
    
    if [ -z "$shell_rc" ]; then
        print_warn "Could not determine shell rc file"
        print_info "Add manually: alias $CLI_NAME='$swarm_script'"
        return 1
    fi
    
    # Dry-run mode
    if [ "$DRY_RUN" = "1" ]; then
        print_dry "Add to $shell_rc:"
        print_dry "  alias $CLI_NAME='$swarm_script'"
        return 0
    fi
    
    if [ ! -f "$shell_rc" ]; then
        print_warn "$shell_rc does not exist"
        return 1
    fi
    
    # Check if alias already exists
    if grep -q "alias $CLI_NAME=" "$shell_rc" 2>/dev/null; then
        print_ok "Alias '$CLI_NAME' already exists in $shell_rc"
        return 0
    fi
    
    echo "" >> "$shell_rc"
    echo "# swarmcli alias" >> "$shell_rc"
    echo "alias $CLI_NAME='$swarm_script'" >> "$shell_rc"
    
    print_ok "Added alias '$CLI_NAME' to $shell_rc"
    print_info "Run: source $shell_rc"
    return 0
}

# Interactive CLI setup menu
setup_cli_interactive() {
    local swarm_script="$SCRIPT_DIR/bin/swarm.sh"
    
    # Ask for command name
    echo ""
    echo -e "      ${DIM}Choose the command name you'll use to run swarmcli.${NC}"
    echo -e "      ${DIM}Examples: swarmcli, swarm, sc${NC}"
    local new_name
    new_name=$(ask_input "Command name" "$CLI_NAME")
    
    # Validate name (alphanumeric, dash, underscore only)
    if [[ ! "$new_name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        print_warn "Invalid name '$new_name', using default: $CLI_NAME"
    else
        CLI_NAME="$new_name"
    fi
    
    echo ""
    echo -e "      ${BOLD}Choose how to access '$CLI_NAME':${NC}"
    echo ""
    echo -e "        ${GREEN}1${NC}) Local symlink in ~/.local/bin/$CLI_NAME"
    echo -e "           ${DIM}Recommended for single user${NC}"
    echo ""
    echo -e "        ${GREEN}2${NC}) Global symlink in /usr/local/bin/$CLI_NAME ${YELLOW}(sudo)${NC}"
    echo -e "           ${DIM}Available to all system users${NC}"
    echo ""
    echo -e "        ${GREEN}3${NC}) Shell alias in $(get_shell_rc)"
    echo -e "           ${DIM}Simple option without creating symlink${NC}"
    echo ""
    echo -e "        ${GREEN}4${NC}) Skip"
    echo -e "           ${DIM}Use: $swarm_script${NC}"
    echo ""
    
    local choice
    while true; do
        echo -n -e "      Choice [1-4]: "
        read -r choice
        
        case "$choice" in
            1)
                setup_local_symlink
                return $?
                ;;
            2)
                setup_global_symlink
                return $?
                ;;
            3)
                setup_shell_alias
                return $?
                ;;
            4)
                print_skip "CLI setup skipped"
                print_info "Use: $swarm_script"
                return 0
                ;;
            *)
                echo -e "      ${RED}Enter a number from 1 to 4${NC}"
                ;;
        esac
    done
}

# ===== Profile Info =====

# Create minimal profile (used when no profiles exist)
# On success: sets CREATED_PROFILE_NAME, returns 0
create_profile_from_installer() {
    CREATED_PROFILE_NAME=""
    local profile_name=""
    profile_name=$(ask_input "Profile name (e.g. server-dev)" "server-dev")

    # Validate: alphanumeric, dash, underscore
    if [[ ! "$profile_name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        print_error "Invalid profile name: $profile_name"
        return 1
    fi

    local profile_dir="$SCRIPT_DIR/profiles/$profile_name"
    if [ -d "$profile_dir" ]; then
        print_error "Profile '$profile_name' already exists"
        return 1
    fi

    if [ "$DRY_RUN" = "1" ]; then
        print_dry "Create profile: $profile_dir"
        print_dry "  config.yaml, stacks/globals.yaml, resources.yaml, endpoints.yaml"
        CREATED_PROFILE_NAME="$profile_name"
        return 0
    fi

    mkdir -p "$profile_dir/stacks"
    mkdir -p "$profile_dir/scripts"

    cat > "$profile_dir/config.yaml" <<EOF
# Profile: $profile_name
# Created by install.sh

name: $profile_name
description: $profile_name server configuration

swarm:
  services_ready_timeout: 30
  keep_images_count: 3

git:
  default_branch: main

retry:
  enabled: true
  max_attempts: 3
  initial_delay: 2
  max_delay: 30
EOF

    cat > "$profile_dir/stacks/globals.yaml" <<'EOF'
# Global variables for all stacks in this profile
TZ: Europe/Moscow
LOG_LEVEL: info
EOF

    cat > "$profile_dir/stacks/resources.yaml" <<'EOF'
# Resource limits - add stack/service definitions here
EOF

    cat > "$profile_dir/stacks/endpoints.yaml" <<'EOF'
# Service endpoints - add SERVICE_* definitions here
EOF

    print_ok "Created profile: $profile_name"
    CREATED_PROFILE_NAME="$profile_name"
    return 0
}

show_profiles() {
    local profiles_dir="$SCRIPT_DIR/profiles"
    
    if [ ! -d "$profiles_dir" ]; then
        print_warn "Directory profiles/ not found"
        return 1
    fi
    
    echo ""
    echo -e "      ${BOLD}Available profiles:${NC}"
    
    local found=0
    for profile_path in "$profiles_dir"/*/config.yaml; do
        [ -f "$profile_path" ] || continue
        local profile_name
        profile_name=$(dirname "$profile_path")
        profile_name=$(basename "$profile_name")
        
        local description=""
        description=$(grep "^description:" "$profile_path" 2>/dev/null | head -1 | cut -d: -f2- | sed 's/^ *//')
        
        if [ -n "$description" ]; then
            echo -e "        ${GREEN}•${NC} ${BOLD}$profile_name${NC} ${DIM}- $description${NC}"
        else
            echo -e "        ${GREEN}•${NC} ${BOLD}$profile_name${NC}"
        fi
        found=$((found + 1))
    done
    
    if [ "$found" -eq 0 ]; then
        print_info "No profiles yet"
    fi
    
    echo ""
}

# ===== Validation =====

run_validation() {
    local has_errors=0
    
    # Test swarmcli
    if [ -x "$SCRIPT_DIR/bin/swarm.sh" ]; then
        if "$SCRIPT_DIR/bin/swarm.sh" system version >/dev/null 2>&1; then
            print_ok "swarmcli is working"
        else
            print_error "swarmcli failed to start"
            has_errors=1
        fi
    else
        print_error "bin/swarm.sh not found or not executable"
        has_errors=1
    fi
    
    # Test Git token if set
    if [ -f "$CONFIG_FILE" ]; then
        local python_cmd="python3"
        if ! command -v python3 >/dev/null 2>&1; then python_cmd="python"; fi
        local token
        token=$("$python_cmd" "$SCRIPT_DIR/bin/lib/config/config_manager.py" get "$CONFIG_FILE" "git.auth.http_token" 2>/dev/null || echo "")
        
        if [ -n "$token" ] && [ "$token" != "null" ]; then
            print_ok "Git token configured"
        else
            print_warn "Git token not configured (private repositories unavailable)"
        fi
    fi
    
    return $has_errors
}

# ===== Next Steps =====

show_next_steps() {
    echo ""
    
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}  ${MAGENTA}▸${NC} ${BOLD}DRY RUN complete - no changes were made${NC}                       ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  To perform actual installation, run without --dry-run:         ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}    ${GREEN}./install.sh${NC}                                                  ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    else
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}  ${GREEN}✓${NC} ${BOLD}Installation complete!${NC}                                       ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${BOLD}Quick start:${NC}                                                    ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}    ${DIM}# Set default profile (saves to .swarmcli.yaml)${NC}             ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}    swarmcli use server-dev                                       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}    ${DIM}# Now you can use commands without --profile${NC}                ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}    swarmcli ls                    ${DIM}# list stacks${NC}                 ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}    swarmcli ps                    ${DIM}# status of all stacks${NC}        ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}    swarmcli deploy my-stack       ${DIM}# deploy stack${NC}                ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}    swarmcli deploy                ${DIM}# interactive deploy${NC}          ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}    ${DIM}# Shortcuts: d=deploy, b=build, s=ps, l=logs${NC}                ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BOLD}Documentation:${NC} docs/README.md                                    ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    fi
    echo ""
}

show_usage() {
    sed -n '2,/^#====/{ /^#/s/^# \?//p }' "${BASH_SOURCE[0]}"
}

# ===== Main =====

main() {
    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --yes|-y)
                AUTO_YES=1
                ;;
            --dry-run)
                DRY_RUN=1
                ;;
            --force)
                FORCE_OVERWRITE=1
                ;;
            --no-symlink)
                NO_SYMLINK=1
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
        shift
    done
    
    # Warn if running as root — installer does not need sudo
    if [ "$(id -u)" = "0" ] && [ -n "${SUDO_USER:-}" ]; then
        echo ""
        echo -e "${YELLOW}WARNING: Running installer with sudo is not recommended.${NC}"
        echo -e "${DIM}  SwarmCLI installs into the current directory — no root privileges needed.${NC}"
        echo -e "${DIM}  Config file (.swarmcli.yaml) will be owned by root and inaccessible to $SUDO_USER.${NC}"
        echo -e "${DIM}  sudo is only needed for global symlink (/usr/local/bin) — the installer will ask for it.${NC}"
        echo ""
        echo -e "  Run without sudo:  ${BOLD}./install.sh${NC}"
        echo ""
        if ! ask_yes_no "Continue anyway?" "n"; then
            exit 0
        fi
    fi
    
    print_header
    
    local os pm
    os=$(detect_os)
    pm=$(get_package_manager)
    
    local total_steps=8
    local critical_errors=0
    local swarm_status=0
    
    # ===== Step 1: System Check =====
    print_step 1 $total_steps "System check"
    print_info "Platform: $(uname -s) ($os)"
    print_info "Package manager: $pm"
    check_bash_version || critical_errors=$((critical_errors + 1))
    
    # ===== Step 2: Dependencies =====
    print_step 2 $total_steps "Checking dependencies"
    
    echo ""
    echo -e "      ${BOLD}Critical:${NC}"
    check_git || critical_errors=$((critical_errors + 1))
    check_jq || critical_errors=$((critical_errors + 1))
    
    check_docker
    swarm_status=$?
    
    if [ $swarm_status -eq 1 ]; then
        critical_errors=$((critical_errors + 1))
    elif [ $swarm_status -eq 3 ]; then
        print_warn "Docker Swarm not initialized — you can run 'docker swarm init' later"
    fi
    
    check_python_required
    local python_status=$?
    if [ $python_status -eq 1 ] || [ $python_status -eq 2 ] || [ $python_status -eq 3 ]; then
        critical_errors=$((critical_errors + 1))
    fi

    # Check for critical errors
    if [ $critical_errors -gt 0 ]; then
        echo ""
        print_error "Critical dependency issues found ($critical_errors)"
        print_info "Install missing dependencies and run the installer again"
        if [ $python_status -eq 2 ] || [ $python_status -eq 3 ]; then
            print_info "Python packages: pip install jinja2 pyyaml"
        fi
        print_info "jq: apt install jq / brew install jq / choco install jq"
        exit 1
    fi

    # ===== Step 3: Permissions =====
    print_step 3 $total_steps "Checking permissions"
    check_permissions || critical_errors=$((critical_errors + 1))

    if [ $critical_errors -gt 0 ]; then
        echo ""
        print_error "Permission check failed - add user to docker group to continue"
        exit 1
    fi

    # ===== Step 4: Configuration =====
    print_step 4 $total_steps "Configuring .swarmcli.yaml"
    
    if [ -f "$CONFIG_FILE" ] && [ "$FORCE_OVERWRITE" != "1" ]; then
        print_ok ".swarmcli.yaml already exists"
        
        echo ""
        if ask_yes_no "Recreate .swarmcli.yaml?" "n"; then
            create_config
        fi
    else
        create_config
    fi
    
    # ===== Step 5: Directories =====
    print_step 5 $total_steps "Creating directories"
    setup_directories
    
    # ===== Step 6: CLI Setup =====
    print_step 6 $total_steps "CLI setup"
    
    # Make swarm.sh executable
    if [ "$DRY_RUN" = "1" ]; then
        print_dry "chmod +x $SCRIPT_DIR/bin/swarm.sh"
    else
        chmod +x "$SCRIPT_DIR/bin/swarm.sh" 2>/dev/null || true
        print_ok "bin/swarm.sh is executable"
    fi
    
    if [ "$NO_SYMLINK" != "1" ]; then
        if [ "$AUTO_YES" = "1" ]; then
            # Non-interactive: use local symlink by default
            setup_local_symlink
        else
            setup_cli_interactive
        fi
    else
        print_skip "CLI setup skipped (--no-symlink)"
        print_info "Use: $SCRIPT_DIR/bin/swarm.sh"
    fi
    
    # ===== Step 7: Profiles =====
    print_step 7 $total_steps "Server profiles"
    show_profiles
    
    # Ask to create profile (if none) or set default
    # NOTE: Default profile is saved to .swarmcli.yaml via 'swarmcli use' command
    if [ "$DRY_RUN" != "1" ]; then
        local profiles_dir="$SCRIPT_DIR/profiles"
        local available_profiles=()
        
        if [ -d "$profiles_dir" ]; then
            for p in "$profiles_dir"/*; do
                [ -d "$p" ] && [ -f "$p/config.yaml" ] && available_profiles+=("$(basename "$p")")
            done
        fi

        # No profiles: offer to create one and set as default
        if [ ${#available_profiles[@]} -eq 0 ]; then
            echo ""
            if ask_yes_no "Create profile and set as default?" "y"; then
                if create_profile_from_installer; then
                    if [ -n "${CREATED_PROFILE_NAME:-}" ]; then
                        "$SCRIPT_DIR/bin/swarm.sh" use "$CREATED_PROFILE_NAME" >/dev/null 2>&1
                        if [ $? -eq 0 ]; then
                            print_ok "Default profile set to: $CREATED_PROFILE_NAME"
                        fi
                    fi
                fi
            fi
        # Existing profiles: offer to set default
        elif [ ${#available_profiles[@]} -gt 0 ]; then
            echo ""
            if ask_yes_no "Set default profile now? (can be changed later with 'swarmcli use')" "y"; then
                echo ""
                echo -e "      ${BOLD}Select default profile:${NC}"
                local i=1
                for p in "${available_profiles[@]}"; do
                    echo -e "        ${GREEN}$i${NC}) $p"
                    i=$((i + 1))
                done
                echo ""
                
                local choice
                while true; do
                    echo -n -e "      Choice [1-${#available_profiles[@]}]: "
                    read -r choice
                    
                    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#available_profiles[@]}" ]; then
                        local selected_profile="${available_profiles[$((choice - 1))]}"
                        
                        # Set default profile using 'swarmcli use' command
                        "$SCRIPT_DIR/bin/swarm.sh" use "$selected_profile" >/dev/null 2>&1
                        if [ $? -eq 0 ]; then
                            print_ok "Default profile set to: $selected_profile"
                        else
                            print_error "Failed to set default profile"
                        fi
                        break
                    else
                        echo -e "      ${RED}Enter a number from 1 to ${#available_profiles[@]}${NC}"
                    fi
                done
            fi
        fi
    fi
    
    # ===== Step 8: Validation =====
    print_step 8 $total_steps "Validating installation"
    run_validation
    
    # ===== Done =====
    show_next_steps
}

main "$@"
