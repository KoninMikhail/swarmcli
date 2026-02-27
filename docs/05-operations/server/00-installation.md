# SwarmCLI Installation

Guide for installing SwarmCLI on a server.

## System Requirements

| Component | Minimum Version | Check |
|-----------|-----------------|-------|
| Ubuntu Server | 20.04+ LTS | `lsb_release -a` |
| Docker | 20.10+ | `docker --version` |
| Docker Swarm | — | `docker info \| grep Swarm` |
| Git | 2.0+ | `git --version` |
| Bash | 4.0+ | `bash --version` |
| Python | 3.x | `python3 --version` |

## Quick Install

### 1. Install via install.sh

```bash
# Download and install
curl -sSL https://raw.githubusercontent.com/KoninMikhail/swarmcli/main/install.sh | bash

# Or clone repository
git clone https://github.com/KoninMikhail/swarmcli.git /opt/swarmcli
cd /opt/swarmcli
./install.sh
```

### 2. Verify installation

```bash
# Check version
swarmcli system version

# Check dependencies
swarmcli system health
```

Expected `system health` output (when all dependencies are OK):

```
Platform: Linux (linux)
Package Manager: apt

=== Critical Dependencies ===
✓ Bash 5.2.15(1)-release (required: 4.0+)
✓ Docker version 24.0.7 - Swarm active
✓ git version 2.43.0
✓ jq-1.6
✓ Python 3.12.0 with Jinja2 3.1.6 and PyYAML 6.0.1

=== Optional Dependencies ===
✓ Docker Buildx v0.12.0

=== Summary ===
✓ All critical dependencies are properly configured
```

## Manual Installation

### 1. Clone repository

```bash
# Recommended location
sudo mkdir -p /opt/swarmcli
sudo chown $USER:$USER /opt/swarmcli
git clone https://github.com/KoninMikhail/swarmcli.git /opt/swarmcli
```

### 2. Create symlink

```bash
sudo ln -sf /opt/swarmcli/bin/swarm.sh /usr/local/bin/swarmcli
```

### 3. Check permissions

```bash
chmod +x /opt/swarmcli/bin/swarm.sh
chmod +x /opt/swarmcli/bin/lib/*.sh
```

### 4. Initialize Docker Swarm (if not initialized)

```bash
# Check status
docker info | grep Swarm

# Initialize if needed
docker swarm init
```

## Installation Structure

```
/opt/
├── swarmcli/                # PLATFORM_ROOT (swarmcli)
│   ├── bin/
│   │   ├── swarm.sh         # CLI entry point
│   │   └── lib/             # Library modules
│   ├── profiles/            # Server profiles
│   │   ├── server-dev/
│   │   ├── server-prod/
│   │   └── server-db/
│   ├── .swarmcli.yaml       # Configuration and state (tokens, paths, profile)
│   ├── .locks/              # Deploy locks (created automatically)
│   # Deploy history stored in each stack: stacks/<stack>/.deploy/
└── secrets/                 # SECRETS_ROOT — secret files (outside swarmcli)
```

> **Data isolation:** The `secrets/` directory is outside the swarmcli repository for data isolation from CLI. This allows updating swarmcli without risk of losing secrets.
> 
> **Note:** Service repositories are stored inside each stack in `.repos/`.

## Deploy User Setup

For CI/CD, create a dedicated user:

### 1. Create user

```bash
sudo useradd -m -s /bin/bash deploy
```

### 2. Add to docker group

```bash
sudo usermod -aG docker deploy
```

### 3. Configure SSH

```bash
# Create .ssh directory
sudo -u deploy mkdir -p /home/deploy/.ssh
sudo -u deploy chmod 700 /home/deploy/.ssh

# Add public key
echo "ssh-ed25519 AAAA..." | sudo -u deploy tee /home/deploy/.ssh/authorized_keys
sudo -u deploy chmod 600 /home/deploy/.ssh/authorized_keys
```

### 4. Grant SwarmCLI access

```bash
# Option 1: Directory permissions
sudo chown -R deploy:deploy /opt/swarmcli

# Option 2: Add to group
sudo chgrp -R swarmcli /opt/swarmcli
sudo usermod -aG swarmcli deploy
```

## Default Profile Setup

### On server

```bash
# Set default profile
swarmcli use server-prod  # or server-dev

# Verify
swarmcli use --show
```

### For CI/CD

Profile is saved in `.swarmcli.yaml`:

```bash
swarmcli system config get state.default_profile
# server-prod
```

## Environment Variables

### .swarmcli.yaml

Instance configuration and state:

```yaml
# /opt/swarmcli/.swarmcli.yaml
paths:
  secrets: .secrets
operations:
  log_format: json
git:
  auth:
    http_token: "your-token"
```

### CLI Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PLATFORM_ROOT` | auto | SwarmCLI root |
| `SECRETS_ROOT` | `$PLATFORM_ROOT/.secrets` | Secret files directory (only from `.swarmcli.yaml`) |
| `LOG_FORMAT` | `text` | Log format (text/json) |
| `TIMEOUT_SECONDS` | `900` | Operation timeout |
| `LOCK_TIMEOUT` | `3600` | Lock timeout |
| `SERVICES_READY_TIMEOUT` | `30` | Service readiness wait (from profile `config.yaml`) |
| `KEEP_IMAGES_COUNT` | `10` | How many images to keep (from profile `config.yaml`) |

> **⚠️ Security:** `SECRETS_ROOT` is read **exclusively** from `.swarmcli.yaml` and cannot be overridden via environment variables.

> **Note:** Service repositories are stored in `stacks/<stack>/.repos/`.

> **Note:** When installing via `install.sh`, paths are saved in `.swarmcli.yaml` and override defaults.

## Updating SwarmCLI

### Via CLI

```bash
swarmcli system update
# or
swarmcli system update develop  # Specific branch
```

### Manually

```bash
cd /opt/swarmcli
git fetch origin
git checkout main
git pull origin main
```

## Removal

### Via uninstall.sh

```bash
cd /opt/swarmcli
./uninstall.sh
```

### Manually

```bash
# Remove symlink
sudo rm -f /usr/local/bin/swarmcli

# Remove directory
sudo rm -rf /opt/swarmcli
```

## Troubleshooting

### "command not found: swarmcli"

```bash
# Check symlink
ls -la /usr/local/bin/swarmcli

# Recreate
sudo ln -sf /opt/swarmcli/bin/swarm.sh /usr/local/bin/swarmcli
```

### "Permission denied"

```bash
# Check execute permissions
chmod +x /opt/swarmcli/bin/swarm.sh
chmod +x /opt/swarmcli/bin/lib/*.sh

# Check owner
ls -la /opt/swarmcli/
```

### "Docker daemon not running"

```bash
# Start Docker
sudo systemctl start docker
sudo systemctl enable docker

# Check status
sudo systemctl status docker
```

### "Not a swarm manager"

```bash
# Initialize Swarm
docker swarm init

# Or join existing
docker swarm join --token SWMTKN-xxx manager-ip:2377
```

### Bash version < 4.0

```bash
# On Ubuntu
sudo apt update && sudo apt install bash

# Verify
bash --version
```

## See also

- [Server configuration](01-configuration.md)
- [First deploy](../../00-onboarding/03-first-deploy.md)
- [Troubleshooting](../troubleshooting/00-common-issues.md)
