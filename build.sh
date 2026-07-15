#!/bin/bash
# Resolve to this script's own directory (repo root) so docker-compose.yml is
# found regardless of the caller's current directory.
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

mkdir -p logs
TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="logs/build-$TS.log"

echo "[$(date +%H:%M:%S)] docker compose build -- log: $LOG_FILE"
docker compose build 2>&1 | tee "$LOG_FILE"
exit_code="${PIPESTATUS[0]}"
echo "[$(date +%H:%M:%S)] docker compose build exited $exit_code"
exit "$exit_code"
