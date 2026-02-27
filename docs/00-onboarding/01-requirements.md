# System Requirements

> **Platform:** SwarmCLI is designed for **Linux servers** (Ubuntu 20.04+, Debian 11+, CentOS 8+, and other modern Linux distributions with Bash 4.0+).

Before installing SwarmCLI, ensure your system meets the requirements.

## Minimum Requirements

| Component | Version | Verification |
|-----------|---------|--------------|
| **Linux** | Ubuntu 20.04+ / Debian 11+ / CentOS 8+ | `lsb_release -a` or `cat /etc/os-release` |
| **Docker** | 20.10+ | `docker --version` |
| **Docker Swarm** | active | `docker info \| grep Swarm` |
| **Git** | 2.0+ | `git --version` |
| **jq** | 1.6+ | `jq --version` |
| **Bash** | 4.0+ | `bash --version` |
| **Python** | 3.x | `python3 --version` |
| **Jinja2** | 2.10+ | `python3 -c "import jinja2; print(jinja2.__version__)"` |
| **PyYAML** | - | `python3 -c "import yaml; print(yaml.__version__)"` |

## Dependency Check

SwarmCLI includes a command for automatic verification:

```bash
swarmcli system health
```

The command checks all required dependencies:

| Check | What is verified |
|-------|------------------|
| **Bash** | Version 4.0+ (required for associative arrays) |
| **Docker** | Installed, daemon running, Swarm active |
| **Git** | Installed |
| **jq** | Installed (required for safe JSON output) |
| **Python** | Installed with Jinja2 and PyYAML modules |
| **Docker Buildx** | Optional, for advanced build features |

Symbols: `✓` OK | `✗` critical error | `⚠` warning | `○` optional missing

Example output (all OK):

```
Platform: Linux (linux)
Package Manager: apt

=== Critical Dependencies ===
✓ Bash 5.1.16(1)-release (required: 4.0+)
✓ Docker version 24.0.7, build afdd53b - Swarm active
✓ git version 2.43.0
✓ jq-1.6
✓ Python 3.12.3 with Jinja2 3.1.6 and PyYAML 6.0.1

=== Optional Dependencies ===
✓ Docker Buildx v0.12.0

=== Summary ===
✓ All critical dependencies are properly configured
```

Example when something is missing (Git not installed, PyYAML missing):

```
Platform: Linux (linux)
Package Manager: apt

=== Critical Dependencies ===
✓ Bash 5.1.16(1)-release (required: 4.0+)
✓ Docker version 24.0.7 - Swarm active
✗ Git - not installed
✗ Python 3.12.3 - installed but PyYAML module missing

=== Optional Dependencies ===
○ Docker Buildx - not installed (optional)

=== Summary ===
✗ 2 critical dependency issue(s) found
○ 1 optional dependency(ies) missing

=== Installation Instructions ===
...
```

Example with warnings (Docker daemon not running or Swarm not initialized):

```
...
⚠ Docker version 24.0.7 - Swarm not initialized
...
=== Summary ===
⚠ All critical dependencies are installed (1 warning(s))
```

**Note:** The command verifies presence and basic configuration. Minimum versions (Docker 20.10+, Git 2.0+, Jinja2 2.10+) are not checked automatically — use the manual verification commands from the table above if needed.

## Installing Dependencies

### Docker

```bash
# Install Docker
curl -fsSL https://get.docker.com | bash

# Add user to docker group
sudo usermod -aG docker $USER

# Re-login to apply changes
exit
# ... connect again ...
```

### Docker Swarm

```bash
# Initialize Swarm mode
docker swarm init

# Verify
docker info | grep -i swarm
# Swarm: active
```

### Git

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y git

# Configuration (optional, for local commits)
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

### jq

jq is required for safe JSON output. Used for `--json` flag and structured logging.

```bash
# Ubuntu/Debian
sudo apt install -y jq

# CentOS/RHEL
sudo yum install -y jq

# Verify
jq --version
```

### Python

```bash
# Usually already installed
python3 --version

# If not:
sudo apt install -y python3
```

### Python Dependencies

SwarmCLI requires two Python libraries:

#### Jinja2

Jinja2 is used for templating `docker-stack.yml` files (see ADR-0012).

```bash
# Install via pip
pip3 install jinja2

# Or via pip3 with sudo (if no permissions)
sudo pip3 install jinja2

# Verify installation
python3 -c "import jinja2; print(jinja2.__version__)"
# Output: 3.1.6 (or another version 2.10+)
```

#### PyYAML

PyYAML is used for reliable parsing of YAML configuration files (see ADR-0004).

```bash
# Install via pip
pip3 install pyyaml

# Or via pip3 with sudo (if no permissions)
sudo pip3 install pyyaml

# Verify installation
python3 -c "import yaml; print(yaml.__version__)"
# Output: 6.0.1 (or another version)
```

**Note:** The installer (`install.sh`) will automatically offer to install Jinja2 and PyYAML if they are missing.

## Network Requirements

### Access to Git Repositories

SwarmCLI must have access to your application Git repositories:

```bash
# For SSH access (GitHub)
ssh -T git@github.com
# Hi username! You've successfully authenticated...

# For HTTPS access
export GIT_HTTP_TOKEN="your-token"
```

### Docker Registry (optional)

If using a private Docker Registry:

```bash
docker login registry.example.com
```

## Recommended Settings

### Docker Settings

```bash
# /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
```

### SSH Keys

For Git repository access, SSH keys are recommended:

```bash
# Generate key (if none exists)
ssh-keygen -t ed25519 -C "server-dev@example.com"

# Add public key to GitLab/GitHub
cat ~/.ssh/id_ed25519.pub
```

### Firewall

For Docker Swarm to work, ensure these ports are open:

| Port | Protocol | Purpose |
|------|----------|---------|
| 2377 | TCP | Cluster management |
| 7946 | TCP/UDP | Node communication |
| 4789 | UDP | Overlay network |

```bash
# UFW example
sudo ufw allow 2377/tcp
sudo ufw allow 7946/tcp
sudo ufw allow 7946/udp
sudo ufw allow 4789/udp
```

## Limitations

### Not Supported

- Windows (only via WSL2)
- macOS (only for local development)
- Docker Compose v1 (Compose v2 or Docker Stack required)
- Kubernetes (this is a Docker Swarm tool)

### Known Limitations

- **Without Container Registry**: old images cannot be restored after deletion
- **Single Swarm cluster**: each profile = one server/cluster
- **Bash-dependent**: Bash 4.0+ required for associative arrays

## Pre-Installation Checklist

- [ ] Ubuntu 20.04+ LTS
- [ ] Docker 20.10+ installed
- [ ] Docker Swarm initialized (`docker swarm init`)
- [ ] Git 2.0+ installed
- [ ] jq 1.6+ installed (`apt install jq` / `brew install jq`)
- [ ] Python 3.x installed
- [ ] Jinja2 2.10+ installed (`pip3 install jinja2`)
- [ ] PyYAML installed (`pip3 install pyyaml`)
- [ ] SSH access to Git repositories configured
- [ ] User in `docker` group

## Next Step

→ [Install SwarmCLI](02-installation.md)
