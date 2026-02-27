# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-02-27

Security and quality patch — resolves all audit findings.

### Security
- Path traversal prevention in plugins, hooks, config export, and resource names
- GIT_ASKPASS mechanism — Git tokens no longer visible in `ps aux`
- Deploy lock now released on any exit (trap EXIT added)
- Unsafe `source` of temp YAML file replaced with safe `read` loop with variable name validation
- Build timeout applied to `docker build` / `docker buildx build` (exit code 124 handling)
- Plugin return codes checked and propagated
- CI GitHub Actions pinned to SHA hashes (supply-chain protection)

### Changed
- jq is now a required dependency for safe JSON output (replaces string concatenation)
- JSON output (errors, deploy summary, diff, locks, profiles, logging) now uses jq for proper escaping
- Profile config validation: schema check for top-level, nested keys, required `name` field
- Config `set` command validates keys against whitelist from defaults
- Python 3.6+ version guard in installer
- Sudo warning when running installer as root
- ShellCheck CI severity lowered to `warning` for better lint coverage
- All Python files now checked with `py_compile` in CI
- GitLab-specific token placeholders replaced with generic ones
- Rollback build uses safe array expansion (no word-splitting)

### Added
- Alpine (apk) and Arch Linux (pacman) package manager support
- Fish shell RC support in installer
- `validate-examples` CI job for example profiles
- `try/except ImportError` guards in all Python modules using PyYAML
- `ruamel.yaml` support for comment-preserving YAML writes (with fallback)
- Atomic secret rotation with versioned names
- Atomic history.jsonl writes via temp file
- Lock TOCTOU fix (mv-based instead of rm+mkdir)
- `get_python_cmd()` centralized in `core/utils.sh`
- Temp file cleanup via RETURN traps in git sync operations

### Fixed
- 57/63 first-audit issues + 14 new issues resolved (90%+ fix rate)
- POSIX `sleep` fallback for non-GNU environments
- Documentation: 33 GitLab URLs → GitHub, timestamps, path corrections, terminology
- `.gitignore` patterns for `.env.*`, `venv/`, `.mypy_cache/`
- Hardcoded `/tmp/` replaced with `${TMPDIR:-/tmp}` in deploy temp files
- Silent `/tmp` fallback for build logs now warns user
- Hook templates use `set -euo pipefail` (added `-u`)
- Deprecated `url_with_http_auth()` removed (dead code)

## [0.1.0] - 2026-02-27

Initial open-source release.

### Added

#### Core
- CLI entry point (`bin/swarm.sh`) with modular architecture
- Profile-based server isolation — one repo, multiple servers (dev, prod, staging)
- Declarative stack configuration via YAML (services.yaml, variables.yaml, externals.yaml, settings.yaml)
- Global variables and resource definitions per profile (globals.yaml, resources.yaml)
- Built-in YAML parser (no `yq`); jq required for safe JSON output
- Docker-familiar command names: `ls`, `ps`, `logs`, `deploy`, `build`, `rollback`
- Command aliases (`d` → deploy, `b` → build, `s` → ps, `l` → logs)
- Global flags: `--profile`, `--json`, `--quiet`, `--no-color`, `--verbose`, `--dry-run`

#### Deployment
- One-command deploy: `swarmcli deploy <stack>`
- Per-service branch and commit targeting (`--service api --branch feature/xxx`)
- Pre-deploy validation (stack config, Docker Swarm readiness, image availability)
- Deploy checkpoints — config and image tags saved before every deploy
- Post-deploy readiness verification with configurable timeout
- Deploy locking — atomic directory-based locks with PID tracking and stale detection
- Deploy history tracking per stack
- Parallel and sequential image build modes (`--parallel`)
- `--no-build`, `--config-only`, `--with-secrets`, `--force`, `--prune` flags
- Structured deploy summary with step-by-step timeline

#### Rollback
- Instant rollback: `swarmcli rollback <stack>`
- Rollback to specific version: `--to-version N`
- Automatic checkpoint restoration (compose config + image tags)

#### Git Integration
- Automatic repository sync before build (`swarmcli sync`)
- Support for SSH and HTTPS Git authentication
- Per-stack and per-service Git credential overrides
- Retry with exponential backoff and jitter for transient Git failures

#### Docker
- Image build from Git repositories (`type: git`) and public registries (`type: registry`)
- Docker Buildx support with `--load` flag
- Build cache management (`--no-cache`, cache-from)
- Build argument injection from variables.yaml

#### Templating
- Jinja2-based docker-stack.yml templating (`.j2` templates)
- Resource injection (CPU/memory limits and reservations) via `resources.yaml`
- Environment variable injection via `inject_env_vars()` template function
- Variable interpolation from globals.yaml and variables.yaml

#### Secrets Management
- Docker Secrets and Configs lifecycle management
- Secret creation: from value, file, stdin, or random generation (`secret generate`)
- Secret sync before deploy (`--with-secrets`)
- Versioned secrets (`secret_v1`, `secret_v2`) for zero-downtime rotation
- Manifest-based secret tracking per stack
- File permissions enforcement (`chmod 600` for secrets, `chmod 700` for directory)

#### Service Registry
- Cross-stack service discovery via `SERVICE_*` variables
- Registry validation (`registry check`)
- Automatic endpoint resolution from `endpoints.yaml`

#### Monitoring & Observability
- `swarmcli ps` — service replica status across stacks
- `swarmcli logs` — aggregated service logs with `--tail` and `--service` filters
- `swarmcli inspect` — detailed stack information
- `swarmcli diff` — show changed stacks since a Git ref
- JSON output mode (`--json`) for automation, webhooks, and monitoring
- Structured exit codes: 0 (success), 1 (error), 2 (deploy error), 3 (missing secrets), 4 (timeout)

#### Hooks & Plugins
- Pre-deploy and post-deploy hooks per stack (`hooks/pre-deploy.sh`, `hooks/post-deploy.sh`)
- Plugin system — executable scripts in `plugins/` directory
- Hook environment: `$STACK`, `$SWARM_PROFILE`, `$TAG_*`, `$GLOBAL_*`, `$DEPLOY_*`

#### Configuration Management
- `swarmcli config` — view and modify `.swarmcli.yaml`
- `swarmcli create` — interactive wizard for profiles, stacks, and services
- `swarmcli check` — validate stack configuration before deploy
- `swarmcli apply` — apply config changes

#### System
- `swarmcli system version` — version info
- `swarmcli system health` — dependency check (Docker, Git, jq, Python, Jinja2, PyYAML)
- `swarmcli system update` — self-update from Git

#### Operations
- Interactive installer (`install.sh`) with `--dry-run`, `--yes`, `--skip-deps` modes
- Uninstaller (`uninstall.sh`) with config backup
- Signal handling — graceful shutdown, child process cleanup, SIGINT/SIGTERM support
- Cancellation support — safe abort during deploy with cleanup
- Retry logic with exponential backoff and jitter for Docker and Git operations
- Dry-run mode across all mutating operations

#### Documentation
- Full documentation suite (47 files) covering onboarding, concepts, guides, reference, architecture, and operations
- CLI command reference with examples
- Configuration format reference for all YAML files
- Architecture documentation with Mermaid diagrams
- ADR (Architecture Decision Records) framework

[Unreleased]: https://github.com/KoninMikhail/swarmcli/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/KoninMikhail/swarmcli/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/KoninMikhail/swarmcli/releases/tag/v0.1.0
