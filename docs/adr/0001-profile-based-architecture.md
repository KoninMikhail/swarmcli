# ADR-0001: Profile-based Architecture

## Status

Accepted

## Context

Managing multiple Docker Swarm servers (dev, staging, production) from a single codebase requires isolated configurations per server.

## Decision

Each server gets a "profile" directory under `profiles/<name>/` containing its own config.yaml, stacks/, and scripts/. Profiles are self-contained and can be selected via `swarmcli use <profile>`.

## Consequences

### Positive
- Complete isolation between servers
- Easy to add new servers
- No risk of cross-environment contamination

### Negative
- Some configuration duplication across profiles

## Date

2024-12-19
