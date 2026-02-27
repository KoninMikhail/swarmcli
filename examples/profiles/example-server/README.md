# Example Server Profile

Demonstration profile for SwarmCLI covering the main system capabilities.

> **Important:** This profile is not production-ready. Git repository URLs are placeholders — replace
> them with your actual repository addresses before use.

## Stacks

| Stack | Description | Service Types | Key Features |
|-------|-------------|---------------|--------------|
| **traefik** | Reverse proxy | registry | Docker configs (simple), healthcheck |
| **app-backend** | API + Worker + Scheduler | git + none | Jinja2 templates, secrets, hooks, runtime.env |
| **app-frontend** | SPA Frontend | git | Static docker-stack.yml, build args |
| **postgres** | Database | registry | Secrets, volumes, healthcheck |
| **redis** | Cache/Queue | registry | Minimal configuration |
| **monitoring** | Prometheus + Grafana | registry (multi) | Jinja2, Docker configs (versioned) |

## Capability Coverage

### Service Types
- `type: git` — build from Git repository → `app-backend`, `app-frontend`
- `type: registry` — image from Docker Registry → `traefik`, `postgres`, `redis`, `monitoring`
- `type: none` — derived service (uses the same image) → `app-backend` (worker, scheduler)

### Configuration
- **Jinja2 templates** (`templates/docker-stack.j2`) → `app-backend`, `monitoring`
- **Static `docker-stack.yml`** → `traefik`, `app-frontend`, `postgres`, `redis`
- **Docker Configs** (simple) → `traefik`
- **Docker Configs** (versioned) → `monitoring`
- **Secrets** (`externals.yaml`) → `app-backend`, `postgres`
- **Build args** → `app-backend`, `app-frontend`
- **runtime.env** (auto-injection of variables) → `app-backend`
- **Hooks** (pre/post-deploy) → `app-backend`

### Profile Level
- **globals.yaml** — shared variables (TZ, LOG_LEVEL, DOMAIN)
- **endpoints.yaml** — inter-service communication
- **resources.yaml** — CPU/Memory limits for all services

## Git Authentication

Stacks with `type: git` (app-backend, app-frontend) require authentication for cloning. The token is used during `swarmcli sync` and `swarmcli build`.

**Priority (highest first):**
1. **Stack** `settings.yaml` — `git.http_user`, `git.http_token` (per-stack override)
2. **Profile** `config.yaml` — `git.http_user`, `git.http_token` (per-profile override)
3. **Global** — `.swarmcli.yaml` or env vars `GIT_HTTP_USER`, `GIT_HTTP_TOKEN`

**Most users** — set globally (env or `.swarmcli.yaml`):
```bash
export GIT_HTTP_TOKEN="your-personal-access-token"   # PAT (GitHub/GitLab)
# or Deploy Token:
export GIT_HTTP_USER="your-deploy-token"
export GIT_HTTP_TOKEN="your-deploy-token-secret"
```

**Per-stack override** — stack uses different token (e.g. vendor repo):
```yaml
# stacks/vendor-app/settings.yaml
git:
  http_token: ${GIT_HTTP_TOKEN_VENDOR}
```
Then: `export GIT_HTTP_TOKEN_VENDOR="xxx"` before deploy.

**Per-profile override** — uncomment `http_user`/`http_token` in profile `config.yaml`.

See `docs/03-reference/config/07-settings-yaml.md`.

## Quick Start

```bash
# 1. Copy the profile
cp -r examples/profiles/example-server profiles/example-server

# 2. Set Git token (required for app-backend, app-frontend)
export GIT_HTTP_TOKEN="your-token"
# or: swarmcli config set git.auth.http_token "your-token"

# 3. Edit config.yaml — specify real Git URLs
nano profiles/example-server/config.yaml

# 4. Edit services.yaml in stacks with type: git
nano profiles/example-server/stacks/app-backend/services.yaml
nano profiles/example-server/stacks/app-frontend/services.yaml

# 5. Create secrets
swarmcli secret create app_db_user
swarmcli secret create app_db_password
swarmcli secret create app_jwt_secret
swarmcli secret create grafana_admin_password

# 6. Activate the profile
swarmcli use example-server

# 7. Validation
swarmcli validate

# 8. Deploy
swarmcli deploy traefik
swarmcli deploy postgres
swarmcli deploy redis
swarmcli deploy app-backend
swarmcli deploy app-frontend
swarmcli deploy monitoring
```

## Architecture

```
                    ┌─────────────┐
                    │   Traefik   │ :80, :443
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
       ┌──────┴──────┐ ┌──┴───┐ ┌──────┴──────┐
       │ app-backend  │ │ app- │ │  monitoring  │
       │  api/worker  │ │front │ │ prom+grafana │
       │  scheduler   │ │ end  │ └──────┬──────┘
       └──────┬───────┘ └──────┘        │
              │                         │
       ┌──────┴──────┐                  │
       │  PostgreSQL  │◄────────────────┘
       │    Redis     │
       └─────────────┘
```

## File Structure

```
example-server/
├── config.yaml                          # Profile settings
├── README.md
└── stacks/
    ├── globals.yaml                     # Global variables
    ├── resources.yaml                   # CPU/Memory resources
    ├── endpoints.yaml                   # Inter-service addresses
    │
    ├── traefik/                         # Reverse proxy
    │   ├── services.yaml
    │   ├── settings.yaml
    │   ├── externals.yaml               # Docker configs (simple)
    │   ├── docker-stack.yml
    │   └── configs/
    │       └── traefik.yml
    │
    ├── app-backend/                     # API + Worker + Scheduler
    │   ├── services.yaml
    │   ├── variables.yaml               # runtime.env variables
    │   ├── settings.yaml
    │   ├── externals.yaml               # Secrets
    │   ├── templates.yaml               # Jinja2 configuration
    │   ├── templates/
    │   │   └── docker-stack.j2
    │   └── hooks/
    │       ├── pre-deploy.sh
    │       └── post-deploy.sh
    │
    ├── app-frontend/                    # SPA Frontend
    │   ├── services.yaml
    │   ├── variables.yaml               # Build args
    │   ├── settings.yaml
    │   ├── externals.yaml
    │   └── docker-stack.yml
    │
    ├── postgres/                        # Database
    │   ├── services.yaml
    │   ├── settings.yaml
    │   ├── externals.yaml               # Secrets
    │   └── docker-stack.yml
    │
    ├── redis/                           # Cache
    │   ├── services.yaml
    │   ├── settings.yaml
    │   └── docker-stack.yml
    │
    └── monitoring/                     # Prometheus + Grafana
        ├── services.yaml
        ├── settings.yaml
        ├── externals.yaml               # Docker configs (versioned)
        ├── templates.yaml
        ├── templates/
        │   └── docker-stack.j2
        └── configs/
            ├── prometheus.yml
            └── grafana-datasources.yml
```
