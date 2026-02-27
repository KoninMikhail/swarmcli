# ADR-0010: Per-stack Service Repositories

## Status

Accepted

## Context

Git service repositories need to be managed per stack to support independent deployment cycles.

## Decision

Each stack's git services are cloned into the stack's `.repos/` directory, allowing independent branch/commit control per stack.

## Consequences

### Positive
- Independent deploy cycles per stack
- Clear ownership

### Negative
- Disk space for multiple clones of the same repo

## Date

2025-01-08
