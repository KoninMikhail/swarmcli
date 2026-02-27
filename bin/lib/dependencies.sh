#!/usr/bin/env bash
# Dependencies checker for Linux servers

# Detect operating system
detect_os() {
  case "$(uname -s)" in
    Linux*) echo "linux" ;;
    Darwin*) echo "macos" ;;
    CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

# Get OS-specific package manager
get_package_manager() {
  local os
  os=$(detect_os)
  
  case "$os" in
    linux)
      if command -v apt >/dev/null 2>&1; then
        echo "apt"
      elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
      elif command -v yum >/dev/null 2>&1; then
        echo "yum"
      elif command -v apk >/dev/null 2>&1; then
        echo "apk"
      elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
      else
        echo "unknown"
      fi
      ;;
    macos)
      if command -v brew >/dev/null 2>&1; then
        echo "brew"
      else
        echo "unknown"
      fi
      ;;
    windows)
      if command -v choco >/dev/null 2>&1; then
        echo "choco"
      elif command -v scoop >/dev/null 2>&1; then
        echo "scoop"
      else
        echo "unknown"
      fi
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

# Check Bash version
check_bash() {
  local required_major=4
  local current_version="${BASH_VERSION%%.*}"
  
  if [ "$current_version" -ge "$required_major" ]; then
    echo "✓ Bash $BASH_VERSION (required: $required_major.0+)"
    return 0
  else
    echo "✗ Bash $BASH_VERSION (required: $required_major.0+)"
    return 1
  fi
}

# Check Docker
check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "✗ Docker - not installed"
    return 1
  fi
  
  local version
  version=$(docker --version 2>&1)
  
  if ! docker info >/dev/null 2>&1; then
    echo "⚠ Docker $version - installed but daemon not running"
    return 2
  fi
  
  if docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "✓ Docker $version - Swarm active"
    return 0
  else
    echo "⚠ Docker $version - Swarm not initialized"
    return 3
  fi
}

# Check Git
check_git() {
  if ! command -v git >/dev/null 2>&1; then
    echo "✗ Git - not installed"
    return 1
  fi
  
  local version
  version=$(git --version 2>&1)
  echo "✓ $version"
  return 0
}

# Check jq (required for safe JSON output)
check_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "✗ jq - not installed"
    return 1
  fi
  
  local version
  version=$(jq --version 2>&1)
  echo "✓ $version"
  return 0
}

# Check Docker Buildx (optional)
check_buildx() {
  if docker buildx version >/dev/null 2>&1; then
    local version
    version=$(docker buildx version 2>&1)
    echo "✓ Docker Buildx $version"
    return 0
  else
    echo "○ Docker Buildx - not installed (optional)"
    return 1
  fi
}

# Check Python with required modules (Jinja2 + PyYAML)
check_python_required() {
  local python_cmd=""
  
  if command -v python3 >/dev/null 2>&1; then
    python_cmd="python3"
  elif command -v python >/dev/null 2>&1; then
    python_cmd="python"
  else
    echo "✗ Python - not installed"
    return 1
  fi
  
  local version
  version=$($python_cmd --version 2>&1)
  
  # Check Jinja2
  if ! $python_cmd -c "import jinja2" 2>/dev/null; then
    echo "✗ $version - installed but Jinja2 module missing"
    return 2
  fi
  
  # Check PyYAML
  if ! $python_cmd -c "import yaml" 2>/dev/null; then
    echo "✗ $version - installed but PyYAML module missing"
    return 3
  fi
  
  local jinja_version
  jinja_version=$($python_cmd -c "import jinja2; print(jinja2.__version__)" 2>/dev/null || echo "unknown")
  
  local yaml_version
  yaml_version=$($python_cmd -c "import yaml; print(yaml.__version__)" 2>/dev/null || echo "unknown")
  
  echo "✓ $version with Jinja2 $jinja_version and PyYAML $yaml_version"
  return 0
}

# Check all required dependencies
check_all_dependencies() {
  local critical_errors=0
  local warnings=0
  local optional_missing=0
  
  log info "checking dependencies..."
  echo ""
  
  local os
  os=$(detect_os)
  local pm
  pm=$(get_package_manager)
  echo "Platform: $(uname -s) ($os)"
  echo "Package Manager: $pm"
  echo ""
  
  echo "=== Critical Dependencies ==="
  
  if ! check_bash; then
    critical_errors=$((critical_errors + 1))
  fi
  
  local docker_status
  check_docker
  docker_status=$?
  if [ $docker_status -eq 1 ]; then
    critical_errors=$((critical_errors + 1))
  elif [ $docker_status -eq 2 ] || [ $docker_status -eq 3 ]; then
    warnings=$((warnings + 1))
  fi
  
  if ! check_git; then
    critical_errors=$((critical_errors + 1))
  fi
  
  if ! check_jq; then
    critical_errors=$((critical_errors + 1))
  fi
  
  local python_status
  check_python_required
  python_status=$?
  if [ $python_status -eq 1 ] || [ $python_status -eq 2 ] || [ $python_status -eq 3 ]; then
    critical_errors=$((critical_errors + 1))
  fi
  
  echo ""
  echo "=== Optional Dependencies ==="
  
  if ! check_buildx; then
    optional_missing=$((optional_missing + 1))
  fi
  
  echo ""
  echo "=== Summary ==="
  
  if [ $critical_errors -eq 0 ] && [ $warnings -eq 0 ]; then
    echo "✓ All critical dependencies are properly configured"
  elif [ $critical_errors -eq 0 ]; then
    echo "⚠ All critical dependencies are installed ($warnings warning(s))"
  else
    echo "✗ $critical_errors critical dependency issue(s) found"
  fi
  
  if [ $optional_missing -gt 0 ]; then
    echo "○ $optional_missing optional dependency(ies) missing"
  fi
  
  echo ""
  
  if [ $critical_errors -gt 0 ]; then
    return 1
  fi
  
  return 0
}

# Print installation instructions
print_install_instructions() {
  local os
  os=$(detect_os)
  
  echo ""
  echo "=== Installation Instructions ==="
  echo ""
  
  case "$os" in
    linux)
      local pm
      pm=$(get_package_manager)
      case "$pm" in
        apt)
          echo "Ubuntu/Debian:"
          echo "  curl -fsSL https://get.docker.com | sh"
          echo "  sudo usermod -aG docker \$USER"
          echo "  sudo apt install -y git jq python3 python3-pip"
          echo "  pip3 install jinja2 pyyaml"
          echo "  docker swarm init"
          ;;
        yum|dnf)
          echo "CentOS/RHEL/Fedora:"
          echo "  curl -fsSL https://get.docker.com | sh"
          echo "  sudo usermod -aG docker \$USER"
          echo "  sudo ${pm} install -y git jq python3 python3-pip"
          echo "  pip3 install jinja2 pyyaml"
          echo "  docker swarm init"
          ;;
        apk)
          echo "Alpine:"
          echo "  apk add docker git jq python3 py3-pip bash"
          echo "  pip3 install jinja2 pyyaml"
          echo "  rc-update add docker boot && service docker start"
          echo "  docker swarm init"
          ;;
        pacman)
          echo "Arch Linux:"
          echo "  sudo pacman -S docker git jq python python-pip"
          echo "  pip install jinja2 pyyaml"
          echo "  sudo systemctl enable --now docker"
          echo "  docker swarm init"
          ;;
        *)
          echo "Linux:"
          echo "  curl -fsSL https://get.docker.com | sh"
          echo "  sudo usermod -aG docker \$USER"
          echo "  Install: git, jq, python3, pip3"
          echo "  pip3 install jinja2 pyyaml"
          echo "  docker swarm init"
          ;;
      esac
      ;;
    *)
      echo "SwarmCLI is designed for Linux servers."
      echo "See: https://github.com/KoninMikhail/swarmcli#requirements"
      ;;
  esac
  
  echo ""
}

# Command: swarmcli check-deps
cmd_check_deps() {
  log info "checking system dependencies"
  
  if check_all_dependencies; then
    log ok "all dependencies are properly configured"
    return 0
  else
    log error "some dependencies are missing or misconfigured"
    print_install_instructions
    return 1
  fi
}
