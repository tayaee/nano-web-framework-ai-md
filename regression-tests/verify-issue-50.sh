#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
set -euo pipefail

grep -q "test_concurrent_unrelated_reloads_do_not_block" engine/tests/test_registry.py
uv run --directory engine pytest tests/test_registry.py -q
echo "issue-50 verified"
