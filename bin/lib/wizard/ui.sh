#!/usr/bin/env bash
# Wizard UI utilities

# Colors for wizard UI
_wiz_bold() { echo -e "\033[1m$1\033[0m"; }
_wiz_cyan() { echo -e "\033[36m$1\033[0m"; }
_wiz_green() { echo -e "\033[32m$1\033[0m"; }
_wiz_yellow() { echo -e "\033[33m$1\033[0m"; }
_wiz_red() { echo -e "\033[31m$1\033[0m"; }

# Print wizard header
_wiz_header() {
  echo ""
  echo "$(_wiz_cyan "╔════════════════════════════════════════════════════════╗")"
  echo "$(_wiz_cyan "║")  $(_wiz_bold "swarmcli create wizard")                              $(_wiz_cyan "║")"
  echo "$(_wiz_cyan "╚════════════════════════════════════════════════════════╝")"
  echo ""
}

# Print step header
_wiz_step() {
  echo ""
  echo "$(_wiz_yellow "▶") $(_wiz_bold "$1")"
  echo ""
}

# Print success message
_wiz_success() {
  echo ""
  echo "$(_wiz_green "✓") $1"
}

# Print error message
_wiz_error() {
  echo ""
  echo "$(_wiz_red "✗") $1"
}

# Prompt for input with default value
# Usage: _wiz_prompt "Label" "default_value" result_var
_wiz_prompt() {
  local label="$1"
  local default="$2"
  local __resultvar="$3"
  local input
  
  if [ -n "$default" ]; then
    printf "  %s [$(_wiz_cyan "%s")]: " "$label" "$default"
  else
    printf "  %s: " "$label"
  fi
  
  read -r input
  
  if [ -z "$input" ] && [ -n "$default" ]; then
    input="$default"
  fi
  
  printf -v "$__resultvar" '%s' "$input"
}

# Prompt for yes/no
# Usage: _wiz_confirm "Question" "y" -> returns 0 for yes, 1 for no
_wiz_confirm() {
  local question="$1"
  local default="${2:-n}"
  local input
  
  local hint="y/N"
  [ "$default" = "y" ] && hint="Y/n"
  
  printf "  %s [%s]: " "$question" "$hint"
  read -r input
  
  [ -z "$input" ] && input="$default"
  
  case "$input" in
    [Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

# Select from numbered list
# Usage: _wiz_select "items\nline\nby\nline" result_var
_wiz_select() {
  local items="$1"
  local __resultvar="$2"
  local i=1
  local choice
  local selected
  
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    printf "  $(_wiz_cyan "%2d") │ %s\n" "$i" "$item"
    i=$((i+1))
  done <<< "$items"
  
  echo ""
  printf "  Enter number: "
  read -r choice
  
  # Validate input
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    _wiz_error "Invalid selection"
    return 1
  fi
  
  # Get selected item
  i=1
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    if [ "$i" -eq "$choice" ]; then
      selected="$item"
      break
    fi
    i=$((i+1))
  done <<< "$items"
  
  if [ -z "$selected" ]; then
    _wiz_error "Invalid selection"
    return 1
  fi
  
  printf -v "$__resultvar" '%s' "$selected"
  return 0
}
