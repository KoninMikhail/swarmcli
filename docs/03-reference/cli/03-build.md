# build

Build Docker images for stack.

## Syntax

```bash
swarmcli build [stack] [flags]
```

## Description

The `build` command builds Docker images for `git` type services:

1. Load build variables
2. Sync Git repositories (optional)
3. Build Docker images

## Arguments

| Argument | Description |
|----------|-------------|
| `stack` | Stack name. If not specified — interactive selection |

## Flags

### Service selection

| Flag | Description |
|------|-------------|
| `--service <name>` | Build only specified service |
| `--branch <name>` | Branch for all services |

### Build modes

| Flag | Description |
|------|-------------|
| `--force` | Force rebuild |
| `--no-cache` | Build without Docker cache |
| `--pull` | Sync repositories before build |

### Additional options

| Flag | Description |
|------|-------------|
| `--dry-run` | Show plan without execution |

## Examples

### Basic build

```bash
swarmcli build my-app
```

### Build specific service

```bash
swarmcli build my-app --service api
```

### Build from feature branch

```bash
swarmcli build my-app --branch feature/new-api
```

### Full rebuild without cache

```bash
swarmcli build my-app --force --no-cache
```

### Build with repo sync

```bash
swarmcli build my-app --pull
```

## Image Tags

For each service a tag is generated:
```
TAG_<SERVICE> = <profile>-<commit_sha>
```

Example:
- `TAG_API=server-dev-abc1234`

## Build Timeout

Timeout is configured:

1. **stack settings.yaml** (highest priority):
```yaml
build_timeout: 1800  # 30 minutes
```

2. **Environment variable:**
```bash
BUILD_TIMEOUT=1800
```

3. **Default:** 900 seconds (15 minutes)

## Build Variables

Before build, variables from `variables.yaml` are loaded:

```yaml
# variables.yaml
build:
  NODE_ENV: production
  NPM_TOKEN: ${NPM_TOKEN}
```

Used as build-args:
```bash
docker build --build-arg NODE_ENV=production ...
```

## Exit Codes

| Code | Description |
|------|-------------|
| 0 | Build successful |
| 1 | Configuration error |
| 2 | Build error |
| 124 | Build timeout |

## Build Logs

Build logs are saved to:
```
~/.swarm-deploy/logs/build_<service>.log
```

## See also

- [deploy](01-deploy.md) — deploy
- [settings.yaml](../config/07-settings-yaml.md) — timeout configuration
