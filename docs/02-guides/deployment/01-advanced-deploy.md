# Advanced Deploy

Extended deployment scenarios and techniques.

## Deploy with Hooks

### Pre-deploy Hook

Runs **before** `docker stack deploy`:

```bash
#!/usr/bin/env bash
# hooks/pre-deploy.sh

set -e

echo "Pre-deploy: $STACK"

# Check dependencies
curl -s --fail http://dependency-service/health || {
    echo "Dependency service is down!"
    exit 1
}

# Database migration
docker exec -i postgres psql -U app -d mydb << SQL
    SELECT 1;
SQL

# Deploy start notification
curl -X POST "https://slack.com/webhook" \
  -d '{"text":"Starting deploy of '"$STACK"'"}'
```

### Post-deploy Hook

Runs **after** successful deploy:

```bash
#!/usr/bin/env bash
# hooks/post-deploy.sh

echo "Post-deploy: $STACK"

# Clear cache
docker exec redis redis-cli FLUSHDB

# Warm cache
curl -s http://localhost:8080/api/warmup

# Success notification
curl -X POST "https://slack.com/webhook" \
  -d '{"text":"Deploy of '"$STACK"' completed!"}'
```

## Deploy with Branch Override

### All Services from One Branch

```bash
swarmcli deploy my-app --branch feature/new-api
```

### Different Branches for Different Services

```bash
swarmcli deploy my-app \
  --service api --branch feature/new-api \
  --service worker --branch develop
```

### Deploy Specific Commit

```bash
swarmcli deploy my-app --service api --branch feature/new-api --commit abc1234
```

## Zero-Downtime Deploy

### update_config Settings

```yaml
# docker-stack.yml
services:
  api:
    deploy:
      replicas: 3
      update_config:
        parallelism: 1          # 1 replica at a time
        delay: 30s               # Delay between
        failure_action: rollback
        monitor: 60s             # Monitor after update
        order: start-first       # New first, then old
```

### Healthcheck

```yaml
services:
  api:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s
```

## Canary Deploy

Manual canary with separate stack:

```bash
# 1. Deploy canary version
swarmcli deploy my-app-canary --branch feature/new

# 2. Route part of traffic (via nginx/traefik)

# 3. Monitor

# 4. Full deploy or rollback
swarmcli deploy my-app --branch feature/new
# or
docker stack rm my-app-canary
```

## Blue-Green Deploy

```bash
# 1. Current version: my-app-blue (port 8080)
# 2. Deploy new: my-app-green (port 8081)
swarmcli deploy my-app-green --branch new-version

# 3. Test on port 8081

# 4. Switch traffic (via nginx/load balancer)

# 5. Remove old version
docker stack rm my-app-blue
```

## Deploy with Custom Variables

### Via Environment Variables

```bash
export BUILD_VERSION="1.2.3"
export RUNTIME_FEATURE_FLAG=true

swarmcli deploy my-app
```

### In variables.yaml

```yaml
# variables.yaml
build:
  VERSION: ${BUILD_VERSION:-0.0.0}

runtime:
  env:
    FEATURE_FLAG: ${RUNTIME_FEATURE_FLAG:-false}
```

## Deploy Only Changed Stacks

### View Changes

```bash
swarmcli diff --since HEAD~5
```

```
Profile: server-dev
Comparing: HEAD~5..HEAD

Changed stacks:

  ● backend
      └─ variables.yaml
      └─ docker-stack.yml

  ● frontend
      └─ services.yaml

total: 2 stack(s) with config changes
```

### Apply Changes

```bash
swarmcli apply
```

Deploys only changed stacks in `--config-only` mode.

## Automatic Rollback

### On Healthcheck Error

```yaml
services:
  api:
    deploy:
      update_config:
        failure_action: rollback
```

### Manual Rollback

```bash
# To previous version
swarmcli rollback my-app

# To specific version
swarmcli rollback my-app --to-version 3
```

### Dry-run Rollback

```bash
swarmcli rollback my-app --dry-run
```

## Parallel Build

SwarmCLI builds services sequentially, but Docker BuildKit parallelizes layers:

```bash
export DOCKER_BUILDKIT=1
swarmcli deploy my-app
```

## Build Caching

### Docker Layer Cache

```dockerfile
# Dockerfile - cache optimization
FROM node:18-alpine

WORKDIR /app

# Dependencies first (rarely change)
COPY package*.json ./
RUN npm ci --only=production

# Code last (changes often)
COPY . .

CMD ["node", "server.js"]
```

### BuildKit Cache Mounts

```dockerfile
RUN --mount=type=cache,target=/root/.npm \
    npm ci --only=production
```

## Deploy with Prune

Clean old images after deploy:

```bash
swarmcli deploy my-app --prune
```

Removes images, keeping `keep_images_count` versions (from config.yaml).

## Monitoring and Alerts

### Slack Integration

```bash
#!/usr/bin/env bash
# hooks/post-deploy.sh

STATUS="success"
COLOR="good"

# Check status
docker service ls --filter "name=${STACK}_" | grep -q "0/" && {
    STATUS="warning"
    COLOR="warning"
}

curl -X POST "$SLACK_WEBHOOK_URL" \
  -H 'Content-Type: application/json' \
  -d '{
    "attachments": [{
      "color": "'"$COLOR"'",
      "title": "Deploy '"$STACK"'",
      "text": "Status: '"$STATUS"'",
      "footer": "SwarmCLI"
    }]
  }'
```

### JSON Output for Automation

```bash
swarmcli deploy my-app --json
```

```json
{
  "status": "success",
  "stack": "my-app",
  "profile": "server-dev",
  "duration_ms": 45000,
  "services": [...]
}
```

## Best Practices

### 1. Test on Dev Before Prod

```bash
swarmcli deploy my-app --profile server-dev
# Testing
swarmcli deploy my-app --profile server-prod
```

### 2. Use Dry-run

```bash
swarmcli deploy my-app --dry-run
```

### 3. Configure Healthcheck

Without healthcheck Swarm doesn't know when service is ready.

### 4. Keep History

Don't delete `.deploy/` folders in stacks — foundation for rollback.

### 5. Monitor After Deploy

```bash
# In separate terminal
watch docker service ls
```

## Next Step

→ [CI/CD integration](../../05-operations/gitlab-ci/)
