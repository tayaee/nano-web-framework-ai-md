#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
set -euo pipefail

grep -q "without sandboxing under host process privileges" README.md
echo "issue-45 verified"
