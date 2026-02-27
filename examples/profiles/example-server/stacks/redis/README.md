# Redis — Cache / Queue

In-memory store for caching and task queues based on [Redis 7](https://redis.io/).

## What It Demonstrates

- **Minimal stack** — smallest possible set of files (3 files)
- **`type: registry`** — ready image `redis:7-alpine` from DockerHub
- **No secrets or configs** — simplest configuration
- **Healthcheck** — `redis-cli ping`
- **Volume** — persistence via AOF (append-only file)
- **Inline configuration** — Redis parameters via `command`

## Files

```
redis/
├── services.yaml       — registry service
├── settings.yaml       — fast startup (15 sec)
├── docker-stack.yml    — Docker Compose for Swarm
└── README.md
```

## Why No externals.yaml

This is intentional — the stack demonstrates minimal configuration. In production, add a password via secrets.

## Configuration via command

Instead of a separate config file, Redis parameters are passed via `command`:

```yaml
command: redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru
```

- `--appendonly yes` — persistence via AOF
- `--maxmemory 256mb` — memory limit
- `--maxmemory-policy allkeys-lru` — LRU eviction when limit is reached

## Connecting from Other Stacks

```yaml
# In another stack's variables.yaml
REDIS_URL: redis://${SERVICE_DATABASES_REDIS_HOST}:${SERVICE_DATABASES_REDIS_PORT}
# → redis://redis:6379
```
