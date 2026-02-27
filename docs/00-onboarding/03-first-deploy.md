# First Deploy

Deploy a test application in 5 minutes.

## What We'll Do

1. Create a simple stack with Nginx
2. Deploy it
3. Verify status
4. Remove it (optional)

## Step 1: Creating the Stack

There are two ways to create a stack:

| Method | When to use |
|--------|-------------|
| `swarmcli create` | Quick creation with correct structure and documenting comments |
| Manual | Full control, copying from existing examples |

### Option A: Via Wizard (`swarmcli create`)

The interactive wizard creates a stack skeleton with the correct structure.

```bash
swarmcli create
```

The wizard will guide you through several steps:

```
✦ Create New Stack

  Select profile:

    1) server-dev
    2) server-prod

  → 1

  Selected: server-dev

  Stack name: hello-world

  Stack settings (leave empty for profile defaults):
  Services ready timeout (seconds): 30
  Diagnostics log tail lines: 20

  ✅ Stack created: profiles/server-dev/stacks/hello-world

  Files created:
    • services.yaml (service definitions)
    • variables.yaml (build/deploy variables)
    • externals.yaml (secrets and configs)
    • settings.yaml (stack settings)
    • docker-stack.yml (Docker Compose for Swarm)
    • hooks/pre-deploy.sh
    • hooks/post-deploy.sh
```

The wizard creates template files with comments and examples. Fill in the key files for the hello-world stack.

**services.yaml** — replace contents:

```yaml
services:
  web:
    type: registry
    image: nginx:alpine
    meta:
      group: demo
      name: Hello World Web
```

**docker-stack.yml** — replace contents:

```yaml
services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
    environment:
      - TZ=${GLOBAL_TZ:-UTC}
    deploy:
      replicas: 1
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure

networks:
  default:
    driver: overlay
```

Other files (`variables.yaml`, `externals.yaml`, `settings.yaml`, hooks) can be left unchanged — default templates work for a simple stack.

### Option B: Manual

Create the stack structure and files yourself.

#### Structure

```bash
cd /opt/swarmcli/profiles/server-dev/stacks

mkdir -p hello-world/hooks
cd hello-world
```

#### services.yaml

```yaml
services:
  web:
    type: registry
    image: nginx:alpine
    meta:
      group: demo
      name: Hello World Web
```

#### docker-stack.yml

```yaml
services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
    environment:
      - TZ=${GLOBAL_TZ:-UTC}
    deploy:
      replicas: 1
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure

networks:
  default:
    driver: overlay
```

#### settings.yaml

```yaml
services_ready_timeout: 30
diagnostics_logs_tail: 20
```

#### variables.yaml

```yaml
# build — for docker build --build-arg
# runtime.env — for inject_env_vars() in Jinja2 templates
runtime:
  env:
    LOG_LEVEL: info
```

#### externals.yaml

```yaml
secrets: []
```

#### hooks

**hooks/pre-deploy.sh:**

```bash
#!/usr/bin/env bash
set -eo pipefail

STACK="${1:-unknown}"
echo "[pre-deploy] running for stack: $STACK"
```

**hooks/post-deploy.sh:**

```bash
#!/usr/bin/env bash
set -eo pipefail

STACK="${1:-unknown}"
echo "[post-deploy] completed for stack: $STACK"
```

```bash
chmod +x hooks/*.sh
```

### Final Structure

Regardless of creation method, you should have:

```
hello-world/
├── docker-stack.yml
├── services.yaml
├── settings.yaml
├── variables.yaml
├── externals.yaml
└── hooks/
    ├── pre-deploy.sh
    └── post-deploy.sh
```

> **Note:** Instead of static `docker-stack.yml` you can use **Jinja2 (J2) templates** in `templates/` — useful for variable substitution, resource injection, and DRY configs. See [Jinja2 templating](../02-guides/templates/00-overview.md).

## Step 2: Deploy

```bash
# Return to swarmcli root
cd /opt/swarmcli

# Deploy the stack
swarmcli deploy hello-world
```

Expected output:

```
2026-01-15T10:00:00Z [info] loaded profile: server-dev

🔍 Checking configurations...
   ✅ Configurations valid

🔄 Syncing repositories...
   ✅ Repositories synced

ℹ skipping TAG export for external service: web (uses public Docker image)

🚀 Deploying stack...
   ✅ Stack deployed

   ✅ Deploy completed successfully
   ├─ Stack: hello-world
   ├─ Services: 1
   └─ Time: 5s
```

## Step 3: Verify

### Stack Status

```bash
swarmcli ps hello-world
```

```
Stack: hello-world

  Service          │ Replicas │ Image          │ Ports
  ─────────────────┼──────────┼────────────────┼──────────
  hello-world_web  │ 1/1      │ nginx:alpine   │ *:8080->80/tcp
```

### Browser Check

Open `http://your-server:8080` — you will see the Nginx page.

### Logs

```bash
swarmcli logs hello-world --service web --tail 10
```

## Step 4: Changing Configuration

### Adding a Variable

Edit `variables.yaml`:

```yaml
runtime:
  env:
    LOG_LEVEL: debug
    NGINX_WELCOME: "Hello from SwarmCLI!"
```

### Redeploy

```bash
swarmcli deploy hello-world
```

Configuration will apply without rebuilding the image (this is an external image).

## Step 5: Removal (Optional)

```bash
# Remove stack from Swarm
docker stack rm hello-world

# Remove configuration (optional)
rm -rf profiles/server-dev/stacks/hello-world
```

## What's Next?

### Use Jinja2 Templates

For more complex stacks with variable substitution, resource injection, and DRY configs, use Jinja2 (.j2) templates instead of static `docker-stack.yml`:

```bash
swarmcli template init hello-world
```

See: [Jinja2 templating](../02-guides/templates/00-overview.md)

### Add Your Own Service

To deploy your own application:

1. Create `services.yaml` with `type: git`
2. Specify repository and Dockerfile
3. SwarmCLI will build the image automatically

Example:

```yaml
services:
  api:
    type: git
    repo: git@github.com:your-org/api.git
    default_branch: develop
    build:
      context: .
      dockerfile: Dockerfile
    image: local/api
    meta:
      group: backend
```

### Add Secrets

```bash
# Create secret
swarmcli secret create db_password

# Specify in externals.yaml
# secrets:
#   - db_password

# Use in docker-stack.yml
# secrets:
#   db_password:
#     external: true
```

### Configure CI/CD

See [CI/CD integration](../05-operations/gitlab-ci/).

## Useful Commands

```bash
# Status of all stacks
swarmcli ps

# List stacks
swarmcli ls

# Stack information
swarmcli inspect hello-world

# Configuration validation
swarmcli check hello-world

# Rollback to previous version
swarmcli rollback hello-world

# Dry-run (preview without execution)
swarmcli deploy hello-world --dry-run
```

## Troubleshooting

### "stack not found"

Ensure that:
- Stack directory exists
- It contains `docker-stack.yml`
- Profile is selected: `swarmcli use server-dev`

### "services did not become ready"

Check logs:

```bash
docker service logs hello-world_web --tail 50
```

### "port already in use"

Change port in `docker-stack.yml`:

```yaml
ports:
  - "8081:80"  # Different port
```

---

## Next Steps

- [Concepts](../01-concepts/) — understand the architecture
- [Guides](../02-guides/) — practical how-tos
- [CLI Reference](../03-reference/cli/) — all commands
