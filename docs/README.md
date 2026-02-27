# SwarmCLI — Documentation

CI/CD platform for Docker Swarm with support for server profiles.

**Version:** 0.1.0  
**Status:** CLI fully functional

---

## 📁 Documentation Structure

```
docs/
├── 00-onboarding/        → 🎓 Quick start for beginners
├── 01-concepts/          → 💡 Core concepts
├── 02-guides/            → 📖 Practical guides
├── 03-reference/         → 📚 Full reference
├── 04-architecture/      → 🏗️ System architecture
├── 05-operations/        → ⚙️ DevOps and CI/CD
└── adr/                  → 📋 Architecture Decision Records
```

---

## 🚀 Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/KoninMikhail/swarmcli.git /opt/swarmcli
cd /opt/swarmcli

# 2. Configure server profile
cp -r profiles/server-dev profiles/my-server
nano profiles/my-server/config.yaml

# 3. Set default profile
./bin/swarm.sh use my-server

# 4. Check dependencies
./bin/swarm.sh system health

# 5. Deploy a stack
./bin/swarm.sh deploy my-stack
```

---

## 📖 Table of Contents

### Getting Started

| Document | Description |
|----------|--------------|
| [Overview](00-onboarding/00-overview.md) | What swarmcli is and why you need it |
| [Requirements](00-onboarding/01-requirements.md) | System requirements |
| [Installation](00-onboarding/02-installation.md) | Installation and setup |
| [First Deploy](00-onboarding/03-first-deploy.md) | Quick start in 5 minutes |

### Concepts

| Document | Description |
|----------|--------------|
| [Glossary](01-concepts/00-glossary.md) | Docker, Swarm, swarmcli terms |
| [Docker Basics](01-concepts/01-docker-basics.md) | Docker for beginners |
| [Swarm Basics](01-concepts/02-swarm-basics.md) | Docker Swarm for beginners |
| [Profiles](01-concepts/03-profiles.md) | What is a server profile |
| [Stacks](01-concepts/04-stacks.md) | What is a stack |
| [Services](01-concepts/05-services.md) | Service types |
| [Deploy Flow](01-concepts/06-deploy-flow.md) | Detailed deploy flow |

### Guides

| Category | Documents |
|----------|-----------|
| Profiles | [Create Profile](02-guides/profiles/00-create-profile.md) |
| Stacks | [Create Stack](02-guides/stacks/00-create-stack.md), [Add Services](02-guides/stacks/01-add-services.md) |
| Resources | [CPU/Memory Management](02-guides/resources/00-overview.md) |
| Secrets | [Secrets Management](02-guides/secrets/00-overview.md) |
| Deployment | [Basic Deploy](02-guides/deployment/00-basic-deploy.md), [Advanced Deploy](02-guides/deployment/01-advanced-deploy.md) |
| Maintenance | [Rollback](02-guides/maintenance/00-rollback.md) |

### Reference

| Category | Documents |
|----------|-----------|
| CLI | [Commands Overview](03-reference/cli/00-overview.md), [deploy](03-reference/cli/01-deploy.md) |
| Configuration | [Overview](03-reference/config/00-overview.md), [config.yaml](03-reference/config/01-config-yaml.md), [globals.yaml](03-reference/config/02-globals-yaml.md), [resources.yaml](03-reference/config/03-resources-yaml.md), [services.yaml](03-reference/config/04-services-yaml.md), [variables.yaml](03-reference/config/05-variables-yaml.md), [externals.yaml](03-reference/config/06-externals-yaml.md), [settings.yaml](03-reference/config/07-settings-yaml.md), [endpoints.yaml](03-reference/config/08-endpoints-yaml.md) |
| Modules | [Modules Overview](03-reference/modules/00-overview.md) |
| Variables | [Environment Variables](03-reference/variables/00-environment.md) |

### Operations

| Document | Description |
|----------|--------------|
| [CI/CD](05-operations/gitlab-ci/) | CI/CD integration |
| [Troubleshooting](05-operations/troubleshooting/) | Problem solving |

---

## 🔍 Quick Search

| Looking for... | Where to find |
|----------------|---------------|
| services.yaml format | [03-reference/config/04-services-yaml.md](03-reference/config/04-services-yaml.md) |
| How to create a stack | [02-guides/stacks/00-create-stack.md](02-guides/stacks/00-create-stack.md) |
| CLI deploy command | [03-reference/cli/01-deploy.md](03-reference/cli/01-deploy.md) |
| All CLI commands | [03-reference/cli/00-overview.md](03-reference/cli/00-overview.md) |
| What is a profile | [01-concepts/03-profiles.md](01-concepts/03-profiles.md) |
| Resource management | [02-guides/resources/00-overview.md](02-guides/resources/00-overview.md) |
| Secrets management | [02-guides/secrets/00-overview.md](02-guides/secrets/00-overview.md) |
| Rollback | [02-guides/maintenance/00-rollback.md](02-guides/maintenance/00-rollback.md) |
| Environment variables | [03-reference/variables/00-environment.md](03-reference/variables/00-environment.md) |
| Glossary | [01-concepts/00-glossary.md](01-concepts/00-glossary.md) |

---

## 📝 Contributing to Documentation

When adding new pages:

1. **Numbered folders** (`00-`, `01-`, ...) — reading order
2. **kebab-case** — all names in lowercase with hyphens
3. **Self-documenting names** — content is clear from the name

When making architectural decisions — create ADR in [`adr/`](adr/).
