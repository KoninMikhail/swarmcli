# ADR-0014: Runtime Variable Naming

## Status

Accepted

## Context

Environment variables used internally by swarmcli could conflict with user-defined variables.

## Decision

All internal runtime variables use prefixed naming convention to avoid conflicts with user service variables.

## Consequences

### Positive
- No naming conflicts
- Clear separation of concerns

### Negative
- Longer variable names internally

## Date

2025-01-08
