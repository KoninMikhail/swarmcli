# down

Remove a deployed stack from Docker Swarm.

## Syntax

```bash
swarmcli down <stack> [flags]
```

Aliases: `rm`, `remove`

## Description

The `down` command removes a deployed stack from Docker Swarm:

1. Check that the stack exists in the profile
2. Check that the stack is currently deployed
3. Ask for confirmation (unless `--force`)
4. Run `docker stack rm`
5. Wait for services to stop (up to 30 seconds)

If the stack is not deployed, the command exits with a warning and returns success.

## Arguments

| Argument | Description |
|----------|-------------|
| `stack` | Stack name (required, or interactive selection) |

## Flags

| Flag | Description |
|------|-------------|
| `--force`, `-f` | Skip confirmation prompt |
| `--dry-run` | Preview without execution (global flag) |

## Examples

### Remove stack with confirmation

```bash
swarmcli down my-app
```

Output:
```
This will remove stack: my-app
  • Services: 3
  • Profile: server-dev

Continue? [y/N]: y
[INFO] removing stack: my-app
[OK] stack removed: my-app
[INFO] waiting for services to stop...
[OK] stack 'my-app' removed successfully
```

### Remove stack without confirmation

```bash
swarmcli down my-app --force
```

### Using aliases

```bash
swarmcli rm my-app --force
swarmcli remove my-app
```

### Dry-run

```bash
swarmcli down my-app --dry-run
```

### In CI/CD

```bash
swarmcli down my-app --force
```

## Behavior

- **Interactive mode**: asks for confirmation before removing
- **Non-interactive mode** (piped input): requires `--force`
- **Not deployed**: prints warning, exits with code 0
- **Dry-run**: prints what would happen, does not remove

## Exit Codes

| Code | Description |
|------|-------------|
| 0 | Stack removed successfully (or was not deployed) |
| 1 | Error (stack not found, docker error) |

## See also

- [deploy](01-deploy.md) — deploy stack
- [rollback](02-rollback.md) — rollback to previous version
- [CLI overview](00-overview.md) — all commands
