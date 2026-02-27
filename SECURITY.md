# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 0.x     | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in SwarmCLI, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, please send an email to **dev.konin@gmail.com** with:

1. A description of the vulnerability
2. Steps to reproduce
3. Potential impact
4. Suggested fix (if any)

### What to expect

- **Acknowledgment** within 48 hours
- **Assessment** within 7 days
- **Fix or mitigation** for confirmed vulnerabilities within 30 days
- Credit in the release notes (unless you prefer to remain anonymous)

## Security Best Practices for Users

### Secrets Management

- **Never** store secrets in `variables.yaml` — use Docker Swarm Secrets via `externals.yaml`
- Keep `.swarmcli.yaml` out of version control (already in `.gitignore`)
- Use deploy tokens with minimal scope for Git authentication
- Rotate credentials regularly

### File Permissions

- Ensure `.secrets/` directory has restricted permissions: `chmod 700 .secrets/`
- Secret files should be readable only by the deploy user: `chmod 600 .secrets/*`

### Network Security

- SwarmCLI operates over SSH for remote deployments — ensure SSH keys are properly secured
- Use Docker overlay networks with encryption for sensitive traffic
- Restrict Docker socket access via socket proxy (e.g., tecnativa/docker-socket-proxy)

## Security Features in SwarmCLI

- `SECRETS_ROOT` is enforced from `.swarmcli.yaml` only — environment variable overrides are blocked
- Git credentials are sanitized in error messages and logs
- Deployment locks prevent concurrent conflicting operations
- Signal handlers ensure graceful cleanup of sensitive temporary files
