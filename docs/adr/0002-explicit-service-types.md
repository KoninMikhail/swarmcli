# ADR-0002: Explicit Service Types

## Status

Accepted

## Context

Docker Swarm services can come from private git repositories (built locally) or public registries. The deploy pipeline needs different steps for each.

## Decision

Services are explicitly typed as `git` (cloned and built locally) or `registry` (pulled from registry). Type is declared in services.yaml.

## Consequences

### Positive
- Clear deploy pipeline per service
- No ambiguity in build process

### Negative
- Must declare type for every service

## Date

2024-12-19
