# Basic Deploy

Main deployment scenarios with SwarmCLI.

## Simple Deploy

```bash
swarmcli deploy my-app
```

What happens:
1. Configuration validation
2. Git repository sync
3. Docker image build
4. Deploy to Swarm
5. Wait for readiness

## Deploy with Flags

### Override Profile

By default, SwarmCLI uses the profile saved via `swarmcli use`. Use `--profile` only to override it for a single command:

```bash
swarmcli deploy my-app --profile server-prod
```

### Specific Service

```bash
swarmcli deploy my-app --service api
```

### Specific Branch for Service

```bash
# Service from feature branch
swarmcli deploy my-app --service api --branch feature/new-api

# Multiple services with different branches
swarmcli deploy my-app \
  --service api --branch feature/auth \
  --service web --branch hotfix/css \
  --service worker
```

### Specific Commit for Service

```bash
# Service to specific commit (requires --branch)
swarmcli deploy my-app --service api --branch feature/auth --commit abc1234
```

### With Secret Sync

```bash
swarmcli deploy my-app --with-secrets
```

## Deploy Modes

### Full Deploy (default)

```bash
swarmcli deploy my-app
```

- ✓ Sync repos
- ✓ Build images
- ✓ Deploy

### Config Only

```bash
swarmcli deploy my-app --config-only
```

- ✗ Sync repos (skipped)
- ✗ Build images (skipped)
- ✓ Deploy with current tags

**When to use:** changed `variables.yaml` or `docker-stack.yml`, code unchanged.

### No Build

```bash
swarmcli deploy my-app --no-build
```

- ✓ Sync repos (to get SHA)
- ✗ Build images (skipped)
- ✓ Deploy

**When to use:** images already built (CI/CD).

### Force Rebuild

```bash
swarmcli deploy my-app --force
```

- ✓ Sync repos
- ✓ Build images (no cache)
- ✓ Deploy

**When to use:** cache issues, need clean build.

### Dry Run

```bash
swarmcli deploy my-app --dry-run
```

Shows plan without execution. Useful for verification.

## Deploy from CI/CD

> The default profile is already set on the server via `swarmcli use`. You do **not** need `--profile` unless you deploy to multiple servers from one runner.

### Basic Pipeline

```yaml
# .gitlab-ci.yml
deploy:
  stage: deploy
  script:
    - swarmcli deploy my-app
  only:
    - develop
```

### With CI Variables for Specific Service

```yaml
deploy:
  stage: deploy
  script:
    - swarmcli deploy my-app
        --service api --branch $CI_COMMIT_BRANCH --commit $CI_COMMIT_SHA
  only:
    - main
```

### Using GitHub Actions

```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: swarmcli deploy my-app
```

## Deploy Monitoring

### Status During Deploy

```
🔍 Checking configurations...
   ✅ Configurations valid

🔄 Syncing repositories...
   ✅ Repositories synced

🔨 Building images...
   ✅ Images built

🚀 Deploying stack...
waiting for services to be ready (timeout: 30s)
  my-app_api: 1/2 (waiting...)
  my-app_api: 2/2 (ready)
   ✅ Stack deployed

   ✅ Deploy completed successfully
   ├─ Stack: my-app
   ├─ Services: 3
   └─ Time: 45s
```

### Logs After Deploy

```bash
# Logs for specific service
swarmcli logs my-app --service api

# Follow mode
swarmcli logs my-app --service api -f
```

## Rollback

On issues:

```bash
# Rollback to previous version
swarmcli rollback my-app

# Rollback 2 versions back
swarmcli rollback my-app --to-version 2
```

## Deploying Multiple Stacks

### Sequentially

```bash
swarmcli deploy backend
swarmcli deploy frontend
swarmcli deploy monitoring
```

### By Changed Files

```bash
# Show changed stacks
swarmcli diff

# Deploy changed
swarmcli apply
```

## Pre-Deploy Checklist

- [ ] Configuration valid: `swarmcli check my-app`
- [ ] Secrets created: `swarmcli secret check my-app`
- [ ] Resources specified in `resources.yaml`
- [ ] Dry-run successful: `swarmcli deploy my-app --dry-run`
- [ ] Rollback available (deploy history)

## Troubleshooting

### "timeout waiting for services"

```bash
# Check logs
docker service logs my-app_api --tail 50

# Check tasks
docker service ps my-app_api --no-trunc
```

### "build failed"

```bash
# Try with clean cache
swarmcli deploy my-app --force --no-cache
```

### "cannot acquire lock"

```bash
# Check locks
swarmcli lock ls

# Force release
swarmcli lock rm my-app
```

## Next Step

→ [Advanced Deploy](01-advanced-deploy.md)
