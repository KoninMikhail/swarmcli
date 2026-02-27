# deploy

Deploy stack to Docker Swarm.

## Syntax

```bash
swarmcli deploy [stack] [flags]
```

## Description

The `deploy` command runs the full deploy cycle:

1. Configuration validation
2. Git repository sync
3. Docker image build
4. Deploy to Docker Swarm
5. Wait for service readiness

## Arguments

| Argument | Description |
|----------|-------------|
| `stack` | Stack name. If not specified — interactive selection |

## Flags

### Service and branch selection

| Flag | Description |
|------|-------------|
| `--service <name>` | Deploy only specified service |
| `--branch <name>` | Branch for previous `--service` |
| `--commit <sha>` | Commit for previous `--service` (requires `--branch`) |

**Important:** Flags `--branch` and `--commit` apply to the last specified `--service`.

### Deploy modes

| Flag | Description |
|------|-------------|
| `--config-only` | Configuration only, no rebuild |
| `--no-build` | Skip image build |
| `--force` | Force rebuild |
| `--no-cache` | No Docker cache |
| `--parallel` | Parallel image build (up to 4 at once) |

### Additional options

| Flag | Description |
|------|-------------|
| `--with-secrets` | Sync secrets before deploy |
| `--prune` | Remove old images after deploy |
| `--dry-run` | Show plan without execution |

## Per-Service Branch/Commit

Specify branch and commit for specific services:

```bash
swarmcli deploy my-app \
  --service api --branch feature/auth --commit abc123 \
  --service web --branch develop \
  --service worker
```

**Rules:**
- `--branch` and `--commit` apply to the last `--service`
- If service has no parameters → uses default branch from `services.yaml`
- `--commit` requires `--branch`
- If only `--branch` specified → uses HEAD of that branch

**Branch resolution priority:**
1. `--service svc --branch xxx`
2. `services.yaml::default_branch`
3. `DEFAULT_BRANCH` (main)

## Examples

### Basic deploy

```bash
# All services from default branches
swarmcli deploy my-app
```

### Deploy from specific profile

```bash
swarmcli deploy my-app --profile server-prod
```

### Deploy specific service

```bash
# API service from its default branch
swarmcli deploy my-app --service api
```

### Deploy service from feature branch

```bash
swarmcli deploy my-app --service api --branch feature/new-api
```

### Deploy service to specific commit

```bash
swarmcli deploy my-app --service api --branch feature/new-api --commit abc1234
```

### Multiple services with different branches

```bash
swarmcli deploy my-app \
  --service api --branch feature/auth \
  --service web --branch hotfix/css \
  --service worker
```

### Apply configuration only

```bash
swarmcli deploy my-app --config-only
```

### Deploy with secret sync

```bash
swarmcli deploy my-app --with-secrets
```

### Force rebuild without cache

```bash
swarmcli deploy my-app --force --no-cache
```

### Parallel build

```bash
# Build up to 4 images simultaneously
# Saves 40-60% time on multi-service stack deploy
swarmcli deploy my-app --parallel
```

### Preview without execution

```bash
swarmcli deploy my-app --dry-run
```

### JSON output

```bash
swarmcli deploy my-app --json
```

## Interactive Mode

If stack is not specified:

```bash
swarmcli deploy
```

SwarmCLI will show:
1. Changed stacks (if any)
2. Stack selection menu

## Output

### Successful deploy

```
🔍 Checking configurations...
   ✅ Configurations valid

🔄 Syncing repositories...
   ✅ Repositories synced

🔨 Building images...
   ✅ Images built

🚀 Deploying stack...
   ✅ Stack deployed

   ✅ Deploy completed successfully
   ├─ Stack: my-app
   ├─ Services: 3
   └─ Time: 45s
```

### Deploy error

```
🚀 Deploying stack...
✗ timeout waiting for services to be ready

╔══════════════════════════════════════════════════════════════════════════════╗
║              DEPLOYMENT FAILURE DIAGNOSTICS                                  ║
╚══════════════════════════════════════════════════════════════════════════════╝

Stack: my-app
Failed services: 1

Service: my-app_api
  Status: 0/2 running
  Last error: task failed: container exited with code 1
  Recent logs:
    Error: Cannot connect to database
```

## Exit Codes

| Code | Description |
|------|-------------|
| 0 | Deploy successful |
| 1 | Validation or configuration error |
| 2 | Build or deploy error |
| 3 | Missing secrets |
| 130 | Deploy cancelled (SIGINT/Cancel) |

## Cancellation Behavior

SwarmCLI supports graceful cancellation — clean termination when deploy is cancelled.

### Mechanism

1. On cancel (Ctrl+C or Cancel in GitLab CI) a `cancel` file is created in lock directory
2. CLI checks this flag every second during long operations
3. On flag detection — clean termination with cleanup
4. Graceful shutdown timeout: 10 seconds, then — forced termination

### Supported stages

| Stage | Behavior on cancel |
|-------|-------------------|
| `validate` | Immediate termination |
| `sync` | Interrupts git clone/fetch |
| `build` | Interrupts docker build, removes dangling images |
| `deploy` | Swarm deploy — atomic operation, may leave partial stack |
| `verify` | Interrupts service readiness wait |

### In GitLab CI

When pressing "Cancel" in GitLab CI:

1. CI sends SIGTERM to SSH session
2. Trap handler creates cancel flag on server
3. Waits for graceful shutdown up to 10 seconds
4. If needed — forced termination

```bash
# View active deploys (and their cancel status)
swarmcli lock ls
```

**Example output after cancel:**
```
⚠️  deployment cancellation detected (reason: gitlab-ci-manual-cancel)
⚠️  cleaning up after cancellation (step: build)
   removing dangling build artifacts...
   cleanup completed
⚠️  deployment cancelled at step: build
```

### Limitations

- Cancel during `docker stack deploy` may leave stack in partial state
- Recommended to check state after cancel: `swarmcli ps <stack>`

## Progress Mode (CI-optimized output)

In GitLab CI, `PROGRESS_MODE=ci` is automatically enabled for structured output.

### What PROGRESS_MODE=ci provides

1. **Build progress** — instead of hundreds of BuildKit log lines:
   - Current build stage every 10 seconds
   - Heartbeat for long operations
   - Completion time for each service

2. **Detailed summary** — at end of deploy:
   - Stack and profile info
   - Number of deployed services
   - Time breakdown by stage (validate, sync, build, deploy, verify)

### Example CI output

```
🔨 Build images

   [  5s] api: #3 [internal] load build definition
   [ 12s] api: #8 [stage-1 3/5] RUN npm install
   [ 45s] api: building...
   [ 78s] api: #12 [stage-2 2/3] COPY --from=builder
   ✓ api built in 127s
   
   [  3s] worker: #3 [internal] load build definition
   [ 45s] worker: building...
   ✓ worker built in 85s

╔════════════════════════════════════════════════════════════════╗
║                    DEPLOYMENT SUCCESSFUL                       ║
╚════════════════════════════════════════════════════════════════╝

  Summary:
    Stack:    my-app
    Profile:  server-dev
    Services: 3 deployed
    Total:    469s

  Timeline:
    validate    5s
    sync       30s
    build     372s
    templates   3s
    deploy     15s
    verify     42s
```

### Local usage

```bash
# Enable CI mode for testing
PROGRESS_MODE=ci swarmcli deploy my-app

# Normal mode (default)
swarmcli deploy my-app
```

### In GitLab CI

Mode is enabled automatically via `deploy.yml` templates. No additional setup needed.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `PROGRESS_MODE` | Output mode: `ci` — structured for CI, otherwise — standard |
| `CI_COMMIT_SHA` | Commit SHA (from GitLab CI) — fallback if `--commit` not specified |
| `COMMIT_SHA` | Commit SHA (alternative) |
| `GIT_HTTP_TOKEN` | Token for HTTPS Git |

## Readiness Timeout

Service readiness timeout is configured:

1. **stack settings.yaml** (highest priority):
```yaml
services_ready_timeout: 120  # 2 minutes
```

2. **profile config.yaml:**
```yaml
swarm:
  services_ready_timeout: 60
```

3. **Default:** 30 seconds

## Important: Per-Service Branch Targeting

Flags `--branch` and `--commit` always require an explicit `--service`:

```bash
# Correct — specify service explicitly
swarmcli deploy stack --service api --branch feature/xxx
swarmcli deploy stack --service api --branch feature/xxx --commit abc123
```

Global `--branch` / `--commit` without `--service` are **not supported**.

## See also

- [rollback](02-rollback.md) — rollback
- [build](03-build.md) — build
- [check](04-check.md) — validation
- [settings.yaml](../config/07-settings-yaml.md) — timeout configuration
