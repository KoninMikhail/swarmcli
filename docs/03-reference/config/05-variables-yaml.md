# variables.yaml

Stack build and runtime variables.

## Location

```
profiles/<profile>/stacks/<stack>/variables.yaml
```

## Format

```yaml
# Common variables (for build and runtime)
common:
  APP_VERSION: "1.0.0"
  SHARED_VALUE: shared

# Build variables (docker build --build-arg)
build:
  NODE_ENV: production
  NPM_TOKEN: ${NPM_TOKEN}

# Runtime variables (environment in docker-stack via inject_env_vars())
runtime:
  env:
    LOG_LEVEL: info
    API_URL: ${SERVICE_CORE_API_URL}
```

## Sections

### common

Variables available both at build and runtime:

```yaml
common:
  APP_VERSION: "1.0.0"
```

Exported as:
- `--build-arg APP_VERSION=1.0.0` at build time
- In environment at deploy time

### build

Variables for build only (`docker build --build-arg`):

```yaml
build:
  NODE_ENV: production
  NPM_TOKEN: ${NPM_TOKEN}
```

Used in Dockerfile:

```dockerfile
ARG NODE_ENV
ARG NPM_TOKEN
RUN echo "//registry.npmjs.org/:_authToken=${NPM_TOKEN}" > ~/.npmrc
RUN npm ci --only=production
```

### runtime.env

Variables for runtime environment (Jinja2 templates with `{{ inject_env_vars() }}`):

```yaml
runtime:
  env:
    LOG_LEVEL: info
    DATABASE_HOST: ${SERVICE_DATABASES_POSTGRES_HOST}
```

Auto-injected into container environment when using templates.

## Variable Usage

### From environment

```yaml
build:
  NPM_TOKEN: ${NPM_TOKEN}       # From env
  API_KEY: ${API_KEY:-default}  # With default value
```

### From endpoints.yaml

```yaml
runtime:
  env:
    BACKEND_URL: ${SERVICE_CORE_BACKEND_API_URL}
    REDIS_HOST: ${SERVICE_DATABASES_REDIS_HOST}
```

### From globals.yaml

Global variables are available with the `GLOBAL_` prefix:

```yaml
# In docker-stack.j2
environment:
  - TZ=${GLOBAL_TZ}
  - LOG_LEVEL=${GLOBAL_LOG_LEVEL}
```

## Injection into docker-stack (templates)

When using Jinja2 templates, `runtime.env` variables are auto-injected via `{{ inject_env_vars() }}`:

```yaml
# templates/docker-stack.j2
services:
  api:
    image: local/api:${TAG_API}
    environment:
      {{ inject_env_vars() }}
```

## Variable Priority

1. `common` (base)
2. `build` / `runtime.env` (override common)
3. Environment variables (from system)

## Examples

### Simple

```yaml
runtime:
  env:
    LOG_LEVEL: info
    DEBUG: "false"
```

### With environment variables

```yaml
build:
  NPM_TOKEN: ${NPM_TOKEN}
  GITHUB_TOKEN: ${GITHUB_TOKEN}

runtime:
  env:
    API_KEY: ${API_KEY}
    SENTRY_DSN: ${SENTRY_DSN}
```

### With endpoints

```yaml
runtime:
  env:
    BACKEND_API_URL: ${SERVICE_CORE_BACKEND_API_URL}
    FILE_UPLOADER_URL: ${SERVICE_CORE_FILE_UPLOADER_URL}
    REDIS_HOST: ${SERVICE_DATABASES_REDIS_HOST}
    REDIS_PORT: ${SERVICE_DATABASES_REDIS_PORT}
```

### Full example

```yaml
# Common variables
common:
  APP_NAME: my-app
  APP_VERSION: "2.0.0"

# Build only
build:
  NODE_ENV: production
  NPM_TOKEN: ${NPM_TOKEN}
  BUILD_DATE: ${BUILD_DATE:-unknown}

# Runtime environment (for inject_env_vars in templates)
runtime:
  env:
    LOG_LEVEL: info
    LOG_FORMAT: json
    
    # Service URLs from endpoints.yaml
    BACKEND_URL: ${SERVICE_CORE_BACKEND_API_URL}/api/v2
    REDIS_URL: redis://${SERVICE_DATABASES_REDIS_HOST}:${SERVICE_DATABASES_REDIS_PORT}
    
    # Feature flags
    FEATURE_NEW_UI: "true"
    FEATURE_ANALYTICS: "false"
```

## Different variables for dev/prod

```yaml
# profiles/server-dev/stacks/my-app/variables.yaml
runtime:
  env:
    LOG_LEVEL: DEBUG
    FEATURE_DEBUG: "true"

# profiles/server-prod/stacks/my-app/variables.yaml
runtime:
  env:
    LOG_LEVEL: WARN
    FEATURE_DEBUG: "false"
```

## Legacy: deploy section

For stacks **without** Jinja2 templates (direct `docker-stack.yml`), the `deploy` section is still supported. Bash exports these as environment variables for `${VAR}` substitution in docker-stack.yml. For new stacks with templates, use `runtime.env` instead.

## Validation of SERVICE_* references

On deploy SwarmCLI verifies that all `${SERVICE_*}` references exist in endpoints.yaml:

```bash
swarmcli registry check
```

## See also

- [endpoints.yaml](08-endpoints-yaml.md)
- [globals.yaml](02-globals-yaml.md)
