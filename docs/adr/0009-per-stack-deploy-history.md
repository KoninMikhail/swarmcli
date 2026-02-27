# ADR-0009: Per-stack Deploy History

## Status

Accepted

## Context

Need to track deployment history for rollback support and audit trail.

## Decision

Each stack maintains a `history.jsonl` file in `.deploy/` directory with timestamps, service versions, and deploy status.

## Consequences

### Positive
- Enables rollback
- Provides audit trail
- Per-stack isolation

### Negative
- History files grow over time, need rotation strategy

## Date

2025-01-08
