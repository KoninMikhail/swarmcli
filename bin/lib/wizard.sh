#!/usr/bin/env bash
# Interactive wizard for creating profiles, stacks, and services
# Loads modules from wizard/ directory

# Load wizard modules
. "$LIB_DIR/wizard/ui.sh"
. "$LIB_DIR/wizard/profile.sh"
. "$LIB_DIR/wizard/stack.sh"
. "$LIB_DIR/wizard/service.sh"

# ============================================================================
# MAIN WIZARD ENTRY POINT
# ============================================================================
cmd_create() {
  _wiz_header
  
  echo "  What do you want to create?"
  echo ""
  
  local options="Profile (server configuration)
Stack (group of services)
Service (add to existing stack)"
  
  local choice
  if ! _wiz_select "$options" choice; then
    return 1
  fi
  
  case "$choice" in
    Profile*) _wizard_create_profile ;;
    Stack*) _wizard_create_stack ;;
    Service*) _wizard_create_service ;;
    *) _wiz_error "Unknown selection"; return 1 ;;
  esac
}
