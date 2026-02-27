# ADR-0005: Automatic Dozzle Label Generation

## Status

Accepted

## Context

Dozzle (Docker log viewer) requires specific labels on services for proper grouping and display.

## Decision

Automatically generate Dozzle-compatible labels during deploy based on stack and service configuration.

## Consequences

### Positive
- No manual label management
- Consistent labeling across all services

### Negative
- Tight coupling with Dozzle label format

## Date

2024-12-21
