# Glossary

Terms and definitions used in SwarmCLI documentation.

## Docker Terms

| Term | Description |
|------|-------------|
| **Image** | Immutable template for creating containers. Contains code, dependencies, configuration |
| **Container** | Running instance of an image. Isolated process with its own filesystem |
| **Dockerfile** | Text file with instructions for building an image |
| **Registry** | Docker image storage (Docker Hub, GitLab Registry, etc.) |
| **Tag** | Image version. E.g.: `nginx:1.25` or `api:server-dev-abc1234` |
| **Volume** | Persistent storage for container data |
| **Network** | Virtual network for container communication |

## Docker Swarm Terms

| Term | Description |
|------|-------------|
| **Swarm** | Docker mode for container orchestration across multiple nodes |
| **Node** | Server in Swarm cluster. Can be manager or worker |
| **Manager** | Node managing the cluster. Accepts commands, distributes tasks |
| **Worker** | Node running containers. Cannot manage the cluster |
| **Service** | Task definition for running in Swarm. Includes image, ports, replicas |
| **Task** | Unit of work — one running container of a service |
| **Replica** | Number of simultaneously running service instances |
| **Stack** | Group of related services deployed together |
| **Secret** | Encrypted data (passwords, keys) available to containers |
| **Config** | Configuration files mounted into containers |

## SwarmCLI Terms

| Term | Description |
|------|-------------|
| **Profile** | Isolated configuration for a server. Contains stacks and settings (secrets — in SECRETS_ROOT, not in profile) |
| **Stack** | Application or microservice. Directory with deployment configuration |
| **Service** | Stack component. Can be internal (from Git) or external (from Registry) |
| **Internal Service** | Service built from Git repository. Type: `git` |
| **External Service** | Service from public/private Registry. Type: `registry` |
| **Hook** | Bash script executed before or after deployment |
| **Endpoint** | Service address (host:port) for inter-service communication |
| **Registry** | Centralized list of service endpoints (`endpoints.yaml`) |

## Configuration Files

| File | Level | Description |
|------|-------|-------------|
| `config.yaml` | Profile | Profile settings (timeouts, retry, git) |
| `globals.yaml` | Profile | Global variables for all stacks |
| `resources.yaml` | Profile | CPU/Memory limits for services |
| `endpoints.yaml` | Profile | Service address registry |
| `docker-stack.yml` | Stack | Docker Compose file for Swarm |
| `services.yaml` | Stack | Stack service descriptions |
| `variables.yaml` | Stack | Build and runtime variables |
| `externals.yaml` | Stack | Required secrets and configs |
| `settings.yaml` | Stack | Stack-specific settings |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `TAG_*` | Image tags for services. Example: `TAG_API=server-dev-abc1234` |
| `GLOBAL_*` | Global variables from `globals.yaml`. Example: `GLOBAL_TZ` |
| `SERVICE_*` | Service addresses from `endpoints.yaml`. Example: `SERVICE_CORE_API_URL` |
| `RUNTIME_*` | Runtime variables from `variables.yaml` runtime.env |
| `BUILD_*` | Build variables from `variables.yaml` |

## Statuses

### Service

| Status | Description |
|--------|-------------|
| `running` | All replicas running |
| `partial` | Some replicas running |
| `stopped` | No running replicas |
| `not deployed` | Service not deployed |

### Deploy

| Status | Description |
|--------|-------------|
| `success` | Deploy successful, all services ready |
| `failed` | Deploy failed (build/start error) |
| `timeout` | Services did not become ready in time |

## Abbreviations

| Abbreviation | Expansion |
|--------------|-----------|
| CLI | Command Line Interface |
| CI/CD | Continuous Integration / Continuous Deployment |
| API | Application Programming Interface |
| SSH | Secure Shell |
| HTTPS | Hypertext Transfer Protocol Secure |
| YAML | YAML Ain't Markup Language |
| JSON | JavaScript Object Notation |

## See Also

- [Docker Basics](01-docker-basics.md) — Docker fundamentals
- [Swarm Basics](02-swarm-basics.md) — Docker Swarm fundamentals
- [Profiles](03-profiles.md) — profile concept
- [Stacks](04-stacks.md) — stack concept
