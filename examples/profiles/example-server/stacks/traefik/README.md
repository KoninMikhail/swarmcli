# Traefik — Reverse Proxy

Registry service based on [Traefik v3](https://doc.traefik.io/traefik/).

## What It Demonstrates

- **`type: registry`** — ready image from DockerHub, no build
- **Docker Configs (simple strategy)** — config file `traefik.yml` is created as Docker config once; on subsequent deploys, existence is checked
- **Static `docker-stack.yml`** — no Jinja2 templating
- **Placement constraints** — binding to manager node (`node.role == manager`)
- **Healthcheck** — built-in `traefik healthcheck` check
- **Host mode ports** — ports 80/443 directly on host (without ingress routing mesh)

## Files

```
traefik/
├── services.yaml       — service definition (registry)
├── settings.yaml       — readiness timeout (20 sec)
├── externals.yaml      — Docker config (simple strategy)
├── docker-stack.yml    — Docker Compose for Swarm
├── configs/
│   └── traefik.yml     — Traefik static configuration
└── README.md
```

## How It Works

1. On first deploy, CLI creates Docker config `traefik_config` from `configs/traefik.yml`
2. Config is mounted inside container as `/etc/traefik/traefik.yml`
3. Traefik automatically discovers services via Docker Swarm provider
4. Routing is configured via deploy labels in each stack's docker-stack.yml

## Routing Other Services

To make a stack accessible via Traefik, add labels to its `deploy` section:

```yaml
deploy:
  labels:
    - traefik.enable=true
    - traefik.http.routers.my-app.rule=Host(`my-app.example.localhost`)
    - traefik.http.routers.my-app.entrypoints=web
    - traefik.http.services.my-app.loadbalancer.server.port=8080
```

## Updating Config

With simple strategy, config is not recreated automatically. To update:

```bash
# Remove old config
docker config rm traefik_config

# Deploy will create new one
swarmcli deploy traefik
```

For automatic versioning use `config_strategy: versioned` (see `monitoring` stack).
