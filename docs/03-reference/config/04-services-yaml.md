# services.yaml

Stack service definitions.

## Location

```
profiles/<profile>/stacks/<stack>/services.yaml
```

## Format

```yaml
services:
  <service-name>:
    type: git | registry | none  # Service type
    repo: <git-url>              # Git URL (for type: git)
    default_branch: <branch>     # Default branch
    build:                       # Build settings (for type: git)
      context: .
      dockerfile: Dockerfile
      build_args:
        KEY: value
    image: <image-name>          # Image name
    meta:                        # Metadata for Dozzle
      group: <group>
      name: <display-name>
```

## Service Types

### type: git

Service is built from a Git repository. Supports SSH and HTTPS URLs (including public repos that need no auth):

```yaml
services:
  api:
    type: git
    repo: https://github.com/your-org/api.git   # HTTPS (or git@... for SSH)
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

**CLI actions:** clone → checkout → build → deploy

> Public HTTPS repositories work without any token configuration. For private repos, set `GIT_HTTP_TOKEN` or configure `git.http_token` in `.swarmcli.yaml`.

### type: registry

Service from Docker Registry:

```yaml
services:
  redis:
    type: registry
    image: redis:7-alpine
    meta:
      group: cache
```

**CLI actions:** deploy (no build)

### type: none

Derived service that reuses an image built by a `type: git` service. Use this when multiple Compose services share the same codebase but run with different commands:

```yaml
services:
  api:
    type: git
    repo: https://github.com/your-org/backend.git
    image: local/backend

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

**CLI actions:** deploy only (no sync, no build)

In `docker-stack.yml`, derived services reference the same image and `TAG_*` variable as the git service they depend on:

```yaml
services:
  api:
    image: local/backend:${TAG_API}
    command: ["./app", "serve"]
  worker:
    image: local/backend:${TAG_API}
    command: ["./app", "worker"]
```

## Fields

### Common

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | Yes | `git`, `registry`, or `none` |
| `image` | string | Yes (git, registry) | Docker image name (not used for `type: none`) |
| `meta.group` | string | No | Group for Dozzle |
| `meta.name` | string | No | Display name |
| `meta.description` | string | No | Service description |

### For type: git

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `repo` | string | Yes | Git repository URL (HTTPS or SSH) |
| `default_branch` | string | No | Default branch (falls back to profile `git.default_branch`, then `main`) |
| `build.context` | string | No | Build context (default: `.`) |
| `build.dockerfile` | string | No | Path to Dockerfile (default: `Dockerfile`) |
| `build.build_args` | map | No | Build arguments |

## Examples

### Simple git service (HTTPS, public repo)

```yaml
services:
  whoami:
    type: git
    repo: https://github.com/traefik/whoami.git
    default_branch: master
    image: local/whoami
```

### Git service with full configuration

```yaml
services:
  api:
    type: git
    repo: https://github.com/your-org/api.git
    default_branch: develop
    build:
      context: ./backend
      dockerfile: Dockerfile.prod
      build_args:
        NODE_ENV: production
        NPM_TOKEN: ${NPM_TOKEN}
    image: local/api
    meta:
      group: core
      name: Backend API
```

### Git service with SSH

```yaml
services:
  api:
    type: git
    repo: git@github.com:your-org/api.git
    image: local/api
```

### Multiple images from one repo (monorepo)

```yaml
services:
  api:
    type: git
    repo: https://github.com/your-org/backend.git
    build:
      dockerfile: Dockerfile
    image: local/api
  
  worker:
    type: git
    repo: https://github.com/your-org/backend.git
    build:
      dockerfile: Dockerfile.worker
    image: local/worker
```

### Derived services (type: none)

When multiple Compose services share one built image:

```yaml
services:
  api:
    type: git
    repo: https://github.com/your-org/backend.git
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

### Public registry image

```yaml
services:
  redis:
    type: registry
    image: redis:7-alpine
    meta:
      group: infrastructure
```

### Private registry

```yaml
services:
  licensed-app:
    type: registry
    image: registry.company.com/app:1.0
    meta:
      group: licensed
```

### Microservices from different repos

```yaml
services:
  user-service:
    type: git
    repo: https://github.com/your-org/user-service.git
    image: local/user-service
    meta:
      group: microservices
      name: User Service
  
  order-service:
    type: git
    repo: git@github.com:your-org/order-service.git
    image: local/order-service
    meta:
      group: microservices
      name: Order Service
```

## Dozzle Labels

Labels are generated from the `meta` section:

```yaml
meta:
  group: backend
  name: API Service
```

Result in docker-stack.yml:

```yaml
deploy:
  labels:
    dev.dozzle.group: backend
    dev.dozzle.name: API Service
```

## Image Tags

For `type: git` services, SwarmCLI generates environment variables:

```
TAG_<SERVICE> = <profile>-<commit_sha>
```

The service name is **uppercased** and **hyphens are replaced with underscores**:

| Service | Variable | Example |
|---------|----------|---------|
| `api` | `TAG_API` | `server-dev-abc1234` |
| `user-service` | `TAG_USER_SERVICE` | `server-dev-abc1234` |

Usage in docker-stack.yml:

```yaml
services:
  api:
    image: local/api:${TAG_API}
  user-service:
    image: local/user-service:${TAG_USER_SERVICE}
```

> `TAG_*` variables are only exported for `type: git` services. `type: registry` services use a fixed tag; `type: none` services share the tag of their parent git service.

## Validation

```bash
swarmcli check my-app
```

## See also

- [Git-Based Stack Workflow](../../02-guides/stacks/02-git-workflow.md) — end-to-end guide
- [Adding services](../../02-guides/stacks/01-add-services.md)
- [variables.yaml](05-variables-yaml.md)
- [settings.yaml](07-settings-yaml.md) — per-stack git auth override
