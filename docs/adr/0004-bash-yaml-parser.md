# ADR-0004: Built-in Bash YAML Parser

## Status

Accepted

## Context

CLI needs to read YAML configurations but adding a heavy dependency like Python just for YAML parsing is undesirable for a shell tool.

## Decision

Implement a lightweight YAML parser in Bash that handles the subset of YAML used by swarmcli configurations.

## Consequences

### Positive
- No external dependencies for basic operations
- Fast startup

### Negative
- Does not support full YAML spec
- Limited to simple key-value and list structures

## Date

2024-12-19
