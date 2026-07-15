#!/bin/bash
# clean-all.sh
# Tears down every stack integration-tests/test-all.sh can leave behind
# (ai-md-<llm> per-provider projects + the default ai-md project) and
# removes the local artifacts those runs generate.
set +e

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cd "$REPO_ROOT" || exit 1

mkdir -p logs
LOG_FILE="logs/clean-all-$(date +%Y%m%d_%H%M%S).log"
SCRIPT_START="$(date +%s)"

log() {
    # log <message> -- timestamps + elapsed-since-start, console + LOG_FILE.
    local elapsed=$(( $(date +%s) - SCRIPT_START ))
    printf '[%s +%02d:%02d] %s\n' "$(date +%H:%M:%S)" "$((elapsed / 60))" "$((elapsed % 60))" "$1" | tee -a "$LOG_FILE"
}

LLM_NAMES="sonnet deepseek minimax openai openrouter"

log "Undeploying default ai-md project..."
docker compose down >/dev/null 2>&1

for name in $LLM_NAMES; do
    log "Undeploying ai-md-$name..."
    docker compose -p "ai-md-$name" down --remove-orphans >/dev/null 2>&1
    rm -rf "src/$name" "dist/$name"
done

log "Restoring committed dist/ artifacts..."
git checkout -- dist/tetris.ai.md.html dist/convert.ai.md.py 2>/dev/null

log "Removing tmp/*..."
rm -rf tmp/*
# logs/ is intentionally left alone here (unlike the old tmp/ wipe): it's
# gitignored and timestamped per run, so past runs stay available for
# after-the-fact debugging instead of being deleted by the next clean-all.

log "Done."
