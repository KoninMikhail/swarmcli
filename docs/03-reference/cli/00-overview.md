# CLI Reference

Complete SwarmCLI command reference.

## Syntax

```bash
swarmcli [global-flags] <command> [subcommand] [args] [flags]
```

## Command Groups

| Group | Description |
|-------|-------------|
| [System](#system) | System commands (version, health, update) |
| [Global](#global) | Global commands (help, use, create) |
| [Profile](#profile) | Profile management |
| [Stack](#stack) | Stack operations |
| [Build & Deploy](#build--deploy) | Build and deploy |
| [Secret](#secret) | Secrets management |
| [Lock](#lock) | Lock management |
| [Registry](#registry) | Service registry |
| [Plugin](#plugin) | Plugins |

## Global Flags

| Flag | Description |
|------|-------------|
| `--profile <name>` | Server profile |
| `--json` | JSON output for automation |
| `--quiet` | Suppress info messages |
| `--no-color` | Disable colored output |
| `--verbose` | Verbose output |
| `--dry-run` | Preview without execution |

## System

### system version

Show CLI version:

```bash
swarmcli system version
```

### system health

Check dependencies:

```bash
swarmcli system health
```

### system update

Update SwarmCLI from git:

```bash
swarmcli system update [branch]
```

## Global

### help

Show help:

```bash
swarmcli help
swarmcli --help
swarmcli -h
```

### use

Manage default profile:

```bash
# Set profile
swarmcli use server-dev

# Show current
swarmcli use --show

# Clear
swarmcli use --clear
```

### create

Interactive creation wizard:

```bash
swarmcli create
```

## Profile

### profile ls

List profiles:

```bash
swarmcli profile ls
```

### profile inspect

Profile information:

```bash
swarmcli profile inspect [name]
```

## Stack

### ls

List stacks:

```bash
swarmcli ls
```

### ps

Stack status:

```bash
# All stacks
swarmcli ps

# Specific stack
swarmcli ps my-app
```

### logs

Service logs:

```bash
swarmcli logs <stack> [--service <name>] [--tail N]
```

### inspect

Detailed stack information:

```bash
swarmcli inspect <stack>
```

### check

Configuration validation:

```bash
swarmcli check [stack]
```

## Build & Deploy

### [sync](05-sync.md)

Repository sync:

```bash
swarmcli sync [stack] [--tree] [--verbose]
```

Aliases: `pull`, `repo sync`

### build

Build images:

```bash
swarmcli build [stack] [flags]
```

Flags:
- `--service <name>` — specific service
- `--branch <name>` — branch for all services
- `--force` — force rebuild
- `--no-cache` — no Docker cache

### deploy

Deploy stack:

```bash
swarmcli deploy [stack] [flags]
```

Flags:
- `--service <name>` — specific service
- `--branch <name>` — branch for previous `--service`
- `--commit <sha>` — commit for previous `--service`
- `--with-secrets` — sync secrets
- `--no-build` — skip build
- `--config-only` — config only
- `--force` — force rebuild
- `--prune` — remove old images

### rollback

Rollback to previous version:

```bash
swarmcli rollback <stack> [--to-version N]
```

### diff

Show changed stacks:

```bash
swarmcli diff [--since <ref>]
```

### apply

Apply config changes:

```bash
swarmcli apply
```

## Secret

### secret ls

List secrets:

```bash
swarmcli secret ls
```

### secret check

Check stack secrets:

```bash
swarmcli secret check <stack>
```

### secret sync

Sync secrets:

```bash
swarmcli secret sync
```

### secret create

Create secret:

```bash
swarmcli secret create <name> [options]
```

Options:
- `--value <val>` — value directly
- `--from-file <path>` — from file
- `--stdin` — from stdin
- `--no-docker` — only create file, don't publish to Docker
- `--force` — overwrite

### secret rm

Remove secret:

```bash
swarmcli secret rm <name> [--keep-file] [--force]
```

### secret generate

Generate random secret:

```bash
swarmcli secret generate <name> [--length N] [--chars CHARS]
```

Options:
- `--length <N>` — secret length (default: 32)
- `--chars <set>` — character set (default: `A-Za-z0-9`)

## Lock

### lock ls

List active locks:

```bash
swarmcli lock ls
```

### lock prune

Remove stale locks:

```bash
swarmcli lock prune
```

### lock rm

Force release lock:

```bash
swarmcli lock rm <stack>
```

## Registry

### registry ls

List services in registry:

```bash
swarmcli registry ls
```

### registry check

Validate SERVICE_* references:

```bash
swarmcli registry check
```

## Plugin

### plugin

Work with plugins:

```bash
# List plugins
swarmcli plugin

# Run plugin
swarmcli plugin <name> [args]
```

## Aliases

| Alias | Command |
|-------|---------|
| `d` | `deploy` |
| `b` | `build` |
| `s` | `ps` |
| `l` | `logs` |
| `list` | `ls` |
| `status` | `ps` |
| `validate` | `check` |
| `profiles` | `profile` |
| `secrets` | `secret` |
| `locks` | `lock` |

## Examples

```bash
# Basic workflow
swarmcli use server-dev
swarmcli ls
swarmcli deploy my-app

# Deploy feature branch
swarmcli deploy my-app --branch feature/new

# Deploy only API from different branch
swarmcli deploy my-app --service api --branch hotfix/fix

# Rollback
swarmcli rollback my-app

# JSON for automation
swarmcli ps my-app --json

# Dry-run
swarmcli deploy my-app --dry-run
```

## Exit Codes

| Code | Description |
|------|-------------|
| 0 | Success |
| 1 | General error |
| 2 | Deploy error |
| 3 | Missing secrets |
| 4 | Timeout |
