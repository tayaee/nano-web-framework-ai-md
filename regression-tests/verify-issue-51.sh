#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
set -euo pipefail

grep -q "test_compile_failure_within_backoff_skips_recompile" engine/tests/test_main.py
uv run --directory engine pytest tests/test_main.py -k test_compile_failure_within_backoff_skips_recompile -q
echo "issue-51 verified"
