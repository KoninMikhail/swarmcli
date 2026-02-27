# Creating a Stack

Step-by-step guide for creating a new stack.

## Stack Structure

```
stacks/my-app/
├── docker-stack.yml     # Docker Compose for Swarm (or templates/)
├── templates.yaml       # Jinja2 config (optional)
├── templates/           # Jinja2 templates (optional)
│   └── docker-stack.j2
├── services.yaml        # Service descriptions
├── variables.yaml       # Variables
├── externals.yaml       # Secrets and configs
├── settings.yaml        # Settings
├── hooks/
│   ├── pre-deploy.sh    # Before deploy
│   └── post-deploy.sh   # After deploy
├── .build/              # Generated files (server-only)
├── .deploy/             # Deploy history (server-only)
└── .repos/              # Service repositories (server-only)
```

> **Note:** Directories `.build/`, `.deploy/`, `.repos/` are created automatically on deploy and not stored in Git.

## Step 1: Create Structure

```bash
cd /opt/swarmcli/profiles/server-dev/stacks

# Create stack directory
mkdir -p my-app/hooks
cd my-app
```

## Step 2: services.yaml

Stack service descriptions:

```yaml
# services.yaml
services:
  # Service from Git
  api:
    type: git
    repo: git@github.com:your-org/api.git
    default_branch: develop
    build:
      context: .
      dockerfile: Dockerfile
    image: local/api
    meta:
      group: backend
      name: API Service
  
  # Service from Registry
  redis:
    type: registry
    image: redis:7-alpine
    meta:
      group: cache
```

## Step 3: docker-stack.yml

Docker Compose file for Swarm:

```yaml
# docker-stack.yml
services:
  api:
    image: local/api:${TAG_API}
    ports:
      - "8080:8080"
    environment:
      - TZ=${GLOBAL_TZ}
      - LOG_LEVEL=${DEPLOY_LOG_LEVEL}
      - REDIS_HOST=redis
    networks:
      - backend
    deploy:
      replicas: 2
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure
  
  redis:
    image: redis:7-alpine
    networks:
      - backend
    deploy:
      replicas: 1

networks:
  backend:
    driver: overlay
```

## Step 4: variables.yaml

Build and runtime variables:

```yaml
# variables.yaml

# Build variables (docker build --build-arg)
build:
  NODE_ENV: production

# Runtime env (used by inject_env_vars in templates)
runtime:
  env:
    LOG_LEVEL: info
    API_VERSION: "1.0.0"
```

## Step 5: settings.yaml

Stack settings:

```yaml
# settings.yaml

# Readiness timeout (overrides profile)
services_ready_timeout: 45

# Log lines on error
diagnostics_logs_tail: 30
```

## Step 6: externals.yaml

List of required secrets:

```yaml
# externals.yaml
secrets: []  # No secrets needed yet
```

If secrets needed:

```yaml
secrets:
  - db_password
  - api_key
```

## Step 7: Hooks

### pre-deploy.sh

```bash
#!/usr/bin/env bash
# Pre-deploy hook

echo "Pre-deploy: $STACK"

# Example: check dependencies
# curl -s http://dependency-service/health || exit 1
```

### post-deploy.sh

```bash
#!/usr/bin/env bash
# Post-deploy hook

echo "Post-deploy: $STACK"

# Example: notification
# curl -X POST https://hooks.example.com/deploy \
#   -d "{\"stack\":\"$STACK\"}"
```

```bash
# Make executable
chmod +x hooks/*.sh
```

## Step 8: Validation

```bash
cd /opt/swarmcli

# Check configuration
swarmcli check my-app
```

## Step 9: Deploy

```bash
# Dry-run
swarmcli deploy my-app --dry-run

# Deploy
swarmcli deploy my-app
```

## Stack Examples

### Simple Stack (registry only)

```yaml
# services.yaml
services:
  nginx:
    type: registry
    image: nginx:alpine
    meta:
      group: frontend
```

```yaml
# docker-stack.yml
services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
```

### Microservice with Database

```yaml
# services.yaml
services:
  api:
    type: git
    repo: git@github.com:your-org/api.git
    image: local/api
  
  postgres:
    type: registry
    image: postgres:15
```

```yaml
# docker-stack.yml
services:
  api:
    image: local/api:${TAG_API}
    environment:
      - DATABASE_URL=postgres://user:${DB_PASSWORD}@postgres:5432/app
    secrets:
      - db_password
    depends_on:
      - postgres
  
  postgres:
    image: postgres:15
    environment:
      - POSTGRES_PASSWORD_FILE=/run/secrets/db_password
    secrets:
      - db_password
    volumes:
      - pgdata:/var/lib/postgresql/data

secrets:
  db_password:
    external: true

volumes:
  pgdata:
```

### Multi-Service Stack

```yaml
# services.yaml
services:
  api:
    type: git
    repo: git@github.com:your-org/api.git
    image: local/api
  
  worker:
    type: git
    repo: git@github.com:your-org/api.git  # Same repo
    build:
      dockerfile: Dockerfile.worker
    image: local/worker
  
  scheduler:
    type: git
    repo: git@github.com:your-org/api.git  # Same repo
    build:
      dockerfile: Dockerfile.scheduler
    image: local/scheduler
  
  redis:
    type: registry
    image: redis:7-alpine
```

## Using Jinja2 Templates

For more complex stacks, Jinja2 templating is recommended instead of `docker-stack.yml`:

```bash
# Convert docker-stack.yml to Jinja2 template
swarmcli template init my-app
```

This creates:
- `templates.yaml` — configuration
- `templates/docker-stack.j2` — template
- `.build/` — output directory

See: [Jinja2 templating](../templates/00-overview.md)

## Checklist

- [ ] Stack directory created
- [ ] `services.yaml` with service descriptions
- [ ] `docker-stack.yml` or `templates/` with Swarm config
- [ ] `variables.yaml` with variables
- [ ] `settings.yaml` with timeouts
- [ ] `externals.yaml` (even if empty)
- [ ] `hooks/` with pre/post-deploy scripts
- [ ] Hooks executable (`chmod +x`)
- [ ] `swarmcli check` passes

## Next Step

→ [Adding Services](01-add-services.md)
→ [Jinja2 templating](../templates/00-overview.md)
