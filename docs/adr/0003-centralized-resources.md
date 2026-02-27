# ADR-0003: Centralized Resource Management

## Status

Accepted

## Context

Docker Swarm resource limits (CPU, memory) are scattered across docker-stack.yml files, making it hard to manage server capacity.

## Decision

Resource limits are defined in a centralized `resources.yaml` and injected into docker-stack.yml via Jinja2 templating.

## Consequences

### Positive
- Single place to manage all resource limits
- Easy capacity planning

### Negative
- Requires Jinja2 templating, adds complexity

## Date

2024-12-20
