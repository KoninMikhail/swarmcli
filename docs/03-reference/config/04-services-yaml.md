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
    type: git | registry        # Service type
    repo: <git-url>             # Git URL (for type: git)
    default_branch: <branch>    # Default branch
    build:                      # Build settings (for type: git)
      context: .
      dockerfile: Dockerfile
      build_args:
        KEY: value
    image: <image-name>         # Image name
    meta:                       # Metadata for Dozzle
      group: <group>
      name: <display-name>
```

## Service Types

### type: git

Service is built from a Git repository:

```yaml
services:
  api:
    type: git
    repo: git@github.com:your-org/api.git
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

## Fields

### Common

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | Yes | `git` or `registry` |
| `image` | string | Yes | Docker image name |
| `meta.group` | string | No | Group for Dozzle |
| `meta.name` | string | No | Display name |

### For type: git

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `repo` | string | Yes | Git repository URL |
| `default_branch` | string | No | Default branch |
| `build.context` | string | No | Build context (default: `.`) |
| `build.dockerfile` | string | No | Path to Dockerfile |
| `build.build_args` | map | No | Build arguments |

## Examples

### Simple git service

```yaml
services:
  api:
    type: git
    repo: git@github.com:your-org/api.git
    image: local/api
```

### Git service with full configuration

```yaml
services:
  api:
    type: git
    repo: git@github.com:your-org/api.git
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

### Multiple services from one repo

```yaml
services:
  api:
    type: git
    repo: git@github.com:your-org/backend.git
    build:
      dockerfile: Dockerfile
    image: local/api
  
  worker:
    type: git
    repo: git@github.com:your-org/backend.git
    build:
      dockerfile: Dockerfile.worker
    image: local/worker
```

### Public image

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

### Microservices

```yaml
services:
  user-service:
    type: git
    repo: git@github.com:your-org/user-service.git
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
  
  notification:
    type: git
    repo: git@github.com:your-org/notification.git
    image: local/notification
    meta:
      group: microservices
      name: Notification Service
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

For `type: git` SwarmCLI generates variables:

```
TAG_<SERVICE> = <profile>-<commit_sha>
```

Example:
- `TAG_API=server-dev-abc1234`
- `TAG_WORKER=server-dev-abc1234`

Usage in docker-stack.yml:

```yaml
services:
  api:
    image: local/api:${TAG_API}
```

## Validation

```bash
swarmcli check my-app
```

## See also

- [Adding services](../../02-guides/stacks/01-add-services.md)
- [variables.yaml](05-variables-yaml.md)
