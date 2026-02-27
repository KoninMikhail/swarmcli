# Adding Services

How to add new services to an existing stack.

## Service Types

### 1. Internal (type: git)

Service from your Git repository:

```yaml
services:
  api:
    type: git
    repo: git@github.com:your-org/api.git
    default_branch: develop
    build:
      context: .
      dockerfile: Dockerfile
    image: local/api
```

### 2. External (type: registry)

Service from Docker Registry:

```yaml
services:
  redis:
    type: registry
    image: redis:7-alpine
```

## Adding a Git Service

### 1. Add to services.yaml

```yaml
services:
  # Existing service
  api:
    type: git
    repo: git@github.com:your-org/api.git
    image: local/api
  
  # NEW service
  notification:
    type: git
    repo: git@github.com:your-org/notification-service.git
    default_branch: develop
    build:
      context: .
      dockerfile: Dockerfile
    image: local/notification
    meta:
      group: services
      name: Notification Service
```

### 2. Add to docker-stack.yml

```yaml
services:
  api:
    image: local/api:${TAG_API}
    # ...
  
  # NEW service
  notification:
    image: local/notification:${TAG_NOTIFICATION}
    environment:
      - TZ=${GLOBAL_TZ}
      - LOG_LEVEL=${LOG_LEVEL}
    networks:
      - backend
    deploy:
      replicas: 1
```

### 3. Deploy

```bash
# Deploy only new service
swarmcli deploy my-app --service notification

# Or entire stack
swarmcli deploy my-app
```

## Adding a Registry Service

### 1. Add to services.yaml

```yaml
services:
  api:
    type: git
    # ...
  
  # NEW external service
  rabbitmq:
    type: registry
    image: rabbitmq:3-management-alpine
    meta:
      group: infrastructure
```

### 2. Add to docker-stack.yml

```yaml
services:
  api:
    # ...
  
  rabbitmq:
    image: rabbitmq:3-management-alpine
    ports:
      - "15672:15672"  # Management UI
    environment:
      - RABBITMQ_DEFAULT_USER=admin
      - RABBITMQ_DEFAULT_PASS_FILE=/run/secrets/rabbitmq_password
    secrets:
      - rabbitmq_password
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    deploy:
      replicas: 1

secrets:
  rabbitmq_password:
    external: true

volumes:
  rabbitmq_data:
```

### 3. Create Secret (if needed)

```bash
swarmcli secret create rabbitmq_password
```

### 4. Add to externals.yaml

```yaml
secrets:
  - rabbitmq_password
```

## Service from Same Repository

Often worker uses the same code as api:

```yaml
services:
  api:
    type: git
    repo: git@github.com:your-org/backend.git
    build:
      context: .
      dockerfile: Dockerfile
    image: local/api
  
  worker:
    type: git
    repo: git@github.com:your-org/backend.git    # Same repo
    build:
      context: .
      dockerfile: Dockerfile.worker          # Different Dockerfile
    image: local/worker
  
  scheduler:
    type: git
    repo: git@github.com:your-org/backend.git    # Same repo
    build:
      context: .
      dockerfile: Dockerfile                 # Can be same
      build_args:
        ENTRYPOINT: scheduler                # Different entrypoint
    image: local/scheduler
```

## Monorepo

For monorepo with multiple services:

```yaml
services:
  user-service:
    type: git
    repo: git@github.com:your-org/monorepo.git
    build:
      context: ./services/user           # Different contexts
      dockerfile: Dockerfile
    image: local/user-service
  
  order-service:
    type: git
    repo: git@github.com:your-org/monorepo.git
    build:
      context: ./services/order          # Different contexts
      dockerfile: Dockerfile
    image: local/order-service
```

## Private Docker Registry

```yaml
services:
  my-licensed-app:
    type: registry
    image: registry.company.com/licensed-app:1.0
    meta:
      group: licensed
```

Ensure Docker is authenticated:

```bash
docker login registry.company.com
```

## Build Args

### Static

```yaml
services:
  api:
    type: git
    build:
      build_args:
        NODE_ENV: production
        API_VERSION: "2.0"
```

### From variables.yaml

```yaml
# services.yaml
services:
  api:
    type: git
    build:
      build_args:
        NPM_TOKEN: ${NPM_TOKEN}

# variables.yaml
build:
  NPM_TOKEN: ${NPM_TOKEN}  # From env
```

## Dozzle Labels

For display in Dozzle:

```yaml
services:
  api:
    type: git
    meta:
      group: backend        # Group
      name: API Service     # Readable name
```

Result:

```yaml
# Injected into docker-stack.yml
deploy:
  labels:
    dev.dozzle.group: backend
    dev.dozzle.name: API Service
```

## Verification

```bash
# Configuration validation
swarmcli check my-app

# View services
swarmcli inspect my-app
```

## Common Errors

### "repository not synced"

```bash
# Sync repositories
swarmcli sync my-app
```

### "image not found"

For registry services check:
- Image name correctness
- Private registry authentication
- Network accessibility

### "undefined variable TAG_*"

`TAG_*` variable is generated only for `type: git` services.

For `type: registry` use full tag:
```yaml
image: redis:7-alpine    # With tag
```

## Next Step

→ [Resource Management](../resources/00-overview.md)
