# Services

A service is a stack component that runs as a Docker container.

## Service Types

SwarmCLI distinguishes three service types:

```mermaid
graph LR
    subgraph gitSvc ["Internal (type: git)"]
        G[Git Repo] --> B[Build]
        B --> I[Local Image]
        I --> D[Deploy]
    end
    
    subgraph regSvc ["External (type: registry)"]
        R[Docker Registry] --> D2[Deploy]
    end

    subgraph noneSvc ["Derived (type: none)"]
        I2["Reuses image<br/>from git service"] --> D3[Deploy]
    end
```

### Internal Service (type: git)

Service built from a Git repository. Supports both SSH and HTTPS URLs, including public repositories that require no authentication:

```yaml
# services.yaml
services:
  api:
    type: git
    repo: https://github.com/your-org/api.git  # HTTPS (or git@... for SSH)
    default_branch: develop
    build:
      context: .
      dockerfile: Dockerfile
      build_args:
        NODE_ENV: production
    image: local/api
    meta:
      group: backend
      name: API Service
```

**What CLI does:**
1. Clones/updates repository (`swarmcli sync`)
2. Builds image (`docker build`)
3. Generates tag: `<profile>-<commit_sha>`
4. Deploys with this tag

> **Note:** Public HTTPS repositories work without any token configuration. For private repos, set `GIT_HTTP_TOKEN` or configure credentials in `.swarmcli.yaml`.

### External Service (type: registry)

Service from Docker Registry (Docker Hub, GitLab Registry, etc.):

```yaml
services:
  redis:
    type: registry
    image: redis:7-alpine
    meta:
      group: cache
```

**What CLI does:**
- Deploys directly (no build)
- Image is pulled from Registry

### Derived Service (type: none)

Service that reuses an image built by another `type: git` service. Useful when the same codebase produces multiple services with different commands (API, worker, scheduler):

```yaml
services:
  api:
    type: git
    repo: https://github.com/your-org/backend.git
    build:
      context: .
      dockerfile: Dockerfile
    image: local/backend
    meta:
      group: core
      name: Backend API

  worker:
    type: none
    meta:
      group: core
      name: Background Worker

  scheduler:
    type: none
    meta:
      group: core
      name: Task Scheduler
```

**What CLI does:**
- Skips sync and build (no repository, no separate image)
- Deploys as part of `docker stack deploy`

In `docker-stack.yml`, derived services reference the same image as the git service:

```yaml
services:
  api:
    image: local/backend:${TAG_API}
    command: ["./app", "serve"]
  worker:
    image: local/backend:${TAG_API}
    command: ["./app", "worker"]
  scheduler:
    image: local/backend:${TAG_API}
    command: ["./app", "scheduler"]
```

## services.yaml Structure

### Full Example

```yaml
services:
  # === Internal services (type: git) ===
  
  api:
    type: git
    repo: https://github.com/your-org/backend.git    # HTTPS
    default_branch: develop
    build:
      context: .
      dockerfile: Dockerfile
      build_args:
        NODE_ENV: production
        BUILD_VERSION: ${BUILD_VERSION}
    image: local/api
    meta:
      group: core
      name: Backend API
  
  # === Derived services (type: none) — same image, different CMD ===
  
  worker:
    type: none
    meta:
      group: core
      name: Background Worker
  
  scheduler:
    type: none
    meta:
      group: core
      name: Task Scheduler
  
  # === External services (type: registry) ===
  
  redis:
    type: registry
    image: redis:7-alpine
    meta:
      group: infrastructure
  
  postgres:
    type: registry
    image: postgres:15
    meta:
      group: databases
      name: PostgreSQL
```

## services.yaml Fields

### Common Fields

| Field | Type | Description |
|-------|------|-------------|
| `type` | `git` \| `registry` \| `none` | Service type (required) |
| `image` | string | Image name (not used for `type: none`) |
| `meta.group` | string | Group for Dozzle labels |
| `meta.name` | string | Display name |

### Fields for type: git

| Field | Type | Description |
|-------|------|-------------|
| `repo` | string | Git repository URL |
| `default_branch` | string | Default branch |
| `build.context` | string | Build context (default: `.`) |
| `build.dockerfile` | string | Dockerfile path (default: `Dockerfile`) |
| `build.build_args` | map | Build arguments |

## Dozzle Labels

SwarmCLI automatically generates labels for [Dozzle](https://github.com/amir20/dozzle):

```yaml
# services.yaml
services:
  api:
    type: git
    meta:
      group: backend        # → dev.dozzle.group: backend
      name: API Service     # → dev.dozzle.name: API Service
```

Result in docker-stack.yml:

```yaml
deploy:
  labels:
    dev.dozzle.group: backend
    dev.dozzle.name: API Service
```

## Use Cases

### One Repo — Multiple Images (monorepo)

```yaml
services:
  api:
    type: git
    repo: https://github.com/your-org/monorepo.git
    build:
      context: ./services/api
      dockerfile: Dockerfile
    image: local/api
  
  worker:
    type: git
    repo: https://github.com/your-org/monorepo.git
    build:
      context: ./services/worker
      dockerfile: Dockerfile
    image: local/worker
```

### One Repo — One Image — Multiple Services (derived)

When multiple Compose services use the same built image with different commands:

```yaml
services:
  api:
    type: git
    repo: https://github.com/your-org/backend.git
    image: local/backend

  worker:
    type: none    # reuses local/backend image

  scheduler:
    type: none    # reuses local/backend image
```

### Microservices from Different Repos

```yaml
services:
  user-service:
    type: git
    repo: https://github.com/your-org/user-service.git
    image: local/user-service
  
  order-service:
    type: git
    repo: git@github.com:your-org/order-service.git   # SSH also works
    image: local/order-service
```

### Public Repository (no auth required)

```yaml
services:
  whoami:
    type: git
    repo: https://github.com/traefik/whoami.git
    default_branch: master
    image: local/whoami
```

### Your Application + Public Images

```yaml
services:
  api:
    type: git
    repo: https://github.com/your-org/api.git
    image: local/api
  
  redis:
    type: registry
    image: redis:7-alpine
  
  postgres:
    type: registry
    image: postgres:15
```

## Image Tags

### Tag Generation

For `type: git` services, SwarmCLI generates an environment variable:

```
TAG_<SERVICE> = <profile>-<commit_sha>
```

The service name is **uppercased** and **hyphens become underscores**:

```bash
# Commit abc1234 on server-dev
TAG_API=server-dev-abc1234            # service: api
TAG_USER_SERVICE=server-dev-abc1234   # service: user-service
```

> **Note:** `TAG_*` variables are only generated for `type: git` services. `type: registry` and `type: none` services do not get their own tag variable.

### Usage in docker-stack.yml

```yaml
services:
  api:
    image: local/api:${TAG_API}
  
  worker:
    image: local/worker:${TAG_WORKER}
  
  # External services don't need tag
  redis:
    image: redis:7-alpine
```

### Branch Override

```bash
# Specific service from feature branch
swarmcli deploy my-app --service api --branch feature/new-api

# Multiple services from different branches
swarmcli deploy my-app \
  --service api --branch feature/new-api \
  --service worker --branch hotfix/fix
```

## Build Args

### Static Arguments

```yaml
services:
  api:
    build:
      build_args:
        NODE_ENV: production
        API_VERSION: "2.0"
```

### Dynamic Arguments

From `variables.yaml`:

```yaml
# variables.yaml
build:
  NPM_TOKEN: ${NPM_TOKEN}     # From env
  BUILD_DATE: ${BUILD_DATE}    # From env
```

SwarmCLI passes them to `docker build --build-arg`.

## Validation

```bash
# Check services.yaml
swarmcli check my-app
```

Checks:
- Required fields present
- Valid type
- Repository accessibility (for git)

## Best Practices

### 1. Specify type Explicitly

```yaml
# Good
services:
  api:
    type: git
    ...

# Bad (implicit)
services:
  api:
    repo: git@...
```

### 2. Use meta for Dozzle

```yaml
meta:
  group: backend
  name: User API
```

### 3. Group Logically

```
group: core         # Core services
group: analytics    # Analytics
group: infrastructure  # Redis, RabbitMQ
group: databases    # PostgreSQL, MongoDB
```

### 4. Name Images Consistently

```yaml
image: local/api            # Local images
image: local/worker
image: registry.com/api     # Private registry
```

## Next Step

→ [Git-Based Stack Workflow](../02-guides/stacks/02-git-workflow.md) — end-to-end guide for git services
→ [Deploy Flow](06-deploy-flow.md) — detailed deploy flow
