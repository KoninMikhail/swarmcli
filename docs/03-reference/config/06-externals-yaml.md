# externals.yaml

Stack external dependencies: Docker Swarm secrets and configs.

## Location

```
profiles/<profile>/stacks/<stack>/externals.yaml
```

> **Note:** Previously this file was named `secrets.yaml`. The new name reflects the extended functionality.

## Format

```yaml
# Docker Swarm secrets
secrets:
  - db_password
  - jwt_private_key
  - api_key

# Docker Configs (optional)
configs:
  - name: nginx_config
    file: configs/nginx.conf
  - name: app_settings
    file: configs/settings.json
```

## Sections

### secrets

List of secrets that must exist in Docker Swarm before deploy.

| Field | Type | Description |
|-------|------|-------------|
| `secrets` | list[string] | List of secret names |

On deploy SwarmCLI checks presence of all secrets and:
- If secret is missing but file exists in `.secrets/` — creates secret automatically
- If both secret and file are missing — deploy aborts with error

### configs

List of Docker Swarm configs for the stack.

| Field | Type | Description |
|-------|------|-------------|
| `configs[].name` | string | Config name in Docker Swarm |
| `configs[].file` | string | Path to file relative to stack directory |

## Config Strategies

Config management strategy is set in `settings.yaml`:

```yaml
# settings.yaml
config_strategy: simple  # or versioned
```

### simple (default)

Creates config once. On subsequent deploys checks presence.

```
nginx_config → nginx_config (unchanged)
```

**When to use:**
- Configs rarely change
- No version history needed

### versioned

Creates a new config on each deploy with versioned name:

```
nginx_config → nginx_config_server-dev_abc1234
```

Name format: `<name>_<profile>_<commit_sha>`

**When to use:**
- Configs change frequently
- Need rollback capability
- CI/CD pipeline with versioning

## Usage in docker-stack.j2

### Simple config (simple)

```yaml
configs:
  nginx_config:
    external: true

services:
  web:
    configs:
      - source: nginx_config
        target: /etc/nginx/nginx.conf
```

### Versioned config (versioned)

Use the `config_name()` function to get the current name:

```yaml
configs:
  {{ config_name('nginx_config') }}:
    external: true

services:
  web:
    configs:
      - source: {{ config_name('nginx_config') }}
        target: /etc/nginx/nginx.conf
```

## File Storage

### Secrets

Secrets are stored in the **global** `.secrets/` directory at swarmcli root:

```
swarmcli/
├── .secrets/                    # Global directory (NOT in git!)
│   ├── db_password
│   └── jwt_private_key
└── profiles/<profile>/stacks/<stack>/
    └── externals.yaml
```

### Configs

Configs are stored **in the stack directory**:

```
profiles/<profile>/stacks/<stack>/
├── configs/                     # Configs directory
│   ├── nginx.conf
│   └── settings.json
├── externals.yaml               # External dependencies definition
└── ...
```

## Examples

### Secrets only

```yaml
secrets:
  - db_password
  - jwt_private_key
```

### Configs only

```yaml
configs:
  - name: nginx_config
    file: configs/nginx.conf
```

### Secrets and configs

```yaml
secrets:
  - db_password
  - api_key

configs:
  - name: nginx_config
    file: configs/nginx.conf
  - name: prometheus_config
    file: configs/prometheus.yml
```

### Empty file

```yaml
secrets: []
```

## CLI Commands

### Secrets

```bash
# Check stack secrets
swarmcli secret check my-app

# Create secret
swarmcli secret create db_password

# List secrets
swarmcli secret ls
```

### Configs (via Docker)

```bash
# List configs
docker config ls

# Create config manually
docker config create nginx_config ./configs/nginx.conf

# Remove config
docker config rm nginx_config
```

## Cleaning Old Versions

When using `--prune` with versioned strategy, old configs are removed automatically:

```bash
swarmcli deploy my-app --prune
```

By default the last 10 versions are kept (configurable via `KEEP_IMAGES_COUNT`).

## Best Practices

### 1. Configs in separate directory

```
stacks/my-app/
├── configs/
│   ├── nginx.conf
│   └── app.json
└── externals.yaml
```

### 2. Versioned for CI/CD

```yaml
# settings.yaml
config_strategy: versioned
```

### 3. Secrets NOT in git

```gitignore
# .gitignore
.secrets/
```

### 4. Configs IN git (they don't contain secrets)

Configs are configuration files without secret data. They can and should be stored in git.

## Troubleshooting

### "Config file not found"

```bash
# Check path in externals.yaml
cat profiles/server-dev/stacks/my-app/externals.yaml

# Check file exists
ls -la profiles/server-dev/stacks/my-app/configs/
```

### "Required secrets missing"

```bash
# Check secrets
swarmcli secret check my-app

# Create missing
swarmcli secret create missing_secret
```

### Rollback versioned config

```bash
# Find previous version
docker config ls | grep nginx_config

# Update docker-stack.yml manually or rollback via git
```

## See also

- [settings.yaml](07-settings-yaml.md) — `config_strategy` setting
- [Secrets management](../../02-guides/secrets/00-overview.md)
