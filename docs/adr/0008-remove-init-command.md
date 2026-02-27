# ADR-0008: Remove init Command

## Status

Accepted

## Context

The `swarmcli init` command created a new project structure. With profile-based architecture, initialization is done via the install wizard.

## Decision

Remove the standalone `init` command. Profile creation is handled by `swarmcli create` wizard or manual directory creation.

## Consequences

### Positive
- Simpler command surface
- No confusion between init and create

### Negative
- Users must use wizard or manual setup

## Date

2024-12-22
