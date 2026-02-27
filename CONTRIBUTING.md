# Contributing to SwarmCLI

Thank you for considering contributing to SwarmCLI! This guide will help you get started.

## Getting Started

### Prerequisites

- Ubuntu Server 20.04+ (or any Linux with Bash 4.0+)
- Docker 20.10+ with Swarm mode enabled
- Git 2.0+
- jq 1.6+
- Python 3.x with `pip`

### Local Setup

```bash
# Clone the repository
git clone https://github.com/KoninMikhail/swarmcli.git
cd swarmcli

# Install Python dependencies
pip install -r requirements.txt

# Run the installer (creates symlink and .swarmcli.yaml)
./install.sh --dry-run   # preview first
./install.sh

# Verify installation
swarmcli system version
swarmcli system health
```

### Project Structure

```
swarmcli/
├── bin/
│   ├── swarm.sh              # CLI entry point
│   └── lib/                  # Shell modules (organized by function)
│       ├── core/             # Logging, errors, retry, time
│       ├── commands/         # CLI commands (deploy, build, sync, etc.)
│       ├── deploy/           # Deployment logic
│       ├── docker/           # Docker operations
│       ├── templates/        # Jinja2 templating (includes templates.py)
│       └── ...               # Other modules
├── profiles/                 # Server profiles (example-server for reference)
├── docs/                     # Documentation
├── scripts/                  # Utility scripts
└── plugins/                  # Plugin system
```

## How to Contribute

### Reporting Bugs

1. Check [existing issues](../../issues) to avoid duplicates
2. Use the **Bug Report** issue template
3. Include: OS version, Bash version, Docker version, steps to reproduce

### Suggesting Features

1. Open an issue with the **Feature Request** template
2. Describe the use case, not just the solution
3. Be open to discussion — there may be alternative approaches

### Submitting Changes

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes following the code style below
4. Test your changes manually (see Testing section)
5. Commit using [Conventional Commits](https://www.conventionalcommits.org/):
   ```
   feat: add parallel sync support
   fix: handle spaces in stack names
   docs: update deployment guide
   refactor: extract retry logic into core module
   ```
6. Push and create a Pull Request

## Code Style

### Bash

- **Shebang:** `#!/usr/bin/env bash`
- **Error handling:** Entry points use `set -euo pipefail`; library files inherit it
- **Variables:** `local` for function scope, `UPPER_SNAKE_CASE` for globals
- **Functions:** `lower_snake_case`, e.g. `deploy_stack()`
- **Conditions:** `[[ ]]` for extended tests, `[ ]` for simple checks
- **Errors:** Use `fail "message"` from `core/`
- **Arrays:** `declare -a` for indexed, `declare -A` for associative
- **Quoting:** Always quote variables unless in arithmetic context

### YAML

- Indent: 2 spaces
- Strings: unquoted unless special characters present
- Comments: `# comment`

### Python

- Follow PEP 8
- Type hints where practical
- Docstrings for public functions

### General

- No trailing whitespace
- Files end with a newline
- Keep functions focused and small
- Comments explain *why*, not *what*

## Testing

### Manual Testing

```bash
# Validate stack configurations
swarmcli validate <stack>

# Dry-run a deployment
swarmcli deploy <stack> --dry-run

# Check system health
swarmcli system health
```

### Static Analysis

```bash
# Run ShellCheck on all scripts
find bin/ -name '*.sh' -exec shellcheck {} +

# Validate Python scripts
python -m py_compile bin/lib/templates/templates.py
python -m py_compile bin/lib/utils/yaml_parser.py
```

## Pull Request Guidelines

- One PR per feature or fix
- Keep changes focused — avoid mixing refactoring with features
- Update documentation if behavior changes
- Add a CHANGELOG entry under `[Unreleased]`
- PRs require at least one review before merging

## Architecture Decisions

Important design decisions are documented as ADRs in `docs/adr/`. If your change involves an architectural decision, please create a new ADR following the template in `docs/adr/README.md`.

## Questions?

Open a [Discussion](../../discussions) or an issue — we're happy to help.
