# Jinja2 Templating

## Overview

The templating system generates `docker-stack.yml` from Jinja2 templates with automatic variable substitution from multiple sources.

## Why Use It

- **Transparency** — see which variables are used and where they come from
- **Auto-injection** — variables from GitLab CI automatically flow to all services
- **Validation** — deploy fails if required variables are missing
- **DRY** — common variables extracted to YAML anchors

## Stack Structure with Templates

```
stacks/my-stack/
├── templates.yaml          # templating configuration
├── templates/              # Jinja2 templates
│   └── docker-stack.j2
├── .build/                 # generation output (in .gitignore)
│   └── docker-stack.yml
├── .deploy/                # deploy history (in .gitignore)
│   ├── history.jsonl
│   └── checkpoint.json
├── .repos/                 # service repositories (in .gitignore)
│   └── my-service/
│       └── .git/
├── variables.yaml          # stack variables
├── services.yaml
├── externals.yaml         # secrets and configs
└── settings.yaml
```

> **Note:** Directories `.build/`, `.deploy/`, `.repos/` — server-only, created automatically and not stored in Git.

## Quick Start

### 1. Initialization

```bash
# Converts docker-stack.yml to Jinja2 template
swarmcli template init my-stack
```

Creates:
- `templates.yaml` — configuration
- `templates/docker-stack.j2` — template (from existing docker-stack.yml)
- `.build/` — output directory

### 2. Rendering

```bash
# Generates .build/docker-stack.yml
swarmcli template render my-stack

# With verbose output
swarmcli template render my-stack --verbose
```

### 3. View Variables

```bash
# Shows all variables and their sources
swarmcli template vars my-stack
```

### 4. Deploy

```bash
# Automatically renders template before deploy
swarmcli deploy my-stack
```

## Variable Sources

Variables are loaded in priority order (last wins):

| Priority | Source | Prefix | Example |
|----------|--------|--------|---------|
| 1 (lowest) | `globals.yaml` | `GLOBAL_` | `GLOBAL_TZ` |
| 2 | `endpoints.yaml` | `SERVICE_` | `SERVICE_CORE_BACKEND_URL` |
| 3 | `variables.yaml` | — | `LOG_LEVEL` |
| 4 (highest) | GitLab CI | `DEPLOY_` → stripped | `DEPLOY_DEBUG` → `DEBUG` |

### Special Variables

| Variable | Description |
|----------|-------------|
| `DEPLOY_VARS` | Dict of all DEPLOY_* variables for iteration |
| `TAG_*` | Docker image tags (generated on deploy) |
| `_generated_at` | Generation timestamp |
| `_stack_name` | Stack name |

## templates.yaml Format

```yaml
# Template engine
engine: jinja2

# Templates to generate
templates:
  docker-stack:
    source: templates/docker-stack.j2
    output: .build/docker-stack.yml

# Variable sources (order = priority)
variable_sources:
  - globals        # GLOBAL_* from profiles/*/stacks/globals.yaml
  - endpoints      # SERVICE_* from profiles/*/stacks/endpoints.yaml
  - variables      # from ./variables.yaml
  - environment    # DEPLOY_*, BUILD_*, COMMON_*, TAG_*

# Required variables (render fails if missing)
required_vars:
  - GLOBAL_TZ
  - TAG_MY_SERVICE
  - SERVICE_DATABASE_HOST
```

## Jinja2 Syntax

### Variable Substitution

```yaml
# Simple substitution
TZ: {{ GLOBAL_TZ }}

# With default filter (if variable may be missing)
LOG_LEVEL: {{ LOG_LEVEL | default('INFO') }}
```

### Auto-inject DEPLOY_* Variables

```yaml
# Create anchor with variables from GitLab CI
{% if DEPLOY_VARS %}
x-deploy-env: &deploy-env
{%- for key, value in DEPLOY_VARS.items() %}
  {{ key }}: "{{ value }}"
{%- endfor %}
{% else %}
x-deploy-env: &deploy-env {}
{% endif %}

services:
  my-service:
    environment:
      # Attach via merge
      <<: [*common-env, *deploy-env]
```

### Conditionals

```yaml
{% if TRAEFIK_ENABLED == 'true' %}
      labels:
        - traefik.enable=true
        - traefik.http.routers.my-service.rule=Host(`{{ PUBLIC_HOST }}`)
{% endif %}
```

## Migrating Existing Stack

1. Run `swarmcli template init my-stack`
2. Check `templates/docker-stack.j2` — all `${VAR}` converted to `{{ VAR }}`
3. Remove original `docker-stack.yml` (optional)
4. Add `required_vars` to `templates.yaml`
5. Test: `swarmcli template render my-stack --verbose`

## GitLab CI Integration

```yaml
# .gitlab-ci.yml
deploy:
  variables:
    RUNTIME_FEATURE_FLAG: "enabled"
    RUNTIME_API_KEY: "$SECRET_API_KEY"
  script:
    - swarmcli deploy my-stack
```

All `RUNTIME_*` variables automatically:
1. Load into template context
2. Available as `{{ FEATURE_FLAG }}` (without prefix)

## Debugging

### View Final File

```bash
swarmcli template render my-stack
cat stacks/my-stack/.build/docker-stack.yml
```

### View All Variables

```bash
swarmcli template vars my-stack
```

### "Missing required variables" Error

```
Error: Missing required variables:
  - TAG_MY_SERVICE

Check: templates.yaml → required_vars
```

Ensure variable is exported or available from specified sources.

## See Also

- [Creating a Stack](../stacks/00-create-stack.md)
- [Variables](../../03-reference/variables/)
- [CI/CD integration](../../05-operations/gitlab-ci/)
