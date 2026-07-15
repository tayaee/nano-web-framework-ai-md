#!/bin/bash
# Targets the compose project ai-md-${LLM_NAME:-default} (see docker-compose.yml).
# Export LLM_NAME to match the deploy-with-<name>.sh you want to tear down.
set +e
# docker-compose.yml requires LLM_API_KEY to be set (${LLM_API_KEY:?...}) even
# just to parse the file for `ps`/`down` -- without this, teardown silently
# no-ops (error hidden by >/dev/null 2>&1) and stale containers survive.
: "${LLM_API_KEY:=noop-for-teardown}"
export LLM_API_KEY
if docker compose ps >/dev/null 2>&1; then
    echo "Undeploying project ai-md-${LLM_NAME:-default}..."
    docker compose down >/dev/null 2>&1
else
    echo "No deployment to undeploy; skipping."
fi
exit 0
