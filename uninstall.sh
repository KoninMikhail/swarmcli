#!/usr/bin/env bash
#===============================================================================
# swarmcli v0.1.0 - Uninstaller
#
# Usage:
#   ./uninstall.sh [options]
#
# Options:
#   --yes, -y           Non-interactive mode (use defaults)
#   --dry-run           Preview what would be removed without changes
#   --list              Only show what's installed, don't remove anything
#   --keep-config       Keep .swarmcli.yaml file
#   --keep-repos        Keep repos/ and stacks/*/.repos/ directories
#   --purge             Remove everything including repos (no prompts)
#   --help, -h          Show this help
#
#===============================================================================
set -euo pipefail

# ===== Configuration =====
VERSION="0.2.1" # x-release-please-version
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.swarmcli.yaml"
REPOS_DIR="$SCRIPT_DIR/repos"
PROFILES_DIR="$SCRIPT_DIR/profiles"
LOCKS_DIR="$SCRIPT_DIR/.locks"
SWARM_SCRIPT="$SCRIPT_DIR/bin/swarm.sh"

# Defaults
AUTO_YES=0
DRY_RUN=0
LIST_ONLY=0
KEEP_CONFIG=0
KEEP_REPOS=0
PURGE_ALL=0

# Found items
declare -a FOUND_SYMLINKS=()
declare -a FOUND_ALIASES=()
declare -a FOUND_PATH_EXPORTS=()

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
    echo -e "${CYAN}║${NC}${BOLD}                   swarmcli v${VERSION} Uninstaller                    ${NC}${CYAN}║${NC}"
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "${CYAN}║${NC}              ${MAGENTA}${BOLD}DRY RUN MODE - no changes will be made${NC}             ${CYAN}║${NC}"
    fi
    if [ "$LIST_ONLY" = "1" ]; then
        echo -e "${CYAN}║${NC}                    ${BLUE}${BOLD}LIST MODE - detection only${NC}                   ${CYAN}║${NC}"
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

print_found() {
    echo -e "      ${GREEN}•${NC} $1"
}

print_not_found() {
    echo -e "      ${DIM}•${NC} $1"
}

# ===== Utility Functions =====

ask_yes_no() {
    local question="$1"
    local default="${2:-y}"
    
    if [ "$AUTO_YES" = "1" ] || [ "$PURGE_ALL" = "1" ]; then
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

get_shell_rc() {
    case "$SHELL" in
        */bash) echo "$HOME/.bashrc" ;;
        */zsh)  echo "$HOME/.zshrc" ;;
        *)      echo "" ;;
    esac
}

# ===== Detection Functions =====

# Find symlinks pointing to swarm.sh
detect_symlinks() {
    FOUND_SYMLINKS=()
    
    local search_dirs=(
        "$HOME/.local/bin"
        "/usr/local/bin"
    )
    
    for dir in "${search_dirs[@]}"; do
        [ -d "$dir" ] || continue
        
        for file in "$dir"/*; do
            [ -L "$file" ] || continue
            
            local target
            target=$(readlink -f "$file" 2>/dev/null || readlink "$file" 2>/dev/null || echo "")
            
            if [ "$target" = "$SWARM_SCRIPT" ] || [ "$target" = "$(realpath "$SWARM_SCRIPT" 2>/dev/null)" ]; then
                FOUND_SYMLINKS+=("$file")
            fi
        done
    done
}

# Find aliases in shell rc files
detect_aliases() {
    FOUND_ALIASES=()
    
    local rc_files=(
        "$HOME/.bashrc"
        "$HOME/.zshrc"
        "$HOME/.bash_profile"
        "$HOME/.profile"
    )
    
    for rc in "${rc_files[@]}"; do
        [ -f "$rc" ] || continue
        
        # Look for alias pointing to swarm.sh
        if grep -q "alias.*=.*swarm\.sh" "$rc" 2>/dev/null; then
            FOUND_ALIASES+=("$rc")
        fi
    done
}

# Find PATH exports added by installer
detect_path_exports() {
    FOUND_PATH_EXPORTS=()
    
    local rc_files=(
        "$HOME/.bashrc"
        "$HOME/.zshrc"
        "$HOME/.bash_profile"
        "$HOME/.profile"
    )
    
    for rc in "${rc_files[@]}"; do
        [ -f "$rc" ] || continue
        
        # Look for swarmcli PATH comment
        if grep -q "# swarmcli" "$rc" 2>/dev/null; then
            FOUND_PATH_EXPORTS+=("$rc")
        fi
    done
}

# Check repos directory for uncommitted changes
# Usage: check_repos_status [repos_dir]
# Returns: "dirty_count:dirty_names" or "0:"
check_repos_status() {
    local repos_dir="${1:-$REPOS_DIR}"
    [ -d "$repos_dir" ] || return 0
    
    local dirty_repos=()
    local total_repos=0
    
    for repo in "$repos_dir"/*/; do
        [ -d "$repo/.git" ] || continue
        total_repos=$((total_repos + 1))
        
        # Check for uncommitted changes
        if ! git -C "$repo" diff --quiet 2>/dev/null || \
           ! git -C "$repo" diff --cached --quiet 2>/dev/null || \
           [ -n "$(git -C "$repo" ls-files --others --exclude-standard 2>/dev/null)" ]; then
            dirty_repos+=("$(basename "$repo")")
        fi
    done
    
    if [ ${#dirty_repos[@]} -gt 0 ]; then
        echo "${#dirty_repos[@]}:${dirty_repos[*]}"
    else
        echo "0:"
    fi
}

# ===== Removal Functions =====

remove_symlink() {
    local symlink="$1"
    
    if [ "$DRY_RUN" = "1" ]; then
        print_dry "rm $symlink"
        return 0
    fi
    
    # Check if needs sudo
    if [ ! -w "$(dirname "$symlink")" ]; then
        if sudo rm -f "$symlink" 2>/dev/null; then
            print_ok "Removed symlink: $symlink"
            return 0
        else
            print_error "Failed to remove: $symlink (sudo required)"
            return 1
        fi
    else
        if rm -f "$symlink" 2>/dev/null; then
            print_ok "Removed symlink: $symlink"
            return 0
        else
            print_error "Failed to remove: $symlink"
            return 1
        fi
    fi
}

remove_alias_from_rc() {
    local rc_file="$1"
    
    if [ "$DRY_RUN" = "1" ]; then
        print_dry "Remove alias from $rc_file"
        return 0
    fi
    
    # Create backup
    cp "$rc_file" "${rc_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Remove lines containing swarmcli alias and the comment before it
    local tmp_file
    tmp_file=$(mktemp)
    
    awk '
        /^# swarmcli alias/ { skip=1; next }
        /^alias.*swarm\.sh/ { skip=0; next }
        !skip { print }
        { skip=0 }
    ' "$rc_file" > "$tmp_file"
    
    mv "$tmp_file" "$rc_file"
    print_ok "Removed alias from $rc_file"
}

remove_path_export_from_rc() {
    local rc_file="$1"
    
    if [ "$DRY_RUN" = "1" ]; then
        print_dry "Remove PATH export from $rc_file"
        return 0
    fi
    
    # Create backup if not already done
    if ! ls "${rc_file}.backup."* >/dev/null 2>&1; then
        cp "$rc_file" "${rc_file}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    local tmp_file
    tmp_file=$(mktemp)
    
    # Remove swarmcli-related lines
    awk '
        /^# swarmcli/ { skip=1; next }
        /\.local\/bin.*PATH/ && skip { skip=0; next }
        !skip { print }
        /^$/ && skip { skip=0 }
        { if (!/^# swarmcli/) skip=0 }
    ' "$rc_file" > "$tmp_file"
    
    mv "$tmp_file" "$rc_file"
    print_ok "Removed PATH export from $rc_file"
}

remove_directory() {
    local dir="$1"
    local desc="$2"
    
    if [ "$DRY_RUN" = "1" ]; then
        print_dry "rm -rf $dir"
        return 0
    fi
    
    if rm -rf "$dir" 2>/dev/null; then
        print_ok "Removed $desc: $dir"
        return 0
    else
        print_error "Failed to remove: $dir"
        return 1
    fi
}

remove_config() {
    if [ "$DRY_RUN" = "1" ]; then
        print_dry "Backup and remove $CONFIG_FILE"
        return 0
    fi
    
    # Create backup
    local backup
    backup="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$backup"
    print_info "Backup saved: $backup"
    
    if rm -f "$CONFIG_FILE" 2>/dev/null; then
        print_ok "Removed .swarmcli.yaml"
        return 0
    else
        print_error "Failed to remove .swarmcli.yaml"
        return 1
    fi
}

# ===== Main Flow =====

show_usage() {
    sed -n '2,/^#====/{ /^#/s/^# \?//p }' "${BASH_SOURCE[0]}"
}

show_summary() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "${CYAN}║${NC}  ${MAGENTA}▸${NC} ${BOLD}DRY RUN complete - no changes were made${NC}                       ${CYAN}║${NC}"
    elif [ "$LIST_ONLY" = "1" ]; then
        echo -e "${CYAN}║${NC}  ${BLUE}ℹ${NC} ${BOLD}Detection complete${NC}                                            ${CYAN}║${NC}"
    else
        echo -e "${CYAN}║${NC}  ${GREEN}✓${NC} ${BOLD}Uninstall complete${NC}                                            ${CYAN}║${NC}"
    fi
    
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    
    local shell_rc
    shell_rc=$(get_shell_rc)
    if [ -n "$shell_rc" ] && [ "$LIST_ONLY" != "1" ] && [ "$DRY_RUN" != "1" ]; then
        echo ""
        print_info "Run 'source $shell_rc' to apply shell changes"
    fi
    echo ""
}

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
            --list)
                LIST_ONLY=1
                ;;
            --keep-config)
                KEEP_CONFIG=1
                ;;
            --keep-repos)
                KEEP_REPOS=1
                ;;
            --purge)
                PURGE_ALL=1
                AUTO_YES=1
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
    
    print_header
    
    local total_steps=4
    [ "$LIST_ONLY" = "1" ] && total_steps=1
    
    # ===== Step 1: Detect Installation =====
    print_step 1 $total_steps "Detecting installation"
    
    # Detect symlinks
    detect_symlinks
    if [ ${#FOUND_SYMLINKS[@]} -gt 0 ]; then
        for sym in "${FOUND_SYMLINKS[@]}"; do
            print_found "Symlink: $sym → $SWARM_SCRIPT"
        done
    else
        print_not_found "No symlinks found"
    fi
    
    # Detect aliases
    detect_aliases
    if [ ${#FOUND_ALIASES[@]} -gt 0 ]; then
        for rc in "${FOUND_ALIASES[@]}"; do
            print_found "Alias in: $rc"
        done
    else
        print_not_found "No aliases found"
    fi
    
    # Detect PATH exports
    detect_path_exports
    if [ ${#FOUND_PATH_EXPORTS[@]} -gt 0 ]; then
        for rc in "${FOUND_PATH_EXPORTS[@]}"; do
            print_found "PATH export in: $rc"
        done
    else
        print_not_found "No PATH exports found"
    fi
    
    # Check .swarmcli.yaml
    if [ -f "$CONFIG_FILE" ]; then
        print_found ".swarmcli.yaml"
    else
        print_not_found ".swarmcli.yaml not found"
    fi
    
    # Check directories
    if [ -d "$LOCKS_DIR" ]; then
        local lock_count
        lock_count=$(find "$LOCKS_DIR" -type f 2>/dev/null | wc -l)
        print_found ".locks/ ($lock_count files)"
    else
        print_not_found ".locks/ not found"
    fi
    
    if [ -d "$REPOS_DIR" ]; then
        local repos_status
        repos_status=$(check_repos_status)
        local dirty_count="${repos_status%%:*}"
        local dirty_names="${repos_status#*:}"
        
        local repo_count
        repo_count=$(find "$REPOS_DIR" -maxdepth 1 -type d 2>/dev/null | wc -l)
        repo_count=$((repo_count - 1))
        
        if [ "$dirty_count" -gt 0 ]; then
            print_warn "repos/ ($repo_count repositories, $dirty_count with uncommitted changes)"
            echo -e "        ${DIM}Dirty: $dirty_names${NC}"
        else
            print_found "repos/ ($repo_count repositories)"
        fi
    else
        print_not_found "repos/ not found"
    fi
    
    # Check stacks/*/.build and stacks/*/.repos (per-stack)
    if [ -d "$PROFILES_DIR" ]; then
        local build_dirs build_count repos_dirs repos_count
        build_dirs=$(find "$PROFILES_DIR" -type d -path "*/.build" 2>/dev/null || true)
        repos_dirs=$(find "$PROFILES_DIR" -type d -path "*/.repos" 2>/dev/null || true)
        build_count=$(echo "$build_dirs" | grep -c . 2>/dev/null || echo 0)
        repos_count=$(echo "$repos_dirs" | grep -c . 2>/dev/null || echo 0)
        if [ "${build_count:-0}" -gt 0 ]; then
            print_found "stacks/*/.build/ ($build_count stacks)"
        else
            print_not_found "stacks/*/.build/"
        fi
        if [ "${repos_count:-0}" -gt 0 ]; then
            print_found "stacks/*/.repos/ ($repos_count stacks)"
        else
            print_not_found "stacks/*/.repos/"
        fi
    fi
    
    # If list only, stop here
    if [ "$LIST_ONLY" = "1" ]; then
        show_summary
        exit 0
    fi
    
    # Check if anything to remove
    local has_stack_dirs=0
    if [ -d "$PROFILES_DIR" ]; then
        [ -n "$(find "$PROFILES_DIR" -type d -name ".build" 2>/dev/null | head -n1)" ] && has_stack_dirs=1
        [ -n "$(find "$PROFILES_DIR" -type d -name ".repos" 2>/dev/null | head -n1)" ] && has_stack_dirs=1
    fi
    if [ ${#FOUND_SYMLINKS[@]} -eq 0 ] && \
       [ ${#FOUND_ALIASES[@]} -eq 0 ] && \
       [ ${#FOUND_PATH_EXPORTS[@]} -eq 0 ] && \
       [ ! -f "$CONFIG_FILE" ] && \
       [ ! -d "$LOCKS_DIR" ] && \
       [ ! -d "$REPOS_DIR" ] && \
       [ "$has_stack_dirs" = "0" ]; then
        echo ""
        print_info "Nothing to uninstall"
        exit 0
    fi
    
    # ===== Step 2: Remove CLI Access =====
    print_step 2 $total_steps "Removing CLI access"
    
    # Remove symlinks
    if [ ${#FOUND_SYMLINKS[@]} -gt 0 ]; then
        for sym in "${FOUND_SYMLINKS[@]}"; do
            if ask_yes_no "Remove symlink $sym?" "y"; then
                remove_symlink "$sym"
            else
                print_skip "Kept: $sym"
            fi
        done
    else
        print_skip "No symlinks to remove"
    fi
    
    # Remove aliases
    if [ ${#FOUND_ALIASES[@]} -gt 0 ]; then
        for rc in "${FOUND_ALIASES[@]}"; do
            if ask_yes_no "Remove alias from $rc?" "y"; then
                remove_alias_from_rc "$rc"
            else
                print_skip "Kept alias in: $rc"
            fi
        done
    else
        print_skip "No aliases to remove"
    fi
    
    # Remove PATH exports
    if [ ${#FOUND_PATH_EXPORTS[@]} -gt 0 ]; then
        for rc in "${FOUND_PATH_EXPORTS[@]}"; do
            # Skip if already processed for alias
            local rc_pattern=" ${rc} "
            if [[ " ${FOUND_ALIASES[*]} " =~ $rc_pattern ]]; then
                continue
            fi
            if ask_yes_no "Remove PATH export from $rc?" "y"; then
                remove_path_export_from_rc "$rc"
            else
                print_skip "Kept PATH in: $rc"
            fi
        done
    fi
    
    # ===== Step 3: Remove Directories =====
    print_step 3 $total_steps "Removing directories"
    
    # Remove .locks
    if [ -d "$LOCKS_DIR" ]; then
        if ask_yes_no "Remove .locks/?" "y"; then
            remove_directory "$LOCKS_DIR" ".locks"
        else
            print_skip "Kept: .locks/"
        fi
    else
        print_skip ".locks/ does not exist"
    fi
    
    # Remove repos
    if [ -d "$REPOS_DIR" ] && [ "$KEEP_REPOS" != "1" ]; then
        local repos_status
        repos_status=$(check_repos_status)
        local dirty_count="${repos_status%%:*}"
        
        if [ "$dirty_count" -gt 0 ] && [ "$PURGE_ALL" != "1" ]; then
            print_warn "repos/ has $dirty_count repositories with uncommitted changes"
            if ask_yes_no "Remove repos/ anyway? (changes will be lost)" "n"; then
                remove_directory "$REPOS_DIR" "repos"
            else
                print_skip "Kept: repos/"
            fi
        else
            if ask_yes_no "Remove repos/?" "y"; then
                remove_directory "$REPOS_DIR" "repos"
            else
                print_skip "Kept: repos/"
            fi
        fi
    elif [ "$KEEP_REPOS" = "1" ]; then
        print_skip "Kept repos/ (--keep-repos)"
    else
        print_skip "repos/ does not exist"
    fi
    
    # Remove stacks/*/.build (generated files)
    if [ -d "$PROFILES_DIR" ]; then
        while IFS= read -r build_dir; do
            [ -z "$build_dir" ] || [ ! -d "$build_dir" ] && continue
            local stack_name
            stack_name=$(echo "$build_dir" | sed 's|.*/stacks/\([^/]*\)/\.build$|\1|')
            if [ "$DRY_RUN" = "1" ]; then
                print_dry "rm -rf $build_dir"
            elif rm -rf "$build_dir" 2>/dev/null; then
                print_ok "Removed .build: stacks/$stack_name"
            else
                print_error "Failed to remove: $build_dir"
            fi
        done < <(find "$PROFILES_DIR" -type d -path "*/.build" 2>/dev/null || true)
    fi
    
    # Remove stacks/*/.repos (service repositories)
    if [ -d "$PROFILES_DIR" ] && [ "$KEEP_REPOS" != "1" ]; then
        while IFS= read -r repos_dir; do
            [ -z "$repos_dir" ] || [ ! -d "$repos_dir" ] && continue
            local stack_name
            stack_name=$(echo "$repos_dir" | sed 's|.*/stacks/\([^/]*\)/\.repos$|\1|')
            local repos_status
            repos_status=$(check_repos_status "$repos_dir")
            local dirty_count="${repos_status%%:*}"
            
            if [ "$dirty_count" -gt 0 ] && [ "$PURGE_ALL" != "1" ]; then
                print_warn "stacks/$stack_name/.repos/ has $dirty_count repositories with uncommitted changes"
                if ask_yes_no "Remove stacks/$stack_name/.repos/ anyway? (changes will be lost)" "n"; then
                    remove_directory "$repos_dir" "stacks/$stack_name/.repos"
                else
                    print_skip "Kept: stacks/$stack_name/.repos/"
                fi
            else
                if ask_yes_no "Remove stacks/$stack_name/.repos/?" "y"; then
                    remove_directory "$repos_dir" "stacks/$stack_name/.repos"
                else
                    print_skip "Kept: stacks/$stack_name/.repos/"
                fi
            fi
        done < <(find "$PROFILES_DIR" -type d -path "*/.repos" 2>/dev/null || true)
    elif [ "$KEEP_REPOS" = "1" ]; then
        print_skip "Kept stacks/*/.repos/ (--keep-repos)"
    fi
    
    # ===== Step 4: Remove Configuration =====
    print_step 4 $total_steps "Removing configuration"
    
    if [ -f "$CONFIG_FILE" ] && [ "$KEEP_CONFIG" != "1" ]; then
        local default_remove="n"
        [ "$PURGE_ALL" = "1" ] && default_remove="y"
        
        if ask_yes_no "Remove .swarmcli.yaml? (backup will be created)" "$default_remove"; then
            remove_config
        else
            print_skip "Kept: .swarmcli.yaml"
        fi
    elif [ "$KEEP_CONFIG" = "1" ]; then
        print_skip "Kept .swarmcli.yaml (--keep-config)"
    else
        print_skip "no configuration files found"
    fi
    
    # ===== Done =====
    show_summary
}

main "$@"

