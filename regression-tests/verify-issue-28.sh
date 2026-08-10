#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
set -euo pipefail

(cd regression-tests && ./verify-issue-5.sh)
echo "issue-28 verified"
