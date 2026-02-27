# GitHub Actions Examples

Example workflows for deploying with SwarmCLI via GitHub Actions.

## Files

| File | Description |
|------|-------------|
| [deploy.yml](deploy.yml) | Full deploy workflow with SSH |

## Setup

### 1. Add secrets to your repository

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Description |
|--------|-------------|
| `DEPLOY_HOST` | Server hostname or IP |
| `DEPLOY_USER` | SSH username |
| `DEPLOY_SSH_KEY` | Private SSH key |
| `DEPLOY_PORT` | SSH port (optional, default: 22) |

### 2. Copy workflow to your project

```bash
mkdir -p .github/workflows
cp examples/github-actions/deploy.yml .github/workflows/deploy.yml
```

### 3. Customize

Edit the workflow to match your setup:
- Change `SWARMCLI_PATH` if installed elsewhere
- Adjust branch triggers
- Add/remove environments

## Manual Trigger

The workflow supports `workflow_dispatch` for manual deploys:

1. Go to **Actions** tab
2. Select **Deploy** workflow
3. Click **Run workflow**
4. Choose profile and optionally specify a stack
