# SwarmCLI

[![CI](https://github.com/KoninMikhail/swarmcli/actions/workflows/ci.yml/badge.svg)](https://github.com/KoninMikhail/swarmcli/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.2.0-green.svg)](CHANGELOG.md)

> Deploy to multiple Docker Swarm servers from one repo — no config drift, no rollback scripts, no CI boilerplate.

```
  Your Repo ──→ SwarmCLI ──→ ┌─ dev-server   (17 stacks)
                              ├─ prod-server  (18 stacks)
                              └─ db-server    (1 stack)
```

---

## The Problem

You manage several Docker Swarm servers — dev, staging, prod, maybe a dedicated database host. Each one has its own configs, scattered across repos or maintained by hand. Deploying means writing 50+ lines of CI pipeline per stack, copy-pasting `docker stack deploy` with slight variations. Rollback? A hand-written script you hope still works. Secrets live in `.env` files shared over Slack. A new team member spends a day just figuring out how to deploy.

SwarmCLI exists to make all of this a single command.

---

## Who Is It For

Built for **small and mid-sized teams** and **solo engineers** who run Docker Swarm on **Linux servers** — no enterprise overhead, no Kubernetes complexity.

| Role | How you use it |
|------|----------------|
| **DevOps** | Set up profiles, CI/CD pipelines, manage secrets |
| **Backend dev** | Deploy your services, check logs, rollback |
| **Frontend dev** | Deploy, check service status |
| **QA** | Deploy feature branches for testing |

If your deployments involve Docker Swarm and you want them to be boring (in a good way) — this is for you.

---

## What You Get

- **One-command deploy** — `swarmcli deploy my-stack` sends the right config to the right server. No guessing.
- **Instant rollback** — `swarmcli rollback my-stack`. Config and image tags are saved before every deploy.
- **Profile-based isolation** — one repo, different settings per server. Dev config never leaks into prod.
- **Minimal CI config** — one CLI call instead of 50 lines of pipeline YAML. Set up CI in minutes, not hours.
- **Docker-familiar commands** — `ls`, `ps`, `logs`, `deploy`. If you know Docker, you already know SwarmCLI.
- **Secure secrets** — Docker Secrets & Configs, synced automatically before deploy. No `.env` files floating around.
- **Per-stack isolation** — each stack owns its repos and data. No cross-stack conflicts.
- **JSON output** — `--json` for automation, webhooks, monitoring, n8n.

---

## Before vs After

| Without SwarmCLI | With SwarmCLI |
|------------------|---------------|
| Separate configs per server, copy-paste | Single repo, profile-based isolation |
| `docker stack deploy` + manual steps | `swarmcli deploy my-stack` |
| Custom rollback scripts | `swarmcli rollback my-stack` |
| SSH + `docker service logs` | `swarmcli logs my-stack --service api` |
| 50+ lines of CI config per stack | One CLI call, minimal pipeline config |
| Secrets in env files or manual sync | `swarmcli secret sync` + Docker Secrets |

---

## How It Works

```
1. Create a profile        →  One per server (dev, prod, db)
2. Define stacks           →  Apps with services, variables, secrets
3. swarmcli deploy <stack> →  Syncs repos → builds images → deploys
4. swarmcli ps <stack>     →  Verify everything is running
5. swarmcli rollback       →  Something wrong? One command to undo
```

Every deploy is checkpointed. Every config is validated before it reaches Docker. All from one repo.

---

## Quick Start

```bash
# Install
git clone https://github.com/KoninMikhail/swarmcli.git /opt/swarmcli && cd /opt/swarmcli
./install.sh

# Create your first profile from the example
cp -r examples/profiles/example-server profiles/my-server

# Select the profile
swarmcli use my-server

# Deploy a stack
swarmcli deploy core-backend

# Check status
swarmcli ps core-backend

# Something wrong? Rollback instantly
swarmcli rollback core-backend
```

<details>
<summary>install.sh options</summary>

```bash
./install.sh --dry-run    # Preview without changes
./install.sh -y           # Non-interactive mode
./install.sh --skip-deps  # Skip dependency installation
```

</details>

---

## Commands

SwarmCLI uses **Docker-familiar command names** — same style, same semantics:

| SwarmCLI | Docker equivalent | What it does |
|----------|-------------------|--------------|
| `swarmcli ls` | `docker stack ls` | List stacks |
| `swarmcli ps [stack]` | `docker service ps` | Service status |
| `swarmcli logs <stack>` | `docker service logs` | Service logs |
| `swarmcli build [stack]` | `docker build` | Build images |
| `swarmcli deploy [stack]` | `docker stack deploy` | Deploy stack |
| `swarmcli rollback [stack]` | — | Rollback to previous version |
| `swarmcli secret ls` | `docker secret ls` | List secrets |
| `swarmcli inspect <stack>` | `docker stack services` | Stack details |

No relearning — if you know Docker, you already know SwarmCLI.

```bash
# Profiles
swarmcli use server-dev          # Set default profile
swarmcli profile ls              # List profiles

# Stacks
swarmcli ls                      # List stacks
swarmcli ps [stack]              # Service status
swarmcli inspect <stack>         # Stack details

# Build & Deploy
swarmcli sync [stack]            # Sync repositories
swarmcli build [stack]           # Build images
swarmcli deploy [stack]          # Deploy
swarmcli rollback [stack]        # Rollback to previous version

# Logs
swarmcli logs <stack> --service api --tail 100

# Secrets
swarmcli secret ls
swarmcli secret create <name>
```

### Deploy Flags

```bash
--profile <name>     # Server profile
--branch <name>      # Branch for all services
--service <name>     # Target service
--with-secrets       # Sync secrets before deploy
--no-build           # Skip build step
--parallel           # Parallel image build
--dry-run            # Preview without execution
--json               # JSON output for automation
```

---

## CI/CD Integration

One CLI call replaces pages of pipeline config. Works with GitLab CI, GitHub Actions, and any shell-based runner.

```yaml
# GitHub Actions example
name: Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: swarmcli deploy my-app --profile server-dev
```

Also works from cron jobs, shell scripts, or manual SSH — it's just a CLI.

---

## SwarmCLI vs Alternatives

| | SwarmCLI | Raw Docker CLI | Portainer | Kubernetes |
|---|---|---|---|---|
| Profile isolation | Built-in | Manual | No | Namespaces |
| One-command deploy | Yes | Multiple steps | GUI-based | Helm |
| Built-in rollback | Yes | Manual | Limited | Yes |
| CI/CD integration | Native | DIY | Webhooks | DIY |
| Secrets management | Built-in | Manual | GUI | Built-in |
| Jinja2 templating | Built-in | No | No | Helm templates |
| Learning curve | Low | Low | Medium | High |
| Setup complexity | Minimal | Minimal | Medium | High |

SwarmCLI **does not replace Docker** — it wraps Docker Swarm operations and adds profiles, deploy history, validation, and automation on top.

---

## Project Structure

```
swarmcli/
├── bin/
│   └── swarm.sh                 # CLI entry point
├── profiles/
│   ├── server-dev/              # Dev server profile
│   │   ├── config.yaml          # Settings (swarm, git, retry)
│   │   └── stacks/              # Application stacks
│   │       ├── my-app/
│   │       │   ├── docker-stack.yml
│   │       │   ├── services.yaml
│   │       │   └── variables.yaml
│   │       └── globals.yaml
│   ├── server-prod/
│   └── server-db/
├── docs/                        # Documentation
└── install.sh
```

---

## Requirements

> **Platform:** Linux servers (Ubuntu 20.04+, Debian 11+, CentOS 8+, and other modern Linux distributions).

| Component | Minimum version |
|-----------|-----------------|
| Linux | Ubuntu 20.04+ / Debian 11+ / CentOS 8+ |
| Bash | 4.0+ |
| Docker | 20.10+ (with Swarm mode) |
| Git | 2.0+ |
| jq | 1.6+ |
| Python | 3.x (Jinja2, PyYAML) |

Written in Bash and Python — no separate runtime required. Docker and Git on target servers are enough.

---

## FAQ

**Q: Does SwarmCLI replace Docker?**
A: No. It wraps Docker Swarm operations — `docker stack deploy`, `docker build`, etc. — and adds profiles, history, and validation on top.

**Q: Can I use it without GitLab?**
A: Yes. Works with GitLab CI, GitHub Actions, and any shell-based runner. It's a standalone CLI — run it manually, over SSH, or from any automation tool.

**Q: How does rollback work?**
A: Before each deploy, SwarmCLI saves a checkpoint (stack config + image tags). `swarmcli rollback` restores the previous state.

**Q: Where are secrets stored?**
A: In files under `SECRETS_ROOT` (from `.swarmcli.yaml`). SwarmCLI syncs them to Docker Secrets before deploy.

**Q: Is Kubernetes supported?**
A: No. SwarmCLI is built specifically for Docker Swarm.

**Q: Is it production-ready?**
A: SwarmCLI is actively used in production by several companies. Bugs surface occasionally, but the tool handles real workloads with 35+ stacks across multiple servers daily.

---

## Documentation

### Getting Started

- [Overview](docs/00-onboarding/00-overview.md) — what SwarmCLI is
- [Requirements](docs/00-onboarding/01-requirements.md) — system requirements
- [Installation](docs/00-onboarding/02-installation.md) — install and configure
- [First deploy](docs/00-onboarding/03-first-deploy.md) — up and running in 5 minutes

### Concepts

- [Profiles](docs/01-concepts/03-profiles.md) — server profiles
- [Stacks](docs/01-concepts/04-stacks.md) — application stacks
- [Services](docs/01-concepts/05-services.md) — service types
- [Deploy flow](docs/01-concepts/06-deploy-flow.md) — what happens on deploy

### Guides

- [Create profile](docs/02-guides/profiles/00-create-profile.md)
- [Create stack](docs/02-guides/stacks/00-create-stack.md)
- [Jinja2 templating](docs/02-guides/templates/00-overview.md)
- [Secrets management](docs/02-guides/secrets/00-overview.md)
- [Resource management](docs/02-guides/resources/00-overview.md)

### Reference

- [CLI commands](docs/03-reference/cli/00-overview.md) — full reference
- [Configuration](docs/03-reference/config/00-overview.md) — all YAML files
- [Environment variables](docs/03-reference/variables/00-environment.md)

### Operations

- [CI/CD integration](docs/05-operations/gitlab-ci/00-overview.md) — CI/CD integration patterns

---

## Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for local setup, code style, conventional commits, and pull request process.

Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before participating. To report security vulnerabilities, see [SECURITY.md](SECURITY.md).

---

## Version

**Current:** 0.2.0

- [Changelog](CHANGELOG.md)
- [Full documentation](docs/README.md)

---

## License

MIT — see [LICENSE](LICENSE).
