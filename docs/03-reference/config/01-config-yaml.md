# config.yaml

Server profile configuration.

## Location

```
profiles/<profile>/config.yaml
```

## Format

```yaml
# Name and description
name: server-dev
description: Development server configuration

# Docker Swarm settings
swarm:
  services_ready_timeout: 30    # Readiness timeout (sec)
  keep_images_count: 3          # Image versions to keep (also used for deploy history retention)

# Git settings
git:
  default_branch: develop      # Default branch
  http_token: ${GIT_HTTP_TOKEN} # Token for HTTPS

# Retry logic
retry:
  enabled: true                 # Enable retry
  max_attempts: 3               # Max attempts
  initial_delay: 2              # Initial delay (sec)
  max_delay: 30                 # Max delay (sec)
```

## Fields

### Main

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Profile name |
| `description` | string | No | Profile description |

### swarm

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `services_ready_timeout` | int | 30 | Service readiness wait timeout (sec) |
| `keep_images_count` | int | 10 | Number of image versions to keep (also used for deploy history retention) |

### git

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `default_branch` | string | main | Default branch |
| `http_user` | string | - | Username for Deploy Token (optional; expands `${VAR}`) |
| `http_token` | string | - | Token for HTTPS auth (expands `${VAR}`) |

### retry

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | bool | true | Enable retry on errors |
| `max_attempts` | int | 3 | Max attempts |
| `initial_delay` | int | 2 | Initial delay (sec) |
| `max_delay` | int | 30 | Max delay (sec) |

## Examples

### Development

```yaml
name: server-dev
description: Development environment

swarm:
  services_ready_timeout: 30
  keep_images_count: 3

git:
  default_branch: develop

retry:
  enabled: true
  max_attempts: 3
```

### Production

```yaml
name: server-prod
description: Production environment

swarm:
  services_ready_timeout: 120    # More time for prod
  keep_images_count: 10          # More versions for rollback

git:
  default_branch: main

retry:
  enabled: true
  max_attempts: 5                # More attempts
  initial_delay: 5
  max_delay: 60
```

### Minimal

```yaml
name: my-server

swarm:
  services_ready_timeout: 30

git:
  default_branch: main
```

## Environment Variables

Fields can use variables:

```yaml
git:
  http_token: ${GIT_HTTP_TOKEN}
```

When loading the profile, `${GIT_HTTP_TOKEN}` will be replaced with the value from env.

## Loading

Profile is loaded when:
- Specifying `--profile <name>`
- Running `swarmcli use <profile>`
- Setting `SWARM_PROFILE` variable

## See also

- [Creating a profile](../../02-guides/profiles/00-create-profile.md)
- [globals.yaml](02-globals-yaml.md)
