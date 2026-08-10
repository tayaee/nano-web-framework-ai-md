#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
set -euo pipefail

grep -q "cannot load spec from" engine/aimd/validators.py
uv run --directory engine pytest tests/ -k load_module
echo "issue-27 verified"
