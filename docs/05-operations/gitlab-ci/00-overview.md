# GitLab CI Integration

SwarmCLI provides ready-made patterns for minimal GitLab CI boilerplate.

> **Note:** The default profile is already configured on the server via `swarmcli use <profile>` during installation. You do **not** need `--profile` in CI/CD commands unless you deploy to multiple servers from a single runner.

## Quick Start

### Option 1: Direct CLI call (recommended)

```yaml
# .gitlab-ci.yml of your application

stages:
  - deploy

deploy:
  stage: deploy
  script:
    - swarmcli deploy "$STACK_NAME"
  variables:
    STACK_NAME: "my-app"
  when: manual
```

**And that's it!** Deploy by button works.

### Option 2: Remote execution (SSH)

```yaml
# .gitlab-ci.yml

stages:
  - deploy

deploy:production:
  stage: deploy
  script:
    - ssh deploy@$DEPLOY_SERVER "swarmcli deploy $CI_PROJECT_NAME --branch $CI_COMMIT_REF_NAME"
  environment:
    name: production
  only:
    - main
```

### Option 3: Local runner on server

```yaml
# .gitlab-ci.yml

stages:
  - deploy

deploy:production:
  stage: deploy
  tags:
    - swarm-prod  # Runner on production server
  script:
    - swarmcli deploy $CI_PROJECT_NAME --branch $CI_COMMIT_REF_NAME
  environment:
    name: production
  only:
    - main
```

## Available Templates

| Template | Workflow | Description |
|----------|----------|-------------|
| `workflows/manual-only.yml` | dev → prod | ⭐ All deploys by button |
| `workflows/trunk-based.yml` | main only | Trunk-based development |
| `workflows/feature-branches.yml` | feature/* → dev → prod | With branch preview |
| `workflows/release-branches.yml` | release/* → stage → prod | With staging environment |

## GitLab CI Variables

### Required

| Variable | Description |
|----------|-------------|
| `STACK_NAME` | Stack name in SwarmCLI |
| `DEV_SERVER` | Dev server address |
| `PROD_SERVER` | Prod server address |
| `SSH_PRIVATE_KEY` | SSH key for connection |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `DEPLOY_USER` | `deploy` | SSH user |
| `DEPLOY_FLAGS` | — | Additional deploy flags |
| `SSH_PRIVATE_KEY_DEV` | `$SSH_PRIVATE_KEY` | SSH key for dev (if different) |
| `SSH_PRIVATE_KEY_PROD` | `$SSH_PRIVATE_KEY` | SSH key for prod |
| `SLACK_WEBHOOK_URL` | — | Slack webhook for notifications |
| `TELEGRAM_BOT_TOKEN` | — | Telegram bot token |
| `TELEGRAM_CHAT_ID` | — | Chat ID for notifications |

### Build and Deploy Variables

SwarmCLI supports variables with prefixes:

- `COMMON_*` — common variables (build + deploy)
- `BUILD_*` — build variables (--build-arg)
- `DEPLOY_*` — deploy variables (environment)

**Example:**

```yaml
# GitLab CI variables
variables:
  COMMON_TZ: Europe/Moscow
  BUILD_NODE_ENV: production
  BUILD_VITE_API_URL: https://api.example.com
  DEPLOY_LOG_LEVEL: info
  DEPLOY_DATABASE_HOST: postgres
```

### Automatic DEPLOY_* Variable Injection

Variables with the `DEPLOY_*` prefix are automatically added to the `environment:` section of each service in `docker-stack.yml`.

**How it works:**

1. GitLab CI passes `DEPLOY_NEW_FEATURE=true`
2. SwarmCLI automatically adds `NEW_FEATURE: ${NEW_FEATURE}` to `environment:` of all services
3. Variable becomes available inside container

**Rules:**

- `DEPLOY_` prefix is removed when adding to container
- If variable **already exists** in `docker-stack.yml` — it is **not overwritten**
- Variables are added to **all services** in the stack

## Pipeline Examples

### Manual-Only (recommended)

```yaml
deploy:
  stage: deploy
  script:
    - swarmcli deploy "$STACK_NAME"
  variables:
    STACK_NAME: "my-app"
  when: manual
```

### Feature Branches with preview

```yaml
deploy:dev:
  stage: deploy
  script:
    - swarmcli deploy "$STACK_NAME" --branch "$CI_COMMIT_REF_NAME"
  variables:
    STACK_NAME: "my-app"
  rules:
    - if: $CI_COMMIT_BRANCH != $CI_DEFAULT_BRANCH

deploy:prod:
  stage: deploy
  script:
    - swarmcli deploy "$STACK_NAME"
  variables:
    STACK_NAME: "my-app"
    DEPLOY_FLAGS: "--prune"
  when: manual
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

### Release Branches with staging

```yaml
deploy:staging:
  stage: deploy
  script:
    - swarmcli deploy "$STACK_NAME"
  variables:
    STACK_NAME: "my-app"
  rules:
    - if: $CI_COMMIT_BRANCH =~ /^release\//

deploy:prod:
  stage: deploy
  script:
    - swarmcli deploy "$STACK_NAME"
  variables:
    STACK_NAME: "my-app"
  when: manual
  rules:
    - if: $CI_COMMIT_TAG
```

### Multi-server Pipelines

If the CI runner deploys to **multiple servers**, use `--profile` to specify the target:

```yaml
deploy:dev:
  script:
    - swarmcli deploy "$STACK_NAME" --profile server-dev --branch "$CI_COMMIT_REF_NAME"

deploy:staging:
  script:
    - swarmcli deploy "$STACK_NAME" --profile server-staging

deploy:prod:
  script:
    - swarmcli deploy "$STACK_NAME" --profile server-prod
  when: manual
```

### With additional tests

```yaml
stages:
  - test
  - validate
  - deploy
  - rollback

test:unit:
  stage: test
  image: node:20-alpine
  script:
    - npm ci
    - npm run test
  only:
    - dev
    - main

deploy:dev:
  needs:
    - test:unit
```

## Server Setup

### 1. Create deploy user

```bash
sudo useradd -m -s /bin/bash deploy
sudo usermod -aG docker deploy
```

### 2. Configure SSH key

```bash
# On your computer
ssh-keygen -t ed25519 -C "gitlab-ci-deploy" -f ~/.ssh/gitlab-ci-deploy

# Copy to server
ssh-copy-id -i ~/.ssh/gitlab-ci-deploy.pub deploy@DEPLOY_HOST

# Add private key to GitLab CI/CD Variables
# Name: SSH_PRIVATE_KEY
# Type: File
# Protected: Yes (for prod)
```

### 3. Install SwarmCLI and configure profile

```bash
# Install SwarmCLI (see install.sh)
curl -sSL https://your-repo/install.sh | bash

# Set default profile
swarmcli use server-prod  # or server-dev
```

## Troubleshooting

### "Permission denied" on SSH

```bash
# Check key permissions in GitLab
# SSH_PRIVATE_KEY variable must be complete (from -----BEGIN to -----END)

# On server check authorized_keys
cat /home/deploy/.ssh/authorized_keys

# Check permissions
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys
```

### "Stack not found"

```bash
# Verify stack exists
ssh deploy@server
cd /opt/swarmcli
./bin/swarm.sh ls
```

### Deploy timeout

```yaml
# Increase job timeout
deploy:prod:
  timeout: 45m  # Increase if build is long
```

## See Also

- [Troubleshooting](../troubleshooting/01-deploy-failures.md)
- [First Deploy](../../00-onboarding/03-first-deploy.md)
- [Advanced Deploy](../../02-guides/deployment/01-advanced-deploy.md)
