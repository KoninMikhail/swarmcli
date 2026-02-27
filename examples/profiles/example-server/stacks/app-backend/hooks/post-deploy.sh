#!/usr/bin/env bash
# Post-deploy hook for app-backend
#
# Runs AFTER successful stack deploy.
# Available environment variables:
#   STACK          — stack name
#   PROFILE        — profile name
#   PLATFORM_ROOT  — swarmcli root

echo "Post-deploy: $STACK ($PROFILE)"

# Example: send deploy notification
# curl -s -X POST "https://hooks.slack.com/services/XXX" \
#     -H "Content-Type: application/json" \
#     -d "{\"text\": \"Deployed $STACK on $PROFILE\"}"

# Example: clear application cache
# docker exec $(docker ps -q -f name=app-backend_api) ./app cache:clear
