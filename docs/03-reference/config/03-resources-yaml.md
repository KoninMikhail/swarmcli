# resources.yaml

Centralized CPU/Memory resource management.

## Location

```
profiles/<profile>/stacks/resources.yaml
```

## Format

```yaml
stacks:
  <stack-name>:
    <service-name>:
      limits:
        cpus: "2.0"
        memory: "2G"
      reservations:
        cpus: "0.5"
        memory: "512M"
```

## Fields

### limits

Hard limits — service cannot use more:

| Field | Type | Example | Description |
|-------|------|---------|-------------|
| `cpus` | string | `"2.0"` | Max CPU cores |
| `memory` | string | `"2G"` | Max memory |

### reservations

Guaranteed resources — service always gets minimum:

| Field | Type | Example | Description |
|-------|------|---------|-------------|
| `cpus` | string | `"0.5"` | Min CPU cores |
| `memory` | string | `"512M"` | Min memory |

## Value Formats

### CPU

```yaml
cpus: "0.5"    # Half core
cpus: "1.0"    # One core
cpus: "2.0"    # Two cores
cpus: "0.25"   # Quarter core
```

### Memory

```yaml
memory: "256M"   # 256 megabytes
memory: "512M"   # 512 megabytes
memory: "1G"     # 1 gigabyte
memory: "2G"     # 2 gigabytes
memory: "4096M"  # 4 gigabytes
```

## Example

```yaml
# profiles/server-dev/stacks/resources.yaml

stacks:
  backend:
    api:
      limits:
        cpus: "2.0"
        memory: "2G"
      reservations:
        cpus: "0.5"
        memory: "512M"
    
    worker:
      limits:
        cpus: "1.0"
        memory: "1G"
      reservations:
        cpus: "0.25"
        memory: "256M"
  
  frontend:
    nginx:
      limits:
        cpus: "0.5"
        memory: "256M"
    
    app:
      limits:
        cpus: "1.0"
        memory: "1G"
  
  infrastructure:
    redis:
      limits:
        cpus: "1.0"
        memory: "1G"
    
    postgres:
      limits:
        cpus: "2.0"
        memory: "4G"
      reservations:
        cpus: "1.0"
        memory: "2G"
```

## How Injection Works

For stacks with j2 templates (`templates.yaml`) resources are injected via the `deploy_resources()` function in the template.

For legacy stacks (without j2) resources must be specified directly in docker-stack.yml.

Example for j2 templates:

### Before

```yaml
# docker-stack.yml
services:
  api:
    image: local/api:${TAG_API}
```

### After (on deploy)

```yaml
services:
  api:
    image: local/api:${TAG_API}
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: "2G"
        reservations:
          cpus: "0.5"
          memory: "512M"
```

## Different Resources for dev/prod

```yaml
# profiles/server-dev/stacks/resources.yaml
stacks:
  backend:
    api:
      limits:
        cpus: "1.0"
        memory: "1G"

# profiles/server-prod/stacks/resources.yaml
stacks:
  backend:
    api:
      limits:
        cpus: "4.0"
        memory: "8G"
      reservations:
        cpus: "2.0"
        memory: "4G"
```

## Best Practices

### 1. Always specify limits

Without limits a service can use all server resources.

### 2. Use reservations for critical services

```yaml
postgres:
  reservations:
    cpus: "1.0"
    memory: "2G"
```

### 3. Leave headroom for the system

On a 16GB RAM server don't allocate all 16GB to services.

### 4. CPU in quotes

```yaml
# ✓ Correct
cpus: "2.0"

# ⚠️ May cause parsing error
cpus: 2.0
```

## Troubleshooting

### Service won't start

Check if there are enough resources:

```bash
docker node ls
docker info | grep -E "CPUs|Memory"
```

### OOMKilled

Increase memory limit:

```yaml
memory: "4G"  # Was 2G
```

## See also

- [Resource management](../../02-guides/resources/00-overview.md)
