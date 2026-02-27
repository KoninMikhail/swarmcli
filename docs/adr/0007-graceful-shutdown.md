# ADR-0007: Graceful Shutdown for Long Operations

## Status

Accepted

## Context

Long-running operations (deploy, sync, build) can be interrupted by Ctrl+C or SIGTERM. Without proper handling, locks remain and temp files accumulate.

## Decision

Implement signal handlers that track child processes and cleanup handlers. On interrupt: terminate children gracefully, run cleanup handlers (release locks, remove temp files), then exit.

## Consequences

### Positive
- No orphaned locks after interruption
- Clean state after cancel

### Negative
- Signal handling adds complexity
- Edge cases with nested operations

## Date

2024-12-22
