# Creating a Profile

Step-by-step guide for creating a new server profile.

## When to Create a Profile

- New server (dev, staging, prod)
- Separate infrastructure (database server, ML server)
- Isolated environment with different settings

## Creating a Profile

### Method 1: Copy Existing

```bash
cd /opt/swarmcli

# Copy existing profile
cp -r profiles/server-dev profiles/my-new-server

# Edit configuration
nano profiles/my-new-server/config.yaml
```

### Method 2: From Scratch

```bash
# Create profile structure
mkdir -p profiles/my-new-server/{stacks,scripts}

# Create config.yaml
cat > profiles/my-new-server/config.yaml << 'EOF'
name: my-new-server
description: My new server configuration

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
```

## Profile Structure

```
profiles/my-new-server/
├── config.yaml          # Profile settings (required)
├── scripts/             # Helper scripts
└── stacks/              # Application stacks
    ├── globals.yaml     # Global variables
    ├── resources.yaml   # CPU/Memory limits
    ├── endpoints.yaml   # Service registry
    └── my-app/          # Application stack
```

## config.yaml Configuration

### Minimal

```yaml
name: my-new-server
description: Server description

swarm:
  services_ready_timeout: 30

git:
  default_branch: main
```

### Full

```yaml
# Name and description
name: my-new-server
description: Production server for main application

# Docker Swarm settings
swarm:
  # Service readiness timeout
  services_ready_timeout: 60
  
  # Number of image versions to keep
  # Important for rollback!
  keep_images_count: 5

# Git settings
git:
  # Default branch
  default_branch: main
  
  # Token for HTTPS (from environment variable)
  http_token: ${GIT_HTTP_TOKEN}

# Retry logic
retry:
  enabled: true
  max_attempts: 3
  initial_delay: 2
  max_delay: 30
```

## Global Files

### globals.yaml

```yaml
# profiles/my-new-server/stacks/globals.yaml

# Timezone
TZ: Europe/Moscow

# Environment
PLATFORM_ENV: production

# Log level
LOG_LEVEL: INFO

# Domain
DOMAIN: app.example.com
```

### resources.yaml

```yaml
# profiles/my-new-server/stacks/resources.yaml

stacks:
  my-app:
    api:
      limits:
        cpus: "4.0"
        memory: "4G"
      reservations:
        cpus: "1.0"
        memory: "1G"
    
    worker:
      limits:
        cpus: "2.0"
        memory: "2G"
```

### endpoints.yaml

```yaml
# profiles/my-new-server/stacks/endpoints.yaml

endpoints:
  core:
    api:
      host: my-app-api
      port: 8080
    
  databases:
    postgres:
      host: postgres-server
      port: 5432
```

## Configuring Secrets

> **Important:** Secrets are stored in the global `.secrets/` directory at swarmcli root, not in profiles!

```bash
# Create directory (if not exists)
mkdir -p .secrets
chmod 700 .secrets

# Ensure .secrets in .gitignore
grep -q "^\.secrets/$" .gitignore || echo ".secrets/" >> .gitignore

# Create secret via CLI (recommended)
swarmcli secret create db_password --value "super_secret_password"

# Or manually
echo -n "super_secret_password" > .secrets/db_password
chmod 600 .secrets/db_password
```

## Activating Profile

```bash
# On server
swarmcli use my-new-server

# Verify
swarmcli use --show
# Current default profile: my-new-server

# Or via flag
swarmcli ls --profile my-new-server
```

## Verifying Profile

```bash
# Profile information
swarmcli profile inspect my-new-server

# Check dependencies
swarmcli system health

# List stacks (should be empty for new profile)
swarmcli ls
```

## Best Practices

### 1. Naming

```
server-<role>
├── server-dev
├── server-staging
├── server-prod
├── server-db
└── server-ml
```

### 2. One Profile per Server

Each server has its own active profile:

```bash
# On dev server
swarmcli use server-dev

# On prod server
swarmcli use server-prod
```

### 3. Secrets — Global for Server

Secrets stored in `.secrets/` at swarmcli root. Each server has its own files:

```bash
# On dev server
.secrets/db_password  # dev password

# On prod server (different machine)
.secrets/db_password  # prod password (different!)
```

### 4. Different Globals for Environments

```yaml
# server-dev/stacks/globals.yaml
LOG_LEVEL: DEBUG
PLATFORM_ENV: development

# server-prod/stacks/globals.yaml
LOG_LEVEL: WARN
PLATFORM_ENV: production
```

## Next Step

→ [Creating a Stack](../stacks/00-create-stack.md)
