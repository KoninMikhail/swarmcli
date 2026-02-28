# endpoints.yaml

Centralized service address file for managing inter-service communication.

## Problem

When manually specifying service addresses (host:port) in environment variables, errors often occur:
- Typos in service names
- Wrong ports
- Desynchronization when changing service name/port

## Solution

The `endpoints.yaml` file at profile level describes service addresses. CLI automatically:
1. Generates `SERVICE_*` variables from the registry
2. Validates that all `${SERVICE_*}` references in `variables.yaml` exist in the registry

## Structure

```
profiles/<profile>/stacks/
├── endpoints.yaml           # Service addresses
├── globals.yaml
├── stack-a/
│   ├── docker-stack.yml
│   └── variables.yaml       # Uses ${SERVICE_*}
└── stack-b/
    └── ...
```

## endpoints.yaml Format

```yaml
endpoints:
  # Service category
  core:
    # Endpoint name
    backend_api:
      host: core-backend-api        # Service hostname/alias
      port: 8080                   # Port
      network: network_aireferent  # Network (optional)
      description: "Backend API"   # Description (optional)
    
    file_uploader:
      host: ar-file-uploader
      port: 8080
      network: network_aireferent

  analytics:
    agregator:
      host: ai-analytics-agregator-service
      port: 8012
      network: network_aireferent

  databases:
    clickhouse:
      host: clickhouse-server
      port: 8123
      network: clickhouse_clickhouse_network
```

## Generated Variables

CLI automatically creates environment variables:

```bash
# For endpoints.core.backend_api:
SERVICE_CORE_BACKEND_API_HOST=core-backend-api
SERVICE_CORE_BACKEND_API_PORT=8080
SERVICE_CORE_BACKEND_API_URL=http://core-backend-api:8080
SERVICE_CORE_BACKEND_API_NETWORK=network_aireferent

# For endpoints.databases.clickhouse:
SERVICE_DATABASES_CLICKHOUSE_HOST=clickhouse-server
SERVICE_DATABASES_CLICKHOUSE_PORT=8123
SERVICE_DATABASES_CLICKHOUSE_URL=http://clickhouse-server:8123
```

## Usage in variables.yaml

**Before (hardcoded):**
```yaml
runtime:
  env:
    BACKEND_CALLBACK_URL: http://core-backend-api:8080/backend/v3/analytic/approve
    CLICKHOUSE_HOST: clickhouse-server
```

**After (registry references):**
```yaml
runtime:
  env:
    BACKEND_CALLBACK_URL: ${SERVICE_CORE_BACKEND_API_URL}/backend/v3/analytic/approve
    CLICKHOUSE_HOST: ${SERVICE_DATABASES_CLICKHOUSE_HOST}
```

## CLI Commands

### List services in registry

```bash
swarmcli registry list
```

Example output:
```
Services Registry (profile: server-dev)

[core]
  ● backend_api
    URL: http://core-backend-api:8080
    Var: ${SERVICE_CORE_BACKEND_API_URL}
  ● file_uploader
    URL: http://ar-file-uploader:8080
    Var: ${SERVICE_CORE_FILE_UPLOADER_URL}

[analytics]
  ● agregator
    URL: http://ai-analytics-agregator-service:8012
    Var: ${SERVICE_ANALYTICS_AGREGATOR_URL}
```

### Validate references

```bash
swarmcli registry validate
```

Validates all profile stacks for undefined `${SERVICE_*}` references.

## Validation on Deploy

On `swarmcli deploy`:

1. CLI loads `endpoints.yaml` and exports `SERVICE_*` variables
2. CLI checks stack `variables.yaml` for `${SERVICE_*}` references
3. If reference to non-existent service found — **deploy aborts with error**

Example error:
```
✗ undefined service reference in my-stack/variables.yaml: ${SERVICE_UNKNOWN_SERVICE_URL}
✗ found 1 undefined SERVICE_* references
✗ undefined SERVICE_* references found (see errors above)
```

## Best Practices

### 1. Service categorization

Group services by functionality:

| Category | Description |
|----------|-------------|
| `core` | Core platform services |
| `analytics` | Analytics services |
| `parsers` | Document parsers and processors |
| `integrations` | External service integrations |
| `databases` | Databases and storage |
| `auth` | Authentication services |
| `automation` | Automation (n8n, etc.) |

### 2. Endpoint naming

- Use snake_case: `backend_api`, `file_uploader`
- Names should be descriptive: `pgch_connector`, not `connector1`

### 3. Descriptions

Add `description` for documentation:

```yaml
backend_api:
  host: core-backend-api
  port: 8080
  description: "Core Backend API - REST API for frontend"
```

### 4. One registry per profile

Each profile has its own `endpoints.yaml`. This allows:
- Different hostname/port for dev/prod
- Different set of services

## Troubleshooting

### Error: "undefined service reference"

Service not found in registry. Check:
1. Name correctness: `${SERVICE_CORE_BACKEND_API_URL}` vs `${SERVICE_CORE_BACKENDAPI_URL}`
2. Service presence in `endpoints.yaml`

### Error: "endpoints.yaml not found"

File is missing. Create it:
```bash
touch profiles/server-dev/stacks/endpoints.yaml
```

### Variables not applied

Ensure that:
1. Registry is loaded before `variables.yaml`
2. `variables.yaml` uses `${VAR}` syntax, not `$VAR`
