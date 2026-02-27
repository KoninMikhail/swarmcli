# Configuration Formats

Reference for all SwarmCLI configuration YAML files.

## File Hierarchy

```
<swarmcli_root>/
├── .secrets/                # Secret files (SECRETS_ROOT from .swarmcli.yaml, not in profiles!)
│   └── <secret_name>        # Default: .secrets; recommended: ../secrets (outside repo)
└── profiles/<profile>/
    ├── config.yaml          # Profile settings
    └── stacks/
        ├── globals.yaml     # Global variables
        ├── resources.yaml   # CPU/Memory resources
        ├── endpoints.yaml   # Service registry
        └── <stack>/
            ├── docker-stack.yml # Docker Compose for Swarm
            ├── services.yaml    # Service definitions
            ├── variables.yaml   # Stack variables
            ├── externals.yaml   # Required secrets and configs
            ├── settings.yaml    # Stack settings
            └── hooks/
                ├── pre-deploy.sh
                └── post-deploy.sh
```

## Profile Files

### [config.yaml](01-config-yaml.md)

Profile settings:

```yaml
name: server-dev
description: Development server

swarm:
  services_ready_timeout: 30
  keep_images_count: 3

git:
  default_branch: develop

retry:
  enabled: true
  max_attempts: 3
```

### [globals.yaml](02-globals-yaml.md)

Global variables:

```yaml
TZ: Europe/Moscow
PLATFORM_ENV: development
LOG_LEVEL: DEBUG
```

### [resources.yaml](03-resources-yaml.md)

CPU/Memory resources:

```yaml
stacks:
  my-app:
    api:
      limits:
        cpus: "2.0"
        memory: "2G"
```

### [endpoints.yaml](08-endpoints-yaml.md)

Service registry:

```yaml
endpoints:
  core:
    api:
      host: my-api
      port: 8080
```

## Stack Files

### [services.yaml](04-services-yaml.md)

Service definitions:

```yaml
services:
  api:
    type: git
    repo: git@github.com:your-org/api.git
    image: local/api
```

### [variables.yaml](05-variables-yaml.md)

Build and runtime variables:

```yaml
build:
  NODE_ENV: production

runtime:
  env:
    LOG_LEVEL: info
```

### [externals.yaml](06-externals-yaml.md)

Required secrets and configs:

```yaml
secrets:
  - db_password
  - api_key
```

### [settings.yaml](07-settings-yaml.md)

Stack settings:

```yaml
services_ready_timeout: 60
build_timeout: 900
diagnostics_logs_tail: 50
```

## docker-stack.yml

Standard Docker Compose file for Swarm. SwarmCLI:
- Injects resources from `resources.yaml`
- Injects variables from `variables.yaml`
- Adds Dozzle labels from `services.yaml`

## Variables in Configuration

### Syntax

```yaml
value: ${VAR_NAME}           # From env
value: ${VAR_NAME:-default}  # With default value
```

### Available Variables

| Prefix | Source |
|--------|--------|
| `TAG_*` | Image tags (generated) |
| `GLOBAL_*` | globals.yaml |
| `BUILD_*` | variables.yaml build |
| `RUNTIME_*` | variables.yaml runtime.env, GitLab CI |
| `SERVICE_*` | endpoints.yaml |

## Validation

```bash
# Stack validation
swarmcli check my-app

# Registry validation
swarmcli registry check
```
