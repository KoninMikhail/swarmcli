# Secrets Security Model

## Architecture Overview

SwarmCLI uses a two-tier secrets storage model:

```
┌─────────────────────┐     swarmcli secret sync     ┌──────────────────────────┐
│  .secrets/          │  ──────────────────────────>  │  Docker Swarm Secrets    │
│  (files on disk)    │                               │  (encrypted Raft store)  │
│                     │                               │                          │
│  db_password        │                               │  db_password             │
│  jwt_key            │                               │  jwt_key                 │
│  api_token          │                               │  api_token               │
└─────────────────────┘                               └──────────────────────────┘
   Intermediate storage                                Final storage
   (plain text)                                         (encryption in Raft)
```

**Key distinction:**

- `.secrets/` — **convenience layer** for managing secrets. This is not a security boundary.
- **Docker Swarm Secrets** — final storage with encryption in Raft store and delivery via tmpfs to containers.

## Threat model

### What it protects against

| Threat | Protection | Mechanism |
|--------|------------|-----------|
| Secrets in git repository | ✅ Yes | `.gitignore` contains `.secrets/` |
| Path override via env | ✅ Yes | `SECRETS_ROOT` read only from `.swarmcli.yaml` |
| Secrets in CLI logs | ✅ Yes | Values not logged, Git credentials sanitized |
| Accidental access by other users | ✅ Partial | `chmod 600/700` on files and directory |
| Secrets in docker-stack.yml variables | ✅ Yes | Delivery via `/run/secrets/` (tmpfs) |

### What it does NOT protect against

| Threat | Status | Explanation |
|--------|--------|-------------|
| Server filesystem access (root/sudo) | ❌ | Plain text on disk. Root access = all secrets |
| `git add -f .secrets/` | ❌ | `.gitignore` can be bypassed with force-add |
| No access audit | ❌ | No logs of who and when read a secret |
| Automatic rotation | ❌ | Rotation only manual |
| Encryption at rest | ❌ | Files not encrypted on disk |
| Centralization across servers | ❌ | Each server stores its own copy |

## Comparison with alternatives

| Criterion | `.secrets/` (SwarmCLI) | HashiCorp Vault | AWS Secrets Manager | SOPS |
|-----------|------------------------|-----------------|---------------------|-----|
| Implementation complexity | Minimal | High | Medium | Low |
| Encryption at rest | ❌ | ✅ | ✅ | ✅ |
| Access audit | ❌ | ✅ | ✅ | Via git |
| Automatic rotation | ❌ | ✅ | ✅ | ❌ |
| Centralization | ❌ | ✅ | ✅ | Via git |
| Cost | Free | Free (self-hosted) / $$ (Cloud) | $$ | Free |
| Additional infrastructure | No | Yes (Vault server) | Yes (AWS) | No |
| Docker Swarm compatibility | Native | Requires integration | Requires integration | Requires script |

### When `.secrets/` is sufficient

- 1–5 servers
- Team up to 10 people
- No compliance requirements (SOC2, PCI DSS, HIPAA)
- Fewer than ~50 secrets
- Secret rotation is rare

### When external system is needed

- Compliance requirements with mandatory access audit
- 10+ servers with shared secrets
- Need for automatic rotation
- Multi-cloud infrastructure
- Strict encryption at rest requirements

## Hardening Recommendations

### 1. Store secrets outside the project

By default `paths.secrets` points to `.secrets` inside `PLATFORM_ROOT`. It is recommended to change to a directory **outside** the project:

```yaml
# .swarmcli.yaml
paths:
  secrets: ../secrets
```

This reduces the risk of accidental git inclusion and isolates secrets from CLI updates.

### 2. Set strict access permissions

```bash
# Secrets directory
chmod 700 /path/to/secrets

# Secret files
chmod 600 /path/to/secrets/*

# Owner — deploy user only
chown deploy:deploy /path/to/secrets -R
```

### 3. Verify .gitignore

Ensure `.secrets/` is in `.gitignore`:

```bash
grep -q '.secrets/' .gitignore || echo '.secrets/' >> .gitignore
```

Additionally, add a pre-commit hook:

```bash
#!/bin/bash
# .git/hooks/pre-commit
if git diff --cached --name-only | grep -q '\.secrets/'; then
  echo "ERROR: Attempting to commit files from .secrets/"
  echo "Remove them: git reset HEAD .secrets/"
  exit 1
fi
```

### 4. Use generation instead of manual input

```bash
swarmcli secret generate db_password --length 32
swarmcli secret generate api_key --length 64
```

Generated secrets are stronger than manually invented ones.

### 5. Minimize file lifetime

In CI/CD create secret files immediately before deploy and delete after:

```bash
echo "$CI_DB_PASSWORD" > "$SECRETS_ROOT/db_password"
swarmcli deploy my-app --with-secrets
rm -f "$SECRETS_ROOT/db_password"
```

### 6. Restrict SSH access to server

Since secret protection depends on filesystem permissions, server access must be restricted:

- SSH key authentication only (disable passwords)
- Minimum number of users with access
- SSH session logging

## FAQ

### Why no encryption at rest?

SwarmCLI focuses on simplicity. Encrypting secret files would require managing encryption keys, which essentially shifts the problem: instead of "where to store secrets" — "where to store the key to secrets".

For projects requiring encryption at rest, SOPS or an external secret manager is recommended.

### Why plain text files, not environment variables?

- Files don't appear in `/proc/<pid>/environ` (accessible to any user process)
- Docker Swarm `docker secret create` accepts a file — this is the native workflow
- Files are easier to control via filesystem permissions
- Environment variables are inherited by child processes, files are not

### What if the server is compromised?

If an attacker gained root access to the server — all secrets in `.secrets/` are compromised. This is a limitation of any system storing secrets locally. In this case:

1. Revoke all compromised secrets
2. Rotate all passwords and keys
3. Recreate Docker Swarm secrets: `swarmcli secret sync --force`
4. Conduct server access audit

### Can SwarmCLI be used with an external secret manager?

Yes. SwarmCLI does not impose `.secrets/` as the only method. You can:

- Populate `.secrets/` from Vault/AWS SM in CI/CD pipeline before deploy
- Use `--stdin` to pass secrets from external source
- Write a wrapper script that pulls secrets from external storage

```bash
# Example: pull from Vault before deploy
vault kv get -field=value secret/db_password | \
  swarmcli secret create db_password --stdin --force
```

## See also

- [Secrets management — overview](./00-overview.md)
- [Security Policy](../../../SECURITY.md)
- [Docker Swarm secrets (docs.docker.com)](https://docs.docker.com/engine/swarm/secrets/)
