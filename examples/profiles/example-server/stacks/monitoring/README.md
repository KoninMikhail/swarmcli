# Monitoring — Prometheus + Grafana

Monitoring stack: metrics collection and visualization.

## What It Demonstrates

- **Multi-service registry stack** — two services from DockerHub in one stack
- **Docker Configs (versioned strategy)** — new config on each deploy with name `<name>_<profile>_<commit_sha>`
- **`config_name()` helper** — get current config name in Jinja2 template
- **Jinja2 template** — `templates/docker-stack.j2` with helper functions
- **Secrets via entrypoint** — Grafana password read from secret in entrypoint script
- **Multiple volumes** — `prometheus_data` and `grafana_data`
- **Traefik labels** — Grafana accessible via reverse proxy

## Files

```
monitoring/
├── services.yaml       — 2 registry services
├── settings.yaml       — config_strategy: versioned
├── externals.yaml      — secret + 2 docker configs
├── templates.yaml      — Jinja2 configuration
├── templates/
│   └── docker-stack.j2 — Jinja2 template
├── configs/
│   ├── prometheus.yml          — Prometheus config (scrape targets)
│   └── grafana-datasources.yml — Grafana datasource provisioning
└── README.md
```

## Versioned Configs

Unlike `traefik` (simple strategy), `monitoring` uses versioned strategy. On each deploy a new Docker config is created:

```
prometheus_config                          ← simple (once)
prometheus_config_example-server_abc1234   ← versioned (each deploy)
```

The template uses `config_name()` to get the current name:

```yaml
# docker-stack.j2
configs:
  {{ config_name('prometheus_config') }}:
    external: true
```

Versioned advantages:
- History of all config versions in Docker Swarm
- Ability to rollback to previous version
- Automatic cleanup of old versions with `--prune`

## Secrets via Entrypoint

Grafana does not support reading password from file directly. Entrypoint pattern is used:

```yaml
entrypoint: |
  /bin/sh -c "
    export GF_SECURITY_ADMIN_PASSWORD=$$(cat /run/secrets/grafana_password)
    exec /run.sh
  "
```

`$$` — escaping `$` in docker-compose YAML (Swarm substitutes `$` → `$$` → `$`).

## Adding Scrape Targets

To monitor a new service, add it to `configs/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: my-new-service
    metrics_path: /metrics
    static_configs:
      - targets: ["my-service-host:8080"]
```

After changing the config, deploy the stack — versioned strategy will create a new version automatically.
