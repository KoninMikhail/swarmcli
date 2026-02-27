# rollback

Rollback stack to previous version.

## Syntax

```bash
swarmcli rollback <stack> [flags]
```

## Description

The `rollback` command restores the previous stack version from deploy history:

1. Load deploy history
2. Restore configuration from checkpoint
3. Rebuild images (if needed)
4. Deploy previous version

## Arguments

| Argument | Description |
|----------|-------------|
| `stack` | Stack name (required) |

## Flags

| Flag | Description |
|------|-------------|
| `--to-version N` | Rollback to specific version (default: previous) |
| `--dry-run` | Show plan without execution |

## Examples

### Rollback to previous version

```bash
swarmcli rollback my-app
```

### Rollback to specific version

```bash
swarmcli rollback my-app --to-version 5
```

### Preview

```bash
swarmcli rollback my-app --dry-run
```

## Deploy History

Deploy history is stored inside the stack:
```
profiles/<profile>/stacks/<stack>/.deploy/
├── history.jsonl       # Deploy history (JSONL)
└── checkpoint.json     # Last checkpoint
```

Each entry in `history.jsonl` contains:
- Timestamp
- Profile
- Status (success/failed)
- Services with tags and commits

## Locks

The command uses the same locks as `deploy`:
- Acquires lock before rollback
- Releases on completion
- Graceful shutdown on interrupt

## Exit Codes

| Code | Description |
|------|-------------|
| 0 | Rollback successful |
| 1 | Error (no history, lock busy) |
| 2 | Deploy error |

## See also

- [deploy](01-deploy.md) — deploy
- [Basic deploy](../../02-guides/deployment/00-basic-deploy.md)
