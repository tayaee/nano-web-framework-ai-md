#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
set -euo pipefail

grep -q "async def" regression-tests/verify-issue-5.sh
./regression-tests/verify-issue-5.sh
echo "issue-34 verified"
