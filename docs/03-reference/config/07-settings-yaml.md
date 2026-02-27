# settings.yaml

Per-stack settings.

## Location

```
profiles/<profile>/stacks/<stack>/settings.yaml
```

## Format

```yaml
# Service readiness timeout (overrides profile)
services_ready_timeout: 60

# One-shot init services excluded from readiness check (run once and exit)
readiness_exclude:
  - superset_init

# Image build timeout (for heavy projects)
build_timeout: 1800

# Number of log lines for error diagnostics
diagnostics_logs_tail: 50

# Docker configs management strategy
config_strategy: simple  # or versioned

# Git auth override for this stack (optional)
# git:
#   http_user: ${GIT_HTTP_USER_BACKEND}
#   http_token: ${GIT_HTTP_TOKEN_BACKEND}
```

## Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `services_ready_timeout` | int | from profile | Service readiness wait timeout (sec) |
| `readiness_exclude` | list | [] | Services to exclude from readiness check (one-shot init jobs) |
| `build_timeout` | int | 900 | Docker image build timeout (sec) |
| `diagnostics_logs_tail` | int | 30 | Number of log lines for diagnostics |
| `config_strategy` | string | simple | Config strategy: `simple` or `versioned` |
| `git.http_user` | string | - | Override username for this stack (expands `${VAR}`) |
| `git.http_token` | string | - | Override token for this stack (expands `${VAR}`) |

## Description

`settings.yaml` allows overriding profile settings for a specific stack.

## Setting Priority

1. Stack `settings.yaml` (highest priority)
2. Profile `config.yaml`
3. `.swarmcli.yaml` or environment variables

## Examples

### One-shot init services (Superset, migrations)

For stacks with init jobs that run once and exit:

```yaml
# superset_init runs migrations and exits — exclude from readiness check
readiness_exclude:
  - superset_init
services_ready_timeout: 60
```

### Increased timeout

For stacks that need more time to start:

```yaml
# Heavy stack with migrations
services_ready_timeout: 120
```

### Standard settings

```yaml
services_ready_timeout: 30
diagnostics_logs_tail: 30
```

### Fast stack

```yaml
# Light stack (nginx, redis)
services_ready_timeout: 15
```

### Heavy build (Java/Node.js)

```yaml
# Long build, but fast start
build_timeout: 1800        # 30 minutes for build
services_ready_timeout: 60
```

### ML/Data Science stack

```yaml
# Very long build (dependency installation)
build_timeout: 3600          # 1 hour
services_ready_timeout: 120  # 2 minutes for model loading
```

### Versioned configs (CI/CD)

```yaml
# For production with config versioning
config_strategy: versioned
services_ready_timeout: 60
```

### Per-stack Git credentials

When a stack uses a different Git token (e.g. vendor repo):

```yaml
# stacks/vendor-app/settings.yaml
git:
  http_user: ${GIT_HTTP_USER_VENDOR}
  http_token: ${GIT_HTTP_TOKEN_VENDOR}
```

Set env vars before deploy: `export GIT_HTTP_TOKEN_VENDOR="xxx"`

## config_strategy

Controls how Docker configs from `externals.yaml` are created.

### simple (default)

Creates config once, checks presence on subsequent deploys:

```yaml
config_strategy: simple
```

Config name stays unchanged: `nginx_config`

### versioned

Creates a new config on each deploy with versioned name:

```yaml
config_strategy: versioned
```

Config name includes profile and commit SHA: `nginx_config_server-dev_abc1234`

For use in templates, apply the `config_name()` function:

```jinja2
configs:
  {{ config_name('nginx_config') }}:
    external: true
```

See [externals.yaml](06-externals-yaml.md) for details.

## Recommended Values

### services_ready_timeout

| Scenario | Recommendation |
|----------|----------------|
| Simple nginx | 15-30 sec |
| API application | 30-60 sec |
| With DB migrations | 60-120 sec |
| ML/heavy services | 120-300 sec |

### build_timeout

| Scenario | Recommendation |
|----------|----------------|
| Python (pip install) | 300-600 sec (5-10 min) |
| Node.js (npm install) | 600-900 sec (10-15 min) |
| Java/Gradle | 900-1800 sec (15-30 min) |
| ML with large dependencies | 1800-3600 sec (30-60 min) |

## Best Practices

### 1. Don't set timeout too low

```yaml
# ⚠️ May not have enough time
services_ready_timeout: 10

# ✓ Safe value
services_ready_timeout: 30
```

### 2. Don't set timeout too high

```yaml
# ⚠️ Long wait on issues
services_ready_timeout: 600

# ✓ Reasonable max for typical cases
services_ready_timeout: 120
```

### 3. Test actual startup time

```bash
# Measure startup time
time swarmcli deploy my-app
```

## Troubleshooting

### "timeout waiting for services"

1. Increase timeout:

```yaml
services_ready_timeout: 120
```

2. Check logs:

```bash
docker service logs my-app_api --tail 50
```

3. Check healthcheck (if present):

```bash
docker service inspect my-app_api --format '{{.Spec.TaskTemplate.ContainerSpec.Healthcheck}}'
```

## See also

- [config.yaml](01-config-yaml.md)
- [Basic deploy](../../02-guides/deployment/00-basic-deploy.md)
