# Environment Variables

SwarmCLI environment variables reference.

## System Variables

### Paths

| Variable | Default | Description |
|----------|---------|-------------|
| `PLATFORM_ROOT` | auto | SwarmCLI project root |
| `SECRETS_ROOT` | `$PLATFORM_ROOT/.secrets` | Directory for secret files |
| `LOCKS_DIR` | `$PLATFORM_ROOT/.locks` | Directory for deployment locks (from `paths.locks` in `.swarmcli.yaml`) |

> **⚠️ Security:** The `SECRETS_ROOT` variable is read **ONLY** from the `.swarmcli.yaml` file (section `paths.secrets`) and cannot be overridden via environment variables (including CI/CD variables). This protects against unauthorized access to secrets.

> **Note:** The `REPOS_ROOT` variable is not used. Service repositories are stored inside each stack in the `.repos/` directory.

### Timeouts

| Variable | Default | Description |
|----------|---------|-------------|
| `TIMEOUT_SECONDS` | 900 | General operation timeout (sec) |
| `LOCK_TIMEOUT` | 3600 | Lock timeout (sec) |
| `SERVICES_READY_TIMEOUT` | 30 | Service readiness timeout (sec, from profile `config.yaml` → `swarm.services_ready_timeout`) |
| `BUILD_TIMEOUT` | 900 | Docker build timeout (sec) |
| `GRACEFUL_SHUTDOWN_TIMEOUT` | 10 | Wait before SIGKILL on Ctrl+C (sec) |

### Retry

| Variable | Default | Description |
|----------|---------|-------------|
| `RETRY_ENABLED` | 1 | Enable retry (1/0) |
| `RETRY_MAX_ATTEMPTS` | 3 | Max attempts |
| `RETRY_INITIAL_DELAY` | 2 | Initial delay (sec) |
| `RETRY_MAX_DELAY` | 30 | Max delay (sec) |

### Docker

| Variable | Default | Description |
|----------|---------|-------------|
| `KEEP_IMAGES_COUNT` | 10 | Number of image versions to keep (from profile `config.yaml` → `swarm.keep_images_count`) |
| `DEFAULT_BRANCH` | main | Default branch (from profile `config.yaml` → `git.default_branch`) |
| `DOCKER_BUILDKIT` | 1 | Use BuildKit |

### Output

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_FORMAT` | text | Log format (text/json) |
| `NO_COLOR` | - | Disable colored output |

### Debug

| Variable | Default | Description |
|----------|---------|-------------|
| `VERBOSE` | 0 | Verbose output |
| `SIGNAL_DEBUG` | 0 | Signal handling debug |
| `QUIET` | 0 | Minimal output |

## Generated Variables

### TAG_*

Image tags for services. Generated automatically:

```bash
TAG_<SERVICE> = <profile>-<commit_sha>
```

Examples:
```bash
TAG_API=server-dev-abc1234
TAG_WORKER=server-dev-abc1234
TAG_FRONTEND=server-dev-def5678
```

Usage:
```yaml
# docker-stack.yml
services:
  api:
    image: local/api:${TAG_API}
```

### GLOBAL_*

Variables from `globals.yaml`. Exported with prefix:

```yaml
# globals.yaml
TZ: Europe/Moscow
LOG_LEVEL: DEBUG
```

```bash
GLOBAL_TZ=Europe/Moscow
GLOBAL_LOG_LEVEL=DEBUG
```

Usage:
```yaml
# docker-stack.yml
environment:
  - TZ=${GLOBAL_TZ}
```

### SERVICE_*

Variables from `endpoints.yaml`:

```yaml
# endpoints.yaml
endpoints:
  core:
    api:
      host: my-api
      port: 8080
```

```bash
SERVICE_CORE_API_HOST=my-api
SERVICE_CORE_API_PORT=8080
SERVICE_CORE_API_URL=http://my-api:8080
```

Usage:
```yaml
# variables.yaml
runtime:
  env:
    BACKEND_URL: ${SERVICE_CORE_API_URL}
```

### RUNTIME_* and BUILD_*

Variables from `variables.yaml`:

```yaml
# variables.yaml
build:
  NODE_ENV: production

runtime:
  env:
    LOG_LEVEL: info
```

Available as:
- `BUILD_NODE_ENV=production` (for docker build)
- `LOG_LEVEL=info` (for environment, via inject_env_vars)

#### Passing via GitLab CI

**Important:** Variables with `RUNTIME_*` and `BUILD_*` prefixes from GitLab CI are passed to the remote server and available in Jinja2 templates.

```yaml
# .gitlab-ci.yml
deploy:dev:
  extends: .deploy_with_lock_shell
  variables:
    RUNTIME_CHELNOK: "true"           # Available in template as {{ CHELNOK }}
    RUNTIME_FEATURE_FLAG_X: "enabled"  # Available as {{ FEATURE_FLAG_X }}
    BUILD_TARGET: "production"        # Available when building images
```

Usage in Jinja2 templates:

```yaml
# templates/docker-stack.j2
services:
  api:
    environment:
      {{ inject_env_vars() }}
```

**Important:** The `RUNTIME_` prefix is automatically removed when used in templates:
- `RUNTIME_CHELNOK=true` → available as `{{ CHELNOK }}`
- `BUILD_TARGET=prod` → available as `{{ TARGET }}`

## CI/CD Variables

### GitLab CI

| Variable | Description |
|----------|-------------|
| `CI_COMMIT_SHA` | Commit SHA (priority for tags) |
| `CI_PROJECT_NAME` | Project name |
| `CI_ENVIRONMENT_NAME` | Environment name |

### SwarmCLI in CI

```yaml
# .gitlab-ci.yml
variables:
  STACK: my-app
  PROFILE: server-${CI_ENVIRONMENT_NAME}

deploy:
  script:
    - swarmcli deploy $STACK --profile $PROFILE --commit $CI_COMMIT_SHA
```

## Profile Variables

When loading a profile, these are set:

| Variable | Description |
|----------|-------------|
| `ACTIVE_PROFILE` | Active profile name |
| `PROFILE_DIR` | Profile directory path |
| `PROFILE_STACKS_DIR` | Stacks directory path |
| `PROFILE_NAME` | Name from config.yaml |
| `PROFILE_DESCRIPTION` | Description from config.yaml |

## Secret Variables

⚠️ **Never store secrets in environment variables!**

Use Docker Secrets:

```yaml
# docker-stack.yml
secrets:
  db_password:
    external: true

services:
  api:
    secrets:
      - db_password
    environment:
      DATABASE_PASSWORD_FILE: /run/secrets/db_password
```

## Example .swarmcli.yaml

The `.swarmcli.yaml` file in project root contains **instance-level** configuration. Profile-specific settings (`default_branch`, `keep_images_count`, `services_ready_timeout`) belong in `profiles/<profile>/config.yaml`:

```yaml
# .swarmcli.yaml

state:
  default_profile: server-dev

paths:
  secrets: .secrets
  locks: .locks

operations:
  log_format: text
  timeout: 900
  lock_timeout: 3600

git:
  auth:
    http_token: "your-token-here"
    http_user: null
    http_password: null
```

**CLI management:**

```bash
swarmcli config set git.auth.http_token "your-token"
swarmcli config get state.default_profile
swarmcli config list
```

⚠️ Add `.swarmcli.yaml` to `.gitignore` if storing secrets in `git.auth`!

## Priority

1. Command line variables (`--branch`, `--commit`)
2. Environment variables (`CI_COMMIT_SHA`, `COMMIT_SHA`)
3. Profile configuration (`config.yaml`)
4. Default values

## See also

- [config.yaml](../config/01-config-yaml.md)
- [globals.yaml](../config/02-globals-yaml.md)
- [endpoints.yaml](../config/08-endpoints-yaml.md)
