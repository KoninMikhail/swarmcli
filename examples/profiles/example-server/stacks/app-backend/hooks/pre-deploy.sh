#!/usr/bin/env bash
# Pre-deploy hook for app-backend
#
# Runs BEFORE stack deploy.
# Available environment variables:
#   STACK          — stack name
#   PROFILE        — profile name
#   PLATFORM_ROOT  — swarmcli root

echo "Pre-deploy: $STACK ($PROFILE)"

# Example: check database availability before deploy
# if ! docker exec $(docker ps -q -f name=postgres) pg_isready -q 2>/dev/null; then
#     echo "WARNING: PostgreSQL is not ready"
# fi

# Example: run migrations before update
# docker exec $(docker ps -q -f name=app-backend_api) ./app migrate --check
