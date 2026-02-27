# PostgreSQL — Database

Relational database based on [PostgreSQL 16](https://www.postgresql.org/).

## What It Demonstrates

- **`type: registry`** — ready image `postgres:16-alpine` from DockerHub
- **Secrets** — DB login and password via Docker Swarm secrets
- **`_FILE` pattern** — reading secrets via `POSTGRES_USER_FILE` / `POSTGRES_PASSWORD_FILE`
- **Volumes** — persistent data storage in `pgdata`
- **Healthcheck** — `pg_isready` for readiness check

## Files

```
postgres/
├── services.yaml       — registry service
├── settings.yaml       — 30 sec timeout
├── externals.yaml      — secrets: app_db_user, app_db_password
├── docker-stack.yml    — Docker Compose for Swarm
└── README.md
```

## `_FILE` Pattern for Secrets

PostgreSQL supports reading credentials from files via variables with `_FILE` suffix:

```yaml
environment:
  POSTGRES_USER_FILE: /run/secrets/db_username
  POSTGRES_PASSWORD_FILE: /run/secrets/db_password
secrets:
  - source: app_db_user
    target: db_username
  - source: app_db_password
    target: db_password
```

This is safer than passing passwords via environment — secrets are not visible in `docker inspect`.

## Creating Secrets

```bash
swarmcli secret create app_db_user
# Enter: myuser

swarmcli secret create app_db_password
# Enter: strong_password
```

## Connecting from Other Stacks

Other stacks use `endpoints.yaml` to get the database address:

```yaml
# In another stack's variables.yaml
DATABASE_URL: postgres://${SERVICE_DATABASES_POSTGRESQL_HOST}:${SERVICE_DATABASES_POSTGRESQL_PORT}/${SERVICE_DATABASES_POSTGRESQL_DATABASE}
# → postgres://postgres:5432/example_db
```
