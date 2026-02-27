# Installing SwarmCLI

Step-by-step SwarmCLI installation on a server.

## Install via Script (Recommended)

Interactive installer checks dependencies, configures `.swarmcli.yaml`, sets up CLI access (symlink or alias), and optionally sets default profile.

```bash
# 1. Clone repository
git clone https://github.com/KoninMikhail/swarmcli.git ~/swarmcli
cd ~/swarmcli

# 2. Run installer
./install.sh
```

The installer will:
- Check dependencies (Git, jq, Docker, Python, Jinja2, PyYAML) — can install Python packages if missing
- Create `.swarmcli.yaml` (Git token, secrets path)
- Set up CLI: symlink in `~/.local/bin` or alias in shell rc
- Show profiles and ask to set default (if profiles exist)

**If no profiles exist** — create one after install:

```bash
swarmcli create
# Select: Profile (server configuration)
# Follow prompts, then:
swarmcli use <profile-name>
```

**Options:** `--yes` (non-interactive), `--dry-run`, `--skip-deps`, `--no-symlink`, `--force` (overwrite config)

---

## Manual Install

For installation without the script (e.g. to `/opt` for production).

### Step 1: Clone

```bash
# Home directory (no sudo)
git clone https://github.com/KoninMikhail/swarmcli.git ~/swarmcli
cd ~/swarmcli

# Or to /opt (FHS compliant)
sudo mkdir -p /opt/swarmcli && sudo chown $USER:$USER /opt/swarmcli
git clone https://github.com/KoninMikhail/swarmcli.git /opt/swarmcli
cd /opt/swarmcli
```

### Step 2: Verify

```bash
./bin/swarm.sh system health
```

### Step 3: Profile and CLI

```bash
# Create profile (if none exist)
./bin/swarm.sh create
# Select: Profile (server configuration)

# Set default profile
./bin/swarm.sh use <profile-name>

# Add alias (optional, adjust path)
echo 'alias swarmcli="/path/to/swarmcli/bin/swarm.sh"' >> ~/.bashrc
source ~/.bashrc
```

## Post-Installation Structure

`<INSTALL_ROOT>` is your clone directory (e.g. `~/swarmcli` or `/opt/swarmcli`).

```
<INSTALL_ROOT>/
├── bin/
│   ├── swarm.sh              # CLI entry point
│   └── lib/                  # Modules
│       ├── core.sh           # Logging, retry
│       ├── profiles.sh       # Profile handling
│       ├── deploy.sh         # Deploy, rollback
│       └── ...
├── profiles/
│   └── my-server/            # Your profile
│       ├── config.yaml       # Configuration
│       └── stacks/           # Application stacks
│           ├── globals.yaml  # Global variables
│           └── resources.yaml # CPU/Memory limits
├── .secrets/                 # Secrets (not in git!)
├── repos/                    # Git repositories (created automatically)
└── .swarmcli.yaml           # Configuration and saved profile (state.default_profile)
# Deploy history is stored inside each stack: stacks/<stack>/.deploy/
```

## Multi-Server Installation

For managing multiple servers, create separate profiles:

```
profiles/
├── server-dev/      # Development
├── server-staging/  # Staging
├── server-prod/     # Production
└── server-db/       # Database server
```

Each server has its own clone of the repository with an active profile:

```bash
# On dev server
swarmcli use server-dev

# On prod server
swarmcli use server-prod
```

## Updating SwarmCLI

```bash
# Manual update (cd to your install directory)
cd ~/swarmcli   # or cd /opt/swarmcli
git pull origin main

# Automatic update (from CLI)
swarmcli system update
```

### CLI Auto-Update

For automatic CLI updates, using a GitLab CI pipeline is recommended rather than auto-update on deploy. This ensures predictable CLI version:

```yaml
# .gitlab-ci.yml
before_script:
  - cd /path/to/swarmcli
  - git fetch origin
  - git checkout main  # or specific version: v0.1.0
```

For manual update use:

```bash
swarmcli system update
```

## Configuring Secrets

```bash
# Add secret (interactive)
swarmcli secret create db_password
# Value: [hidden input]
# ✓ created secret file: .secrets/db_password
# ✓ Docker secret created: db_password

# Or create manually
mkdir -p .secrets && chmod 700 .secrets
echo "my_password" > .secrets/db_password
chmod 600 .secrets/db_password
```

## Configuring CI/CD

For CI/CD integration see [CI/CD Guide](../05-operations/gitlab-ci/).

Basic GitHub Actions example:

```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: swarmcli deploy my-app --profile server-dev
```

## Verifying Installation

```bash
# Version
swarmcli system version

# List profiles
swarmcli profile ls

# List stacks (should be empty on new server)
swarmcli ls
```

## Troubleshooting

### "command not found: swarmcli"

Alias not configured. Use full path:

```bash
~/swarmcli/bin/swarm.sh system version   # or /opt/swarmcli/bin/swarm.sh
```

Or add alias (adjust path to your install directory):

```bash
echo 'alias swarmcli="/path/to/swarmcli/bin/swarm.sh"' >> ~/.bashrc
source ~/.bashrc
```

### "profile not found"

Profile does not exist or `config.yaml` is missing:

```bash
# Check existing profiles
./bin/swarm.sh profile ls   # or swarmcli profile ls if alias is set

# If no profiles — create via wizard
./bin/swarm.sh create       # or swarmcli create
# Select: Profile (server configuration)
```

### "permission denied"

User not in `docker` group:

```bash
sudo usermod -aG docker $USER
# Re-login!
exit
```

### "Docker daemon not running"

```bash
sudo systemctl start docker
sudo systemctl enable docker
```

## Next Step

→ [First Deploy](03-first-deploy.md) — deploy your first application
