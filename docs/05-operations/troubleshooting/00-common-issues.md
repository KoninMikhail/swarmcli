# Common Issues

Solutions for common problems when working with SwarmCLI.

## Diagnostics

### Diagnostic Commands

```bash
# Check system health
swarmcli system health

# Stack configuration validation
swarmcli check my-stack

# Service status
swarmcli ps my-stack

# Service logs
swarmcli logs my-stack --service api
```

### Docker Commands

```bash
# Service status
docker service ls

# Service details
docker service ps my-stack_api --no-trunc

# Logs
docker service logs my-stack_api --tail 100

# Inspect
docker service inspect my-stack_api
```

## Installation Issues

### "command not found: swarmcli"

**Cause:** symlink not created or not in PATH.

**Solution:**

```bash
# Check symlink
ls -la /usr/local/bin/swarmcli

# Recreate
sudo ln -sf /opt/swarmcli/bin/swarm.sh /usr/local/bin/swarmcli

# Check PATH
echo $PATH | grep -q "/usr/local/bin" || export PATH="/usr/local/bin:$PATH"
```

### "Permission denied"

**Cause:** no execute permissions on scripts.

**Solution:**

```bash
chmod +x /opt/swarmcli/bin/swarm.sh
chmod +x /opt/swarmcli/bin/lib/*.sh

# If error when accessing Docker
sudo usermod -aG docker $USER
# Re-login!
```

### "bash: bad array subscript"

**Cause:** Bash version < 4.0.

**Solution:**

```bash
# Check version
bash --version

# Update
sudo apt update && sudo apt install bash
```

## Profile Issues

### "profile not found"

**Cause:** profile doesn't exist or typo.

**Solution:**

```bash
# List profiles
swarmcli profile ls

# Check structure
ls -la profiles/
```

### "no default profile set"

**Cause:** default profile not set.

**Solution:**

```bash
# Set
swarmcli use server-dev

# Verify
swarmcli use --show
```

## Validation Issues

### "services.yaml not found"

**Cause:** services.yaml file missing in stack.

**Solution:**

```bash
# Check stack structure
ls -la profiles/server-dev/stacks/my-stack/

# Create services.yaml
cat > profiles/server-dev/stacks/my-stack/services.yaml << 'EOF'
services:
  api:
    type: git
    repo: git@github.com:org/api.git
    default_branch: main
    build:
      context: .
      dockerfile: Dockerfile
    image: local/api
EOF
```

### "unknown service type"

**Cause:** incorrect service type.

**Solution:**

```yaml
# Valid types:
services:
  api:
    type: git       # For build from Git
    # ...
    
  redis:
    type: registry  # For public images
    image: redis:7-alpine
```

### "required secret not found"

**Cause:** secret not created in Docker Swarm.

**Solution:**

```bash
# Check secrets
docker secret ls

# Create secret
swarmcli secret create my_secret

# Or sync all
swarmcli secret sync
```

## Git Issues

### "repository not synced"

**Cause:** repository not cloned.

**Solution:**

```bash
# Sync
swarmcli sync my-stack

# Or manually
cd /opt/swarmcli/repos
git clone git@github.com:org/api.git api
```

### "Permission denied (publickey)"

**Cause:** SSH key not configured or not added.

**Solution:**

```bash
# Check SSH key
ssh -T git@github.com

# Add key to ssh-agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# For CI/CD — check SSH_PRIVATE_KEY variable
```

### "could not resolve host"

**Cause:** DNS or network issues.

**Solution:**

```bash
# Check DNS
nslookup github.com

# Check network
ping github.com

# Use HTTP with token
export GIT_HTTP_TOKEN="your-token"
```

## Build Issues

### "build failed after retries"

**Cause:** Docker build error.

**Solution:**

```bash
# Build with verbose logs
swarmcli build my-stack --verbose

# Build manually
cd /opt/swarmcli/repos/api
docker build -t test:latest .
```

### "no space left on device"

**Cause:** disk space exhausted.

**Solution:**

```bash
# Clean Docker
docker system prune -a --volumes

# Clean old stack images
swarmcli deploy my-stack --prune

# Check space
df -h
```

### "BuildKit not supported"

**Cause:** old Docker version.

**Solution:**

```bash
# Check version
docker --version

# Update Docker
sudo apt update && sudo apt install docker-ce

# Disable BuildKit (workaround)
export DOCKER_BUILDKIT=0
```

## Deploy Issues

### "cannot acquire deployment lock"

**Cause:** another deploy in progress or stuck lock.

**Solution:**

```bash
# Check locks
swarmcli lock ls

# Clean stale
swarmcli lock prune

# Force remove
swarmcli lock rm my-stack
```

### "timeout waiting for services"

**Cause:** services didn't start in time.

**Solution:**

```bash
# Increase timeout
# In stack settings.yaml:
services_ready_timeout: 120

# Check cause
docker service ps my-stack_api --no-trunc
docker service logs my-stack_api --tail 50
```

### "image not found"

**Cause:** image not built or not loaded.

**Solution:**

```bash
# Check images
docker images | grep my-stack

# Rebuild
swarmcli build my-stack --force

# Deploy with rebuild
swarmcli deploy my-stack --force
```

### "network not found"

**Cause:** network doesn't exist.

**Solution:**

```bash
# Create network
docker network create --driver overlay my-network

# Or add to docker-stack.yml:
networks:
  my-network:
    driver: overlay
```

## Resource Issues

### "OOMKilled"

**Cause:** service exceeded memory limit.

**Solution:**

```yaml
# resources.yaml — increase limit
stacks:
  my-stack:
    api:
      limits:
        memory: "4G"  # Was 2G
```

### "no resources available"

**Cause:** insufficient resources on nodes.

**Solution:**

```bash
# Check node resources
docker node ls
docker node inspect <node-id> --format '{{.Description.Resources}}'

# Reduce reservations
stacks:
  my-stack:
    api:
      reservations:
        memory: "512M"  # Less reservation
```

## Hook Issues

### "hook not executable"

**Cause:** no execute permissions.

**Solution:**

```bash
chmod +x hooks/pre-deploy.sh
chmod +x hooks/post-deploy.sh
```

### "hook failed with exit code"

**Cause:** error in hook script.

**Solution:**

```bash
# Run manually
cd profiles/server-dev/stacks/my-stack
STACK=my-stack SWARM_PROFILE=server-dev ./hooks/pre-deploy.sh

# Add set -x for debug
#!/bin/bash
set -euxo pipefail  # x for trace
```

## Secret Issues

### "secret already exists"

**Cause:** secret with that name already exists.

**Solution:**

```bash
# Remove old
swarmcli secret rm old_secret

# Create new
swarmcli secret create old_secret
```

### "secret not accessible"

**Cause:** secret not mounted to service.

**Solution:**

```yaml
# docker-stack.yml
services:
  api:
    secrets:
      - pg_password
      
secrets:
  pg_password:
    external: true
```

## Logs and Debugging

### Verbose mode

```bash
swarmcli deploy my-stack --verbose
```

### JSON logs

```bash
swarmcli deploy my-stack --json 2>&1 | jq .
```

### Dry-run

```bash
swarmcli deploy my-stack --dry-run
```

### Docker logs

```bash
# All service logs
docker service logs my-stack_api

# Last 100 lines
docker service logs my-stack_api --tail 100

# Follow mode
docker service logs my-stack_api -f

# With timestamps
docker service logs my-stack_api --timestamps
```

## Useful Commands

```bash
# Restart service
docker service update --force my-stack_api

# Scale
docker service scale my-stack_api=3

# Rollback
swarmcli rollback my-stack

# Inspect task
docker inspect $(docker service ps -q my-stack_api | head -1)

# Connect to container
docker exec -it $(docker ps -q -f name=my-stack_api) /bin/sh
```

## See also

- [Deploy issues](01-deploy-failures.md)
- [Installation](../server/00-installation.md)
- [Deploy process](../../01-concepts/06-deploy-flow.md)
