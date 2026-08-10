#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
set -euo pipefail

! grep -q "|| (echo" regression-tests/verify-issue-5.sh
./regression-tests/verify-issue-5.sh
echo "issue-29 verified"
