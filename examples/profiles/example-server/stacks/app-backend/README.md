# App Backend — API + Worker + Scheduler

Multi-service stack: REST API, background task processor, and scheduler.

## What It Demonstrates

- **`type: git`** — `api` service is built from Git repository
- **`type: none`** — `worker` and `scheduler` services use the same image as `api`, but with different CMD
- **Jinja2 templates** — `templates/docker-stack.j2` instead of static `docker-stack.yml`
- **Helper functions** — `service_image()`, `deploy_resources()`, `dozzle_labels()`
- **runtime.env** — auto-injection of variables from `variables.yaml` into container environment
- **Secrets** — `externals.yaml` with three secrets (DB + JWT)
- **Build args** — passing `APP_ENV` during `docker build`
- **Hooks** — `pre-deploy.sh` and `post-deploy.sh` scripts
- **YAML anchors** — `x-global-env`, `x-env-vars`, `x-runtime-env` for block reuse
- **Traefik labels** — API routing through reverse proxy
- **Inter-service communication** — database and Redis URLs from `endpoints.yaml`

## Files

```
app-backend/
├── services.yaml       — 3 services: api (git), worker (none), scheduler (none)
├── variables.yaml      — runtime.env variables + build args
├── settings.yaml       — 90 sec timeout (migrations on startup)
├── externals.yaml      — secrets: app_db_user, app_db_password, app_jwt_secret
├── templates.yaml      — Jinja2 configuration
├── templates/
│   └── docker-stack.j2 — Jinja2 template
├── hooks/
│   ├── pre-deploy.sh   — runs BEFORE deploy
│   └── post-deploy.sh  — runs AFTER deploy
└── README.md
```

## How type: none Works

Worker and scheduler have no own repository or image. They use the `api` service image:

```yaml
# services.yaml
services:
  api:
    type: git
    image: local/app-backend    # ← built
  worker:
    type: none                  # ← uses api image
  scheduler:
    type: none                  # ← uses api image
```

In the template it looks like this:

```yaml
# docker-stack.j2
services:
  api:
    image: {{ service_image('api') }}          # local/app-backend:server-dev-abc1234
  worker:
    image: {{ service_image('api') }}          # same image
    command: ["./app", "worker"]               # different CMD
  scheduler:
    image: {{ service_image('api') }}          # same image
    command: ["./app", "scheduler"]            # different CMD
```

## Hooks

**pre-deploy.sh** — runs before deploy. Typical scenarios:
- Check dependency availability (DB, external APIs)
- Run migrations
- Backup before update

**post-deploy.sh** — runs after successful deploy. Typical scenarios:
- Slack / Telegram notification
- Cache cleanup
- Smoke test of new deploy

## Variable Priority

```
CI (RUNTIME_*)  →  runtime.env (variables.yaml)  →  globals.yaml
  (highest)              (medium)                     (lowest)
```
