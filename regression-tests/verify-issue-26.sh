#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
set -euo pipefail

grep -q "실패 시에도 카운터는 advance됩니다" engine/aimd/validators.py
uv run --directory engine pytest tests/ -k load_module
echo "issue-26 verified"
