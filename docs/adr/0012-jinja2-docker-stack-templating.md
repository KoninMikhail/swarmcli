# ADR-0012: Jinja2 Docker Stack Templating

## Status

Accepted

## Context

Docker Compose/Stack YAML files need dynamic values (resource limits, environment-specific settings) that can't be expressed in static YAML.

## Decision

Use Jinja2 templates for docker-stack.yml. Templates are rendered to `.build/docker-stack.yml` before deploy.

## Consequences

### Positive
- Full template power
- Resource injection
- Conditional blocks

### Negative
- Requires Python/Jinja2 dependency, adds render step to deploy

## Date

2025-01-08
