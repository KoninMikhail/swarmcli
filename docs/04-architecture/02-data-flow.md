# Data Flows

Detailed data flow diagrams in SwarmCLI.

## CLI Initialization

```mermaid
sequenceDiagram
    participant User
    participant CLI as swarm.sh
    participant Core as core.sh
    participant Profiles as profiles.sh
    participant FS as File system
    
    User->>CLI: swarmcli --profile server-dev deploy my-app
    
    Note over CLI: Initialization
    CLI->>CLI: set -euo pipefail
    CLI->>CLI: Resolve PLATFORM_ROOT
    CLI->>CLI: Export default variables
    
    Note over CLI: Load modules
    CLI->>Core: source core.sh
    CLI->>Profiles: source profiles.sh
    CLI->>CLI: source remaining modules
    
    Note over CLI: Parse arguments
    CLI->>CLI: Parse --profile server-dev
    CLI->>CLI: Parse command: deploy
    CLI->>CLI: Parse stack: my-app
    
    Note over CLI: Load profile
    CLI->>Profiles: load_profile("server-dev")
    Profiles->>FS: Check profiles/server-dev/
    FS-->>Profiles: OK
    Profiles->>FS: Read config.yaml
    FS-->>Profiles: config data
    Profiles->>CLI: ACTIVE_PROFILE=server-dev
    
    Note over CLI: Route command
    CLI->>CLI: route to cmd_deploy()
```

## Profile Loading

```mermaid
flowchart TB
    subgraph Input["Input Data"]
        ARG["--profile arg"]
        ENV["$SWARM_PROFILE"]
        STATE[".swarmcli.yaml (state.default_profile)"]
    end
    
    subgraph Priority["Priority"]
        P1["1. --profile"]
        P2["2. Saved default (state.default_profile)"]
        P3["3. $SWARM_PROFILE"]
    end
    
    subgraph Load["Loading"]
        CHECK{"profile_exists?"}
        READ["Read config.yaml"]
        EXPORT["Export variables"]
    end
    
    subgraph Result["Result"]
        ACTIVE["ACTIVE_PROFILE"]
        PROFILE_DIR["PROFILE_DIR"]
        STACKS_DIR["PROFILE_STACKS_DIR"]
    end
    
    ARG --> P1
    STATE --> P2
    ENV --> P3
    
    P1 --> CHECK
    P2 --> CHECK
    P3 --> CHECK
    
    CHECK -->|Yes| READ
    CHECK -->|No| FAIL[fail: profile not found]
    
    READ --> EXPORT
    EXPORT --> ACTIVE
    EXPORT --> PROFILE_DIR
    EXPORT --> STACKS_DIR
```

## Deploy Process (Detailed)

```mermaid
sequenceDiagram
    participant User
    participant CMD as commands.sh
    participant VAL as validation.sh
    participant LOCK as locks.sh
    participant DEP as deploy.sh
    participant GIT as git.sh
    participant DOCK as docker.sh
    participant TPL as templates.py
    participant SW as Docker Swarm
    
    User->>CMD: cmd_deploy("my-stack")
    
    rect rgb(200, 230, 200)
        Note over CMD,VAL: Stage 1: Validation
        CMD->>VAL: validate_deploy_prerequisites()
        VAL->>VAL: Check stack directory
        VAL->>VAL: Check docker-stack.yml
        VAL->>VAL: validate_services_yaml()
        VAL->>VAL: check_required_secrets()
        VAL-->>CMD: OK or fail
    end
    
    rect rgb(200, 200, 230)
        Note over CMD,LOCK: Stage 2: Lock
        CMD->>LOCK: acquire_deploy_lock()
        LOCK->>LOCK: mkdir .locks/deploy_my-stack
        LOCK-->>CMD: OK or fail
    end
    
    rect rgb(230, 200, 200)
        Note over CMD,DEP: Stage 3: Checkpoint
        CMD->>DEP: save_deploy_checkpoint()
        DEP->>SW: docker stack ps my-stack
        SW-->>DEP: current state
        DEP->>DEP: Save to stacks/my-stack/.deploy/
    end
    
    rect rgb(230, 230, 200)
        Note over CMD,GIT: Stage 4: Sync repos
        CMD->>GIT: sync_repo_for_service() (for each)
        GIT->>GIT: git fetch origin $branch
        GIT->>GIT: git checkout FETCH_HEAD (detached)
        GIT-->>CMD: SHA for each service
    end
    
    rect rgb(200, 230, 230)
        Note over CMD,DOCK: Stage 5: Build
        CMD->>DOCK: build_for_service() (for each)
        DOCK->>DOCK: docker build -t image:tag
        DOCK-->>CMD: images built
    end
    
    rect rgb(230, 200, 230)
        Note over CMD,TPL: Stage 6: Prepare compose
        CMD->>DEP: export_service_tags()
        DEP->>DEP: Export TAG_API, TAG_WORKER...
        CMD->>DEP: load variables.yaml
        alt Stack with j2 templates
            CMD->>TPL: template_render()
            TPL->>TPL: Render templates
            TPL->>TPL: deploy_resources()
            TPL->>TPL: inject_env_vars()
            TPL->>TPL: dozzle_labels()
            TPL-->>CMD: .build/docker-stack.yml
        else Legacy stack
            CMD->>DEP: generate_compose_with_resources()
            DEP-->>CMD: /tmp/composed.yml
        end
    end
    
    rect rgb(200, 200, 200)
        Note over CMD,SW: Stage 7: Deploy
        CMD->>DEP: run_hook("pre-deploy.sh")
        CMD->>SW: docker stack deploy -c composed.yml
        SW-->>CMD: Stack deployed
        CMD->>DEP: wait_for_services_ready()
        DEP->>SW: Check replicas loop
        SW-->>DEP: All ready
        CMD->>DEP: run_hook("post-deploy.sh")
    end
    
    rect rgb(200, 230, 200)
        Note over CMD,LOCK: Stage 8: Completion
        CMD->>DEP: save_deploy_history("success")
        CMD->>LOCK: release_deploy_lock()
        CMD-->>User: ✅ Deploy completed
    end
```

## Variable Loading

```mermaid
flowchart TB
    subgraph Sources["Variable Sources"]
        EP[endpoints.yaml]
        GL[globals.yaml]
        VC[variables.yaml common]
        VD[variables.yaml runtime.env]
        ENV[Environment]
    end
    
    subgraph Process["Processing"]
        PARSE["Parse YAML"]
        MERGE["Merge with priority"]
        PREFIX["Add prefixes"]
    end
    
    subgraph Output["Result"]
        SERVICE["SERVICE_* variables"]
        GLOBAL["GLOBAL_* variables"]
        DEPLOY["DEPLOY_* variables"]
        TAG["TAG_* variables"]
    end
    
    EP --> PARSE
    GL --> PARSE
    VC --> PARSE
    VD --> PARSE
    
    PARSE --> MERGE
    MERGE --> PREFIX
    
    PREFIX --> SERVICE
    PREFIX --> GLOBAL
    PREFIX --> DEPLOY
    ENV --> TAG
```

**Priority order (lowest to highest):**

1. `endpoints.yaml` → `SERVICE_*`
2. `globals.yaml` → `GLOBAL_*`
3. `variables.yaml` (common) → variables
4. `variables.yaml` (runtime.env) → environment
5. Environment → overrides all

## Resource Injection

```mermaid
flowchart LR
    subgraph Input["Input Files"]
        TEMPLATE[templates/docker-stack.j2]
        TEMPLATE_YAML[templates.yaml]
        RESOURCES[resources.yaml]
        SERVICES[services.yaml]
        VARIABLES[variables.yaml]
    end
    
    subgraph Templates["templates.py"]
        LOAD["Load files"]
        RENDER["Render templates"]
        FUNC_RES["deploy_resources()"]
        FUNC_ENV["inject_env_vars()"]
        FUNC_LAB["dozzle_labels()"]
        WRITE["Write result"]
    end
    
    subgraph Output["Result"]
        OUT[.build/docker-stack.yml]
    end
    
    TEMPLATE --> LOAD
    TEMPLATE_YAML --> LOAD
    RESOURCES --> LOAD
    SERVICES --> LOAD
    VARIABLES --> LOAD
    
    LOAD --> RENDER
    RENDER --> FUNC_RES
    RENDER --> FUNC_ENV
    RENDER --> FUNC_LAB
    FUNC_RES --> WRITE
    FUNC_ENV --> WRITE
    FUNC_LAB --> WRITE
    WRITE --> OUT
```

**What gets injected:**

```yaml
# Before injection
services:
  api:
    image: local/api:${TAG_API}

# After injection
services:
  api:
    image: local/api:${TAG_API}
    environment:
      - LOG_LEVEL=${LOG_LEVEL}
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: "2G"
      labels:
        dev.dozzle.group: backend
        dev.dozzle.name: API Service
```

## Rollback

```mermaid
flowchart TB
    subgraph Trigger["Trigger"]
        CMD["swarmcli rollback my-stack"]
        OPT["--to-version N"]
    end
    
    subgraph Read["Read History"]
        HIST["stacks/<stack>/.deploy/history.jsonl"]
        FIND["Find N-th successful deploy"]
    end
    
    subgraph Prepare["Preparation"]
        CHECK["Check images"]
        REBUILD["Rebuild if missing"]
        TAGS["Set TAG_*"]
    end
    
    subgraph Deploy["Deploy"]
        LOAD["Load variables"]
        DEPLOY["docker stack deploy"]
        WAIT["Wait for readiness"]
        SAVE["Save history"]
    end
    
    CMD --> HIST
    OPT --> HIST
    HIST --> FIND
    
    FIND --> CHECK
    CHECK -->|Image exists| TAGS
    CHECK -->|Image missing| REBUILD
    REBUILD --> TAGS
    
    TAGS --> LOAD
    LOAD --> DEPLOY
    DEPLOY --> WAIT
    WAIT --> SAVE
```

## Lock System

```mermaid
stateDiagram-v2
    [*] --> Free: Initial state
    
    Free --> Acquiring: acquire_deploy_lock()
    Acquiring --> Locked: mkdir success
    Acquiring --> Waiting: mkdir failed
    
    Waiting --> Acquiring: Retry
    Waiting --> Failed: Timeout
    
    Locked --> Deploying: Deploy
    Deploying --> Releasing: Completion
    Releasing --> Free: release_deploy_lock()
    
    Failed --> [*]: Error
    Free --> [*]: Success
```

**Mechanism:**

```bash
# Acquire (atomic mkdir)
mkdir .locks/deploy_my-stack 2>/dev/null

# Release
rmdir .locks/deploy_my-stack

# Timeout: LOCK_TIMEOUT seconds (default: 3600)
```

## Hooks

```mermaid
flowchart TB
    subgraph PreDeploy["Pre-Deploy"]
        PRE_CHECK["Check hooks/pre-deploy.sh"]
        PRE_PERM["Check/fix permissions"]
        PRE_RUN["Execute script"]
        PRE_STATUS{"Status?"}
    end
    
    subgraph Deploy["Main Deploy"]
        DEPLOY["docker stack deploy"]
        WAIT["wait_for_services_ready"]
    end
    
    subgraph PostDeploy["Post-Deploy"]
        POST_RUN["Execute post-deploy.sh"]
    end
    
    PRE_CHECK --> PRE_PERM
    PRE_PERM --> PRE_RUN
    PRE_RUN --> PRE_STATUS
    
    PRE_STATUS -->|OK| DEPLOY
    PRE_STATUS -->|Fail| ABORT[Abort deploy]
    
    DEPLOY --> WAIT
    WAIT --> POST_RUN
```

**Variables available in hooks:**

```bash
$STACK           # Stack name
$SWARM_PROFILE   # Active profile
$TAG_API         # API image tag
$TAG_WORKER      # Worker image tag
$GLOBAL_TZ       # Global variable TZ
$DEPLOY_LOG_LEVEL # Deploy variable
```

## Readiness Wait

```mermaid
flowchart TB
    START["wait_for_services_ready(stack, timeout)"]
    
    LOOP["Check loop"]
    CHECK["Check all service replicas"]
    STATUS{"All ready?"}
    
    TIMEOUT{"Timeout?"}
    WAIT["sleep 2s"]
    
    SUCCESS["✅ All services ready"]
    DIAGNOSE["diagnose_deploy_failure()"]
    FAIL["❌ Timeout"]
    
    START --> LOOP
    LOOP --> CHECK
    CHECK --> STATUS
    
    STATUS -->|Yes| SUCCESS
    STATUS -->|No| TIMEOUT
    
    TIMEOUT -->|No| WAIT
    WAIT --> LOOP
    
    TIMEOUT -->|Yes| DIAGNOSE
    DIAGNOSE --> FAIL
```

**Diagnostics on failure:**

```
╔══════════════════════════════════════════════════════════════════════════════╗
║              DEPLOYMENT FAILURE DIAGNOSTICS                                  ║
╚══════════════════════════════════════════════════════════════════════════════╝

Stack: my-stack
Failed services: 1

my-stack_api: 0/2
  Tasks:
    - State: Failed, Error: "image not found"
    
  Recent logs:
    Error: Cannot pull image...

╔══════════════════════════════════════════════════════════════════════════════╗
║                        TROUBLESHOOTING HINTS                                 ║
╚══════════════════════════════════════════════════════════════════════════════╝

1. Check task errors: docker service ps my-stack_api --no-trunc
2. View service logs: docker service logs my-stack_api --tail 50
```

## See also

- [Architecture Overview](00-overview.md)
- [Modules](01-modules.md)
- [Deploy Process](../01-concepts/06-deploy-flow.md)
