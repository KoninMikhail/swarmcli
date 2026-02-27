# globals.yaml

Global variables for all stacks in a profile.

## Location

```
profiles/<profile>/stacks/globals.yaml
```

## Format

```yaml
# Simple key-value pairs
TZ: Europe/Moscow
PLATFORM_ENV: development
LOG_LEVEL: DEBUG
DOMAIN: dev.example.com
```

## Description

Variables from `globals.yaml` are exported with the `GLOBAL_` prefix and are available in all stacks of the profile.

## Usage

### In docker-stack.yml

```yaml
services:
  api:
    environment:
      - TZ=${GLOBAL_TZ}
      - LOG_LEVEL=${GLOBAL_LOG_LEVEL}
      - DOMAIN=${GLOBAL_DOMAIN}
```

### In variables.yaml

```yaml
runtime:
  env:
    FULL_URL: https://${GLOBAL_DOMAIN}/api
```

## Examples

### Development

```yaml
# profiles/server-dev/stacks/globals.yaml
TZ: Europe/Moscow
PLATFORM_ENV: development
LOG_LEVEL: DEBUG
DOMAIN: dev.example.com
DEBUG_MODE: "true"
```

### Production

```yaml
# profiles/server-prod/stacks/globals.yaml
TZ: Europe/Moscow
PLATFORM_ENV: production
LOG_LEVEL: WARN
DOMAIN: app.example.com
DEBUG_MODE: "false"
```

## Typical Variables

| Variable | Description |
|----------|-------------|
| `TZ` | Timezone (Europe/Moscow, UTC, etc.) |
| `PLATFORM_ENV` | Environment (development, staging, production) |
| `LOG_LEVEL` | Log level (DEBUG, INFO, WARN, ERROR) |
| `DOMAIN` | Primary domain |
| `DEBUG_MODE` | Debug mode (true/false) |

## Best Practices

### 1. Only common variables

Put in globals.yaml only variables common to all stacks:

```yaml
# ✓ Good — common for all
TZ: Europe/Moscow
LOG_LEVEL: DEBUG

# ✗ Bad — stack-specific
API_DATABASE_URL: postgres://...
```

### 2. No secrets

```yaml
# ✗ Never!
DB_PASSWORD: secret123

# ✓ Use Docker Secrets
```

### 3. String values

```yaml
# ✓ Safe
DEBUG: "true"
PORT: "8080"

# ⚠️ May cause parsing issues
DEBUG: true
PORT: 8080
```

## See also

- [config.yaml](01-config-yaml.md)
- [variables.yaml](05-variables-yaml.md)
