#!/usr/bin/env bash
# Tree-style validation output: cmd_validate_tree, cmd_validate

# Tree drawing characters (compact style like Deployment info)
_tree_branch="├─"
_tree_last="└─"
_tree_pipe="│ "
_tree_space="  "

# Print tree item
# Usage: _tree_item <prefix> <is_last> <icon> <text>
_tree_item() {
  local prefix="$1"
  local is_last="$2"
  local icon="$3"
  local text="$4"
  
  if [ "$is_last" = "1" ]; then
    printf "%s%s %s %s\n" "$prefix" "$_tree_last" "$icon" "$text"
  else
    printf "%s%s %s %s\n" "$prefix" "$_tree_branch" "$icon" "$text"
  fi
}

# Print tree section header
# Usage: _tree_section <prefix> <is_last> <icon> <title>
_tree_section() {
  local prefix="$1"
  local is_last="$2"
  local icon="$3"
  local title="$4"
  
  # Format icon with space if present
  local icon_part=""
  [ -n "$icon" ] && icon_part="$icon "
  
  if [ "$is_last" = "1" ]; then
    printf "%s%s %s$(c 1 "%s")\n" "$prefix" "$_tree_last" "$icon_part" "$title"
  else
    printf "%s%s %s$(c 1 "%s")\n" "$prefix" "$_tree_branch" "$icon_part" "$title"
  fi
}

# Validate with tree output (default mode)
# Usage: cmd_validate_tree <stack>
cmd_validate_tree() {
  local stack="$1"
  local stack_dir
  stack_dir="$(get_current_stack_dir "$stack")"
  
  local errors=0
  local start_ms=$(now_ms)
  
  # Header
  printf "\n$(c 90 "─────────────────────────────────────────────────────────────")\n"
  printf "🔍 $(c 1 "Validating stack:") %s $(c 90 "(profile: %s)")\n" "$stack" "$ACTIVE_PROFILE"
  
  # ===== Section 1: Stack Structure =====
  _tree_section "" "0" "" "Stack Structure"
  local struct_prefix="$_tree_pipe"
  
  # Check stack directory
  if [ ! -d "$stack_dir" ]; then
    _tree_item "$struct_prefix" "1" "$(c 31 "✗")" "Stack directory not found"
    errors=$((errors + 1))
    printf "\n"
    printf "❌ $(c 31 "Validation failed"): stack directory does not exist\n\n"
    return 1
  fi
  
  # Determine mode: templates or static docker-stack.yml
  local has_templates=0
  [ -f "$stack_dir/templates.yaml" ] && has_templates=1
  
  # Required files
  # services.yaml - always required
  if [ -f "$stack_dir/services.yaml" ]; then
    _tree_item "$struct_prefix" "0" "$(c 32 "✓")" "services.yaml"
  else
    _tree_item "$struct_prefix" "0" "$(c 31 "✗")" "services.yaml $(c 31 "(required)")"
    errors=$((errors + 1))
  fi
  
  # Template mode files
  if [ "$has_templates" = "1" ]; then
    _tree_item "$struct_prefix" "0" "$(c 32 "✓")" "templates.yaml"
    
    # templates/docker-stack.j2
    if [ -f "$stack_dir/templates/docker-stack.j2" ]; then
      _tree_item "$struct_prefix" "0" "$(c 32 "✓")" "templates/docker-stack.j2"
    else
      _tree_item "$struct_prefix" "0" "$(c 31 "✗")" "templates/docker-stack.j2 $(c 31 "(required)")"
      errors=$((errors + 1))
    fi
    
    # variables.yaml - optional but common
    if [ -f "$stack_dir/variables.yaml" ]; then
      _tree_item "$struct_prefix" "0" "$(c 32 "✓")" "variables.yaml"
    else
      _tree_item "$struct_prefix" "0" "○" "variables.yaml $(c 90 "(optional)")"
    fi
    
    # .build/docker-stack.yml - rendered output
    if [ -f "$stack_dir/.build/docker-stack.yml" ]; then
      _tree_item "$struct_prefix" "0" "$(c 32 "✓")" ".build/docker-stack.yml"
    else
      _tree_item "$struct_prefix" "0" "○" ".build/docker-stack.yml $(c 90 "(will be rendered)")"
    fi
  else
    # Static mode - docker-stack.yml required
    if [ -f "$stack_dir/docker-stack.yml" ]; then
      _tree_item "$struct_prefix" "0" "$(c 32 "✓")" "docker-stack.yml"
    else
      _tree_item "$struct_prefix" "0" "$(c 31 "✗")" "docker-stack.yml $(c 31 "(required)")"
      errors=$((errors + 1))
    fi
  fi
  
  # Optional files (both modes)
  # externals.yaml / required_secrets.yaml
  if [ -f "$stack_dir/externals.yaml" ]; then
    _tree_item "$struct_prefix" "1" "$(c 32 "✓")" "externals.yaml"
  elif [ -f "$stack_dir/required_secrets.yaml" ]; then
    _tree_item "$struct_prefix" "1" "$(c 33 "⚠")" "required_secrets.yaml $(c 33 "(deprecated, rename to externals.yaml)")"
  else
    _tree_item "$struct_prefix" "1" "○" "externals.yaml $(c 90 "(optional)")"
  fi
  
  # ===== Section 2: Services Configuration =====
  _tree_section "" "0" "" "Services"
  local svc_prefix="$_tree_pipe"
  
  if [ -f "$stack_dir/services.yaml" ]; then
    local services
    services=$(get_services_list "$stack" 2>/dev/null || echo "")
    local services_arr=()
    while IFS= read -r svc; do
      [ -n "$svc" ] && services_arr+=("$svc")
    done <<< "$services"
    
    local total=${#services_arr[@]}
    local idx=0
    
    for svc in "${services_arr[@]}"; do
      idx=$((idx + 1))
      local is_last_svc=$( [ $idx -eq $total ] && echo "1" || echo "0" )
      
      # Service name
      if [ "$is_last_svc" = "1" ]; then
        printf "%s%s $(c 36 "%s")\n" "$svc_prefix" "$_tree_last" "$svc"
        local svc_sub_prefix="$svc_prefix$_tree_space"
      else
        printf "%s%s $(c 36 "%s")\n" "$svc_prefix" "$_tree_branch" "$svc"
        local svc_sub_prefix="$svc_prefix$_tree_pipe"
      fi
      
      # Service details
      local svc_type image repo branch
      svc_type=$(get_service_type "$stack" "$svc" 2>/dev/null || echo "")
      image=$(get_service_field "$stack" "$svc" image 2>/dev/null || echo "")
      
      # type: none - metadata-only service, skip image/repo validation
      if [ "$svc_type" = "none" ]; then
        _tree_item "$svc_sub_prefix" "1" "○" "type: $(c 90 "metadata-only")"
      elif [ "$svc_type" = "git" ]; then
        if [ -n "$image" ]; then
          _tree_item "$svc_sub_prefix" "0" "$(c 32 "✓")" "image: $(c 90 "$image")"
        else
          _tree_item "$svc_sub_prefix" "0" "$(c 31 "✗")" "image: $(c 31 "missing")"
          errors=$((errors + 1))
        fi
        
        repo=$(get_service_field "$stack" "$svc" repo 2>/dev/null || echo "")
        branch=$(get_service_branch "$stack" "$svc" 2>/dev/null || echo "")
        
        if [ -n "$repo" ]; then
          _tree_item "$svc_sub_prefix" "0" "$(c 32 "✓")" "repo: $(c 90 "$repo")"
        else
          _tree_item "$svc_sub_prefix" "0" "$(c 31 "✗")" "repo: $(c 31 "missing")"
          errors=$((errors + 1))
        fi
        
        if [ -n "$branch" ]; then
          _tree_item "$svc_sub_prefix" "1" "$(c 32 "✓")" "branch: $(c 90 "$branch")"
        else
          _tree_item "$svc_sub_prefix" "1" "$(c 31 "✗")" "branch: $(c 31 "missing")"
          errors=$((errors + 1))
        fi
      else
        # type: registry or unknown
        if [ -n "$image" ]; then
          _tree_item "$svc_sub_prefix" "0" "$(c 32 "✓")" "image: $(c 90 "$image")"
        else
          _tree_item "$svc_sub_prefix" "0" "$(c 31 "✗")" "image: $(c 31 "missing")"
          errors=$((errors + 1))
        fi
        _tree_item "$svc_sub_prefix" "1" "○" "type: $(c 90 "external")"
      fi
    done
  else
    _tree_item "$svc_prefix" "1" "$(c 31 "✗")" "No services defined"
  fi
  
  # ===== Section 3: Secrets =====
  # Security: don't list secret names in logs, only show missing ones on error
  _tree_section "" "0" "" "Secrets"
  local sec_prefix="$_tree_pipe"
  
  local secrets_file=""
  [ -f "$stack_dir/externals.yaml" ] && secrets_file="$stack_dir/externals.yaml"
  [ -f "$stack_dir/required_secrets.yaml" ] && secrets_file="$stack_dir/required_secrets.yaml"
  
  if [ -n "$secrets_file" ]; then
    local secrets_list
    secrets_list=$(get_required_secrets_list "$stack" 2>/dev/null || echo "")
    local secrets_arr=()
    while IFS= read -r sec; do
      [ -n "$sec" ] && secrets_arr+=("$sec")
    done <<< "$secrets_list"
    
    local total=${#secrets_arr[@]}
    local missing_secrets=()
    
    if [ $total -eq 0 ]; then
      _tree_item "$sec_prefix" "1" "○" "No secrets required"
    else
      # Check all secrets, collect missing ones
      for sec in "${secrets_arr[@]}"; do
        if ! secret_exists "$sec" 2>/dev/null && ! secret_exists "${sec}_latest" 2>/dev/null; then
          missing_secrets+=("$sec")
          errors=$((errors + 1))
        fi
      done
      
      local missing_count=${#missing_secrets[@]}
      local present_count=$((total - missing_count))
      
      if [ $missing_count -eq 0 ]; then
        # All secrets present - show only count
        _tree_item "$sec_prefix" "1" "$(c 32 "✓")" "All secrets present ($total)"
      else
        # Some missing - show present count and list missing ones
        if [ $present_count -gt 0 ]; then
          _tree_item "$sec_prefix" "0" "$(c 32 "✓")" "Present: $present_count"
        fi
        _tree_item "$sec_prefix" "0" "$(c 31 "✗")" "Missing: $missing_count"
        
        # List only missing secrets (security: show names only on error)
        local idx=0
        for sec in "${missing_secrets[@]}"; do
          idx=$((idx + 1))
          local is_last=$( [ $idx -eq $missing_count ] && echo "1" || echo "0" )
          _tree_item "$sec_prefix$_tree_space" "$is_last" "$(c 31 "•")" "$sec"
        done
      fi
    fi
  else
    _tree_item "$sec_prefix" "1" "○" "No secrets required"
  fi
  
  # ===== Section 4: Configs =====
  _tree_section "" "1" "" "Configs"
  local cfg_prefix="$_tree_space"
  
  local configs_list
  configs_list=$(get_required_configs_list "$stack" 2>/dev/null || echo "")
  
  if [ -n "$configs_list" ]; then
    local configs_arr=()
    local config_files_arr=()
    while IFS=$'\t' read -r name file; do
      [ -n "$name" ] && configs_arr+=("$name") && config_files_arr+=("$file")
    done <<< "$configs_list"
    
    local total=${#configs_arr[@]}
    local missing_files=()
    
    if [ $total -eq 0 ]; then
      _tree_item "$cfg_prefix" "1" "○" "No configs required"
    else
      local strategy
      strategy="$(get_config_strategy "$stack")"
      
      # Check all config files exist
      local idx=0
      for cfg in "${configs_arr[@]}"; do
        local file="${config_files_arr[$idx]}"
        local file_path="$stack_dir/$file"
        
        if [ ! -f "$file_path" ] || [ ! -s "$file_path" ]; then
          missing_files+=("$cfg ($file)")
          errors=$((errors + 1))
        fi
        idx=$((idx + 1))
      done
      
      local missing_count=${#missing_files[@]}
      local present_count=$((total - missing_count))
      
      if [ $missing_count -eq 0 ]; then
        _tree_item "$cfg_prefix" "1" "$(c 32 "✓")" "All config files present ($total, strategy: $strategy)"
      else
        if [ $present_count -gt 0 ]; then
          _tree_item "$cfg_prefix" "0" "$(c 32 "✓")" "Present: $present_count"
        fi
        _tree_item "$cfg_prefix" "0" "$(c 31 "✗")" "Missing files: $missing_count"
        
        local idx=0
        for cfg in "${missing_files[@]}"; do
          idx=$((idx + 1))
          local is_last=$( [ $idx -eq $missing_count ] && echo "1" || echo "0" )
          _tree_item "$cfg_prefix$_tree_space" "$is_last" "$(c 31 "•")" "$cfg"
        done
      fi
    fi
  else
    _tree_item "$cfg_prefix" "1" "○" "No configs required"
  fi
  
  # ===== Result =====
  local end_ms=$(now_ms)
  local duration=$((end_ms - start_ms))
  
  if [ $errors -eq 0 ]; then
    printf "✅ $(c 32 "Validation completed") in %dms\n" "$duration"
    return 0
  else
    printf "❌ $(c 31 "Validation failed") with %d error(s)\n" "$errors"
    return 1
  fi
}

# Command: swarmcli validate <stack>
# Tree mode is default, --verbose switches to plain CLI output
cmd_validate() {
  local stack="$1"
  
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --verbose|-v) VERBOSE=1 ;;
    esac
    shift
  done
  
  [ -n "$stack" ] || fail "usage: swarmcli validate <STACK> --profile <PROFILE> [--verbose]"
  
  ensure_stack_exists "$stack"
  
  clear_errors
  
  # Verbose mode: plain CLI output
  if [ "$VERBOSE" = "1" ]; then
    local start_ms=$(now_ms)
    
    log info "validating stack: $stack (profile: $ACTIVE_PROFILE)"
    
    if ! validate_stack_all "$stack"; then
      local end_ms=$(now_ms)
      output_result "error" "validate" $((end_ms - start_ms)) "configuration validation failed"
      return 1
    fi
    
    if validate_deploy_prerequisites "$stack"; then
      local end_ms=$(now_ms)
      output_result "success" "validate" $((end_ms - start_ms)) "all checks passed"
      return 0
    else
      local end_ms=$(now_ms)
      output_result "error" "validate" $((end_ms - start_ms)) "validation failed"
      return 1
    fi
  fi
  
  # Default: tree mode
  cmd_validate_tree "$stack"
  return $?
}
