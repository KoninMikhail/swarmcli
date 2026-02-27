# ADR-0016: Per-Service Branch/Commit Specification

## Status

Accepted

## Context

Different services in a stack may need to be deployed from different branches or specific commits.

## Decision

Support `--service <name> --branch <branch>` and `--service <name> --commit <sha>` flags to override the default branch per service during deploy/build.

## Consequences

### Positive
- Granular control over service versions
- Supports hotfix scenarios

### Negative
- More complex CLI argument parsing

## Date

2025-01-09
