# check

Stack configuration validation.

## Syntax

```bash
swarmcli check [stack]
```

## Description

The `check` command performs full stack configuration validation:

1. YAML file syntax check
2. Configuration structure validation
3. Service type validation
4. SERVICE_* reference validation
5. Secret presence check

## Arguments

| Argument | Description |
|----------|-------------|
| `stack` | Stack name. If not specified — interactive selection |

## Aliases

- `swarmcli validate <stack>`

## Examples

### Check stack

```bash
swarmcli check my-app
```

### Interactive selection

```bash
swarmcli check
```

## Checked Files

| File | Checks |
|------|--------|
| `services.yaml` | Syntax, service types, required fields |
| `variables.yaml` | Syntax |
| `externals.yaml` | Syntax, secret presence |
| `settings.yaml` | Syntax, valid fields |
| `docker-stack.yml` | Syntax, Docker Compose validity |

## Check Types

### 1. YAML Syntax

Syntax validation using Python `yaml.safe_load`:

```bash
# Syntax error
services:
  api:
    type: git
    image  local/api    # ← Missing colon
```

### 2. Service Types

Valid types:
- `git` — build from repository
- `registry` — image from registry

```yaml
# Type error
services:
  api:
    type: external  # ← Unknown type
```

### 3. Required Fields

For `type: git`:
- `repo` — required

```yaml
# Error: missing repo
services:
  api:
    type: git
    image: local/api
```

### 4. SERVICE_* References

Validation of service references in `endpoints.yaml`:

```yaml
# docker-stack.yml
environment:
  API_URL: ${SERVICE_CORE_API_URL}  # ← Presence checked
```

### 5. Secrets

Validation of required secret presence:

```yaml
# externals.yaml
secrets:
  - db_password    # ← File checked
  - api_key
```

## Output

### Successful validation

```
2024-12-22T12:34:56Z [info] validating stack: my-app (profile: server-dev)
2024-12-22T12:34:56Z [ok] all checks passed
{
  "status": "success",
  "operation": "validate",
  "duration_ms": 127,
  "message": "all checks passed"
}
```

### Validation errors

```
2024-12-22T12:34:56Z [info] validating stack: my-app (profile: server-dev)
2024-12-22T12:34:56Z [error] services.yaml: unknown service type 'external' for dozzle
2024-12-22T12:34:56Z [error] externals.yaml: missing secret: db_password
{
  "status": "error",
  "operation": "validate",
  "duration_ms": 89,
  "message": "validation failed"
}
```

## Exit Codes

| Code | Description |
|------|-------------|
| 0 | Validation successful |
| 1 | Validation errors |

## JSON Output

```bash
swarmcli check my-app --json
```

```json
{
  "status": "success",
  "operation": "validate",
  "duration_ms": 127,
  "message": "all checks passed"
}
```

## CI Integration

```yaml
# .gitlab-ci.yml
validate:
  script:
    - swarmcli check my-app --json
  allow_failure: false
```

## See also

- [services.yaml](../config/04-services-yaml.md) — service format
- [externals.yaml](../config/06-externals-yaml.md) — externals format
- [deploy](01-deploy.md) — deploy
