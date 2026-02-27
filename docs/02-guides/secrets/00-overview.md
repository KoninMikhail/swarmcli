# Secrets Management

Secrets are stored via Docker Swarm Secrets and never end up in git.

## Security Principles

### What to store as secrets

❌ **Secrets (NOT in git) → Docker Swarm Secrets:**
- Passwords
- API keys
- Tokens
- Private keys
- Any sensitive data

✅ **Configuration (in git) → variables.yaml:**
- Hosts and ports
- Log levels
- Feature flags
- Timeouts
- Service URLs (without tokens)

## File Structure

```
/opt/
├── swarmcli/                    # PLATFORM_ROOT (swarmcli)
│   └── profiles/<profile>/
│       └── stacks/<stack>/
│           └── externals.yaml   # List of required secrets
└── secrets/                     # SECRETS_ROOT (outside swarmcli)
    ├── db_password
    ├── jwt_private_key
    └── api_key
```

> **Important:** Secrets are stored in a separate directory **outside** swarmcli (`SECRETS_ROOT`). By default when installing via `install.sh` this is `../secrets/`. This ensures:
> - Isolation of secrets from the CLI repository
> - Security when updating swarmcli
> - Ability to use the same secrets for multiple profiles

The path to secrets is configured **exclusively** through `paths.secrets` in `.swarmcli.yaml` and cannot be overridden via environment variables to prevent unauthorized access.

## Creating Secrets

### Method 1: Via CLI (recommended)

```bash
# Interactive input
swarmcli secret create db_password

# From value directly
swarmcli secret create db_password --value "my_secure_password_123"

# From file
swarmcli secret create jwt_key --from-file /path/to/key.pem

# From stdin
echo "secret_value" | swarmcli secret create api_key --stdin

# Generate random secret
swarmcli secret generate db_password --length 32
```

### Method 2: Manually

```bash
# Path to secrets directory (default: ../secrets relative to swarmcli)
SECRETS_DIR="/opt/secrets"

# Create directory
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# Create secret file
echo -n "my_secure_password_123" > "$SECRETS_DIR/db_password"

# Set permissions (important!)
chmod 600 "$SECRETS_DIR/db_password"
```

### Specify required stack secrets

```yaml
# profiles/server-prod/stacks/my-app/externals.yaml
secrets:
  - db_password
  - jwt_private_key
  - api_key
```

### Publishing to Docker Swarm

```bash
# Sync all secrets
swarmcli secret sync

# During deploy (secrets are synced automatically)
swarmcli deploy my-app --profile server-prod
```

## Usage in docker-stack.yml

```yaml
services:
  api:
    image: local/api:${TAG_API}
    environment:
      # Path to secret file
      DATABASE_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password

secrets:
  db_password:
    external: true
```

## Reading Secrets in Applications

### Node.js

```javascript
const fs = require('fs');

const dbPassword = fs.readFileSync('/run/secrets/db_password', 'utf8').trim();

const dbConfig = {
  host: process.env.DATABASE_HOST,
  port: process.env.DATABASE_PORT,
  password: dbPassword
};
```

### Python

```python
import os

with open('/run/secrets/db_password') as f:
    db_password = f.read().strip()

db_config = {
    'host': os.getenv('DATABASE_HOST'),
    'port': os.getenv('DATABASE_PORT'),
    'password': db_password
}
```

### Go

```go
package main

import (
	"os"
	"strings"
)

func readSecret(name string) string {
	data, err := os.ReadFile("/run/secrets/" + name)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

func main() {
	dbPassword := readSecret("db_password")
	// use dbPassword
}
```

## CLI Commands

### List secrets

```bash
# Secrets in Docker Swarm
swarmcli secret ls

# JSON for automation
swarmcli secret ls --json
```

### Check stack secrets

```bash
# Check presence of all required secrets
swarmcli secret check <stack> --profile <profile>

# If secret is not in Swarm but file exists in .secrets/,
# it will be created automatically
```

### Sync secrets

```bash
# Sync all secrets from .secrets/ to Docker Swarm
swarmcli secret sync
```

### Create secret

```bash
swarmcli secret create <name> [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--value <val>` | Secret value directly |
| `--from-file <path>` | Read value from file |
| `--stdin` | Read value from stdin |
| `--no-docker` | Only create file, do not publish to Docker |
| `--force` | Overwrite existing file without confirmation |

**Examples:**

```bash
# Interactive input (hidden, like password)
swarmcli secret create db_password

# From environment variable
swarmcli secret create api_key --value "$API_KEY"

# From config file
swarmcli secret create ssl_cert --from-file ./cert.pem

# In CI/CD pipeline
echo "$SECRET_VALUE" | swarmcli secret create my_secret --stdin

# File only, no Docker (for preparation)
swarmcli secret create db_password --value "test123" --no-docker
```

### Generate random secret

```bash
swarmcli secret generate <name> [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--length <N>` | Secret length (default: 32) |
| `--chars <set>` | Character set (default: `A-Za-z0-9`) |

**Examples:**

```bash
# Standard 32-character secret
swarmcli secret generate db_password

# 64-character secret
swarmcli secret generate api_key --length 64

# Digits only
swarmcli secret generate pin_code --length 6 --chars "0-9"

# With forced overwrite
swarmcli secret generate jwt_secret --length 128 --force
```

### Remove secret

```bash
swarmcli secret rm <name> [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--keep-file` | Do not delete file from `.secrets/` |
| `--force` | Without confirmation |

**Examples:**

```bash
# With confirmation
swarmcli secret rm old_password

# Without confirmation
swarmcli secret rm old_password --force

# Remove from Docker only, keep file
swarmcli secret rm db_password --keep-file
```

## Secret Rotation

When `swarmcli secret sync` detects that a secret already exists in Docker Swarm, it performs **atomic rotation** — services are updated without downtime:

### How it works

```
1. Create versioned copy:     db_password_v1709042400
2. Update each service:       docker service update
                                --secret-rm db_password
                                --secret-add source=db_password_v1709042400,target=db_password
3. Remove old secret:         docker secret rm db_password
4. Re-create original name:   docker secret create db_password (new content)
5. Cleanup:                   remove db_password_v* after next deploy
```

- **Zero downtime** — services are updated via rolling update
- **Safe** — if any step fails, old secret remains intact
- **Compatible** — `docker-stack.yml` keeps referencing `db_password` by name
- Inside containers the path `/run/secrets/db_password` stays the same

### Updating Secrets

#### Via CLI (recommended)

```bash
# 1. Update secret value
swarmcli secret create db_password --value "new_password_456" --force

# 2. Sync to Docker Swarm (triggers atomic rotation)
swarmcli secret sync
```

#### Via file

```bash
# 1. Modify secret file
echo -n "new_password_456" > /opt/secrets/db_password

# 2. Sync and deploy
swarmcli deploy my-app --profile server-prod --with-secrets
```

#### During deploy

```bash
# --with-secrets triggers secret sync before deploy
swarmcli deploy my-app --with-secrets
```

## Best Practices

### 1. File permissions

```bash
# Secret files must have 600 permissions
chmod 600 /opt/secrets/*

# Secrets directory must have 700 permissions
chmod 700 /opt/secrets
```

### 2. Repository isolation

Secrets are stored **outside** the swarmcli directory:
- Won't accidentally end up in git
- Won't be deleted when updating swarmcli
- Can have separate access permissions

### 3. Don't log secrets

```javascript
// Bad
console.log('DB Password:', dbPassword);

// Good
console.log('DB Password: [REDACTED]');
```

### 4. Use environment variables for paths

```yaml
# docker-stack.yml
environment:
  # Path to secret, not the secret itself
  DATABASE_PASSWORD_FILE: /run/secrets/db_password
```

### 5. Validate before deploy

```bash
# Always check secrets before deploy
swarmcli secret check my-app --profile server-prod
```

### 6. Use generation for passwords

```bash
# Generate strong passwords via CLI
swarmcli secret generate db_password --length 32
swarmcli secret generate api_key --length 64
```

## Troubleshooting

### "Required secrets missing"

```bash
# Check what secrets exist in Docker
docker secret ls

# Check what's required for stack
cat profiles/server-prod/stacks/my-app/externals.yaml

# Check file presence (path from SECRETS_ROOT)
ls -la /opt/secrets/

# Sync secrets
swarmcli secret sync
```

### "Secret already exists"

```bash
# Remove old and recreate
swarmcli secret rm db_password --force
swarmcli secret create db_password --value "new_value"

# Or use --force when creating
swarmcli secret create db_password --value "new_value" --force
```

### "Permission denied reading secret"

```bash
# Check secret file permissions (path from SECRETS_ROOT)
ls -la /opt/secrets/

# Fix permissions
chmod 600 /opt/secrets/*
chmod 700 /opt/secrets
```

### "Secret is in use by service(s)"

This is handled automatically by `swarmcli secret sync`. It creates a versioned copy and updates services via `docker service update`. No manual intervention needed:

```bash
# Just sync — rotation happens automatically
swarmcli secret sync
```

### "Secret file not found"

```bash
# Check file presence (path from SECRETS_ROOT)
ls /opt/secrets/db_password

# Create via CLI
swarmcli secret create db_password --value "my_value"
```

### "Secret file is empty"

```bash
# Check contents (path from SECRETS_ROOT)
cat /opt/secrets/db_password

# Recreate secret
swarmcli secret create db_password --value "my_value" --force
```

## Security Checklist

Before production:

- [ ] All secret files have `600` permissions
- [ ] `SECRETS_ROOT` directory has `700` permissions
- [ ] `SECRETS_ROOT` is outside swarmcli repository
- [ ] `variables.yaml` files do NOT contain secrets
- [ ] `externals.yaml` is up to date for each stack
- [ ] Secrets published: `swarmcli secret check --profile prod`
- [ ] Applications read secrets from files (`/run/secrets/`)
- [ ] Secrets are not logged in applications
- [ ] Generated passwords of sufficient length are used

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SECRETS_ROOT` | Path to directory with secret files (from `paths.secrets` in `.swarmcli.yaml`) | `$PLATFORM_ROOT/.secrets` |

> **⚠️ Security:** `SECRETS_ROOT` is read **exclusively** from `.swarmcli.yaml` (section `paths.secrets`) and cannot be overridden via environment variables or CI/CD.

> **Note:** When installing via `install.sh` the recommended `SECRETS_ROOT` path is `../secrets` (outside swarmcli).

## See also

- [Secrets security model](./01-security-model.md)
- [CLI secrets reference](../../03-reference/cli/00-overview.md#secret)
- [Stacks concept](../../01-concepts/04-stacks.md)
- [Architecture](../../04-architecture/00-overview.md)
