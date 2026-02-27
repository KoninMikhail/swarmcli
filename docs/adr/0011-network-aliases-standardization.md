# ADR-0011: Network Aliases Standardization

## Status

Proposed

## Context

Docker Swarm services communicate via network aliases, but naming is inconsistent across stacks.

## Decision

Standardize network alias naming convention: `<service-name>` within the same stack, `<stack>-<service>` for cross-stack communication.

## Consequences

### Positive
- Predictable service discovery
- Easier debugging

### Negative
- May require migration of existing configurations

## Date

2025-01-08
