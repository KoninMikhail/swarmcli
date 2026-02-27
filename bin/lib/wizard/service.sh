#!/usr/bin/env bash
# Wizard: Create Service

# ============================================================================
# WIZARD: Create Service
# ============================================================================
_wizard_create_service() {
  _wiz_step "Add Service to Stack"
  
  # Select profile
  local profiles
  profiles=$(list_profiles)
  
  if [ -z "$profiles" ]; then
    _wiz_error "No profiles found. Create a profile first."
    return 1
  fi
  
  echo "  Select profile:"
  echo ""
  local selected_profile
  if ! _wiz_select "$profiles" selected_profile; then
    return 1
  fi
  
  echo ""
  echo "  Selected profile: $(_wiz_green "$selected_profile")"
  echo ""
  
  # Select stack
  local stacks
  stacks=$(list_profile_stacks "$selected_profile")
  
  if [ -z "$stacks" ]; then
    _wiz_error "No stacks found in profile '$selected_profile'. Create a stack first."
    return 1
  fi
  
  echo "  Select stack:"
  echo ""
  local selected_stack
  if ! _wiz_select "$stacks" selected_stack; then
    return 1
  fi
  
  echo ""
  echo "  Selected stack: $(_wiz_green "$selected_stack")"
  echo ""
  
  # Service name
  local service_name
  _wiz_prompt "Service name" "" service_name
  [ -z "$service_name" ] && { _wiz_error "Service name is required"; return 1; }
  
  # Check if service exists
  local stack_dir="$PLATFORM_ROOT/profiles/$selected_profile/stacks/$selected_stack"
  local services_file="$stack_dir/services.yaml"
  
  if [ -f "$services_file" ]; then
    if grep -q "^  $service_name:" "$services_file" 2>/dev/null; then
      _wiz_error "Service '$service_name' already exists in this stack"
      return 1
    fi
  else
    echo "services:" > "$services_file"
  fi
  
  # Service type
  echo ""
  echo "  Select service type:"
  echo ""
  local types="git (internal, requires build)
registry (external Docker image)"
  local selected_type
  if ! _wiz_select "$types" selected_type; then
    return 1
  fi
  
  local svc_type
  case "$selected_type" in
    git*) svc_type="git" ;;
    registry*) svc_type="registry" ;;
  esac
  
  echo ""
  echo "  Selected type: $(_wiz_green "$svc_type")"
  
  local repo="" image="" branch="" context="" dockerfile="" group="" description=""
  
  if [ "$svc_type" = "git" ]; then
    echo ""
    echo "  $(_wiz_bold "Git repository settings:")"
    _wiz_prompt "Repository URL" "" repo
    [ -z "$repo" ] && { _wiz_error "Repository URL is required for git services"; return 1; }
    
    _wiz_prompt "Default branch" "develop" branch
    _wiz_prompt "Image name" "local/$service_name" image
    
    echo ""
    echo "  $(_wiz_bold "Build settings:")"
    _wiz_prompt "Build context" "." context
    _wiz_prompt "Dockerfile path" "Dockerfile" dockerfile
  else
    echo ""
    echo "  $(_wiz_bold "Registry settings:")"
    _wiz_prompt "Image (e.g. redis:7-alpine)" "" image
    [ -z "$image" ] && { _wiz_error "Image is required for registry services"; return 1; }
  fi
  
  echo ""
  echo "  $(_wiz_bold "Metadata (optional):")"
  _wiz_prompt "Group (e.g. core, infrastructure)" "" group
  _wiz_prompt "Description" "" description
  
  # Append service to services.yaml
  {
    echo "  $service_name:"
    echo "    type: $svc_type"
    
    if [ "$svc_type" = "git" ]; then
      echo "    repo: $repo"
      echo "    default_branch: $branch"
      echo "    build:"
      echo "      context: $context"
      echo "      dockerfile: $dockerfile"
    fi
    
    echo "    image: $image"
    
    if [ -n "$group" ] || [ -n "$description" ]; then
      echo "    meta:"
      [ -n "$group" ] && echo "      group: $group"
      [ -n "$description" ] && echo "      description: $description"
    fi
  } >> "$services_file"
  
  _wiz_success "Service '$service_name' added to $selected_stack"
  echo ""
  echo "  Updated: $services_file"
  
  if [ "$svc_type" = "git" ]; then
    echo ""
    echo "  Next steps:"
    echo "    1. Add service to docker-stack.yml:"
    echo "       $(_wiz_cyan "image: $image:\${TAG_$(echo "$service_name" | tr '[:lower:]-' '[:upper:]_')}")"
    echo "    2. Run: $(_wiz_cyan "swarmcli --profile $selected_profile deploy $selected_stack")"
  else
    echo ""
    echo "  Next steps:"
    echo "    1. Add service to docker-stack.yml with image: $(_wiz_cyan "$image")"
    echo "    2. Run: $(_wiz_cyan "swarmcli --profile $selected_profile deploy $selected_stack")"
  fi
  
  return 0
}
