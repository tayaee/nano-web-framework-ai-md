#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
set -euo pipefail

grep -q "dont_write_bytecode" engine/aimd/compiler.py
uv run --directory engine pytest tests/test_compiler.py -q
echo "issue-47 verified"
