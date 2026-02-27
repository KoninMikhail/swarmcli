# Server Configuration

Guide for configuring SwarmCLI on a server.

## Profile Configuration

### config.yaml

Main profile settings file:

```yaml
# profiles/server-prod/config.yaml

name: server-prod
description: Production server

# Docker Swarm settings
swarm:
  services_ready_timeout: 30   # Readiness wait timeout (sec)
  keep_images_count: 3         # How many images to keep
  diagnostics_logs_tail: 30    # Log lines for diagnostics

# Git settings
git:
  default_branch: main         # Default branch
  http_token: ${GIT_HTTP_TOKEN} # Token for HTTP cloning

# Retry logic
retry:
  enabled: true
  max_attempts: 3
  initial_delay: 2
  max_delay: 30
```

### Variables in config.yaml

Environment variable substitution is supported:

```yaml
git:
  http_token: ${GIT_HTTP_TOKEN}  # Taken from environment
```

## Global Variables

### globals.yaml

Variables available to all profile stacks:

```yaml
# profiles/server-prod/stacks/globals.yaml

TZ: Europe/Moscow
PLATFORM_ENV: production
LOG_LEVEL: info
METRICS_ENABLED: "true"
```

**Usage:**

Variables are exported with the `GLOBAL_` prefix:

```bash
GLOBAL_TZ=Europe/Moscow
GLOBAL_PLATFORM_ENV=production
```

In `docker-stack.yml`:

```yaml
environment:
  - TZ=${GLOBAL_TZ}
```

## CPU/Memory Resources

### resources.yaml

Centralized resource management for all stacks:

```yaml
# profiles/server-prod/stacks/resources.yaml

stacks:
  my-app:
    api:
      limits:
        cpus: "2.0"
        memory: "4G"
      reservations:
        cpus: "0.5"
        memory: "1G"
    worker:
      limits:
        cpus: "1.0"
        memory: "2G"
        
  another-app:
    backend:
      limits:
        cpus: "1.0"
        memory: "1G"
```

**Centralization benefits:**

- All resources in one place
- Easy to see overall picture
- Convenient balancing between stacks
- No need to edit docker-stack.yml

## Secrets

### Secret Structure

Secrets are stored globally under `SECRETS_ROOT` (default: `.secrets/` in the project root), **not** inside individual profile directories. This is configured in `.swarmcli.yaml`:

```yaml
paths:
  secrets: .secrets   # relative to project root, or absolute path
```

```
<project-root>/
└── .secrets/
    ├── pg_password
    ├── jwt_private_key
    ├── redis_password
    └── ...
```

### Creating Secrets

```bash
# Interactive
swarmcli secret create pg_password

# From file
echo "my-secret-password" > .secrets/pg_password
swarmcli secret sync

# Generate random
swarmcli secret generate jwt_secret --length 64
```

### Stack externals.yaml

Describes required secrets and configs:

```yaml
# stacks/my-app/externals.yaml

secrets:
  - pg_password
  - jwt_private_key
  - redis_password
```

## Endpoints (Service Discovery)

### endpoints.yaml

Describes internal services for discovery:

```yaml
# profiles/server-prod/stacks/endpoints.yaml

endpoints:
  core-api:
    host: api
    port: 8080
    protocol: http
    
  auth-service:
    host: auth
    port: 3000
    protocol: http
    
  redis:
    host: redis
    port: 6379
```

**Generated variables:**

```bash
SERVICE_CORE_API_URL=http://api:8080
SERVICE_AUTH_SERVICE_URL=http://auth:3000
SERVICE_REDIS_HOST=redis
SERVICE_REDIS_PORT=6379
```

## Per-Stack Configuration

### settings.yaml

Per-stack settings:

```yaml
# stacks/my-app/settings.yaml

services_ready_timeout: 60   # Override timeout for this stack
diagnostics_logs_tail: 50    # More logs for diagnostics
```

### Hooks

```bash
stacks/my-app/hooks/
├── pre-deploy.sh    # Before deploy
└── post-deploy.sh   # After successful deploy
```

**Example pre-deploy.sh:**

```bash
#!/usr/bin/env bash
# Database migration before deploy

set -euo pipefail

echo "Running database migrations..."
docker exec $(docker ps -q -f name=${STACK}_api) npm run migrate
echo "Migrations completed"
```

**Example post-deploy.sh:**

```bash
#!/usr/bin/env bash
# Cache clear after deploy

set -euo pipefail

echo "Clearing cache..."
docker exec $(docker ps -q -f name=${STACK}_api) npm run cache:clear
echo "Cache cleared"

# Slack notification
if [ -n "${SLACK_WEBHOOK:-}" ]; then
  curl -s -X POST "$SLACK_WEBHOOK" \
    -H 'Content-type: application/json' \
    -d "{\"text\":\"✅ ${STACK} deployed to ${SWARM_PROFILE}\"}"
fi
```

## Environment Variables

### .swarmcli.yaml

Global SwarmCLI configuration is stored in `.swarmcli.yaml`:

```yaml
# /opt/swarmcli/.swarmcli.yaml

state:
  default_profile: server-dev

paths:
  secrets: .secrets
  locks: .locks

operations:
  log_format: text
  timeout: 900
  lock_timeout: 3600

git:
  auth:
    http_user: null
    http_token: null
    http_password: null
```

**CLI management:**

```bash
swarmcli config set operations.log_format json
swarmcli config get state.default_profile
swarmcli config list
```

**Profile variables** (e.g., `PLATFORM_ENV`, `METRICS_ENABLED`) are stored in `profiles/<profile>/stacks/globals.yaml`.

**Profile-specific operations** (`default_branch`, `keep_images_count`, `services_ready_timeout`) are in `profiles/<profile>/config.yaml` — see [config.yaml](../../03-reference/config/01-config-yaml.md).

## Docker Settings

### BuildKit

SwarmCLI automatically enables BuildKit:

```bash
export DOCKER_BUILDKIT=1
export BUILDKIT_PROGRESS=plain
```

### Registry

For private registry:

```bash
# Login to registry
docker login registry.example.com

# Credentials saved in ~/.docker/config.json
```

### Prune Policy

Automatic cleanup of old images:

```bash
# Number of images to keep
export KEEP_IMAGES_COUNT=5

# On deploy with --prune
swarmcli deploy my-app --prune
```

## Monitoring

### Dozzle Integration

SwarmCLI automatically generates Dozzle labels:

```yaml
# services.yaml
services:
  api:
    type: git
    meta:
      group: backend
      name: API Service
```

**Result:**

```yaml
deploy:
  labels:
    dev.dozzle.group: backend
    dev.dozzle.name: API Service
```

### JSON Logging

For log system integration:

```bash
# Enable JSON logs
export LOG_FORMAT=json

# Or via flag
swarmcli deploy my-app --json
```

## Security

### SSH Keys

```bash
# Generate key for CI/CD
ssh-keygen -t ed25519 -C "swarmcli-deploy" -f ~/.ssh/swarmcli-deploy

# Add public key to GitLab/GitHub

# Private key — in CI/CD variables
```

### Access Permissions

```bash
# Recommended permissions
chmod 700 /opt/swarmcli
chmod 600 /opt/swarmcli/.swarmcli.yaml
chmod 700 /opt/swarmcli/.secrets
chmod 600 /opt/swarmcli/.secrets/*
```

### Firewall

```bash
# Docker Swarm ports
ufw allow 2377/tcp  # Cluster management
ufw allow 7946/tcp  # Node communication
ufw allow 7946/udp
ufw allow 4789/udp  # Overlay network
```

## Backups

### What to Backup

```bash
# Configuration
/opt/swarmcli/profiles/

# Secrets (global directory)
/opt/swarmcli/.secrets/

# Deploy history stored inside each stack:
# profiles/<profile>/stacks/<stack>/.deploy/
```

### Backup Script

```bash
#!/bin/bash
# backup-swarmcli.sh

BACKUP_DIR="/backup/swarmcli/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# Configuration
tar -czf "$BACKUP_DIR/profiles.tar.gz" -C /opt/swarmcli profiles/

# Secrets (encrypt!)
tar -czf - -C /opt/swarmcli .secrets/ | \
  gpg --symmetric --cipher-algo AES256 -o "$BACKUP_DIR/secrets.tar.gz.gpg"

# History (stored inside stacks in .deploy/)
find /opt/swarmcli/profiles -name ".deploy" -type d -exec tar -rf "$BACKUP_DIR/history.tar" {} \;

echo "Backup completed: $BACKUP_DIR"
```

## Recommendations

### Production

1. **Dedicated user** — `deploy` without sudo
2. **Minimal permissions** — docker group only
3. **SSH keys** — separate for each environment
4. **Secrets** — store encrypted
5. **Monitoring** — JSON logs + centralized collection
6. **Backups** — regular configuration backups

### Development

1. **Single profile** — `server-dev`
2. **More resources** — for debugging
3. **Verbose logs** — `LOG_LEVEL=debug`
4. **No prune** — keep images for rollback

## See also

- [Installation](00-installation.md)
- [CI/CD integration](../gitlab-ci/00-overview.md)
- [Troubleshooting](../troubleshooting/00-common-issues.md)
